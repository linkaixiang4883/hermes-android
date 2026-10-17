// Phase 2B-i of the mobile live-follow plan: the async-event and
// session-bound registrations on DesktopGatewayClient must be multiplexed.
//
// The plan lifts the gateway socket into one application-wide
// DesktopGatewayClient, so more than one consumer (the mounted chat screen,
// the turn coordinator's dispatcher, the notification/approval path) has to
// observe the same connection at the same time. The old single-slot
// `setAsyncEventListener` / `setSessionBoundListener` let the last
// registration win, which would silently starve every earlier consumer.
//
// These tests drive the REAL DesktopGatewayClient against a fake gateway, the
// way ws_server_requests_test.dart and ws_reconnect_replay_test.dart do, and
// pin the token-based contract:
//   * every registered listener receives each delivered event, exactly once
//   * removing one token leaves the other registrations attached
//   * the per-listener `acceptsSession` predicate still filters by mobile id
//   * session-bound bindings fan out and survive a removal
//
// Real local WS traffic cannot share a suite with TestWidgetsFlutterBinding
// (see ws_keepalive_test.dart), so this file owns its fake gateway.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';

/// Mobile-side chat ids the UI knows; resolved by the fake gateway to
/// [_runtimeSession]/[_storedSession] ids, minted in `session.create` order.
const _mobileA = 'mob-a';
const _mobileB = 'mob-b';

String _runtimeSession(int ordinal) => 'runtime-$ordinal';
String _storedSession(int ordinal) => 'stored-$ordinal';

void main() {
  test('every registered async listener receives a delivered event once', () async {
    final gateway = await _MultiplexFakeGateway.start();
    addTearDown(gateway.stop);
    final client = DesktopGatewayClient.fromConnection(
      _connection(gateway.baseUrl),
    );
    addTearDown(client.close);

    final first = <String>[];
    final second = <String>[];
    client.addAsyncEventListener(
      (sessionId, event) =>
          first.add('$sessionId#${event.type}#${event.seq}'),
    );
    client.addAsyncEventListener(
      (sessionId, event) =>
          second.add('$sessionId#${event.type}#${event.seq}'),
    );

    await client.ensureSession(_mobileA);
    expect(gateway.createdSessions, [_storedSession(1)]);

    await gateway.sendEvent(
      sessionId: _runtimeSession(1),
      seq: 1,
      text: 'live',
    );
    await _waitFor(() => first.isNotEmpty && second.isNotEmpty);
    // Settle, so a duplicated delivery would have landed before asserting.
    await _settle();

    expect(first, ['$_mobileA#notification.show#1']);
    expect(second, ['$_mobileA#notification.show#1']);
  });

  test('removing one async listener token leaves the others attached', () async {
    final gateway = await _MultiplexFakeGateway.start();
    addTearDown(gateway.stop);
    final client = DesktopGatewayClient.fromConnection(
      _connection(gateway.baseUrl),
    );
    addTearDown(client.close);

    final kept = <String>[];
    final dropped = <String>[];
    final keptToken = client.addAsyncEventListener(
      (sessionId, event) => kept.add('$sessionId#${event.seq}'),
    );
    final droppedToken = client.addAsyncEventListener(
      (sessionId, event) => dropped.add('$sessionId#${event.seq}'),
    );

    await client.ensureSession(_mobileA);
    await gateway.sendEvent(
      sessionId: _runtimeSession(1),
      seq: 1,
      text: 'before removal',
    );
    await _waitFor(() => kept.length == 1 && dropped.length == 1);

    client.removeAsyncEventListener(droppedToken);
    await gateway.sendEvent(
      sessionId: _runtimeSession(1),
      seq: 2,
      text: 'after removal',
    );
    await _waitFor(() => kept.length == 2);
    await _settle();

    expect(kept, ['$_mobileA#1', '$_mobileA#2']);
    expect(dropped, ['$_mobileA#1']);

    // The survivor detaches by its own token, and nothing is left behind.
    client.removeAsyncEventListener(keptToken);
    await gateway.sendEvent(
      sessionId: _runtimeSession(1),
      seq: 3,
      text: 'after both removals',
    );
    await _settle();
    expect(kept, hasLength(2));
  });

  test('acceptsSession filters events per listener', () async {
    final gateway = await _MultiplexFakeGateway.start();
    addTearDown(gateway.stop);
    final client = DesktopGatewayClient.fromConnection(
      _connection(gateway.baseUrl),
    );
    addTearDown(client.close);

    final scoped = <String>[];
    final unscoped = <String>[];
    client.addAsyncEventListener(
      (sessionId, event) => scoped.add('$sessionId#${event.seq}'),
      acceptsSession: (sessionId) => sessionId == _mobileA,
    );
    client.addAsyncEventListener(
      (sessionId, event) => unscoped.add('$sessionId#${event.seq}'),
    );

    await client.ensureSession(_mobileA);
    await client.ensureSession(_mobileB);
    expect(gateway.createdSessions, [
      _storedSession(1),
      _storedSession(2),
    ]);

    // A frame for the rejected session reaches only the unscoped listener:
    // the predicate skips one registration, it does not mute the client.
    await gateway.sendEvent(
      sessionId: _runtimeSession(2),
      seq: 1,
      text: 'for b',
    );
    await _waitFor(() => unscoped.isNotEmpty);
    await _settle();
    expect(scoped, isEmpty);
    expect(unscoped, ['$_mobileB#1']);

    await gateway.sendEvent(
      sessionId: _runtimeSession(1),
      seq: 2,
      text: 'for a',
    );
    await _waitFor(() => scoped.isNotEmpty && unscoped.length == 2);
    expect(scoped, ['$_mobileA#2']);
    expect(unscoped, ['$_mobileB#1', '$_mobileA#2']);
  });

  test('session-bound bindings fan out and survive a removal', () async {
    final gateway = await _MultiplexFakeGateway.start();
    addTearDown(gateway.stop);
    final client = DesktopGatewayClient.fromConnection(
      _connection(gateway.baseUrl),
    );
    addTearDown(client.close);

    final first = <(String, String)>[];
    final second = <(String, String)>[];
    final firstToken = client.addSessionBoundListener(
      (localSessionId, storedSessionId) =>
          first.add((localSessionId, storedSessionId)),
    );
    client.addSessionBoundListener(
      (localSessionId, storedSessionId) =>
          second.add((localSessionId, storedSessionId)),
    );

    await client.ensureSession(_mobileA);
    await _waitFor(() => first.length == 1 && second.length == 1);
    expect(first, [(_mobileA, _storedSession(1))]);
    expect(second, [(_mobileA, _storedSession(1))]);

    client.removeSessionBoundListener(firstToken);
    await client.ensureSession(_mobileB);
    await _waitFor(() => second.length == 2);
    await _settle();
    expect(first, hasLength(1));
    expect(second, [
      (_mobileA, _storedSession(1)),
      (_mobileB, _storedSession(2)),
    ]);
  });
}

SavedConnection _connection(String baseUrl) => SavedConnection(
  id: 'conn-multiplex-listeners',
  label: 'Multiplex listener gateway',
  // The override host must differ from [host]: that is what makes the client
  // treat [baseUrl] as the gateway origin instead of falling back to the
  // default dashboard topology and bypassing this fixture.
  host: 'localhost',
  port: 8642,
  apiKey: 'fixture-api-key',
  desktopGatewayUrl: baseUrl,
  dashboardUsername: 'u',
  dashboardPassword: 'p',
);

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
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

/// A minimal secured gateway: REST for the password login and the single-use
/// WebSocket ticket, then JSON-RPC over the socket.
///
/// Sessions are minted on demand in `session.create` order, so the Nth created
/// session is always `runtime-N` / `stored-N` — tests name those ids instead of
/// scraping them off the client.
class _MultiplexFakeGateway {
  _MultiplexFakeGateway(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final List<WebSocket> _sockets = [];
  final Set<String> _consumedTickets = {};
  final Map<String, String> _runtimeByStored = {};

  /// Stored ids handed out by `session.create`, in creation order.
  final List<String> createdSessions = [];

  int _ticketCount = 0;
  int _sessionCount = 0;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  static Future<_MultiplexFakeGateway> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _MultiplexFakeGateway(server);
  }

  Future<void> stop() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    _sockets.clear();
    await _server.close(force: true);
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
      request.response.statusCode = 401;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    _sockets.add(socket);
    socket.add(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'event',
        'params': <String, dynamic>{
          'type': 'gateway.ready',
          'payload': <String, dynamic>{'heartbeat': true},
        },
      }),
    );
    socket.listen((raw) {
      _answer(socket, jsonDecode(raw as String) as Map<String, dynamic>);
    });
  }

  void _answer(WebSocket socket, Map<String, dynamic> frame) {
    final method = frame['method'];
    final params = (frame['params'] as Map?)?.cast<String, dynamic>() ?? {};

    void reply(Object? result, {Map<String, dynamic>? error}) {
      socket.add(
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
        reply(<String, dynamic>{'ok': true});
      case 'session.resume':
        final stored = params['session_id']?.toString() ?? '';
        final runtime = _runtimeByStored[stored];
        if (runtime == null) {
          reply(null, error: {'code': 4007, 'message': 'session not found'});
        } else {
          reply(<String, dynamic>{
            'session_id': runtime,
            'stored_session_id': stored,
          });
        }
      case 'session.create':
        _sessionCount++;
        final stored = _storedSession(_sessionCount);
        final runtime = _runtimeSession(_sessionCount);
        _runtimeByStored[stored] = runtime;
        createdSessions.add(stored);
        reply(<String, dynamic>{
          'session_id': runtime,
          'stored_session_id': stored,
        });
      case 'session.events.since':
        reply(<String, dynamic>{
          'events': const <Object>[],
          'latest_seq': 0,
          'truncated': false,
        });
      default:
        reply(null, error: {'code': -32601, 'message': 'method not found'});
    }
  }

  /// Pushes one durable event frame for [sessionId] on the live socket.
  Future<void> sendEvent({
    required String sessionId,
    required int seq,
    required String text,
  }) async {
    await _waitFor(() => _sockets.isNotEmpty);
    _sockets.last.add(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'event',
        'params': <String, dynamic>{
          'type': 'notification.show',
          'session_id': sessionId,
          'seq': seq,
          'payload': <String, dynamic>{'text': text},
        },
      }),
    );
  }
}
