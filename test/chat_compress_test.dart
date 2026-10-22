// One-tap context compaction from the usage bar: the app's first slash
// command. The transport is a test seam here (no socket); what is pinned is
// the screen's side of the contract — the confirm gate, exactly one
// `/compress` send, the busy spinner that refuses a second tap, the usage
// refresh after success, and the gateway's own wording on a refusal.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

class _EmptyHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'data': <Object>[]}))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'error': 'unexpected request'}))),
      404,
      headers: {'content-type': 'application/json'},
    );
  }
}

Map<String, dynamic> _breakdown() => {
  'context_used': 12000,
  'context_max': 200000,
  'context_percent': 6.0,
  'model': 'fixture-model',
};

Future<void> _pumpChat(
  WidgetTester tester, {
  required String sessionId,
  Future<String> Function(String command)? slashExec,
  void Function()? onUsageFetch,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: preferredSupportedLocales(),
      locale: const Locale('en'),
      home: ChatScreen(
        connection: SavedConnection(
          id: 'compress-fixture',
          label: 'Compress fixture',
          host: 'compress.fixture',
          port: 8642,
          apiKey: 'compress-fixture-key',
        ),
        session: Session(
          id: sessionId,
          title: 'Compress chat',
          model: 'fixture-model',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        testApiClient: ApiClient(
          baseUrl: 'http://compress.fixture',
          apiKey: 'compress-fixture-key',
          httpClient: _EmptyHttpClient(),
        ),
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        testContextUsageFetcher: ({required String sessionId}) async {
          onUsageFetch?.call();
          return _breakdown();
        },
        testSlashExec: slashExec,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
  });

  testWidgets('the compress button confirms first, then sends one command', (
    tester,
  ) async {
    final calls = <String>[];
    var usageFetches = 0;
    await _pumpChat(
      tester,
      sessionId: 'compress-one',
      onUsageFetch: () => usageFetches += 1,
      slashExec: (command) async {
        calls.add(command);
        return 'Compressed 42 messages';
      },
    );

    await tester.tap(find.byKey(const Key('compress-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      calls,
      isEmpty,
      reason: 'opening the confirm dialog must not compress anything yet',
    );

    await tester.tap(find.byKey(const Key('compress-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls, ['/compress']);
    expect(
      find.textContaining('Context compressed'),
      findsOneWidget,
      reason: 'a completed compaction reports itself',
    );
    expect(
      usageFetches,
      greaterThanOrEqualTo(2),
      reason: 'the usage bar must re-read after the transcript was rewritten',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing the confirm sends nothing', (tester) async {
    final calls = <String>[];
    await _pumpChat(
      tester,
      sessionId: 'compress-cancel',
      slashExec: (command) async {
        calls.add(command);
        return '';
      },
    );

    await tester.tap(find.byKey(const Key('compress-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AlertDialog), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('a busy refusal surfaces the gateway wording', (tester) async {
    await _pumpChat(
      tester,
      sessionId: 'compress-busy',
      slashExec: (command) async =>
          throw const SlashExecFailure('Session is busy running a turn'),
    );

    await tester.tap(find.byKey(const Key('compress-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('compress-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('Session is busy running a turn'),
      findsOneWidget,
      reason: 'the refusal must reach the user, not vanish',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the button spins and refuses a second tap while compressing', (
    tester,
  ) async {
    final gate = Completer<String>();
    var calls = 0;
    await _pumpChat(
      tester,
      sessionId: 'compress-spin',
      slashExec: (command) {
        calls += 1;
        return gate.future;
      },
    );

    await tester.tap(find.byKey(const Key('compress-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('compress-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final button = tester.widget<IconButton>(
      find.byKey(const Key('compress-button')),
    );
    expect(
      button.onPressed,
      isNull,
      reason: 'a compaction in flight must not be started twice',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('compress-button')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    gate.complete('done');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls, 1);
    final settled = tester.widget<IconButton>(
      find.byKey(const Key('compress-button')),
    );
    expect(settled.onPressed, isNotNull);
  });
}
