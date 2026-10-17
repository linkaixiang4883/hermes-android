// Phase 3 of the mobile live-follow plan, widget half: entering a chat whose
// turn is still running must rebuild that turn — partial reply, its user row,
// and a "running" state — and follow it until the gateway stops reporting it.
//
// No socket is opened here: real local WS traffic cannot share a suite with
// TestWidgetsFlutterBinding (see the ownership/reattach suites, which drive
// their screens through `ChatScreen.test*Hook` seams for the same reason), so
// the live-turn delivery the shared client's listener would make is handed
// straight to the screen through [TestDesktopLiveTurnHook], while the client's
// own listener registration is pinned through the real
// [DesktopGatewayClient.liveTurnListenerCount].
//
// The history refetch that ends the follow is pinned through the injected
// ApiClient: the follow must hand the transcript back to the stored rows.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_live_turn.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

/// The mobile-side chat id this screen shows.
const _sessionId = 'follow-session';

/// The copy the follow state must show while the turn is still running.
const _followingCopy = 'Running · auto-syncing';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('entering a chat rebuilds the running turn and follows it', (
    tester,
  ) async {
    final hook = TestDesktopLiveTurnHook();
    final history = _FollowChatHttpClient();
    final bound = <DesktopGatewayClient>[];
    await _pumpChat(
      tester,
      hook: hook,
      history: history,
      onGatewayBound: bound.add,
    );

    expect(history.messageRequestCount, 1, reason: 'the initial hydration');
    final client = bound.single;
    expect(
      client.liveTurnListenerCount,
      1,
      reason:
          'the screen follows the shared connection: without a registration '
          'a fresh resume snapshot would never reach this page',
    );

    // The gateway answered the entry refresh with the running turn.
    hook.handler?.call(
      _sessionId,
      const LiveTurnProjection(
        running: true,
        status: 'running',
        user: 'hi',
        assistant: 'partial',
        streaming: true,
      ),
    );
    await tester.pump();

    expect(find.text(_followingCopy), findsOneWidget);
    expect(find.text('partial'), findsOneWidget);
    expect(find.text('hi'), findsOneWidget);

    // Idempotent: the same snapshot arriving again must not paint the turn
    // twice, and must not add a second user bubble for the same prompt.
    hook.handler?.call(
      _sessionId,
      const LiveTurnProjection(
        running: true,
        status: 'running',
        user: 'hi',
        assistant: 'partial',
        streaming: true,
      ),
    );
    await tester.pump();

    expect(find.text('hi'), findsOneWidget);
    expect(find.text('partial'), findsOneWidget);
    expect(find.text(_followingCopy), findsOneWidget);

    // A projection for another chat on the same shared connection is not this
    // screen's turn.
    hook.handler?.call(
      'another-session',
      const LiveTurnProjection(running: true, user: 'elsewhere'),
    );
    await tester.pump();
    expect(find.text('elsewhere'), findsNothing);

    await _dispose(tester);
    expect(
      client.liveTurnListenerCount,
      0,
      reason: 'the disposed screen detaches exactly its own listener',
    );
  });

  testWidgets('a prompt the transcript already holds is not added twice', (
    tester,
  ) async {
    final hook = TestDesktopLiveTurnHook();
    final history = _FollowChatHttpClient()
      ..rows = const [
        {'id': 1, 'role': 'user', 'content': 'hi'},
        {'id': 2, 'role': 'assistant', 'content': 'previous reply'},
      ];
    await _pumpChat(tester, hook: hook, history: history);

    expect(find.text('hi'), findsOneWidget);

    hook.handler?.call(
      _sessionId,
      const LiveTurnProjection(
        running: true,
        status: 'running',
        user: 'hi',
        assistant: 'partial',
        streaming: true,
      ),
    );
    await tester.pump();

    expect(
      find.text('hi'),
      findsOneWidget,
      reason:
          'the turn persists its user row before inference begins, so the '
          'resume snapshot and the stored transcript would paint it twice',
    );
    expect(find.text('partial'), findsOneWidget);
    expect(find.text(_followingCopy), findsOneWidget);
  });

  testWidgets('a turn that stopped running ends the follow and refetches', (
    tester,
  ) async {
    final hook = TestDesktopLiveTurnHook();
    final history = _FollowChatHttpClient();
    await _pumpChat(tester, hook: hook, history: history);

    hook.handler?.call(
      _sessionId,
      const LiveTurnProjection(
        running: true,
        status: 'running',
        user: 'hi',
        assistant: 'partial',
        streaming: true,
      ),
    );
    await tester.pump();
    expect(find.text(_followingCopy), findsOneWidget);
    final refetchesWhileFollowing = history.messageRequestCount;

    // The next refresh finds nothing running: the gateway reports no live
    // turn for this session at all (null), exactly what
    // `LiveTurnProjection.fromResume` yields for a bare snapshot.
    hook.handler?.call(_sessionId, null);
    await tester.pump();
    await tester.pump();

    expect(find.text(_followingCopy), findsNothing);
    expect(
      find.text('partial'),
      findsNothing,
      reason: 'the projection is replaced by the stored transcript',
    );
    expect(
      history.messageRequestCount,
      refetchesWhileFollowing + 1,
      reason:
          'the committed rows, not the snapshot, must own the transcript '
          'once the turn settles',
    );

    // A handful of non-live projections (a resume answering with the user row
    // only) is the other shape of the same transition; it must be idempotent.
    hook.handler?.call(
      _sessionId,
      const LiveTurnProjection(running: false, user: 'hi', status: 'idle'),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text(_followingCopy), findsNothing);
    expect(find.text('partial'), findsNothing);
    expect(history.messageRequestCount, refetchesWhileFollowing + 1);
  });
  testWidgets('a cold start follows a running turn and settles it', (
    tester,
  ) async {
    // Deliberately the FIRST thing this screen ever does with this chat: the
    // machine has been asleep, the app was just opened onto a chat that has
    // never been loaded, and the resume it issues as it mounts is the only
    // history this route has. (The entry case above pins the rebuild and its
    // idempotence; this one pins the whole cold lifetime — rebuild, live
    // settle, and the single refetch that hands the transcript back.)
    final hook = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final history = _FollowChatHttpClient();
    await _pumpChat(tester, hook: hook, history: history, asyncHook: asyncHook);

    expect(history.messageRequestCount, 1, reason: 'the initial hydration');
    expect(find.text('partial'), findsNothing);

    // The gateway was already running a turn for this chat when the screen
    // opened: nothing on screen precedes it.
    hook.handler?.call(
      _sessionId,
      const LiveTurnProjection(
        running: true,
        status: 'running',
        user: 'hi',
        assistant: 'partial',
        streaming: true,
      ),
    );
    await tester.pump();

    expect(find.text(_followingCopy), findsOneWidget);
    expect(find.text('partial'), findsOneWidget);
    expect(find.text('hi'), findsOneWidget);
    expect(
      find.byIcon(Icons.stop_rounded),
      findsOneWidget,
      reason: 'the followed turn is live: it keeps the stop affordance',
    );
    final refetchesWhileFollowing = history.messageRequestCount;

    // It settles on the live stream: the terminal frame is the only
    // end-of-turn signal a followed turn gets (Phase 4's branch).
    history.rows = const [
      {'id': 1, 'role': 'user', 'content': 'hi'},
      {'id': 2, 'role': 'assistant', 'content': 'the whole reply'},
    ];
    asyncHook.handler?.call(
      StreamEvent(
        type: 'message.complete',
        data: {'session_id': _sessionId, 'seq': 7, 'text': 'the whole reply'},
        sessionId: _sessionId,
        seq: 7,
        isComplete: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text(_followingCopy),
      findsNothing,
      reason: 'the turn settled: nothing is left to follow',
    );
    expect(find.text('partial'), findsNothing);
    expect(
      history.messageRequestCount,
      refetchesWhileFollowing + 1,
      reason:
          'the committed rows, not the cold-start snapshot, own the settled '
          'reply',
    );
    expect(find.text('the whole reply'), findsOneWidget);
  });
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required TestDesktopLiveTurnHook hook,
  required _FollowChatHttpClient history,
  TestDesktopAsyncEventHook? asyncHook,
  ValueChanged<DesktopGatewayClient>? onGatewayBound,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: _connection(),
        session: _session(),
        testApiClient: ApiClient(
          baseUrl: 'http://follow.fixture',
          apiKey: 'follow-fixture-key',
          httpClient: history,
        ),
        testDesktopLiveTurnHook: hook,
        testDesktopAsyncEventHook: asyncHook,
        testDesktopGatewayObserver: onGatewayBound,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
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

/// The desktop-gateway URL is unreachable on purpose: what is asserted is the
/// screen's own handling of a projection, not a live transport (that half is
/// covered by `desktop_gateway_live_turn_test.dart`).
SavedConnection _connection() => SavedConnection(
  id: 'conn-live-follow',
  label: 'Live follow fixture',
  host: 'follow.fixture',
  port: 8642,
  apiKey: 'follow-fixture-key',
  desktopGatewayUrl: 'https://gateway.invalid:8642',
);

Session _session() => const Session(
  id: _sessionId,
  title: 'Follow fixture chat',
  model: 'fixture-model',
  source: 'test',
  messageCount: 0,
  isActive: true,
  preview: '',
  startedAt: 1,
);

/// Serves the stored transcript and counts how many times the screen fetched
/// it, so the follow's exit can be pinned to a real refetch.
class _FollowChatHttpClient extends http.BaseClient {
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
