import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/dashboard_rest_client.dart';

DashboardRestClient _client(MockClient httpClient, {String? profile = 'sol'}) {
  return DashboardRestClient(
    DashboardClient(
      host: 'dashboard.test',
      port: 9119,
      proxied: true,
      gatewayProfile: profile,
      httpClient: httpClient,
    ),
    gatewayProfile: profile,
  );
}

void main() {
  test('reads the dashboard sessions envelope with recency and profile', () async {
    late Uri seen;
    final client = _client(
      MockClient((request) async {
        seen = request.url;
        return http.Response(
          jsonEncode({
            'sessions': [
              {'id': 's1', 'title': 'One', 'last_active': 10, 'profile': 'sol'},
            ],
            'total': 2,
            'limit': 1,
            'offset': 0,
            'storage': <String, String>{},
          }),
          200,
        );
      }),
    );

    final page = await client.getSessionsPage(limit: 1);

    expect(seen.host, 'dashboard.test');
    expect(seen.port, 9119);
    expect(seen.queryParameters['order'], 'recent');
    expect(seen.queryParameters['limit'], '1');
    expect(seen.queryParameters['profile'], 'sol');
    expect(page.sessions.single.id, 's1');
    expect(page.hasMore, isTrue);
  });

  test('reads messages, drops hidden rows and prefers display_content', () async {
    final client = _client(
      MockClient((_) async => http.Response(
        jsonEncode({
          'messages': [
            {'role': 'user', 'content': 'hello'},
            {'role': 'system', 'content': 'scaffold', 'display_kind': 'hidden'},
            {
              'role': 'assistant',
              'content': 'raw storage form',
              'display_content': 'display form',
            },
          ],
          'pagination': {'limit': 10, 'offset': 0},
        }),
        200,
      )),
    );

    final messages = await client.getMessages('s1', limit: 10, latest: true);

    expect(messages, hasLength(2));
    expect(messages.last['content'], 'display form');
    expect(messages.last['raw_content'], 'raw storage form');
    expect(
      messages.any((message) => message['display_kind'] == 'hidden'),
      isFalse,
    );
  });

  test('reads the bare dashboard session object', () async {
    final client = _client(
      MockClient((request) async {
        expect(request.url.path, '/api/sessions/s1');
        return http.Response(
          jsonEncode({'id': 's1', 'title': 'One', 'message_count': 3}),
          200,
        );
      }),
    );

    final session = await client.getSessionById('s1');

    expect(session?.id, 's1');
    expect(session?.title, 'One');
  });

  test('maps search lineage_root onto Session.lineageRootId', () async {
    final client = _client(
      MockClient((request) async {
        expect(request.url.path, '/api/sessions/search');
        expect(request.url.queryParameters['q'], 'Old pin');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 'tip-id',
                'session_id': 'tip-id',
                'lineage_root': 'root-id',
                'title': 'Old pin',
                'last_active': 5,
              },
            ],
          }),
          200,
        );
      }),
    );

    final page = await client.getSessionsPage(title: 'Old pin');

    expect(page.sessions, hasLength(1));
    expect(page.sessions.single.id, 'tip-id');
    expect(page.sessions.single.lineageRootId, 'root-id');
  });

  test('treats a dashboard 404 delete as already removed', () async {
    final client = _client(
      MockClient((_) async => http.Response('{"detail":"not found"}', 404)),
    );

    await client.deleteSession('gone');
  });

  test('does not silently support model REST writes', () async {
    final client = _client(MockClient((_) async => http.Response('{}', 200)));

    expect(
      () => client.setSessionModel(
        sessionId: 's1',
        provider: 'p',
        model: 'm',
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
