import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('getLocale resolves system, en, and zh preferences', () async {
    final prefs = await SharedPreferences.getInstance();

    expect(HermesApp.getLocale(prefs), isNull);

    await HermesApp.setLocale(prefs, 'en');
    expect(HermesApp.getLocale(prefs), const Locale('en'));

    await HermesApp.setLocale(prefs, 'zh');
    expect(HermesApp.getLocale(prefs), const Locale('zh'));
    expect(prefs.getString('app_locale'), 'zh');
  });

  testWidgets('HermesApp renders Chinese when the zh locale is persisted', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await HermesApp.setLocale(prefs, 'zh');

    await tester.pumpWidget(
      HermesApp(connManager: ConnectionManager(prefs)),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无连接'), findsOneWidget);
    expect(find.text('No connections'), findsNothing);
  });

  testWidgets('unsupported system locales fall back to English', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(() => tester.platformDispatcher.clearLocalesTestValue());
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      HermesApp(connManager: ConnectionManager(prefs)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No connections'), findsOneWidget);
    expect(find.text('暂无连接'), findsNothing);
  });

  testWidgets('setLocale rebuilds the app and persists the preference', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final appKey = GlobalKey<HermesAppState>();

    await tester.pumpWidget(
      HermesApp(key: appKey, connManager: ConnectionManager(prefs)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No connections'), findsOneWidget);

    await appKey.currentState!.setLocale('zh');
    await tester.pump();

    expect(find.text('暂无连接'), findsOneWidget);
    expect(prefs.getString('app_locale'), 'zh');
  });
}
