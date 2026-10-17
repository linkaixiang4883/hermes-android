// Transport-level contract tests for the seq gate + `session.events.since`
// replay (Phase 1 of the mobile live-follow plan). Mirrors the desktop
// client's semantics (apps/shared/src/json-rpc-gateway.ts: fetchReplay /
// fetchSessionReplay / dispatchIfNewer / skipTruncatedWindow) at the
// WsClient layer: live and replayed frames share ONE dispatch path, are
// de-duplicated by per-session seq, and live frames racing a replay window
// are parked until that window has been delivered.
//
// The one place this differs from the desktop: this client also speaks the
// turn-recovery protocol, whose events are numbered per turn from 1 again, so
// a frame carrying `turn_id` is gated inside its turn instead of against the
// session watermark (see `WsClient._passSeqGate`).
//
// Real local WS traffic cannot share a suite with
// TestWidgetsFlutterBinding (see ws_keepalive_test.dart), so this file owns
// its own fake gateway, like ws_server_requests_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/ws_client.dart';

/// Writes a server frame only while the socket is still open.
///
/// Fixture replies are fire-and-forget: under the load of a full parallel test
/// run a reply can be produced after the peer has closed the socket, and
/// dart:io then throws `Bad state: StreamSink is closed` out of the socket's
/// listener -- which kills that listener and leaves the client waiting on an
/// answer that can never arrive. A late frame is dropped instead, exactly as a
/// gateway whose peer is already gone would behave.
void _safeAdd(WebSocket socket, Object? frame) {
  if (socket.readyState != WebSocket.open) return;
  try {
    socket.add(frame);
  } catch (_) {
    // Closed between the check above and the write: same late-write race.
  }
}

const _fixtureKey = 'fixture-key';
const _sessionId = 'runtime-1';

void main() {
  test('drops a duplicate seq frame and keeps the stream monotonic', () async {
    final gateway = await _ReplayFakeGateway.start();
    addTearDown(gateway.stop);
    final client = _clientFor(gateway);
    addTearDown(client.close);
    final received = <StreamEvent>[];
    client.onStreamEvent = received.add;

    await client.connect().timeout(const Duration(seconds: 10));

    await gateway.sendEvent(
      _event(type: 'message.delta', seq: 5, text: 'once'),
    );
    await gateway.sendEvent(
      _event(type: 'message.delta', seq: 5, text: 'once'),
    );
    await gateway.sendEvent(
      _event(type: 'message.delta', seq: 6, text: 'twice'),
    );

    await _waitFor(() => received.length >= 2);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(received.map((event) => event.seq), <int>[5, 6]);
  });

  test('gates a turn-scoped seq inside its own turn numbering', () async {
    final gateway = await _ReplayFakeGateway.start();
    addTearDown(gateway.stop);
    final client = _clientFor(gateway);
    addTearDown(client.close);
    final received = <StreamEvent>[];
    client.onStreamEvent = received.add;

    await client.connect().timeout(const Duration(seconds: 10));

    // The turn-recovery protocol numbers every turn from 1 again (its state
    // machine requires seq == lastSeq + 1 inside one turn), so turn-b's seq 1
    // is not a duplicate of turn-a's: a per-session watermark would swallow it.
    for (final turnId in <String>['turn-a', 'turn-b']) {
      for (final seq in <int>[1, 2]) {
        await gateway.sendEvent(
          _event(
            type: 'message.delta',
            seq: seq,
            text: '$turnId-$seq',
            turnId: turnId,
          ),
        );
      }
    }
    await _waitFor(() => received.length == 4);
    expect(received.map((event) => event.data['text']), <String>[
      'turn-a-1',
      'turn-a-2',
      'turn-b-1',
      'turn-b-2',
    ]);

    // A duplicate inside one turn is still dropped...
    await gateway.sendEvent(
      _event(type: 'message.delta', seq: 2, text: 'turn-b-2', turnId: 'turn-b'),
    );
    // ...and no turn frame moved the session watermark, so a transport frame
    // (no turn scope) whose seq restarts at 1 still dispatches.
    await gateway.sendEvent(
      _event(type: 'message.delta', seq: 1, text: 'session-1'),
    );
    await _waitFor(() => received.length == 5);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(received.map((event) => event.data['text']), <String>[
      'turn-a-1',
      'turn-a-2',
      'turn-b-1',
      'turn-b-2',
      'session-1',
    ]);
  });

  test('replays the frames missed while the socket was down', () async {
    final gateway = await _ReplayFakeGateway.start();
    addTearDown(gateway.stop);
    final client = _clientFor(gateway);
    addTearDown(client.close);
    final received = <StreamEvent>[];
    client.onStreamEvent = received.add;

    await client.connect().timeout(const Duration(seconds: 10));
    for (final seq in <int>[1, 2, 3]) {
      await gateway.sendEvent(
        _event(type: 'message.delta', seq: seq, text: 'live-$seq'),
      );
    }
    await _waitFor(() => received.length == 3);

    gateway.sinceResult = (sessionId, lastSeen) async => <String, dynamic>{
      'epoch': gateway.epoch,
      'events': <Object>[
        _event(type: 'message.delta', seq: 4, text: 'replay-4'),
        _event(type: 'message.delta', seq: 5, text: 'replay-5'),
      ],
      'latest_seq': 5,
      'truncated': false,
    };

    await gateway.dropSocket();
    await _waitFor(() => !client.isConnected);
    await client.connect().timeout(const Duration(seconds: 20));
    await _waitFor(() => received.length >= 5);

    final sinceRequest = gateway.requests.singleWhere(
      (request) => request['method'] == 'session.events.since',
    );
    expect(sinceRequest['params'], <String, dynamic>{
      'session_id': _sessionId,
      'last_seen': 3,
    });
    expect(
      gateway.requests.where(
        (request) => request['method'] == 'session.events.since',
      ),
      hasLength(1),
    );
    expect(received.map((event) => event.seq), <int>[1, 2, 3, 4, 5]);
    expect(received.map((event) => event.data['text']), <String>[
      'live-1',
      'live-2',
      'live-3',
      'replay-4',
      'replay-5',
    ]);
  });

  test(
    'parks live frames until the replay window has been delivered',
    () async {
      final gateway = await _ReplayFakeGateway.start();
      addTearDown(gateway.stop);
      final client = _clientFor(gateway);
      addTearDown(client.close);
      final received = <StreamEvent>[];
      client.onStreamEvent = received.add;

      await client.connect().timeout(const Duration(seconds: 10));
      for (final seq in <int>[1, 2, 3, 4]) {
        await gateway.sendEvent(
          _event(type: 'message.delta', seq: seq, text: 'live-$seq'),
        );
      }
      await _waitFor(() => received.length == 4);

      // Hold the replay answer open, then race a live frame past it.
      final release = Completer<void>();
      gateway.sinceResult = (sessionId, lastSeen) async {
        await release.future;
        return <String, dynamic>{
          'epoch': gateway.epoch,
          'events': <Object>[
            _event(type: 'message.delta', seq: 5, text: 'replay-5'),
            _event(type: 'message.delta', seq: 6, text: 'replay-6'),
          ],
          'latest_seq': 6,
          'truncated': false,
        };
      };

      await gateway.dropSocket();
      await _waitFor(() => !client.isConnected);
      await client.connect().timeout(const Duration(seconds: 20));
      await _waitFor(
        () => gateway.requests.any(
          (request) => request['method'] == 'session.events.since',
        ),
      );

      await gateway.sendEvent(
        _event(type: 'message.delta', seq: 7, text: 'live-7'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // The racer must not dispatch ahead of the gap it would then suppress.
      expect(received.map((event) => event.seq), <int>[1, 2, 3, 4]);

      release.complete();
      await _waitFor(() => received.length >= 7);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(received.map((event) => event.seq), <int>[1, 2, 3, 4, 5, 6, 7]);
      expect(received.map((event) => event.data['text']), <String>[
        'live-1',
        'live-2',
        'live-3',
        'live-4',
        'replay-5',
        'replay-6',
        'live-7',
      ]);
    },
  );

  test(
    'a changed replay epoch clears watermarks instead of replaying',
    () async {
      final gateway = await _ReplayFakeGateway.start();
      addTearDown(gateway.stop);
      final client = _clientFor(gateway);
      addTearDown(client.close);
      final received = <StreamEvent>[];
      client.onStreamEvent = received.add;

      await client.connect().timeout(const Duration(seconds: 10));
      for (final seq in <int>[1, 2, 3]) {
        await gateway.sendEvent(
          _event(type: 'message.delta', seq: seq, text: 'live-$seq'),
        );
      }
      await _waitFor(() => received.length == 3);

      // The backend restarted: its in-process seq counters start over under a
      // new epoch, so the held watermarks describe a numbering that is gone.
      gateway.epoch = 'e2';

      await gateway.dropSocket();
      await _waitFor(() => !client.isConnected);
      await client.connect().timeout(const Duration(seconds: 20));
      await _waitFor(
        () => client.isConnected && gateway.connectionCount >= 2,
        timeout: const Duration(seconds: 20),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(
        gateway.requests.where(
          (request) => request['method'] == 'session.events.since',
        ),
        isEmpty,
      );

      // Proof the watermark was cleared: the restarted backend's low seqs are
      // delivered again instead of being swallowed as duplicates.
      await gateway.sendEvent(
        _event(type: 'message.delta', seq: 1, text: 'after-1'),
      );
      await gateway.sendEvent(
        _event(type: 'message.delta', seq: 2, text: 'after-2'),
      );
      await _waitFor(() => received.length >= 5);
      expect(received.map((event) => event.seq), <int>[1, 2, 3, 1, 2]);
      expect(received.map((event) => event.data['text']), <String>[
        'live-1',
        'live-2',
        'live-3',
        'after-1',
        'after-2',
      ]);
    },
  );

  test('skips a truncated replay window and reports it', () async {
    final gateway = await _ReplayFakeGateway.start();
    addTearDown(gateway.stop);
    final client = _clientFor(gateway);
    addTearDown(client.close);
    final received = <StreamEvent>[];
    client.onStreamEvent = received.add;
    final truncated = <String>[];
    client.onReplayTruncated = truncated.add;

    await client.connect().timeout(const Duration(seconds: 10));
    for (final seq in <int>[1, 2, 3]) {
      await gateway.sendEvent(
        _event(type: 'message.delta', seq: seq, text: 'live-$seq'),
      );
    }
    await _waitFor(() => received.length == 3);

    // The ring evicted the gap: a tail-only replay would paint a hole
    // (missing prefix / tool state / terminal event), so none of it paints.
    gateway.sinceResult = (sessionId, lastSeen) async => <String, dynamic>{
      'epoch': gateway.epoch,
      'events': <Object>[
        _event(type: 'message.delta', seq: 5, text: 'hole-5'),
        _event(type: 'message.delta', seq: 6, text: 'hole-6'),
        _event(type: 'message.delta', seq: 7, text: 'hole-7'),
        _event(type: 'message.delta', seq: 8, text: 'hole-8'),
      ],
      'latest_seq': 9,
      'truncated': true,
    };

    await gateway.dropSocket();
    await _waitFor(() => !client.isConnected);
    await client.connect().timeout(const Duration(seconds: 20));
    await _waitFor(() => truncated.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(received.map((event) => event.seq), <int>[1, 2, 3]);
    expect(truncated, <String>[_sessionId]);

    // The watermark advanced to the server head, so the holed frames stay
    // gone and only genuinely newer frames dispatch.
    await gateway.sendEvent(
      _event(type: 'message.delta', seq: 9, text: 'holed'),
    );
    await gateway.sendEvent(
      _event(type: 'message.delta', seq: 10, text: 'fresh-10'),
    );
    await _waitFor(() => received.length >= 4);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received.map((event) => event.seq), <int>[1, 2, 3, 10]);
  });

  test(
    'reports a hole when the parked-frame buffer overflows',
    () async {
      final gateway = await _ReplayFakeGateway.start();
      addTearDown(gateway.stop);
      final client = _clientFor(gateway);
      addTearDown(client.close);
      final received = <StreamEvent>[];
      client.onStreamEvent = received.add;
      final truncated = <String>[];
      client.onReplayTruncated = truncated.add;

      await client.connect().timeout(const Duration(seconds: 10));
      for (final seq in <int>[1, 2, 3]) {
        await gateway.sendEvent(
          _event(type: 'message.delta', seq: seq, text: 'live-$seq'),
        );
      }
      await _waitFor(() => received.length == 3);

      // Hold the replay answer open, then flood the session with more frames
      // than the parked-frame bound: the oldest parked frames fall out of the
      // hold, so flushing the rest jumps their seqs. That hole is exactly as
      // unrecoverable as a truncated window and must be reported the same way.
      final release = Completer<void>();
      gateway.sinceResult = (sessionId, lastSeen) async {
        await release.future;
        return <String, dynamic>{
          'epoch': gateway.epoch,
          'events': const <Object>[],
          'latest_seq': 0,
          'truncated': false,
        };
      };

      await gateway.dropSocket();
      await _waitFor(() => !client.isConnected);
      await client.connect().timeout(const Duration(seconds: 20));
      await _waitFor(
        () => gateway.requests.any(
          (request) => request['method'] == 'session.events.since',
        ),
      );

      // 300 frames against a 256-frame hold: seqs 4..47 are evicted unparked.
      for (var seq = 4; seq <= 303; seq++) {
        await gateway.sendEvent(
          _event(type: 'message.delta', seq: seq, text: 'flood-$seq'),
        );
      }
      // Parked frames never reach a listener, so the barrier frame (another
      // session, no replay in flight) is what proves the whole flood has been
      // processed — frames on one socket arrive in order.
      await _sendBarrier(gateway, received, seq: 1);

      release.complete();
      // 300 frames were flooded ahead of this wait; the release flushes 256.
      await _waitFor(
        () => received.length >= 260,
        timeout: const Duration(seconds: 20),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final seqs = received
          .where((event) => event.sessionId == _sessionId)
          .map((event) => event.seq)
          .toList();
      // Whatever survived the hold is still delivered in order, once each: the
      // silent part of the eviction is what the report has to cover.
      expect(seqs, <int>[
        1,
        2,
        3,
        ...List<int>.generate(256, (index) => index + 48),
      ]);
      for (var index = 1; index < seqs.length; index++) {
        expect(seqs[index], greaterThan(seqs[index - 1]!));
      }
      // The frames the hold evicted were never delivered, so their seqs are a
      // hole in the delivered stream: the caller has to be told to re-read
      // history, exactly as for a truncated window.
      expect(truncated, <String>[_sessionId]);
    },
  );

  test(
    'a close during a replay round drops the parked frames instead of '
    'flushing them',
    () async {
      final gateway = await _ReplayFakeGateway.start();
      addTearDown(gateway.stop);
      final client = _clientFor(gateway);
      addTearDown(client.close);
      final received = <StreamEvent>[];
      client.onStreamEvent = received.add;
      final truncated = <String>[];
      client.onReplayTruncated = truncated.add;

      await client.connect().timeout(const Duration(seconds: 10));
      for (final seq in <int>[1, 2, 3]) {
        await gateway.sendEvent(
          _event(type: 'message.delta', seq: seq, text: 'live-$seq'),
        );
      }
      await _waitFor(() => received.length == 3);

      final release = Completer<void>();
      gateway.sinceResult = (sessionId, lastSeen) async {
        await release.future;
        return <String, dynamic>{
          'epoch': gateway.epoch,
          'events': const <Object>[],
          'latest_seq': 0,
          'truncated': false,
        };
      };

      await gateway.dropSocket();
      await _waitFor(() => !client.isConnected);
      await client.connect().timeout(const Duration(seconds: 20));
      await _waitFor(
        () => gateway.requests.any(
          (request) => request['method'] == 'session.events.since',
        ),
      );

      await gateway.sendEvent(
        _event(type: 'message.delta', seq: 4, text: 'parked-4'),
      );
      await _sendBarrier(gateway, received, seq: 1);
      // The barrier frame belongs to another session; parked frames reach no
      // listener at all, so the session's seqs are still [1, 2, 3].
      Iterable<int?> sessionSeqs() => received
          .where((event) => event.sessionId == _sessionId)
          .map((event) => event.seq);
      expect(sessionSeqs(), <int>[1, 2, 3]);

      // A deliberate teardown owns this client's state from here on: the window
      // still in flight belongs to a socket that no longer exists, so its parked
      // frames must not be dispatched into the closed client.
      client.close();
      expect(client.isConnected, isFalse);
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(sessionSeqs(), <int>[1, 2, 3]);
      expect(truncated, isEmpty);
    },
  );

  test('a close while disconnected still clears the seq watermarks', () async {
    final gateway = await _ReplayFakeGateway.start();
    addTearDown(gateway.stop);
    final client = _clientFor(gateway);
    addTearDown(client.close);
    final received = <StreamEvent>[];
    client.onStreamEvent = received.add;

    await client.connect().timeout(const Duration(seconds: 10));
    for (final seq in <int>[1, 2, 3]) {
      await gateway.sendEvent(
        _event(type: 'message.delta', seq: seq, text: 'live-$seq'),
      );
    }
    await _waitFor(() => received.length == 3);

    await gateway.dropSocket();
    await _waitFor(() => !client.isConnected);

    // The socket is already gone, but a deliberate teardown must still start
    // over: the next connect has nothing to replay and no watermark left to
    // swallow the restarted numbering's low seqs.
    client.close();

    await client.connect().timeout(const Duration(seconds: 20));
    for (final seq in <int>[1, 2, 3]) {
      await gateway.sendEvent(
        _event(type: 'message.delta', seq: seq, text: 'fresh-$seq'),
      );
    }
    await _sendBarrier(gateway, received, seq: 1);

    expect(
      received
          .where((event) => event.sessionId == _sessionId)
          .map((event) => event.data['text']),
      <String>['live-1', 'live-2', 'live-3', 'fresh-1', 'fresh-2', 'fresh-3'],
    );
    // A cleared watermark also means there is no gap left to ask about.
    expect(
      gateway.requests.where(
        (request) => request['method'] == 'session.events.since',
      ),
      isEmpty,
    );
  });

  test(
    'reports one hole per replay round when a truncated window also overflows',
    () async {
      final gateway = await _ReplayFakeGateway.start();
      addTearDown(gateway.stop);
      final client = _clientFor(gateway);
      addTearDown(client.close);
      final received = <StreamEvent>[];
      client.onStreamEvent = received.add;
      final truncated = <String>[];
      client.onReplayTruncated = truncated.add;

      await client.connect().timeout(const Duration(seconds: 10));
      for (final seq in <int>[1, 2, 3]) {
        await gateway.sendEvent(
          _event(type: 'message.delta', seq: seq, text: 'live-$seq'),
        );
      }
      await _waitFor(() => received.length == 3);

      final release = Completer<void>();
      gateway.sinceResult = (sessionId, lastSeen) async {
        await release.future;
        return <String, dynamic>{
          'epoch': gateway.epoch,
          'events': <Object>[
            _event(type: 'message.delta', seq: 4, text: 'hole-4'),
          ],
          'latest_seq': 4,
          'truncated': true,
        };
      };

      await gateway.dropSocket();
      await _waitFor(() => !client.isConnected);
      await client.connect().timeout(const Duration(seconds: 20));
      await _waitFor(
        () => gateway.requests.any(
          (request) => request['method'] == 'session.events.since',
        ),
      );

      for (var seq = 4; seq <= 303; seq++) {
        await gateway.sendEvent(
          _event(type: 'message.delta', seq: seq, text: 'flood-$seq'),
        );
      }
      await _sendBarrier(gateway, received, seq: 1);

      release.complete();
      // 300 frames were flooded ahead of this wait; the release flushes 256.
      await _waitFor(
        () => received.length >= 260,
        timeout: const Duration(seconds: 20),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Truncation and overflow describe one and the same hole: the caller is
      // told once, not twice.
      expect(truncated, <String>[_sessionId]);
      final seqs = received
          .where((event) => event.sessionId == _sessionId)
          .map((event) => event.seq)
          .toList();
      expect(seqs, <int>[
        1,
        2,
        3,
        ...List<int>.generate(256, (index) => index + 48),
      ]);
    },
  );

  test(
    'an epoch changed by the replay answer clears turn watermarks too',
    () async {
      final gateway = await _ReplayFakeGateway.start();
      addTearDown(gateway.stop);
      final client = _clientFor(gateway);
      addTearDown(client.close);
      final received = <StreamEvent>[];
      client.onStreamEvent = received.add;

      await client.connect().timeout(const Duration(seconds: 10));
      for (final seq in <int>[1, 2, 3]) {
        await gateway.sendEvent(
          _event(type: 'message.delta', seq: seq, text: 'live-$seq'),
        );
      }
      // A live turn whose numbering dies with the gateway process too.
      await gateway.sendEvent(
        _event(type: 'message.delta', seq: 5, text: 'turn-5', turnId: 'turn-x'),
      );
      await _waitFor(() => received.length == 4);

      // The gateway restarts between this socket's greeting and its answer, so
      // only the answer carries the new epoch: BOTH numbering spaces must be
      // dropped from there, or the turn's stale high-water mark swallows the
      // restarted turn's low seqs.
      final answered = Completer<void>();
      gateway.sinceResult = (sessionId, lastSeen) async {
        answered.complete();
        return <String, dynamic>{
          'epoch': 'e2',
          'events': <Object>[
            _event(type: 'message.delta', seq: 4, text: 'stale-4'),
          ],
          'latest_seq': 4,
          'truncated': false,
        };
      };

      await gateway.dropSocket();
      await _waitFor(() => !client.isConnected);
      await client.connect().timeout(const Duration(seconds: 20));
      await answered.future.timeout(const Duration(seconds: 20));
      await _waitFor(
        () => gateway.connectionCount >= 2,
        timeout: const Duration(seconds: 20),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      await gateway.sendEvent(
        _event(type: 'message.delta', seq: 1, text: 'after-1'),
      );
      await gateway.sendEvent(
        _event(
          type: 'message.delta',
          seq: 1,
          text: 'turn-after-1',
          turnId: 'turn-x',
        ),
      );
      await _sendBarrier(gateway, received, seq: 1);

      expect(
        received
            .where((event) => event.sessionId == _sessionId)
            .map((event) => event.data['text']),
        <String>[
          'live-1',
          'live-2',
          'live-3',
          'turn-5',
          'after-1',
          'turn-after-1',
        ],
      );
      // Nothing from the old numbering painted, the rejected window included.
      expect(
        received.any((event) => event.data['text'] == 'stale-4'),
        isFalse,
      );
    },
  );

  test('bounds the turn watermarks by evicting the oldest turn', () async {
    final gateway = await _ReplayFakeGateway.start();
    addTearDown(gateway.stop);
    final client = _clientFor(gateway);
    addTearDown(client.close);
    final received = <StreamEvent>[];
    client.onStreamEvent = received.add;

    await client.connect().timeout(const Duration(seconds: 10));
    // A turn watermark only matters while its turn is live, so the map is
    // bounded: the 65th turn evicts the 1st, and none of the 64 newest.
    for (var turn = 1; turn <= 65; turn++) {
      await gateway.sendEvent(
        _event(
          type: 'message.delta',
          seq: 1,
          text: 'turn-$turn-1',
          turnId: 'turn-$turn',
        ),
      );
    }
    await _sendBarrier(gateway, received, seq: 1);
    expect(
      received.where((event) => event.sessionId == _sessionId),
      hasLength(65),
    );

    // A duplicate inside a turn that is still held is still dropped...
    await gateway.sendEvent(
      _event(type: 'message.delta', seq: 1, text: 'turn-65-dup', turnId: 'turn-65'),
    );
    // ...while the evicted turn starts over instead of being suppressed forever.
    await gateway.sendEvent(
      _event(type: 'message.delta', seq: 1, text: 'turn-1-restart', turnId: 'turn-1'),
    );
    await _sendBarrier(gateway, received, seq: 2);

    expect(
      received
          .where((event) => event.sessionId == _sessionId)
          .map((event) => event.data['text'])
          .toList(),
      <String>[
        for (var turn = 1; turn <= 65; turn++) 'turn-$turn-1',
        'turn-1-restart',
      ],
    );
  });
}

/// Session used only for barrier frames: no replay is ever in flight for it, so
/// its frames dispatch immediately and observing one proves every frame sent
/// before it has been processed by the client.
const _barrierSessionId = 'runtime-barrier';

/// Send a barrier frame and wait until the client dispatches it.
///
/// Parked frames are invisible to a listener (they sit in the replay hold until
/// the window is released), so this is the only deterministic way to know a
/// flood has been received before the replay answer is released.
Future<void> _sendBarrier(
  _ReplayFakeGateway gateway,
  List<StreamEvent> received, {
  required int seq,
}) async {
  await gateway.sendEvent(
    _event(
      type: 'message.delta',
      seq: seq,
      text: 'barrier-$seq',
      sessionId: _barrierSessionId,
    ),
  );
  // The barrier session's own seq gate means each barrier frame is dispatched
  // exactly once, so waiting for THIS seq cannot be satisfied by an earlier one.
  // Up to 300 frames can sit queued ahead of the barrier frame, so this
  // wait is wider than the plain delivery default.
  await _waitFor(
    () => received.any(
      (event) =>
          event.sessionId == _barrierSessionId && event.seq == seq,
    ),
    timeout: const Duration(seconds: 20),
  );
}

WsClient _clientFor(_ReplayFakeGateway gateway) => WsClient(
  'http://127.0.0.1:${gateway.port}',
  token: _fixtureKey,
  heartbeatInterval: const Duration(hours: 1),
  heartbeatDeadline: const Duration(hours: 2),
);

Map<String, dynamic> _event({
  required String type,
  required int seq,
  required String text,
  String sessionId = _sessionId,
  String? turnId,
}) => <String, dynamic>{
  'type': type,
  'session_id': sessionId,
  'seq': seq,
  'turn_id': ?turnId,
  'message_id': 'message-$seq',
  'payload': <String, dynamic>{'text': text},
};

Future<void> _waitFor(
  bool Function() condition, {
  // Default wait, not 5s: a real loopback socket can sit unserved for
  // seconds while the whole suite runs in parallel.
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Minimal gateway: one `gateway.ready` per socket, recorded request frames,
/// switchable replay answers, and an explicit socket drop for reconnect tests.
class _ReplayFakeGateway {
  _ReplayFakeGateway(this._server);

  final HttpServer _server;
  final List<WebSocket> _sockets = [];

  /// Every inbound JSON-RPC request frame, in arrival order, with the
  /// 1-based connection ordinal it arrived on.
  final List<Map<String, dynamic>> requests = [];

  /// Server process identity advertised in `gateway.ready` and in every
  /// `session.events.since` answer.
  String epoch = 'e1';

  int connectionCount = 0;

  /// Answer factory for `session.events.since`; defaults to an empty window.
  Future<Map<String, dynamic>> Function(String sessionId, int lastSeen)?
  sinceResult;

  int get port => _server.port;

  static Future<_ReplayFakeGateway> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final gateway = _ReplayFakeGateway(server);
    server.listen(gateway._handleRequest);
    return gateway;
  }

  Future<void> _handleRequest(HttpRequest httpRequest) async {
    if (httpRequest.uri.path != '/api/ws') {
      httpRequest.response.statusCode = 404;
      await httpRequest.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(httpRequest);
    _sockets.add(socket);
    connectionCount++;
    _safeAdd(socket,
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'event',
        'params': <String, dynamic>{
          'type': 'gateway.ready',
          'payload': <String, dynamic>{
            'heartbeat': true,
            'replay_epoch': epoch,
          },
        },
      }),
    );
    socket.listen((raw) {
      final request = jsonDecode(raw as String) as Map<String, dynamic>;
      requests.add(<String, dynamic>{
        ...request,
        'connection': connectionCount,
      });
      unawaited(_answer(socket, request));
    });
  }

  Future<void> _answer(WebSocket socket, Map<String, dynamic> request) async {
    final id = request['id'];
    final method = request['method'];
    final params = request['params'] is Map<String, dynamic>
        ? request['params'] as Map<String, dynamic>
        : const <String, dynamic>{};
    if (method == 'gateway.ping') {
      _send(socket, <String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{'ok': true},
      });
      return;
    }
    if (method == 'session.events.since') {
      final sessionId = (params['session_id'] ?? '').toString();
      final lastSeen = params['last_seen'] is int
          ? params['last_seen'] as int
          : -1;
      final answer = sinceResult == null
          ? <String, dynamic>{
              'epoch': epoch,
              'events': const <Object>[],
              'latest_seq': 0,
              'truncated': false,
            }
          : await sinceResult!(sessionId, lastSeen);
      _send(socket, <String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': answer,
      });
      return;
    }
    _send(socket, <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'error': <String, dynamic>{
        'code': -32601,
        'message': 'unknown method $method',
      },
    });
  }

  void _send(WebSocket socket, Map<String, dynamic> frame) {
    // A socket dropped mid-answer is exactly what the reconnect test wants:
    // the guarded write drops the frame instead of killing the listener.
    _safeAdd(socket, jsonEncode(frame));
  }

  /// Push one server event frame on the newest socket.
  ///
  /// Awaits the socket: the client's `connect()` resolves on the handshake, and
  /// the fixture's upgrade handler may not have registered the socket on this
  /// shared event loop yet, so the very first frame of a test would otherwise
  /// race the registration.
  Future<void> sendEvent(
    Map<String, dynamic> params, {
    int? socketIndex,
  }) async {
    final index = socketIndex ?? -1; // -1 = newest socket
    await _waitFor(
      () => index < 0 ? _sockets.isNotEmpty : _sockets.length > index,
    );
    final socket = _sockets[index < 0 ? _sockets.length - 1 : index];
    _safeAdd(socket,
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'event',
        'params': params,
      }),
    );
  }

  Future<void> dropSocket() async {
    final sockets = List<WebSocket>.from(_sockets);
    _sockets.clear();
    for (final socket in sockets) {
      await socket.close(WebSocketStatus.goingAway, 'fixture drop');
    }
  }

  Future<void> stop() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    _sockets.clear();
    await _server.close(force: true);
  }
}
