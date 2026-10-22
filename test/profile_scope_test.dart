// P0: the profile scope is a per-session fact.
//
// Bot Mode's bots are Hermes profiles. A session opened for one bot must carry
// that profile wherever a stored id is resolved (resume, history) — otherwise
// the call lands in the connection's default profile. These tests pin the
// model and the REST surface; the WS frames are covered by the bot roster
// tests once P1 lands.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;

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
  test('a session defaults to the connection profile (profile == null)', () {
    final session = Session(
      id: 'plain',
      title: 'Plain',
      model: 'm',
      source: 'test',
      messageCount: 0,
      isActive: false,
      preview: '',
      startedAt: 1,
    );
    expect(session.profile, isNull);
  });

  test('a bot session keeps its profile', () {
    final session = Session(
      id: 'bot-chat',
      title: 'Bot Chat',
      model: 'm',
      source: 'test',
      messageCount: 0,
      isActive: false,
      preview: '',
      startedAt: 1,
      profile: 'research',
    );
    expect(session.profile, 'research');
  });

  test('gateway rows do not invent a profile', () {
    final session = Session.fromJson({'id': 'x', 'title': 'X'});
    expect(session.profile, isNull);
  });

  test('history reads carry the profile as a query parameter', () async {
    final http = _CapturingHttpClient();
    final api = ApiClient(
      baseUrl: 'http://profile.fixture',
      apiKey: 'k',
      httpClient: http,
    );
    await api.getMessages(
      'stored-id',
      limit: 10,
      latest: true,
      profile: 'research',
    );
    final uri = http.requests.single;
    expect(uri.queryParameters['profile'], 'research');
    expect(uri.queryParameters['limit'], '10');
  });

  test('history reads stay profile-free for default-profile chats', () async {
    final http = _CapturingHttpClient();
    final api = ApiClient(
      baseUrl: 'http://profile.fixture',
      apiKey: 'k',
      httpClient: http,
    );
    await api.getMessages('stored-id', limit: 10, latest: true);
    expect(http.requests.single.queryParameters.containsKey('profile'), isFalse);
  });
}
