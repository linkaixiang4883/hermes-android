import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/l10n_test_utils.dart';

/// The model's own thinking, streamed through `reasoning.delta`.
const _thinking = 'Look at the gateway contract before answering.';

/// The reply the gateway later echoes back as `reasoning.available`.
const _answer =
    'Hermes groups a chat into a project by the session working directory, '
    'so a project chat has to be created with that directory.';

void main() {
  setUp(() {
    // Verbose mode expands the reasoning card, so its text is in the tree.
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
  });

  testWidgets(
    'keeps streamed reasoning when the gateway echoes the reply back',
    (tester) async {
      await _pumpChat(
        tester,
        remoteSubmit:
            ({required sessionId, required text, required onEvent}) async {
              onEvent(
                StreamEvent(
                  type: 'reasoning.delta',
                  data: {'text': _thinking, 'verbose': true},
                ),
              );
              onEvent(StreamEvent(type: 'message.delta', data: {'text': _answer}));
              // Hermes relays the reply's first characters as "reasoning".
              onEvent(
                StreamEvent(
                  type: 'reasoning.available',
                  data: {'text': _answer.substring(0, 60), 'verbose': true},
                ),
              );
            },
      );

      await _send(tester);

      expect(find.text(_thinking), findsOneWidget);
      expect(find.text(_answer.substring(0, 60)), findsNothing);
      expect(
        find.textContaining('Hermes groups a chat into a project'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'still replaces reasoning when the payload is not the reply opening',
    (tester) async {
      await _pumpChat(
        tester,
        remoteSubmit:
            ({required sessionId, required text, required onEvent}) async {
              onEvent(
                StreamEvent(
                  type: 'reasoning.delta',
                  data: {'text': _thinking, 'verbose': true},
                ),
              );
              onEvent(StreamEvent(type: 'message.delta', data: {'text': _answer}));
              onEvent(
                StreamEvent(
                  type: 'reasoning.available',
                  data: {
                    'text': 'Second look: the cwd decides the project.',
                    'verbose': true,
                  },
                ),
              );
            },
      );

      await _send(tester);

      expect(find.text('Second look: the cwd decides the project.'), findsOneWidget);
      expect(find.text(_thinking), findsNothing);
    },
  );
}

Future<void> _send(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'Group this chat');
  await tester.tap(find.byTooltip('Send'));
  await tester.pumpAndSettle();
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required TestRemotePromptSubmit remoteSubmit,
}) async {
  final apiClient = ApiClient(
    baseUrl: 'http://reasoning.fixture',
    apiKey: 'test-key',
    httpClient: _EmptyChatHttpClient(),
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: l10nTestDelegates,
      supportedLocales: l10nTestSupportedLocales,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'reasoning-fixture',
          label: 'Reasoning fixture',
          host: 'reasoning.fixture',
          port: 8642,
          apiKey: 'test-key',
        ),
        session: const Session(
          id: 'reasoning-session',
          title: 'Reasoning chat',
          model: 'fixture-model',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        testApiClient: apiClient,
        testRemotePromptSubmit: remoteSubmit,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
