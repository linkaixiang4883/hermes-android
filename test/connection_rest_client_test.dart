import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/connection_rest_client.dart';

SavedConnection _connection({
  String? desktopGatewayUrl,
  bool proxied = false,
  String? profile,
}) => SavedConnection(
  id: 'conn-1',
  label: 'Test',
  host: 'gateway.test',
  port: 8642,
  apiKey: 'api-key',
  desktopGatewayUrl: desktopGatewayUrl,
  dashboardProxied: proxied,
  gatewayProfile: profile,
);

void main() {
  test('a desktop connection reads from the dashboard origin', () async {
    late Uri seen;
    final client = buildConnectionRestClient(
      _connection(
        desktopGatewayUrl: 'http://127.0.0.1:9119',
        proxied: true,
        profile: 'sol',
      ),
      httpClient: MockClient((request) async {
        seen = request.url;
        return http.Response(
          jsonEncode({'sessions': [], 'total': 0, 'storage': {}}),
          200,
        );
      }),
    );

    await client.getSessionsPage();

    expect(seen.host, '127.0.0.1');
    expect(seen.port, 9119);
    expect(seen.path, '/api/sessions');
    expect(seen.queryParameters['profile'], 'sol');
  });

  test('a legacy connection keeps the 8642 bearer path', () async {
    late Uri seen;
    late String? authorization;
    final client = buildConnectionRestClient(
      _connection(),
      httpClient: MockClient((request) async {
        seen = request.url;
        authorization = request.headers['Authorization'];
        return http.Response(
          jsonEncode({'data': [], 'has_more': false}),
          200,
        );
      }),
    );

    await client.getSessionsPage();

    expect(seen.port, 8642);
    expect(authorization, 'Bearer api-key');
  });
}
