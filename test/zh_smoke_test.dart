import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/widgets/more_pane.dart';
import 'package:hermes_android/l10n/app_localizations.dart';


/// Proves the Chinese bundle loads and renders: pumps real widgets under the
/// zh locale and asserts representative copy (including parameterized keys and
/// the fork's own overlay strings). The en-locale widget tests cannot catch a
/// dropped zh translation — it falls back to English silently at runtime.
void main() {
  AppLocalizations zhL10n() => lookupAppLocalizations(const Locale('zh'));

  Future<void> pumpZh(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: preferredSupportedLocales(),
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
            Text(context.l10n.usage_title),
            Text(context.l10n.usage_bar_summary('12K', '200K', 6)),
            Text(context.l10n.moved_to('Demo')),
            Text(context.l10n.speech_recognition_use_keyboard),
            Text(context.l10n.cancel),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('用量统计'), findsOneWidget);
    expect(find.text('已用 12K/200K · 6%'), findsOneWidget);
    expect(find.text('已移动到 Demo'), findsOneWidget);
    expect(find.text('语音识别服务不可用，请使用输入法键盘上的语音按钮'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zh renders the More menu in Chinese', (tester) async {
    // A tall viewport renders every section without scrolling: the previous
    // scrollUntilVisible approach relied on the pre-merge pane layout.
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpZh(
      tester,
      MorePane(
        sections: buildMoreSections(l10n: zhL10n(), dashboardReachable: true),
        onSelect: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('工作区'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
