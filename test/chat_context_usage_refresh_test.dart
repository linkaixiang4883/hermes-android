import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/l10n_test_utils.dart';

Future<void> _pumpChat(
  WidgetTester tester, {
  required String sessionId,
  TestContextUsageFetcher? fetcher,
}) async {
  final apiClient = ApiClient(
    baseUrl: 'http://usage.fixture',
    apiKey: 'test-key',
    httpClient: _EmptyChatHttpClient(),
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
          apiKey: 'test-key',
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
  });

  testWidgets('slow usage return after session switch never throws', (
    tester,
  ) async {
    final gate = Completer<Map<String, dynamic>?>();
    final seenSessions = <String>[];
    Future<Map<String, dynamic>?> fetcher({required String sessionId}) {
      seenSessions.add(sessionId);
      if (sessionId == 'session-a') return gate.future;
      return Future.value(null);
    }

    await _pumpChat(tester, sessionId: 'session-a', fetcher: fetcher);
    // Let _fetchMessages finish so the slow usage fetch for A is in flight.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(seenSessions, contains('session-a'));

    // Fast switch to B while A's fetch is still pending. Same element,
    // new widget.session — the stale A result must not overwrite B.
    await _pumpChat(tester, sessionId: 'session-b', fetcher: fetcher);
    await tester.pump();

    gate.complete({
      'context_used': 12000,
      'context_max': 200000,
      'context_percent': 6.0,
      'model': 'stale-model',
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  testWidgets('throwing usage fetcher never throws', (tester) async {
    Future<Map<String, dynamic>?> fetcher({required String sessionId}) async {
      throw Exception('boom');
    }

    await _pumpChat(tester, sessionId: 'usage-throw', fetcher: fetcher);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}

class _EmptyChatHttpClient extends http.BaseClient {
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
