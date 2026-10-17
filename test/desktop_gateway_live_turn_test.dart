// Phase 3 of the mobile live-follow plan, client half: the resume inflight
// snapshot must reach the UI as a projection, and reopening a chat must ask
// for a FRESH one.
//
// Two contracts are pinned here, both against the REAL DesktopGatewayClient
// over a fake gateway (real local WS traffic cannot share a suite with
// TestWidgetsFlutterBinding, so this file owns its fixture):
//
//   * `ensureSession(..., refresh: true)` re-issues `session.resume` even when
//     the session is already mapped on a live socket — re-entering a chat
//     needs the CURRENT snapshot, not the one taken when the socket came up —
//     and never falls back to `session.create` (that would mint a new session
//     where the user expects the old one);
//   * the projection is stored per mobile session and fanned out to every
//     live-turn listener (token-based, several at a time: the mounted chat
//     screen, and later whoever else follows the same shared connection).
//
// A plain `ensureSession` keeps its documented early exit: once a session is
// mapped on a live socket it must not re-resume on every call.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_live_turn.dart';

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

/// The mobile-side chat id the UI knows; the gateway resolves it to the same
/// stored key, so a resume needs no prior create.
const _mobileSessionId = 'mob-live';

void main() {
  test('a forced refresh publishes the live turn to every listener', () async {
    final gateway = await _LiveTurnFakeGateway.start();
    addTearDown(gateway.stop);
    final client = DesktopGatewayClient.fromConnection(
      _connection(gateway.baseUrl),
    );
    addTearDown(client.close);

    final first = <String>[];
    final second = <String>[];
    client.addLiveTurnListener(
      (mobileSessionId, projection) =>
          first.add(_describe(mobileSessionId, projection)),
    );
    client.addLiveTurnListener(
      (mobileSessionId, projection) =>
          second.add(_describe(mobileSessionId, projection)),
    );

    await client.ensureSession(_mobileSessionId, refresh: true);

    expect(
      gateway.creates,
      isEmpty,
      reason: 'refresh re-attaches; it never mints a session',
    );
    expect(gateway.resumes, hasLength(1));

    final projection = client.liveTurnProjectionFor(_mobileSessionId);
    expect(projection, isNotNull);
    expect(projection!.running, isTrue);
    expect(projection.user, 'hi');
    expect(projection.assistant, 'partial');
    expect(projection.streaming, isTrue);
    expect(projection.isLive, isTrue);

    // Both consumers see it exactly once, in registration order.
    expect(first, ['$_mobileSessionId#live#hi#partial']);
    expect(second, ['$_mobileSessionId#live#hi#partial']);
  });

  test('a plain ensure on a mapped session keeps its early exit', () async {
    final gateway = await _LiveTurnFakeGateway.start();
    addTearDown(gateway.stop);
    final client = DesktopGatewayClient.fromConnection(
      _connection(gateway.baseUrl),
    );
    addTearDown(client.close);
    final delivered = <String>[];
    client.addLiveTurnListener(
      (mobileSessionId, projection) =>
          delivered.add(_describe(mobileSessionId, projection)),
    );

    await client.ensureSession(_mobileSessionId, refresh: true);
    expect(gateway.resumes, hasLength(1));

    await client.ensureSession(_mobileSessionId);

    expect(
      gateway.resumes,
      hasLength(1),
      reason:
          'an already-mapped session must not re-resume on every call: that '
          'would add an attach round-trip to every action in the chat',
    );
    expect(
      delivered,
      hasLength(1),
      reason: 'nothing was refreshed, so nothing was republished',
    );
  });

  test('every refresh republishes, and one removal leaves the rest', () async {
    final gateway = await _LiveTurnFakeGateway.start();
    addTearDown(gateway.stop);
    final client = DesktopGatewayClient.fromConnection(
      _connection(gateway.baseUrl),
    );
    addTearDown(client.close);

    final kept = <String>[];
    final dropped = <String>[];
    final droppedToken = client.addLiveTurnListener(
      (mobileSessionId, projection) =>
          dropped.add(_describe(mobileSessionId, projection)),
    );
    client.addLiveTurnListener(
      (mobileSessionId, projection) =>
          kept.add(_describe(mobileSessionId, projection)),
    );

    await client.ensureSession(_mobileSessionId, refresh: true);
    await client.ensureSession(_mobileSessionId, refresh: true);
    expect(gateway.resumes, hasLength(2));

    client.removeLiveTurnListener(droppedToken);
    await client.ensureSession(_mobileSessionId, refresh: true);

    expect(
      kept,
      hasLength(3),
      reason: 're-entering a chat must report the current snapshot again',
    );
    expect(dropped, hasLength(2), reason: 'its token was detached');
  });

  test('a refresh for a session the gateway no longer holds clears the '
      'projection without creating one', () async {
    final gateway = await _LiveTurnFakeGateway.start();
    addTearDown(gateway.stop);
    final client = DesktopGatewayClient.fromConnection(
      _connection(gateway.baseUrl),
    );
    addTearDown(client.close);
    final delivered = <String>[];
    client.addLiveTurnListener(
      (mobileSessionId, projection) =>
          delivered.add(_describe(mobileSessionId, projection)),
    );

    await client.ensureSession(_mobileSessionId, refresh: true);
    expect(client.liveTurnProjectionFor(_mobileSessionId), isNotNull);

    // The durable row is gone by the time the user comes back: the gateway
    // answers 4007 on the resume.
    gateway.liveSessionId = null;
    await client.ensureSession(_mobileSessionId, refresh: true);

    expect(
      gateway.creates,
      isEmpty,
      reason:
          'a refresh must never create: a new session would fork the chat '
          'and strand the history the user came back for',
    );
    expect(
      client.liveTurnProjectionFor(_mobileSessionId),
      isNull,
      reason: 'there is no live turn left to follow',
    );
    expect(delivered, hasLength(2));
    expect(delivered.last, '$_mobileSessionId#none');
  });
}

/// A stable one-line description of a delivery, so an assertion can pin both
/// the session the projection belongs to and whether the fan-out said "no
/// live turn" (null) versus a projection.
String _describe(String mobileSessionId, LiveTurnProjection? projection) {
  if (projection == null) return '$mobileSessionId#none';
  return '$mobileSessionId#${projection.isLive ? 'live' : 'idle'}'
      '#${projection.user}#${projection.assistant}';
}

SavedConnection _connection(String baseUrl) => SavedConnection(
  id: 'conn-live-turn',
  label: 'Live turn gateway',
  // The override host must differ from [host]: that is what makes the client
  // treat [baseUrl] as the gateway origin instead of falling back to the
  // default dashboard topology (port 9119) and bypassing this fixture.
  host: 'gateway.test',
  port: 8642,
  apiKey: 'test-live-turn-key',
  desktopGatewayUrl: baseUrl,
  dashboardUsername: 'misha',
  dashboardPassword: 'secret',
);

/// A minimal secured gateway: REST for the password login and the WebSocket
/// ticket, then JSON-RPC over the socket. `session.resume` answers with the
/// stock live snapshot shape (running + inflight) for [liveSessionId], and
/// with the contract's 4007 for anything else. `session.create` is recorded
/// but never expected by these tests.
class _LiveTurnFakeGateway {
  _LiveTurnFakeGateway(this._server) {
    _server.listen(_handle);
  }

  static Future<_LiveTurnFakeGateway> start() async => _LiveTurnFakeGateway(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  );

  final HttpServer _server;
  final List<Map<String, dynamic>> creates = [];
  final List<Map<String, dynamic>> resumes = [];

  /// When set, `session.resume` succeeds for this id with the live snapshot
  /// below. Null answers 4007 ("session not found") for every id.
  String? liveSessionId = _mobileSessionId;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> stop() => _server.close(force: true);

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
        request.response
          ..statusCode = 200
          ..write('{"ticket":"ONE_TIME"}');
        await request.response.close();
      case '/api/ws':
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((raw) {
          _answer(socket, jsonDecode(raw as String) as Map<String, dynamic>);
        });
      default:
        request.response.statusCode = 404;
        await request.response.close();
    }
  }

  void _answer(WebSocket socket, Map<String, dynamic> frame) {
    final method = frame['method'];
    final params = (frame['params'] as Map?)?.cast<String, dynamic>() ?? {};

    void reply(Object? result, {Map<String, dynamic>? error}) {
      _safeAdd(
        socket,
        jsonEncode({
          'jsonrpc': '2.0',
          'id': frame['id'],
          if (error != null) 'error': error else 'result': result,
        }),
      );
    }

    switch (method) {
      case 'session.resume':
        resumes.add(params);
        final live = liveSessionId;
        if (live != null && params['session_id'] == live) {
          reply({
            'session_id': live,
            'stored_session_id': live,
            'running': true,
            'status': 'running',
            'inflight': {
              'user': 'hi',
              'assistant': 'partial',
              'streaming': true,
            },
          });
        } else {
          reply(null, error: {'code': 4007, 'message': 'session not found'});
        }
      case 'session.create':
        creates.add(params);
        reply({'session_id': 'runtime-1', 'stored_session_id': 'stored-1'});
      case 'client.capabilities':
        // WsClient advertises server-request support on every socket and
        // ignores the answer, so the fixture stays silent rather than writing
        // a frame that can race a socket close.
        return;
      default:
        reply(null, error: {'code': -32601, 'message': 'method not found'});
    }
  }
}
