// Bot Mode roster: the native list, its empty/error states, and the open path
// that hands a profile-scoped Session back to the host.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/models/bot_profile.dart';
import 'package:hermes_android/core/screens/bots_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';

BotProfile _bot(String name, {String display = '', String preview = ''}) =>
    BotProfile(
      name: name,
      displayName: display,
      model: 'model-x',
      description: 'desc',
      canonicalSession: preview.isEmpty
          ? null
          : {'id': 'chat-$name', 'preview': preview},
    );

Future<void> _pump(
  WidgetTester tester, {
  required BotsRosterLoader loader,
  BotChatOpener? opener,
  ValueChanged<Session>? onOpen,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: preferredSupportedLocales(),
      locale: const Locale('en'),
      home: BotsScreen(
        connection: SavedConnection(
          id: 'bots-fixture',
          label: 'Bots fixture',
          host: 'bots.fixture',
          port: 8642,
          apiKey: 'k',
        ),
        testLoader: loader,
        testOpener: opener,
        onOpenSession: onOpen,
        refreshInterval: const Duration(hours: 1),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('renders the roster with names and previews', (tester) async {
    await _pump(
      tester,
      loader: () async => [
        _bot('research', display: 'Research Bot', preview: 'last message'),
        _bot('writer'),
      ],
    );
    expect(find.text('Research Bot'), findsOneWidget);
    expect(find.textContaining('last message'), findsOneWidget);
    expect(find.text('writer'), findsOneWidget);
  });

  testWidgets('tapping a bot resolves its chat and hands the Session up',
      (tester) async {
    Session? opened;
    var openedBots = <String>[];
    await _pump(
      tester,
      loader: () async => [_bot('research')],
      opener: (bot) async {
        openedBots.add(bot.name);
        return Session(
          id: 'stored-chat',
          title: 'Bot Chat',
          model: 'm',
          source: 'bot',
          messageCount: 0,
          isActive: false,
          preview: '',
          startedAt: 1,
          profile: bot.name,
        );
      },
      onOpen: (session) => opened = session,
    );

    await tester.tap(find.text('research'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(openedBots, ['research']);
    expect(opened?.profile, 'research');
    expect(opened?.id, 'stored-chat');
  });

  testWidgets('an empty roster explains itself', (tester) async {
    await _pump(tester, loader: () async => const []);
    expect(find.text('No profiles yet'), findsOneWidget);
  });

  testWidgets('a first-read failure shows the error and a retry', (
    tester,
  ) async {
    await _pump(tester, loader: () async => throw StateError('gateway down'));
    expect(find.text('Could not load bots'), findsOneWidget);
    expect(find.textContaining('gateway down'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
