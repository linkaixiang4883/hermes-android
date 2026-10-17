// Phase 5 of the mobile live-follow plan, widget half: the two loose ends the
// Phase 4 review left behind.
//
// The transport reports a replay window the gateway's ring could not deliver
// hole-free (`onReplayTruncated`), and nothing consumed it: a phone that slept
// through a turn came back to a transcript with a silent hole. The screen now
// re-reads history for its own chat on that report, and the refetch runs
// through the same reconcile as every other wholesale replacement — so a turn
// being followed keeps its bubble while the committed rows land underneath it.
//
// The second half is the conflict between that reconcile and the older
// detached-turn recovery: a pending reattach resync watches the SAME terminal
// frame the follow branch consumes, and its retry tick knows nothing about the
// follow that just ended. Consuming the frame has to settle both, once.
//
// No socket is opened here: the deliveries the shared client's bridge would make
// are handed straight to the screen through [TestDesktopReplayTruncatedHook],
// [TestDesktopAsyncEventHook] and [TestDesktopLiveTurnHook] — the same seams the
// Phase 3/4 suites use, for the same reason (real local WS traffic cannot share
// a suite with TestWidgetsFlutterBinding).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hermes_android/core/models/projects_tree_overview.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_client_registry.dart';
import 'package:hermes_android/core/services/gateway_live_turn.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

/// The mobile-side chat id this screen shows.
const _sessionId = 'truncated-session';

/// The copy the follow state shows while the turn is still running.
const _followingCopy = 'Running · auto-syncing';

/// The snapshot a `session.resume` answers with for a running turn.
const _runningTurn = LiveTurnProjection(
  running: true,
  status: 'running',
  user: 'hi',
  assistant: 'partial',
  streaming: true,
);

/// A terminal frame for [type].
StreamEvent _terminal(String type, {required int seq}) => StreamEvent(
  type: type,
  data: {'session_id': _sessionId, 'seq': seq},
  sessionId: _sessionId,
  seq: seq,
  isComplete: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a truncated replay re-reads this chat and keeps the follow', (
    tester,
  ) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final truncation = TestDesktopReplayTruncatedHook();
    final bound = <DesktopGatewayClient>[];
    final registry = GatewayClientRegistry();
    addTearDown(registry.close);
    final history = _TruncatedFollowHttpClient()
      ..rows = const [
        {'id': 1, 'role': 'user', 'content': 'hi'},
      ];
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      truncationHook: truncation,
      gatewayRegistry: registry,
      onGatewayBound: bound.add,
    );

    expect(
      bound.single.replayTruncatedListenerCount,
      1,
      reason:
          'the screen reads this chat\'s history: without a registration on '
          'the shared connection a truncated window never reaches this page',
    );

    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();
    expect(find.text('partial'), findsOneWidget);
    final refetchesWhileFollowing = history.messageRequestCount;

    // The shared connection carries every session: another chat's hole is
    // another chat's re-read, and must not pull this transcript.
    truncation.handler?.call('another-session');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      history.messageRequestCount,
      refetchesWhileFollowing,
      reason: 'the report names the chat whose stream has the hole',
    );

    // This chat's own window was evicted: the frames that would have carried
    // the missing prefix, tool state or terminal frame are gone, so the only
    // backfill is a history re-read.
    truncation.handler?.call(_sessionId);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      history.messageRequestCount,
      refetchesWhileFollowing + 1,
      reason: 'the truncated window is repaired by re-reading history',
    );
    expect(
      find.text('partial'),
      findsOneWidget,
      reason:
          'the backfill replaces the COMMITTED rows only: the turn this screen '
          'is following is replayed on top of them, not dropped with the page',
    );
    expect(find.text(_followingCopy), findsOneWidget);
    expect(find.text('hi'), findsOneWidget);

    // The registration is this route's own, and it goes when the route does:
    // the connection is shared with the rest of the app (and borrowed here, so
    // nothing closes it), and a listener left behind would keep re-reading
    // history for a chat nobody is showing.
    await _dispose(tester);
    expect(
      bound.single.isClosed,
      isFalse,
      reason: 'a borrowed connection outlives the route that borrowed it',
    );
    expect(bound.single.replayTruncatedListenerCount, 0);
  });

  testWidgets('a terminal frame captures a pending reattach resync once', (
    tester,
  ) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final connectionHook = TestDesktopConnectionHook();
    final submission = Completer<void>();
    final history = _TruncatedFollowHttpClient();
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      asyncHook: asyncHook,
      connectionHook: connectionHook,
      // A chat whose first prompt is still in flight: it has no stored row
      // yet, so the reattach resync goes straight to the authoritative fetch
      // instead of re-binding a session the server has never seen.
      localDraft: true,
      remoteSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            onSent();
            return submission.future;
          },
    );

    connectionHook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Local prompt');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Local prompt'), findsOneWidget);

    // The socket drops with a submitted prompt in flight: the detached-turn
    // recovery arms, and its resync will keep pulling history until it sees
    // terminal evidence. Both transitions are handed over with no frame in
    // between, so a state the client emits on its own cannot sit in the middle
    // — and the notice is the arming itself, so the rest of this test really
    // runs against an armed resync instead of an idle one.
    connectionHook.handler?.call(DesktopConnectionState.connected);
    connectionHook.handler?.call(DesktopConnectionState.reconnecting);
    await tester.pump();
    expect(
      find.textContaining('the running reply continues on the server'),
      findsOneWidget,
      reason: 'the drop was seen as a drop: the detached-turn resync is armed',
    );

    // The resume reports the same turn as running: this screen follows it. The
    // bubbles stay the submit's own, so the follow is entered with NO
    // projection row of its own.
    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();
    expect(find.text(_followingCopy), findsOneWidget);

    history.rows = const [
      {'id': 1, 'role': 'user', 'content': 'hi'},
      {'id': 2, 'role': 'assistant', 'content': 'the settled reply'},
    ];
    final refetchesBeforeSettle = history.messageRequestCount;

    // The frame arrives before this screen's own `connected` transition, which
    // is exactly the ordering the resync is paused for: the async bridge is fed
    // by the socket, the connection state by a listener of its own.
    asyncHook.handler?.call(_terminal('message.complete', seq: 9));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The follow branch consumed the frame, so the exit's own refetch is the
    // capture — not a read the pending guard silently swallows.
    expect(
      history.messageRequestCount,
      refetchesBeforeSettle + 1,
      reason: 'the settled turn is read back exactly once',
    );
    expect(
      find.text('the settled reply'),
      findsOneWidget,
      reason: 'the committed rows take the transcript back',
    );
    expect(
      find.text(_followingCopy),
      findsNothing,
      reason:
          'the follow is over: no status bar may stand over a projection row '
          'that no longer exists',
    );
    expect(find.text('partial'), findsNothing);
    expect(
      find.byIcon(Icons.stop_rounded),
      findsNothing,
      reason: 'there is no running turn left to stop',
    );

    // Reconnecting now must not start a second pull: the resync was settled by
    // the same frame, so its retry tick and generation are gone with it.
    connectionHook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(
      history.messageRequestCount,
      refetchesBeforeSettle + 1,
      reason:
          'a resync left armed behind a settled follow would keep refetching '
          'and race the transcript the follow already replaced',
    );
    expect(find.text('the settled reply'), findsOneWidget);

    // ...and the composer is free again, which is the other half of "cleared":
    // the send affordance is gated on exactly this flag, so an enabled button
    // is the pending resync being gone rather than merely idle. (Read, not
    // tapped: the arming notice is still over the composer as a SnackBar.)
    final sendButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Send'),
        matching: find.byType(IconButton),
      ),
    );
    expect(
      sendButton.onPressed,
      isNotNull,
      reason:
          'a resync left armed holds the composer back; the follow that '
          'settled the turn owns that state and must release it',
    );

    submission.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('an exited follow does not repaint over a local pending turn', (
    tester,
  ) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final truncation = TestDesktopReplayTruncatedHook();
    final connectionHook = TestDesktopConnectionHook();
    final submission = Completer<void>();
    final history = _TruncatedFollowHttpClient()
      ..rows = const [
        {'id': 1, 'role': 'user', 'content': 'hi'},
      ];
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      asyncHook: asyncHook,
      truncationHook: truncation,
      connectionHook: connectionHook,
      remoteSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            onSent();
            return submission.future;
          },
    );
    connectionHook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();

    // A turn this screen did not submit is followed, and then settles.
    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();
    expect(find.text('partial'), findsOneWidget);
    history.rows = const [
      {'id': 1, 'role': 'user', 'content': 'hi'},
      {'id': 2, 'role': 'assistant', 'content': 'the settled reply'},
    ];
    asyncHook.handler?.call(_terminal('message.complete', seq: 9));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('partial'), findsNothing, reason: 'the follow is over');

    // The next prompt is this screen's own: its bubbles belong to that submit,
    // not to the turn that just settled.
    await tester.enterText(find.byType(TextField), 'Next prompt');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Next prompt'), findsOneWidget);
    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();
    expect(find.text(_followingCopy), findsOneWidget);
    expect(
      find.text('partial'),
      findsNothing,
      reason: 'a locally pending reply owns its bubbles',
    );

    // Any wholesale replacement reaches the same rule; the truncated-replay
    // backfill is the one a sleeping phone actually triggers.
    final refetchesBeforeBackfill = history.messageRequestCount;
    truncation.handler?.call(_sessionId);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      history.messageRequestCount,
      greaterThan(refetchesBeforeBackfill),
      reason:
          'the backfill really replaced the transcript: the assertions below '
          'are about what that replacement may repaint, not about a refetch '
          'that never happened',
    );

    expect(
      find.text('partial'),
      findsNothing,
      reason:
          'the snapshot belongs to the turn that ended: without clearing it on '
          'exit, the next reconcile would replay it over the turn the user '
          'just started',
    );
    expect(
      find.text(_followingCopy),
      findsNothing,
      reason: 'the replacement removed the rows the follow was entered with',
    );

    submission.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required _TruncatedFollowHttpClient history,
  TestDesktopLiveTurnHook? liveTurnHook,
  TestDesktopAsyncEventHook? asyncHook,
  TestDesktopReplayTruncatedHook? truncationHook,
  TestDesktopConnectionHook? connectionHook,
  TestRemotePromptSubmit? remoteSubmit,
  ValueChanged<DesktopGatewayClient>? onGatewayBound,
  GatewayClientRegistry? gatewayRegistry,
  bool localDraft = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: _connection(),
        session: _session(localDraft: localDraft),
        gatewayRegistry: gatewayRegistry,
        testApiClient: ApiClient(
          baseUrl: 'http://truncated.fixture',
          apiKey: 'truncated-fixture-key',
          httpClient: history,
        ),
        testDesktopLiveTurnHook: liveTurnHook,
        testDesktopAsyncEventHook: asyncHook,
        testDesktopReplayTruncatedHook: truncationHook,
        testDesktopConnectionHook: connectionHook,
        testRemotePromptSubmit: remoteSubmit,
        testDesktopGatewayObserver: onGatewayBound,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        // The gateway is unreachable on purpose; answering the sticky-header
        // lookup here keeps the client from starting a connection attempt the
        // test would then have to out-race (it emits connection states of its
        // own, which these scenarios drive explicitly).
        testProjectOverviewLoader: () async => ProjectsTreeOverview.empty,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

/// Replaces the tree so the chat screen's [State.dispose] runs.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// The gateway URL is unreachable on purpose — and loopback, so the attempt
/// fails on a refused connection instead of a DNS timeout: what is asserted is
/// the screen's own handling of the reports and frames it is handed.
SavedConnection _connection() => SavedConnection(
  id: 'conn-truncated-follow',
  label: 'Truncated follow fixture',
  host: 'truncated.fixture',
  port: 8642,
  apiKey: 'truncated-fixture-key',
  desktopGatewayUrl: 'http://127.0.0.1:1',
);

Session _session({bool localDraft = false}) => Session(
  id: _sessionId,
  title: 'Truncated follow fixture chat',
  model: 'fixture-model',
  source: 'test',
  messageCount: 0,
  isActive: true,
  preview: '',
  startedAt: 1,
  isLocalDraft: localDraft,
);

/// Serves the stored transcript and counts how many times the screen fetched
/// it, so a backfill's single refetch can be pinned.
class _TruncatedFollowHttpClient extends http.BaseClient {
  int messageRequestCount = 0;

  /// The committed rows the gateway holds for this chat.
  List<Map<String, dynamic>> rows = const [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      messageRequestCount += 1;
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'data': rows}))),
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
