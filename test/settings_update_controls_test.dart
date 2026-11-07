import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/services/app_update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_test_utils.dart';

String _releaseJson(String tag) =>
    '{"tag_name":"$tag","name":"Hermes Android $tag","body":"Notes.",'
    '"html_url":"https://github.com/linkaixiang4883/hermes-android/releases/tag/$tag",'
    '"draft":false,"published_at":"2026-10-15T09:30:00Z"}';

SavedConnection _connection() => SavedConnection(
  id: 'offline-dashboard',
  label: 'Offline dashboard',
  host: '127.0.0.1',
  port: 9119,
  apiKey: '',
  dashboardPortOverride: 1,
  dashboardUsername: 'tester',
  dashboardPassword: 'secret',
);

Future<void> _pumpSettings(
  WidgetTester tester, {
  AppUpdateService? service,
  Future<String?> Function()? installedVersionLoader,
}) async {
  await tester.pumpWidget(
    testAppWithL10n(
      SettingsScreen(
        connection: _connection(),
        updateService: service,
        installedVersionLoader: installedVersionLoader,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('update controls stay reachable when the dashboard fails', (
    tester,
  ) async {
    await _pumpSettings(tester);

    expect(find.text('Failed to load settings'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Check for updates on launch'), findsOneWidget);

    await tester.tap(find.text('Check for updates on launch'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppUpdateService.checkOnLaunchKey), isFalse);
  });

  testWidgets('manual check shows a newer release and can skip it', (
    tester,
  ) async {
    final service = AppUpdateService(
      client: MockClient(
        (request) async => http.Response(_releaseJson('v2.1.20'), 200),
      ),
    );
    await _pumpSettings(
      tester,
      service: service,
      installedVersionLoader: () async => '2.1.19',
    );

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Hermes Android v2.1.20'), findsOneWidget);

    await tester.tap(find.text('Skip this version'));
    await tester.pumpAndSettle();

    expect(await service.skippedVersion(), '2.1.20');
  });

  testWidgets('manual check reports the latest version', (tester) async {
    final service = AppUpdateService(
      client: MockClient(
        (request) async => http.Response(_releaseJson('v2.1.19'), 200),
      ),
    );
    await _pumpSettings(
      tester,
      service: service,
      installedVersionLoader: () async => '2.1.19',
    );

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.text('You’re on the latest version.'), findsOneWidget);
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('manual check reports a failed fetch', (tester) async {
    final service = AppUpdateService(
      client: MockClient((request) async => http.Response('down', 500)),
    );
    await _pumpSettings(
      tester,
      service: service,
      installedVersionLoader: () async => '2.1.19',
    );

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.text('Couldn’t check for updates.'), findsOneWidget);
  });
}
