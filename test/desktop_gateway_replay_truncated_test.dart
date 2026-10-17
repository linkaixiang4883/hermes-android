// Phase 5 of the mobile live-follow plan, transport half: a replay window the
// gateway's ring could not deliver hole-free must reach the consumer that owns
// the transcript.
//
// Phase 1 gave `WsClient` its `onReplayTruncated` callback, but the callback
// stops at the socket: nothing forwarded it, so a truncated window silently
// left a hole in the transcript (a missing message prefix, tool state or the
// terminal frame) with no consumer ever learning to re-read history. This suite
// pins the forwarding contract on the REAL DesktopGatewayClient over a fake
// gateway (real local WS traffic cannot share a suite with
// TestWidgetsFlutterBinding, so this file owns its fixture):
//
//   * a truncated `session.events.since` answer after a reconnect reaches
//     every registered listener, exactly once, named by the MOBILE session id
//     the UI knows (the socket reports the gateway's runtime id);
//   * a report that arrives while this client cannot name the session — the
//     reconnect re-binds AFTER its replay round starts, so this is the normal
//     ordering — is delivered the moment the binding names it, never dropped;
//   * listeners are multiplexed, and detach one at a time by token.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';

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

/// The mobile-side chat id the UI knows; resolved to [_runtimeSessionId] by
/// the gateway, and remembered as [_storedSessionId] for reconnects.
const _mobileSessionId = 'mob-trunc';
const _runtimeSessionId = 'gw-runtime-trunc';
const _storedSessionId = 'stored-trunc';

/// Server-process identity advertised in `gateway.ready` and in every
/// `session.events.since` answer. Constant across the reconnect, so adopting it
/// must NOT drop the watermarks.
const _replayEpoch = 'epoch-trunc';

void main() {
  test('a truncated replay reaches every registered listener once', () async {
    final gateway = await _TruncationFakeGateway.start();
    addTearDown(gateway.stop);
    final client = DesktopGatewayClient.fromConnection(
      _connection(gateway.baseUrl),
    );
    addTearDown(client.close);

    final first = <String>[];
    final second = <String>[];
    client.addReplayTruncatedListener((sessionId) => first.add(sessionId));
    client.addReplayTruncatedListener((sessionId) => second.add(sessionId));
    final delivered = <int>[];
    client.addAsyncEventListener(
      (mobileSessionId, event) => delivered.add(event.seq ?? -1),
    );

    await client.ensureSession(_mobileSessionId);
    await gateway.sendEvent(seq: 1, text: 'live-1');
    await _waitFor(() => delivered.length == 1);

    // The phone slept: the frames that followed are older than the gateway's
    // ring, so the reconnect's catch-up window comes back truncated.
    gateway.truncateReplays = true;
    await gateway.dropSocket();
    await _waitFor(
      () => gateway.replayRequests.isNotEmpty,
      timeout: const Duration(seconds: 20),
    );

    await _waitFor(() => first.isNotEmpty && second.isNotEmpty);
    // Settle, so a duplicated delivery would have landed before asserting.
    await _settle();

    final replay = gateway.replayRequests.single;
    expect(replay.connection, 2, reason: 'asked on the reopened socket');
    expect(replay.params['session_id'], _runtimeSessionId);
    expect(replay.params['last_seen'], 1, reason: 'the watermark was the gap');

    // The listener is told the id the UI knows, not the gateway's runtime id:
    // a screen can only match the report against the chat it is showing.
    expect(first, [_mobileSessionId]);
    expect(second, [_mobileSessionId]);
  });

  test('a report that arrives before the session is named waits for it', () async {
    final gateway = await _TruncationFakeGateway.start();
    addTearDown(gateway.stop);
    final client = DesktopGatewayClient.fromConnection(
      _connection(gateway.baseUrl),
    );
    addTearDown(client.close);

    final seen = <String>[];
    client.addReplayTruncatedListener((sessionId) => seen.add(sessionId));
    final delivered = <int>[];
    client.addAsyncEventListener(
      (mobileSessionId, event) => delivered.add(event.seq ?? -1),
    );

    await client.ensureSession(_mobileSessionId);
    await gateway.sendEvent(seq: 1, text: 'live-1');
    await _waitFor(() => delivered.length == 1);

    // The reconnect re-binds over `session.resume`, and the replay round starts
    // as soon as the greeting lands — so the hole is reported while the session
    // is still nameless on this client (the drop cleared its runtime bindings).
    // Holding the resume makes that ordering explicit instead of racy.
    gateway
      ..truncateReplays = true
      ..holdResumes = true;
    await gateway.dropSocket();
    await _waitFor(
      () => gateway.replayRequests.isNotEmpty,
      timeout: const Duration(seconds: 20),
    );
    await _settle();

    expect(
      seen,
      isEmpty,
      reason:
          'the report names no chat yet, and a runtime id is not something a '
          'listener could match against',
    );
    expect(
      gateway.resumeRequests.length,
      2,
      reason: 'the reconnect really did try to re-bind while the report landed',
    );

    gateway.releaseResumes();

    // Delivered by the binding, not dropped: nothing replays the report, and a
    // dropped one is a transcript hole nobody is told about.
    await _waitFor(() => seen.isNotEmpty);
    await _settle();
    expect(seen, [_mobileSessionId]);
  });

  test('removing one replay listener leaves the others attached', () async {
    final gateway = await _TruncationFakeGateway.start();
    addTearDown(gateway.stop);
    final client = DesktopGatewayClient.fromConnection(
      _connection(gateway.baseUrl),
    );
    addTearDown(client.close);

    final kept = <String>[];
    final dropped = <String>[];
    final droppedToken = client.addReplayTruncatedListener(
      (sessionId) => dropped.add(sessionId),
    );
    client.addReplayTruncatedListener((sessionId) => kept.add(sessionId));
    final delivered = <int>[];
    client.addAsyncEventListener(
      (mobileSessionId, event) => delivered.add(event.seq ?? -1),
    );

    await client.ensureSession(_mobileSessionId);
    await gateway.sendEvent(seq: 1, text: 'live-1');
    await _waitFor(() => delivered.length == 1);

    gateway.truncateReplays = true;
    await gateway.dropSocket();
    await _waitFor(
      () => gateway.replayRequests.length == 1,
      timeout: const Duration(seconds: 20),
    );
    await _waitFor(() => kept.isNotEmpty && dropped.isNotEmpty);

    client.removeReplayTruncatedListener(droppedToken);

    // A second hole on a later reconnect: only the surviving token is told.
    await gateway.dropSocket();
    await _waitFor(
      () => gateway.replayRequests.length == 2,
      timeout: const Duration(seconds: 20),
    );
    await _waitFor(() => kept.length == 2);
    await _settle();

    expect(kept, [_mobileSessionId, _mobileSessionId]);
    expect(dropped, [_mobileSessionId]);
  });

  test('a closed client detaches its replay listeners', () async {
    final client = DesktopGatewayClient.fromConnection(
      _connection('http://127.0.0.1:1'),
    );

    final token = client.addReplayTruncatedListener((_) {});
    expect(client.replayTruncatedListenerCount, 1);

    client.close();

    expect(
      client.replayTruncatedListenerCount,
      0,
      reason:
          'a closed client keeps no listeners: the screen that owned them is '
          'gone with the connection, and a later report has nobody to reach',
    );
    // A stale token is a no-op, so a teardown path can run twice safely.
    client.removeReplayTruncatedListener(token);
    expect(client.replayTruncatedListenerCount, 0);
  });
}

SavedConnection _connection(String baseUrl) => SavedConnection(
  id: 'conn-replay-truncated',
  label: 'Truncated replay gateway',
  // The override host must differ from [host]: that is what makes the client
  // treat [baseUrl] as the gateway origin instead of falling back to the
  // default dashboard topology (port 9119) and bypassing this fixture.
  host: 'localhost',
  port: 8642,
  apiKey: 'truncated-fixture-key',
  desktopGatewayUrl: baseUrl,
  dashboardUsername: 'u',
  dashboardPassword: 'p',
);

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

/// Lets every already-queued socket frame finish delivering, so a delivery
/// that should NOT happen has had its chance before an assertion.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

/// One recorded `session.events.since` request.
class _ReplayRequest {
  _ReplayRequest(this.connection, this.params);

  /// 1-based ordinal of the socket the request arrived on.
  final int connection;
  final Map<String, dynamic> params;
}

/// A minimal secured gateway: REST for the password login and the single-use
/// WebSocket ticket, then JSON-RPC over the socket. Tickets are enforced — a
/// consumed ticket cannot open a second socket — so the reconnect has to rotate
/// it, exactly like a real Hermes dashboard.
class _TruncationFakeGateway {
  _TruncationFakeGateway(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final List<WebSocket> _sockets = [];
  final Set<String> _consumedTickets = {};

  /// Every `session.events.since` request, in arrival order.
  final List<_ReplayRequest> replayRequests = [];

  /// Every `session.resume` request, in arrival order. Counted whether or not
  /// the answer was held, so a test can see the re-bind reaching the fixture.
  final List<Map<String, dynamic>> resumeRequests = [];

  /// Answers every replay window with `truncated: true`, the way a gateway
  /// whose ring no longer holds the whole gap does.
  bool truncateReplays = false;

  /// Holds `session.resume` answers until [releaseResumes], so a test can pin
  /// what happens to a report that lands before the session is named again.
  bool holdResumes = false;

  final List<void Function()> _heldResumes = [];

  int _ticketCount = 0;
  int connectionCount = 0;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  static Future<_TruncationFakeGateway> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _TruncationFakeGateway(server);
  }

  Future<void> stop() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    _sockets.clear();
    await _server.close(force: true);
  }

  /// Answers the held `session.resume` requests.
  void releaseResumes() {
    holdResumes = false;
    final held = List<void Function()>.from(_heldResumes);
    _heldResumes.clear();
    for (final answer in held) {
      answer();
    }
  }

  Future<void> _handle(HttpRequest request) async {
    switch (request.uri.path) {
      case '/auth/password-login':
        await request.drain<void>();
        request.response
          ..statusCode = 200
          ..headers.set('set-cookie', 'hermes_session_at=TOK; Path=/')
          ..write('{"ok":true}');
        await request.response.close();
      case '/api/auth/ws-ticket':
        await request.drain<void>();
        _ticketCount++;
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"ticket":"TICKET-$_ticketCount"}');
        await request.response.close();
      case '/api/ws':
        await _upgrade(request);
      default:
        request.response.statusCode = 404;
        await request.response.close();
    }
  }

  Future<void> _upgrade(HttpRequest request) async {
    final ticket = request.uri.queryParameters['ticket'] ?? '';
    if (ticket.isEmpty || !_consumedTickets.add(ticket)) {
      // Missing, unknown, or already-spent ticket: no socket, like the real
      // dashboard's single-use ticket flow.
      request.response.statusCode = 401;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
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
            'replay_epoch': _replayEpoch,
          },
        },
      }),
    );
    socket.listen((raw) {
      final frame = jsonDecode(raw as String) as Map<String, dynamic>;
      _answer(socket, frame);
    });
  }

  void _answer(WebSocket socket, Map<String, dynamic> frame) {
    final method = frame['method'];
    final params = (frame['params'] as Map?)?.cast<String, dynamic>() ?? {};
    final connection = connectionCount;

    void reply(Object? result, {Map<String, dynamic>? error}) {
      _safeAdd(socket,
        jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': frame['id'],
          if (error != null) 'error': error else 'result': result,
        }),
      );
    }

    switch (method) {
      case 'gateway.ping':
        reply(<String, dynamic>{'ok': true});
      case 'client.capabilities':
        // Connection-scoped handshake: the client advertises that it can
        // answer server→client requests. Answering is what a real gateway does.
        reply(<String, dynamic>{'ok': true});
      case 'session.resume':
        resumeRequests.add(params);
        final stored = params['session_id']?.toString() ?? '';
        void answer() {
          if (stored == _storedSessionId) {
            reply(<String, dynamic>{
              'session_id': _runtimeSessionId,
              'stored_session_id': _storedSessionId,
            });
          } else {
            // The mobile id is not a stored key yet on the first touch; the
            // gateway mints the pair through `session.create`.
            reply(null, error: {'code': 4007, 'message': 'session not found'});
          }
        }

        if (holdResumes) {
          _heldResumes.add(answer);
          return;
        }
        answer();
      case 'session.create':
        reply(<String, dynamic>{
          'session_id': _runtimeSessionId,
          'stored_session_id': _storedSessionId,
        });
      case 'session.events.since':
        replayRequests.add(_ReplayRequest(connection, params));
        reply(<String, dynamic>{
          'epoch': _replayEpoch,
          'events': const <Object>[],
          'latest_seq': 3,
          'truncated': truncateReplays,
        });
      default:
        reply(null, error: {'code': -32601, 'message': 'method not found'});
    }
  }

  /// Push one server event frame on the newest socket.
  ///
  /// Awaits the socket: the upgrade handler registers it on the shared event
  /// loop, so a frame sent before registration would race the fixture.
  Future<void> sendEvent({required int seq, required String text}) async {
    await _waitFor(() => _sockets.isNotEmpty);
    _safeAdd(_sockets.last,
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'event',
        'params': <String, dynamic>{
          'type': 'notification.show',
          'session_id': _runtimeSessionId,
          'seq': seq,
          'payload': <String, dynamic>{'text': text},
        },
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
}
