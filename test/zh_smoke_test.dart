import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/widgets/more_pane.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/l10n/l10n.dart';

import 'support/l10n_test_utils.dart';

/// Proves the Chinese bundle loads and renders: pumps real widgets under the
/// zh locale and asserts representative copy (including a parameterized key).
/// This complements the en-locale widget tests — a missing zh translation
/// falls back to English silently at runtime, so without this test a dropped
/// translation would only be caught by manual QA.
void main() {
  AppLocalizations zhL10n() => lookupAppLocalizations(const Locale('zh'));

  Future<void> pumpZh(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: l10nTestDelegates,
        supportedLocales: l10nTestSupportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('zh renders translated copy including parameters', (
    tester,
  ) async {
    await pumpZh(
      tester,
      Builder(
        builder: (context) => Column(
          children: [
            Text(context.l10n.newAction),
            Text(context.l10n.homeNothingNeedsYou),
            Text(context.l10n.andCountMore(28)),
            Text(context.l10n.movedToProject('Demo')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('新建'), findsOneWidget);
    expect(find.text('暂无待办'), findsOneWidget);
    expect(find.text('还有 28 项'), findsOneWidget);
    expect(find.text('已移到 Demo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zh renders the More menu in Chinese', (tester) async {
    await pumpZh(
      tester,
      MorePane(
        sections: buildMoreSections(
          l10n: zhL10n(),
          dashboardReachable: true,
        ),
        onSelect: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('工作区'), findsOneWidget);
    expect(find.text('未归档聊天'), findsOneWidget);
    for (final text in ['定时任务', '设置']) {
      await tester.scrollUntilVisible(
        find.text(text),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(text), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
