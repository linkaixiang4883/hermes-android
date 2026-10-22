// Gateway notices must not bury the transcript.
//
// The background memory/skill agent reports every review pass as
// `review.summary`, and the screen used to append a card per report — with no
// close button and no TTL, a chat that stayed open filled its tail with
// "Hermes review" cards the user could only get rid of by killing the app.
// These tests pin the four properties that make the cards livable:
//
// - consecutive review reports collapse into ONE counted card;
// - every card can be closed, and the dismissal survives rebuilds (the
//   identity joins a session-level dismissed set);
// - completion cards are capped (two is enough to notice the work);
// - the cards are page state, not a process-wide cache: leaving the chat and
//   coming back does not replay notices the user already read.
//
// No socket is involved: frames go in through [TestDesktopAsyncEventHook], the
// same seam the live-follow suites use.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/projects_tree_overview.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_android/l10n/app_localizations.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/recording_turn_notification_sink.dart';

const _sessionId = 'hygiene-session';

SavedConnection _connection() => SavedConnection(
  id: 'hygiene-fixture',
  label: 'Notice hygiene fixture',
  host: 'hygiene.fixture',
  port: 8642,
  apiKey: 'hygiene-key',
);

Session _session() => const Session(
  id: _sessionId,
  title: 'Notice hygiene',
  model: 'fixture-model',
  source: 'test',
  messageCount: 0,
  isActive: true,
  preview: '',
  startedAt: 1,
);

void main() {
  late TestDesktopAsyncEventHook asyncHook;

  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    asyncHook = TestDesktopAsyncEventHook();
  });

  /// Delivers one gateway frame the way the shared connection's async bridge
  /// would.
  void send(String type, Map<String, dynamic> data) {
    asyncHook.handler!(StreamEvent(type: type, data: data));
  }

  Future<void> pumpChat(
    WidgetTester tester, {
    TurnNotificationService? notifications,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChatScreen(
          key: const ValueKey('notice-hygiene'),
          connection: _connection(),
          session: _session(),
          testApiClient: ApiClient(
            baseUrl: 'http://hygiene.fixture',
            apiKey: 'hygiene-key',
            httpClient: _EmptyChatHttpClient(),
          ),
          testDesktopAsyncEventHook: asyncHook,
          testTurnNotifications: notifications,
          testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
          // The gateway is unreachable on purpose; answering the sticky-header
          // lookup here keeps the screen from starting a connection attempt
          // this suite would then have to out-race.
          testProjectOverviewLoader: () async => ProjectsTreeOverview.empty,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Android walks the whole lifecycle chain; skipping a step trips Flutter's
  /// transition assertions.
  void background(WidgetTester tester) {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  List<GatewayNoticeCard> cards(WidgetTester tester) => tester
      .widgetList<GatewayNoticeCard>(find.byType(GatewayNoticeCard))
      .toList();

  testWidgets('ten review summaries collapse into one counted card', (
    tester,
  ) async {
    await pumpChat(tester);

    for (var pass = 1; pass <= 10; pass++) {
      send('review.summary', {'text': 'Skill update $pass'});
      await tester.pump();
    }

    expect(find.byType(GatewayNoticeCard), findsOneWidget);
    expect(cards(tester).single.notice.updateCount, 10);
    // en locale: "Hermes review: 10 updates".
    expect(find.text('Hermes review: 10 updates'), findsOneWidget);
    // Collapsed, the card shows the newest pass; the rest live behind it.
    expect(find.text('Skill update 10'), findsOneWidget);
    expect(find.text('Skill update 1'), findsNothing);

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('Skill update 1'), findsOneWidget);
  });

  testWidgets('a closed card does not come back on rebuild or replay', (
    tester,
  ) async {
    await pumpChat(tester);

    send('review.summary', {'text': 'Memory consolidated.'});
    send('background.complete', {'task_id': 'bg-1', 'text': 'Indexed files.'});
    await tester.pump();
    expect(find.byType(GatewayNoticeCard), findsNWidgets(2));
    expect(find.text('Hermes review'), findsOneWidget);

    await tester.tap(
      find
          .descendant(
            of: find.byType(GatewayNoticeCard),
            matching: find.byIcon(Icons.close),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Hermes review'), findsNothing);
    expect(find.text('Background task bg-1 completed'), findsOneWidget);

    // A replayed frame is not new information: the dismissal holds.
    send('review.summary', {'text': 'Memory consolidated.'});
    await tester.pump();
    expect(find.text('Hermes review'), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(GatewayNoticeCard), findsNothing);
  });

  testWidgets('completion cards are capped at two, oldest dropped', (
    tester,
  ) async {
    await pumpChat(tester);

    for (var task = 1; task <= 3; task++) {
      send('background.complete', {
        'task_id': 'bg-$task',
        'text': 'Finished job $task.',
      });
      await tester.pump();
    }

    expect(find.byType(GatewayNoticeCard), findsNWidgets(2));
    expect(find.text('Background task bg-1 completed'), findsNothing);
    expect(find.text('Background task bg-2 completed'), findsOneWidget);
    expect(find.text('Background task bg-3 completed'), findsOneWidget);
  });

  testWidgets('re-entering the chat does not replay stored notice cards', (
    tester,
  ) async {
    await pumpChat(tester);
    send('review.summary', {'text': 'Memory consolidated.'});
    send('background.complete', {'task_id': 'bg-1', 'text': 'Indexed files.'});
    await tester.pump();
    expect(find.byType(GatewayNoticeCard), findsNWidgets(2));

    // Leave the chat.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    // Come back to the same session over the same connection.
    await pumpChat(tester);
    expect(find.byType(GatewayNoticeCard), findsNothing);
  });

  testWidgets('review summaries stay in the transcript, not the tray', (
    tester,
  ) async {
    final sink = RecordingTurnNotificationSink();
    await pumpChat(tester, notifications: TurnNotificationService(sink: sink));

    background(tester);
    await tester.pump();

    send('review.summary', {'text': 'Two skills updated.'});
    await tester.pump();
    expect(sink.shown, isEmpty);

    send('background.complete', {'task_id': 'bg-9', 'text': 'Indexed files.'});
    await tester.pump();
    expect(sink.shown, hasLength(1));
    expect(sink.shown.single.title, 'Background task complete');
  });
}

class _EmptyChatHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'data': <Object>[]}))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'error': 'unexpected request'}))),
      404,
      headers: {'content-type': 'application/json'},
    );
  }
}
