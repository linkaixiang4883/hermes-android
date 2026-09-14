// On-device QA for Project chat filing.
//
// The bug this pins: opening "New chat" inside a Project used to fail on the
// official gateway (`projects.assign_session` does not exist), so the chat
// never opened. Now the project rides along to the chat, which anchors its
// gateway session to the project's folder — the gateway files the chat under
// that Project by its working directory.
//
// Run against a live gateway (the app's saved connection is used):
//   flutter test integration_test/project_chat_filing_test.dart -d <device>
//
// Environment-dependent by design: it needs the gateway to serve the Project
// named below. Everything else skips instead of failing, so a machine without
// that Project (or without a connection) reports "skipped", not "broken".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/main.dart' as app;
import 'package:hermes_android/core/widgets/project_detail_screen.dart';
import 'package:integration_test/integration_test.dart';

/// The Project this machine's gateway serves (see `~/.hermes/projects.db`).
const _projectName = 'hermes-android';

/// The gateway's own refusal message for a chat it cannot file, translated.
const _unfiledMessages = <String>[
  '项目聊天创建失败',
  'Opened as a normal chat — couldn’t file it into a project',
  '未能把此聊天归入项目，已按普通聊天打开',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a Project chat opens without a filing failure', (tester) async {
    app.main();
    await _settle(tester, seconds: 8);

    // The shell renders the five fixed destinations; a missing one means the
    // app never reached Home (no connection), which this test cannot judge.
    if (!await _tapWhenFound(tester, find.text('Projects'), seconds: 15)) {
      markTestSkipped('The shell never offered the Projects tab');
      return;
    }
    await _settle(tester, seconds: 6);

    final project = find.text(_projectName);
    if (!tester.any(project)) {
      markTestSkipped('This gateway serves no "$_projectName" project');
      return;
    }
    await tester.tap(project.first);
    await _settle(tester, seconds: 6);

    final newChat = find.byKey(kProjectNewChatButtonKey);
    expect(newChat, findsOneWidget, reason: 'the Project detail offers New chat');

    await tester.tap(newChat);
    await _settle(tester, seconds: 8);

    // The chat opened: the composer is live and the Project is named.
    expect(find.byType(TextField), findsWidgets);
    expect(find.text(_projectName), findsWidgets);

    // And nothing had to be refused: the chat is filed, not held back.
    for (final message in _unfiledMessages) {
      expect(find.text(message), findsNothing, reason: 'unexpected: $message');
    }

    // Send one short turn: the gateway persists the chat's row on its first
    // prompt, and that row's working directory is the artifact this fix is
    // judged by (read back on the host: it must be the project's folder).
    final composer = find.byType(TextField);
    if (composer.evaluate().isEmpty) {
      markTestSkipped('The chat opened without a composer to send from');
      return;
    }
    await tester.enterText(composer.last, 'QA: 一条测试消息，不必回复');
    await _settle(tester, seconds: 1);

    final send = find.widgetWithIcon(IconButton, Icons.send);
    expect(send, findsWidgets, reason: 'the composer offers Send');
    await tester.tap(send.last);
    await _settle(tester, seconds: 25);

    // The user's own turn is on screen: the gateway accepted the prompt.
    expect(find.textContaining('QA: 一条测试消息'), findsWidgets);
  });
}

/// Pumps in slices instead of `pumpAndSettle`: the app streams, polls and keeps
/// keep-alive timers running, which never "settle".
Future<void> _settle(WidgetTester tester, {int seconds = 3}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Taps [finder] as soon as it appears, up to [seconds]; false when it never did.
Future<bool> _tapWhenFound(
  WidgetTester tester,
  Finder finder, {
  int seconds = 10,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    if (tester.any(finder)) {
      await tester.tap(finder.first);
      await _settle(tester, seconds: 1);
      return true;
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
  return false;
}
