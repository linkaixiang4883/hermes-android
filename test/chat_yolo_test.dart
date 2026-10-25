// The in-chat YOLO button: one tap (plus a confirm on enable) flips the
// session-scoped flag, the banner reflects it, and turning it off needs no
// second confirmation.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
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

Future<void> _pumpChat(
  WidgetTester tester, {
  required Future<bool> Function(bool enabled) onToggle,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: preferredSupportedLocales(),
      locale: const Locale('en'),
      home: ChatScreen(
        connection: SavedConnection(
          id: 'yolo-fixture',
          label: 'YOLO fixture',
          host: 'yolo.fixture',
          port: 8642,
          apiKey: 'yolo-fixture-key',
        ),
        session: Session(
          id: 'yolo-session',
          title: 'YOLO chat',
          model: 'fixture-model',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        testApiClient: ApiClient(
          baseUrl: 'http://yolo.fixture',
          apiKey: 'yolo-fixture-key',
          httpClient: _EmptyHttpClient(),
        ),
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        testYoloEnabled: false,
        testYoloToggle: onToggle,
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

  testWidgets('enabling asks first, then shows the banner; disabling is direct',
      (tester) async {
    final toggles = <bool>[];
    await _pumpChat(
      tester,
      onToggle: (enabled) async {
        toggles.add(enabled);
        return enabled;
      },
    );

    expect(find.byKey(const ValueKey('yolo-banner')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-yolo-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('yolo-confirm')), findsOneWidget);
    expect(toggles, isEmpty, reason: 'the confirm gate comes first');

    await tester.tap(find.byKey(const ValueKey('yolo-confirm-enable')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(toggles, [true]);
    expect(find.byKey(const ValueKey('yolo-banner')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-yolo-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(toggles, [true, false]);
    expect(find.byKey(const ValueKey('yolo-banner')), findsNothing);
  });

  testWidgets('a gateway refusal keeps the previous state and reports it',
      (tester) async {
    await _pumpChat(
      tester,
      onToggle: (enabled) async => throw StateError('gateway said no'),
    );

    await tester.tap(find.byKey(const ValueKey('chat-yolo-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('yolo-confirm-enable')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('yolo-banner')), findsNothing);
    expect(find.textContaining('gateway said no'), findsOneWidget);
  });
}
