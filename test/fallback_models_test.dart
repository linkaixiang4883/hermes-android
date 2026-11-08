import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/widgets/fallback_models.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FallbackFixture {
  _FallbackFixture({
    Map<String, dynamic>? config,
    this.configStatus = 200,
  }) : config = config ?? {
         'fallback_providers': [
           {'provider': 'openai', 'model': 'old'},
         ],
       };

  Map<String, dynamic> config;
  final int configStatus;
  final writes = <Map<String, dynamic>>[];
  late final DashboardClient client = DashboardClient(
    host: 'example.test',
    port: 8642,
    pathPrefix: '/proxy',
    proxied: true,
    gatewayProfile: 'research',
    httpClient: MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/config')) {
        if (request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          writes.add(body);
          final next = body['config'];
          if (next is Map<String, dynamic>) {
            config = {...config, ...next};
          }
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        if (configStatus != 200) {
          return http.Response(
            jsonEncode({'detail': 'never-show-server-secret'}),
            configStatus,
          );
        }
        return http.Response(jsonEncode(config), 200);
      }
      if (path.endsWith('/model/options')) {
        return http.Response(
          jsonEncode({
            'providers': [
              {
                'slug': 'openai',
                'models': ['old', 'new'],
              },
              {
                'slug': 'other',
                'models': ['other-1', 'other-2'],
              },
              {
                'slug': 'secret-route',
                'models': ['private'],
                'api_url': 'https://private.invalid',
              },
            ],
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    }),
  );
}

Widget _host(DashboardClient client) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(child: FallbackModels(client: client)),
  ),
);

Finder _row(int index) => find.byKey(ValueKey('fallback-row-$index'));

Finder _picker(int index, int which) => find
    .descendant(
      of: _row(index),
      matching: find.byType(DropdownButtonFormField<String>),
    )
    .at(which);

Future<void> _choose(
  WidgetTester tester,
  int index,
  int which,
  String value,
) async {
  await tester.ensureVisible(_picker(index, which));
  await tester.tap(_picker(index, which));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads the primary chain and saves an explicit ordered draft', (
    tester,
  ) async {
    final fixture = _FallbackFixture();
    addTearDown(fixture.client.close);
    await tester.pumpWidget(_host(fixture.client));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fallback-row-0')), findsOneWidget);
    expect(find.text('openai'), findsWidgets);
    expect(fixture.writes, isEmpty);

    await tester.tap(find.byKey(const ValueKey('fallback-add')));
    await tester.pumpAndSettle();
    await _choose(tester, 1, 0, 'other');
    await _choose(tester, 1, 1, 'other-2');
    expect(fixture.writes, isEmpty);

    await tester.tap(find.byKey(const ValueKey('fallback-save')));
    await tester.pumpAndSettle();

    expect(fixture.writes.single['profile'], 'research');
    expect(fixture.writes.single['config'], {
      'fallback_providers': [
        {'provider': 'openai', 'model': 'old'},
        {'provider': 'other', 'model': 'other-2'},
      ],
    });
    expect(find.text('Fallback list saved and verified.'), findsOneWidget);
  });

  testWidgets('keeps legacy fallback entries visible and read-only', (
    tester,
  ) async {
    final fixture = _FallbackFixture(
      config: {
        'fallback_providers': [
          {'provider': 'openai', 'model': 'old'},
        ],
        'fallback_model': {'provider': 'legacy', 'model': 'old-model'},
      },
    );
    addTearDown(fixture.client.close);
    await tester.pumpWidget(_host(fixture.client));
    await tester.pumpAndSettle();

    expect(find.text('Legacy fallbacks (read-only)'), findsOneWidget);
    expect(find.textContaining('legacy / old-model'), findsOneWidget);
  });

  testWidgets('unavailable config is an explicit failure, not an empty list', (
    tester,
  ) async {
    final fixture = _FallbackFixture(configStatus: 500);
    addTearDown(fixture.client.close);
    await tester.pumpWidget(_host(fixture.client));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Fallback settings are unavailable or invalid. Check the connection, selected profile and host version, then retry.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('fallback-save')), findsNothing);
  });

  testWidgets('routing metadata is preserved and cannot be edited', (
    tester,
  ) async {
    final fixture = _FallbackFixture(
      config: {
        'fallback_providers': [
          {
            'provider': 'openai',
            'model': 'old',
            'base_url': 'https://private.invalid',
          },
        ],
      },
    );
    addTearDown(fixture.client.close);
    await tester.pumpWidget(_host(fixture.client));
    await tester.pumpAndSettle();

    expect(find.text('openai / old'), findsOneWidget);
    expect(
      find.textContaining('Routing details or an unlisted provider'),
      findsOneWidget,
    );
  });
}
