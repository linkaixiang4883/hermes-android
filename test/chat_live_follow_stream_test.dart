// Phase 4 of the mobile live-follow plan, widget half: a followed turn must
// KEEP STREAMING, not just paint the snapshot it was rebuilt from.
//
// Phase 3 rebuilt the running turn from the `session.resume` inflight snapshot
// and then watched for its end, but every asynchronous frame that would have
// grown the reply was still dropped by the transport's async bridge, and the
// screen routed none of them into the followed bubble. This suite pins the
// whole follow lifetime:
//
// - stream frames (`message.delta`, `message.interim`, `tool.*`, reasoning)
//   reach the projected row/bubble while the screen follows the turn;
// - a frame delivered twice — the shared connection reaches this screen over
//   more than one registration, and a replay can overlap a live frame — is
//   applied once, mirroring the transport's own seq watermark;
// - a locally submitted turn keeps ownership of its own frames: the bridge
//   copy of a frame the submit listener already applied must not paint it a
//   second time;
// - terminal frames (`message.complete`/`turn.end`/`turn.error`/`error`) end
//   the follow, hand the transcript back to the committed rows and surface the
//   same failure notice the detached-turn recovery shows;
// - the stop button ends a followed turn honestly (no "no active gateway turn"
//   notice) and leaves no projection behind for a late frame to resurrect;
// - a wholesale transcript replacement (the reattach resync) leaves no follow
//   state pointing at rows that no longer exist.
//
// No socket is opened here: the delivery the shared client's bridge would make
// is handed straight to the screen through [TestDesktopAsyncEventHook], and
// the projection the client's live-turn listener would publish through
// [TestDesktopLiveTurnHook] — the same seams the Phase 3 suites use, for the
// same reason (real local WS traffic cannot share a suite with
// TestWidgetsFlutterBinding).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hermes_android/core/models/projects_tree_overview.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_live_turn.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/widgets/gateway_activity_card.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

/// The mobile-side chat id this screen shows.
const _sessionId = 'stream-session';

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

/// A streamed delta as the socket delivers it: the seq is the session's
/// monotonic watermark, carried on the envelope (never inside the payload).
StreamEvent _delta(String text, {required int seq, String? turnId}) =>
    StreamEvent(
      type: 'message.delta',
      data: {'text': text, 'session_id': _sessionId, 'seq': seq},
      sessionId: _sessionId,
      turnId: turnId,
      seq: seq,
    );

/// A tool progress frame, minimal shape (`tool_id` + `name`).
StreamEvent _tool(String type, {required String id, required String name}) =>
    StreamEvent(
      type: type,
      data: {'tool_id': id, 'name': name, 'session_id': _sessionId},
      sessionId: _sessionId,
    );

/// A terminal frame for [type].
StreamEvent _terminal(
  String type, {
  Map<String, dynamic> data = const {},
  int? seq,
}) => StreamEvent(
  type: type,
  data: {'session_id': _sessionId, 'seq': ?seq, ...data},
  sessionId: _sessionId,
  seq: seq,
  isComplete: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the async bridge carries the followed turn\'s stream', () {
    test('forwards stream frames, including the tool family', () {
      for (final type in const [
        'message.delta',
        'message.interim',
        'reasoning.delta',
        'thinking.delta',
        'reasoning.available',
        'tool.start',
        'tool.complete',
        'tool.progress',
      ]) {
        expect(
          DesktopGatewayClient.shouldBridgeAsyncEvent(type),
          isTrue,
          reason: '$type must reach a following screen',
        );
      }
    });

    test('keeps the pre-Phase-4 filtering for everything else', () {
      for (final type in const [
        'message.start',
        'turn.start',
        'session.updated',
        'tools.ready',
        'gateway.ready',
      ]) {
        expect(
          DesktopGatewayClient.shouldBridgeAsyncEvent(type),
          isFalse,
          reason: '$type has no consumer on the bridge',
        );
      }
    });
  });

  testWidgets('a streamed delta grows the followed turn', (tester) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final history = _StreamHistoryHttpClient()
      ..rows = const [
        {'id': 1, 'role': 'user', 'content': 'hi'},
      ];
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      asyncHook: asyncHook,
    );

    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();
    expect(find.text('partial'), findsOneWidget);
    expect(find.text(_followingCopy), findsOneWidget);

    asyncHook.handler?.call(_delta(' keeps going', seq: 2));
    await tester.pump();

    expect(
      find.text('partial keeps going'),
      findsOneWidget,
      reason:
          'the follow must keep receiving the turn, not freeze on the '
          'snapshot it was rebuilt from',
    );
    expect(
      find.byIcon(Icons.stop_rounded),
      findsOneWidget,
      reason:
          'the turn is still running: the follow keeps the stop affordance '
          'up (the "auto-syncing" status line itself is the "no content yet" '
          'indicator the stream handlers clear, as they do for a local turn)',
    );
  });

  testWidgets('a streamed interim replaces the followed reply in place', (
    tester,
  ) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final history = _StreamHistoryHttpClient();
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      asyncHook: asyncHook,
    );

    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();

    asyncHook.handler?.call(
      StreamEvent(
        type: 'message.interim',
        data: {
          // The full reply as the gateway already streamed it: the interim
          // seals the reply it replaces instead of appending to it.
          'text': 'partial, corrected',
          'session_id': _sessionId,
          'seq': 3,
          'already_streamed': true,
        },
        sessionId: _sessionId,
        seq: 3,
      ),
    );
    await tester.pump();

    expect(find.text('partial, corrected'), findsOneWidget);
    expect(
      find.text('partial'),
      findsNothing,
      reason: 'interim text seals the reply it replaces, it does not append',
    );
  });

  testWidgets('a duplicate stream frame is applied once', (tester) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final history = _StreamHistoryHttpClient();
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      asyncHook: asyncHook,
    );

    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();

    // The same frame, delivered twice: the shared connection reaches this
    // screen over more than one registration, and a replayed frame can
    // overlap a live one. The transport gates them by seq; a frame that gets
    // past it twice must not be written twice.
    final frame = _delta(' keeps going', seq: 2);
    asyncHook.handler?.call(frame);
    await tester.pump();
    asyncHook.handler?.call(frame);
    await tester.pump();

    expect(find.text('partial keeps going'), findsOneWidget);
    expect(
      find.text('partial keeps going keeps going'),
      findsNothing,
      reason: 'a redelivered frame is the same frame, not another token',
    );
  });

  testWidgets('a distinct frame sharing the duplicate\'s scope still lands', (
    tester,
  ) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final history = _StreamHistoryHttpClient();
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      asyncHook: asyncHook,
    );

    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();

    asyncHook.handler?.call(_delta(' one', seq: 2));
    await tester.pump();
    asyncHook.handler?.call(_delta(' two', seq: 3));
    await tester.pump();

    expect(
      find.text('partial one two'),
      findsOneWidget,
      reason: 'the watermark only drops what it has already applied',
    );
  });

  testWidgets('tool frames reach the followed turn\'s activity card', (
    tester,
  ) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final history = _StreamHistoryHttpClient();
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      asyncHook: asyncHook,
    );

    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();

    asyncHook.handler?.call(_tool('tool.start', id: 't1', name: 'web_search'));
    await tester.pump();

    expect(find.byType(GatewayActivityCard), findsOneWidget);
    expect(
      find.text('🔧 Web search'),
      findsOneWidget,
      reason: 'the running tool is on the card, not just in the status line',
    );

    asyncHook.handler?.call(
      StreamEvent(
        type: 'tool.complete',
        data: {
          'tool_id': 't1',
          'name': 'web_search',
          'duration_s': 2.0,
          'session_id': _sessionId,
        },
        sessionId: _sessionId,
      ),
    );
    await tester.pump();

    expect(
      find.text('Completed in 2.0 s'),
      findsOneWidget,
      reason: 'the same tool id updates the running card instead of adding one',
    );
    expect(find.byType(GatewayActivityCard), findsOneWidget);
  });

  testWidgets('a reasoning frame reaches the followed turn\'s thinking block', (
    tester,
  ) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final history = _StreamHistoryHttpClient();
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      asyncHook: asyncHook,
    );

    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();

    asyncHook.handler?.call(
      StreamEvent(
        type: 'reasoning.delta',
        data: {'text': 'weighing options', 'session_id': _sessionId, 'seq': 4},
        sessionId: _sessionId,
        seq: 4,
      ),
    );
    await tester.pump();

    // The card's own children are lazily built while it is collapsed, so the
    // thinking is read off the card the frame produced.
    final reasoningCard = tester.widget<GatewayReasoningCard>(
      find.byType(GatewayReasoningCard),
    );
    expect(
      reasoningCard.text,
      'weighing options',
      reason: 'the streamed thinking reached the followed turn',
    );
  });

  testWidgets(
    'the reasoning card stays open while the thinking keeps streaming',
    (tester) async {
      final liveTurn = TestDesktopLiveTurnHook();
      final asyncHook = TestDesktopAsyncEventHook();
      final history = _StreamHistoryHttpClient();
      await _pumpChat(
        tester,
        history: history,
        liveTurnHook: liveTurn,
        asyncHook: asyncHook,
      );

      liveTurn.handler?.call(_sessionId, _runningTurn);
      await tester.pump();

      asyncHook.handler?.call(
        StreamEvent(
          type: 'reasoning.delta',
          data: {'text': 'weighing options', 'session_id': _sessionId, 'seq': 4},
          sessionId: _sessionId,
          seq: 4,
        ),
      );
      await tester.pump();
      expect(find.byType(GatewayReasoningCard), findsOneWidget);

      await tester.tap(find.byType(GatewayReasoningCard));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.text('weighing options'),
        findsOneWidget,
        reason: 'the tapped reasoning card must open',
      );

      // Another token grows the SAME block: its expansion must survive the
      // rebuild (the tile identity is the block, not its current text).
      asyncHook.handler?.call(
        StreamEvent(
          type: 'reasoning.delta',
          data: {'text': ' and more', 'session_id': _sessionId, 'seq': 5},
          sessionId: _sessionId,
          seq: 5,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('weighing options and more'),
        findsOneWidget,
        reason:
            'a streaming token must not rebuild the tile into a closed one '
            '(the "cannot open while it streams" report)',
      );
    },
  );

  testWidgets(
    'a completed tool card opens and stays open while the turn streams on',
    (tester) async {
      final liveTurn = TestDesktopLiveTurnHook();
      final asyncHook = TestDesktopAsyncEventHook();
      final history = _StreamHistoryHttpClient();
      await _pumpChat(
        tester,
        history: history,
        liveTurnHook: liveTurn,
        asyncHook: asyncHook,
      );

      liveTurn.handler?.call(_sessionId, _runningTurn);
      await tester.pump();

      asyncHook.handler?.call(
        _tool('tool.start', id: 't1', name: 'web_search'),
      );
      asyncHook.handler?.call(
        StreamEvent(
          type: 'tool.progress',
          data: {
            'tool_id': 't1',
            'name': 'web_search',
            'detail': 'searching the web',
            'session_id': _sessionId,
          },
          sessionId: _sessionId,
        ),
      );
      asyncHook.handler?.call(
        _tool('tool.complete', id: 't1', name: 'web_search'),
      );
      await tester.pump();
      expect(find.byType(GatewayActivityCard), findsOneWidget);
      expect(
        find.text('searching the web'),
        findsNothing,
        reason: 'a finished card starts collapsed',
      );

      await tester.tap(find.byType(GatewayActivityCard));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.text('searching the web'),
        findsOneWidget,
        reason: 'the tapped tool card must open',
      );

      asyncHook.handler?.call(
        StreamEvent(
          type: 'message.delta',
          data: {'text': ' next', 'session_id': _sessionId, 'seq': 6},
          sessionId: _sessionId,
          seq: 6,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('searching the web'),
        findsOneWidget,
        reason: 'a later streamed token must not collapse the opened card',
      );
    },
  );

  testWidgets(
    'the streaming follow holds while a finger is on the transcript',
    (tester) async {
      final liveTurn = TestDesktopLiveTurnHook();
      final asyncHook = TestDesktopAsyncEventHook();
      final history = _StreamHistoryHttpClient()
        ..rows = [
          {'id': 1, 'role': 'user', 'content': 'hi'},
          for (var i = 0; i < 40; i++)
            {'id': 100 + i, 'role': 'assistant', 'content': 'filler line $i'},
        ];
      await _pumpChat(
        tester,
        history: history,
        liveTurnHook: liveTurn,
        asyncHook: asyncHook,
      );

      liveTurn.handler?.call(_sessionId, _runningTurn);
      await tester.pump();
      asyncHook.handler?.call(_delta(' one', seq: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final listView = tester.widget<ListView>(
        find.byType(ListView).first,
      );
      final controller = listView.controller!;
      expect(
        controller.offset,
        controller.position.maxScrollExtent,
        reason: 'the follow sits at the end before the touch',
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView).first),
      );
      addTearDown(() async {
        try {
          await gesture.up();
        } catch (_) {}
      });
      final heldOffset = controller.offset;

      // Long enough to wrap: the assertion below is about real layout growth,
      // not about the string differing.
      asyncHook.handler?.call(_delta(' ${'streaming words ' * 40}', seq: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        controller.position.maxScrollExtent,
        greaterThan(heldOffset),
        reason: 'the streamed text grew under the finger',
      );
      expect(
        controller.offset,
        heldOffset,
        reason:
            'a finger on the transcript must hold the auto-follow — jumping '
            'under it is what swallowed taps on the reasoning/tool cards',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        controller.offset,
        controller.position.maxScrollExtent,
        reason: 'lifting the finger catches up to the end',
      );
    },
  );

  testWidgets('a terminal frame ends the follow and refetches the transcript', (
    tester,
  ) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final history = _StreamHistoryHttpClient()
      ..rows = const [
        {'id': 1, 'role': 'user', 'content': 'hi'},
        {'id': 2, 'role': 'assistant', 'content': 'the whole reply'},
      ];
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      asyncHook: asyncHook,
    );

    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();
    expect(find.text('partial'), findsOneWidget);
    final refetchesWhileFollowing = history.messageRequestCount;

    asyncHook.handler?.call(
      _terminal('message.complete', data: {'text': 'the whole reply'}, seq: 9),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text(_followingCopy),
      findsNothing,
      reason: 'the turn settled: there is nothing left to follow',
    );
    expect(
      find.text('partial'),
      findsNothing,
      reason: 'the projection row goes with the follow',
    );
    expect(
      history.messageRequestCount,
      refetchesWhileFollowing + 1,
      reason: 'the committed rows must own the settled reply',
    );
    expect(find.text('the whole reply'), findsOneWidget);
  });

  testWidgets('a failed followed turn reports the failure and ends the follow', (
    tester,
  ) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final history = _StreamHistoryHttpClient();
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      asyncHook: asyncHook,
    );

    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();

    asyncHook.handler?.call(
      _terminal(
        'turn.error',
        data: {'status': 'error', 'message': 'Provider unavailable'},
        seq: 10,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('The detached reply failed: Provider unavailable'),
      findsOneWidget,
      reason: 'a followed turn that died must say so, not just vanish',
    );
    expect(find.text(_followingCopy), findsNothing);
    expect(find.text('partial'), findsNothing);
  });

  testWidgets('a failure frame without a message still ends the follow', (
    tester,
  ) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final history = _StreamHistoryHttpClient();
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      asyncHook: asyncHook,
    );

    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();

    asyncHook.handler?.call(_terminal('error', data: {'status': 'error'}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('The detached reply failed.'), findsOneWidget);
    expect(find.text(_followingCopy), findsNothing);
  });

  testWidgets('a stream frame outside a follow does not paint', (tester) async {
    final asyncHook = TestDesktopAsyncEventHook();
    final history = _StreamHistoryHttpClient()
      ..rows = const [
        {'id': 1, 'role': 'user', 'content': 'hi'},
        {'id': 2, 'role': 'assistant', 'content': 'previous reply'},
      ];
    await _pumpChat(tester, history: history, asyncHook: asyncHook);

    expect(find.text('previous reply'), findsOneWidget);

    // Nothing is being followed: this screen is showing stored rows, so a
    // frame from another turn has no bubble of its own to land in and must
    // stay dropped — the bridge carrying stream frames is not a licence for
    // every listener to render them.
    asyncHook.handler?.call(_delta(' not mine', seq: 2));
    asyncHook.handler?.call(
      _tool('tool.start', id: 't9', name: 'web_search'),
    );
    await tester.pump();

    expect(
      find.text('previous reply'),
      findsOneWidget,
      reason: 'the stored reply is not what the streamed delta lands in',
    );
    expect(find.textContaining('not mine'), findsNothing);
    expect(find.byType(GatewayActivityCard), findsNothing);
  });

  testWidgets('a locally submitted turn keeps its frames to itself', (
    tester,
  ) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final connectionHook = TestDesktopConnectionHook();
    final submission = Completer<void>();
    StreamCallback? submitEvents;
    final history = _StreamHistoryHttpClient();
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      asyncHook: asyncHook,
      connectionHook: connectionHook,
      remoteSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            submitEvents = onEvent;
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

    // The shared connection reports the same turn as running: the follow state
    // is entered, but the bubbles belong to the submit that started it.
    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();
    expect(find.text(_followingCopy), findsOneWidget);
    expect(find.text('partial'), findsNothing);

    // One frame, two paths: the async bridge and the submit listener. The
    // submit owns the turn while it is in flight, so its copy is the only one
    // that may paint.
    final frame = _delta('token', seq: 4);
    asyncHook.handler?.call(frame);
    await tester.pump();
    submitEvents!(frame);
    await tester.pump();

    expect(find.text('token'), findsOneWidget);
    expect(
      find.text('tokentoken'),
      findsNothing,
      reason: 'the same frame must not be painted once per delivery path',
    );

    submission.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('stopping a followed turn ends it without a ghost reply', (
    tester,
  ) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final history = _StreamHistoryHttpClient()
      ..rows = const [
        {'id': 1, 'role': 'user', 'content': 'hi'},
      ];
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      asyncHook: asyncHook,
    );

    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();
    expect(find.text('partial'), findsOneWidget);
    final refetchesWhileFollowing = history.messageRequestCount;
    history.rows = const [
      {'id': 1, 'role': 'user', 'content': 'hi'},
      {'id': 2, 'role': 'assistant', 'content': 'stopped reply'},
    ];

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(_followingCopy), findsNothing);
    expect(find.text('partial'), findsNothing);
    expect(
      find.text(
        'Response closed locally; no active gateway turn was found.',
      ),
      findsNothing,
      reason:
          'the followed turn IS the active gateway turn: claiming otherwise '
          'is the misleading notice this path used to show',
    );
    expect(
      history.messageRequestCount,
      refetchesWhileFollowing + 1,
      reason: 'the committed rows take the transcript back',
    );
    expect(find.text('stopped reply'), findsOneWidget);

    // A frame that crossed the stop must not resurrect the projection: the
    // follow is over, so nothing this screen renders can receive it.
    asyncHook.handler?.call(_delta(' late-token', seq: 6));
    await tester.pump();
    expect(find.textContaining('late-token'), findsNothing);
  });

  testWidgets('the stop reaches the gateway on the shared interrupt channel', (
    tester,
  ) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final history = _StreamHistoryHttpClient();
    final bound = <DesktopGatewayClient>[];
    await _pumpChat(
      tester,
      history: history,
      liveTurnHook: liveTurn,
      onGatewayBound: bound.add,
    );

    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();
    expect(find.text(_followingCopy), findsOneWidget);

    // The transport is unreachable in this suite, so the interrupt cannot be
    // acknowledged — but the attempt must not throw out of the stop path, and
    // the follow must end either way.
    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(bound, hasLength(1), reason: 'the screen really owns a gateway');
    expect(find.text(_followingCopy), findsNothing);
    expect(tester.takeException(), isNull);
  });


  group('a turn this screen never submitted', () {
    testWidgets(
      'its frames ask for the live snapshot, and the answer walks the follow',
      (tester) async {
        final liveTurn = TestDesktopLiveTurnHook();
        final asyncHook = TestDesktopAsyncEventHook();
        final refreshCalls = <bool>[];
        final history = _StreamHistoryHttpClient()
          ..rows = const [
            {'id': 1, 'role': 'user', 'content': 'hi'},
          ];
        await _pumpChat(
          tester,
          history: history,
          liveTurnHook: liveTurn,
          asyncHook: asyncHook,
          ensureHook: refreshCalls.add,
        );
        expect(find.text(_followingCopy), findsNothing);

        // A running turn this screen did not submit announces itself the
        // only way it can: a stream frame. The frame is not rendered — only
        // a resume answer may rebuild a turn — but it is the signal that a
        // fresh resume is one request away.
        final before = refreshCalls.length;
        asyncHook.handler?.call(_delta(' ext', seq: 9));
        await tester.pump();

        expect(
          refreshCalls.length,
          before + 1,
          reason:
              'a stream frame of a turn this screen neither submitted nor '
              'follows must ask the gateway what is running',
        );
        expect(
          refreshCalls.last,
          isTrue,
          reason:
              'the ask must refresh: a plain ensure would reuse the very '
              'snapshot that predates the turn',
        );

        // The resume's answer: the projection its listener publishes, which
        // is the normal follow entry.
        liveTurn.handler?.call(_sessionId, _runningTurn);
        await tester.pump();
        expect(find.text(_followingCopy), findsOneWidget);
        expect(find.text('partial'), findsOneWidget);
        expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

        // While following, frames belong to the follow: they render, and ask
        // for nothing further.
        final whileFollowing = refreshCalls.length;
        asyncHook.handler?.call(_delta(' more', seq: 10));
        await tester.pump();
        expect(find.text('partial more'), findsOneWidget);
        expect(
          refreshCalls.length,
          whileFollowing,
          reason: 'a followed screen applies frames; it does not re-attach',
        );
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets('the frames of one running turn ask once', (tester) async {
      final liveTurn = TestDesktopLiveTurnHook();
      final asyncHook = TestDesktopAsyncEventHook();
      final refreshCalls = <bool>[];
      await _pumpChat(
        tester,
        history: _StreamHistoryHttpClient(),
        liveTurnHook: liveTurn,
        asyncHook: asyncHook,
        ensureHook: refreshCalls.add,
      );

      final before = refreshCalls.length;
      // A burst, delivered the way a stream delivers it: frame after frame
      // in the same event-loop turn.
      asyncHook.handler?.call(_delta(' a', seq: 9));
      asyncHook.handler?.call(_delta(' b', seq: 10));
      await tester.pump();

      expect(
        refreshCalls.length,
        before + 1,
        reason:
            'frames of the same turn all mean one question — what is '
            'running — so one resume is in flight at a time',
      );
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a local submission keeps owning its stream', (tester) async {
      final liveTurn = TestDesktopLiveTurnHook();
      final asyncHook = TestDesktopAsyncEventHook();
      final refreshCalls = <bool>[];
      final submission = Completer<void>();
      await _pumpChat(
        tester,
        history: _StreamHistoryHttpClient(),
        liveTurnHook: liveTurn,
        asyncHook: asyncHook,
        ensureHook: refreshCalls.add,
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

      await tester.enterText(find.byType(TextField), 'Local prompt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();

      final before = refreshCalls.length;
      asyncHook.handler?.call(_delta(' ghost-token', seq: 9));
      await tester.pump();
      expect(
        find.textContaining('ghost-token'),
        findsNothing,
        reason: 'the submit owns the bubbles; the bridge copy is a duplicate',
      );
      expect(
        refreshCalls.length,
        before,
        reason:
            'a frame while this screen owns a submission is that '
            "submission's, not an invitation to re-attach",
      );

      submission.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  testWidgets('a replacement during a follow leaves no orphan status bar', (
    tester,
  ) async {
    final liveTurn = TestDesktopLiveTurnHook();
    final asyncHook = TestDesktopAsyncEventHook();
    final connectionHook = TestDesktopConnectionHook();
    final submission = Completer<void>();
    final history = _StreamHistoryHttpClient();
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

    // The resume reports the turn as running while this screen's own submit
    // owns the bubbles: the follow is entered with NO projection row of its
    // own — the local pending reply plays that part.
    liveTurn.handler?.call(_sessionId, _runningTurn);
    await tester.pump();
    expect(find.text(_followingCopy), findsOneWidget);
    expect(find.text('partial'), findsNothing);

    // The socket drops with a submitted prompt in flight: reattach recovery
    // arms, and the reconnect resync will replace the transcript wholesale.
    // (Both transitions are handed over with no frame in between, so a state
    // the client emits on its own cannot sit in the middle.)
    connectionHook.handler?.call(DesktopConnectionState.connected);
    connectionHook.handler?.call(DesktopConnectionState.reconnecting);
    await tester.pump();

    history.rows = const [
      {'id': 1, 'role': 'user', 'content': 'hi'},
      {'id': 2, 'role': 'assistant', 'content': 'recovered reply'},
    ];
    connectionHook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final fetchesAfterResync = history.messageRequestCount;
    expect(
      fetchesAfterResync,
      greaterThan(1),
      reason: 'the resync refetched the transcript it then replaced',
    );

    expect(
      find.text('recovered reply'),
      findsOneWidget,
      reason: 'the resync owns the transcript after the replacement',
    );
    expect(
      find.text(_followingCopy),
      findsNothing,
      reason:
          'the projection row and the locally pending reply it pointed at '
          'were both replaced: the follow state must go with them instead of '
          'standing over rows that no longer exist',
    );

    // And the follow is really over: a frame that crossed the replacement has
    // nothing to paint into.
    asyncHook.handler?.call(_delta(' ghost-token', seq: 11));
    await tester.pump();
    expect(find.textContaining('ghost-token'), findsNothing);

    submission.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required _StreamHistoryHttpClient history,
  TestDesktopLiveTurnHook? liveTurnHook,
  TestDesktopAsyncEventHook? asyncHook,
  TestDesktopConnectionHook? connectionHook,
  void Function(bool refresh)? ensureHook,
  TestRemotePromptSubmit? remoteSubmit,
  ValueChanged<DesktopGatewayClient>? onGatewayBound,
  bool localDraft = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: _connection(),
        session: _session(localDraft: localDraft),
        testApiClient: ApiClient(
          baseUrl: 'http://stream.fixture',
          apiKey: 'strea...ey',
          httpClient: history,
        ),
        testDesktopLiveTurnHook: liveTurnHook,
        testDesktopAsyncEventHook: asyncHook,
        testDesktopConnectionHook: connectionHook,
        testDesktopEnsureSessionHook: ensureHook,
        testRemotePromptSubmit: remoteSubmit,
        testDesktopGatewayObserver: onGatewayBound,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        // The gateway is unreachable on purpose; answering the sticky-header
        // lookup here keeps the client from starting a connection attempt the
        // test would then have to out-race (it emits connection states of its
        // own, which the reconnect scenarios drive explicitly).
        testProjectOverviewLoader: () async => ProjectsTreeOverview.empty,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

/// The gateway URL is unreachable on purpose — and loopback, so the attempt
/// fails on a refused connection instead of a DNS timeout: what is asserted is
/// the screen's own handling of frames and replacements, not a live transport
/// (that half is covered by `desktop_gateway_live_turn_test.dart` and the
/// replay suites).
SavedConnection _connection() => SavedConnection(
  id: 'conn-live-stream',
  label: 'Live stream fixture',
  host: 'stream.fixture',
  port: 8642,
  apiKey: 'strea...ey',
  desktopGatewayUrl: 'http://127.0.0.1:1',
);

Session _session({bool localDraft = false}) => Session(
  id: _sessionId,
  title: 'Stream fixture chat',
  model: 'fixture-model',
  source: 'test',
  messageCount: 0,
  isActive: true,
  preview: '',
  startedAt: 1,
  isLocalDraft: localDraft,
);

/// Serves the stored transcript and counts how many times the screen fetched
/// it, so a follow's exit can be pinned to a real refetch.
class _StreamHistoryHttpClient extends http.BaseClient {
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
