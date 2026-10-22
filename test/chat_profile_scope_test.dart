// P0: a ChatScreen opened for a bot profiles every history read.
//
// The visible transcript comes from REST; if the request omits `profile`, the
// gateway resolves the stored id in the connection's default profile and the
// screen shows the wrong conversation (or an empty one). This pins the URI.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

class _CapturingHttpClient extends http.BaseClient {
  final List<Uri> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'data': <Object>[]}))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
  });

  testWidgets('a bot chat asks for its profile transcript', (tester) async {
    final client = _CapturingHttpClient();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: preferredSupportedLocales(),
        locale: const Locale('en'),
        home: ChatScreen(
          connection: SavedConnection(
            id: 'profile-fixture',
            label: 'Profile fixture',
            host: 'profile.fixture',
            port: 8642,
            apiKey: 'profile-fixture-key',
          ),
          session: Session(
            id: 'bot-chat',
            title: 'Bot Chat',
            model: 'fixture-model',
            source: 'test',
            messageCount: 0,
            isActive: false,
            preview: '',
            startedAt: 1,
            profile: 'research',
          ),
          testApiClient: ApiClient(
            baseUrl: 'http://profile.fixture',
            apiKey: 'profile-fixture-key',
            httpClient: client,
          ),
          testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final messageReads = client.requests
        .where((uri) => uri.path.endsWith('/messages'))
        .toList();
    expect(messageReads, isNotEmpty);
    expect(messageReads.first.queryParameters['profile'], 'research');
  });
}
