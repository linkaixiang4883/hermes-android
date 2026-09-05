import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/l10n_test_utils.dart';

const _kUsageSse = 'data: {"choices":[{"delta":{"content":"hi"}}]}\n\n'
    'data: {"usage":{"prompt_tokens":120,"completion_tokens":45,"total_tokens":165}}\n\n'
    'data: [DONE]\n\n';

class _HintHttpClient extends http.BaseClient {
  final String sseBody;

  _HintHttpClient({this.sseBody = ''});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'data': <Object>[]}))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'POST' &&
        request.url.path.endsWith('/v1/chat/completions')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(sseBody)),
        200,
        headers: {'content-type': 'text/event-stream'},
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
  required String sessionId,
  TestContextUsageFetcher? fetcher,
  String sseBody = '',
}) async {
  final apiClient = ApiClient(
    baseUrl: 'http://usage.fixture',
    apiKey: 'hint-key',
    httpClient: _HintHttpClient(sseBody: sseBody),
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: l10nTestDelegates,
      supportedLocales: l10nTestSupportedLocales,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'usage-fixture',
          label: 'Usage fixture',
          host: 'usage.fixture',
          port: 8642,
          apiKey: 'hint-key',
        ),
        session: Session(
          id: sessionId,
          title: 'Usage chat',
          model: 'fixture-model',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        testApiClient: apiClient,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        testContextUsageFetcher: fetcher,
      ),
    ),
  );
}

Map<String, dynamic> _breakdown() => {
      'context_used': 12000,
      'context_max': 200000,
      'context_percent': 6.0,
      'model': 'fixture-model',
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
  });

  testWidgets('breakdown with data shows hint bar with summary text',
      (tester) async {
    Future<Map<String, dynamic>?> fetcher({required String sessionId}) async =>
        _breakdown();

    await _pumpChat(tester, sessionId: 'hint-summary', fetcher: fetcher);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final bar = find.byKey(const Key('usage-hint-bar'));
    expect(bar, findsOneWidget);
    final label = tester.widget<Text>(
      find.descendant(of: bar, matching: find.byType(Text)),
    );
    expect(label.data, contains('of '));
    expect(label.data, contains('%'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('all-zero breakdown hides hint bar', (tester) async {
    Future<Map<String, dynamic>?> fetcher({required String sessionId}) async =>
        {
          'context_used': 0,
          'context_max': 200000,
          'context_percent': 0.0,
        };

    await _pumpChat(tester, sessionId: 'hint-zero', fetcher: fetcher);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('usage-hint-bar')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('turn usage only shows this-turn text', (tester) async {
    Future<Map<String, dynamic>?> fetcher({required String sessionId}) async =>
        null;

    await _pumpChat(
      tester,
      sessionId: 'hint-triple',
      fetcher: fetcher,
      sseBody: _kUsageSse,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));

    final bar = find.byKey(const Key('usage-hint-bar'));
    expect(bar, findsOneWidget);
    final label = tester.widget<Text>(
      find.descendant(of: bar, matching: find.byType(Text)),
    );
    expect(label.data, contains('This turn'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap opens dialog with usage and model lines', (tester) async {
    Future<Map<String, dynamic>?> fetcher({required String sessionId}) async =>
        _breakdown();

    await _pumpChat(tester, sessionId: 'hint-dialog', fetcher: fetcher);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('usage-hint-bar')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.textContaining('%')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('Model:')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching session hides hint bar', (tester) async {
    Future<Map<String, dynamic>?> fetcher({required String sessionId}) async =>
        sessionId == 'session-a' ? _breakdown() : null;

    await _pumpChat(tester, sessionId: 'session-a', fetcher: fetcher);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('usage-hint-bar')), findsOneWidget);

    // Dispose the old screen so the new session starts from a fresh state,
    // mirroring the real navigation-driven session switch.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await _pumpChat(tester, sessionId: 'session-b', fetcher: fetcher);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('usage-hint-bar')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
