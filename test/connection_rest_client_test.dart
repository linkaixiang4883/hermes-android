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
  String apiKey = 'api-key',
  String? dashboardUsername,
  String? dashboardPassword,
  int? dashboardPort,
}) => SavedConnection(
  id: 'conn-1',
  label: 'Test',
  host: 'gateway.test',
  port: 8642,
  apiKey: apiKey,
  desktopGatewayUrl: desktopGatewayUrl,
  dashboardProxied: proxied,
  dashboardUsername: dashboardUsername,
  dashboardPassword: dashboardPassword,
  dashboardPortOverride: dashboardPort,
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

  test('dashboard credentials work without an API key', () async {
    late Uri seen;
    final client = buildConnectionRestClient(
      _connection(
        apiKey: '',
        proxied: true,
        dashboardUsername: 'operator',
        dashboardPassword: 'secret',
        dashboardPort: 9119,
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

    expect(seen.host, 'gateway.test');
    expect(seen.port, 9119);
    expect(seen.path, '/api/sessions');
  });

  test('a connection without a desktop URL still uses the dashboard origin', () async {
    late Uri seen;
    final client = buildConnectionRestClient(
      _connection(apiKey: '', proxied: true),
      httpClient: MockClient((request) async {
        seen = request.url;
        return http.Response(
          jsonEncode({'sessions': [], 'total': 0, 'storage': {}}),
          200,
        );
      }),
    );

    await client.getSessionsPage();

    expect(seen.port, 9119);
    expect(seen.path, '/api/sessions');
  });
}
