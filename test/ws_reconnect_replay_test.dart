// Phase 2A of the mobile live-follow plan: a reconnect must reuse the SAME
// WsClient.
//
// The per-session replay watermarks (`WsClient._lastSeenSeq`) live on the
// client INSTANCE, and `session.events.since` can only name the gap the user
// missed if the instance that saw seq N is still the one opening the next
// socket. A reconnect that drops the client and builds a fresh one starts
// from an empty watermark map, so the replay silently degrades to "nothing to
// do" and every Phase 1 guarantee becomes a no-op on a real phone.
//
// This test pins the whole chain at the DesktopGatewayClient level:
//   live frames advance the watermark -> the socket drops -> the client
//   reconnects on its own (with a freshly minted single-use ticket) -> the
//   reopened socket asks `session.events.since` for exactly the gap.
//
// Real local WS traffic cannot share a suite with
// TestWidgetsFlutterBinding (see ws_keepalive_test.dart), so this file owns
// its own fake gateway, like ws_client_event_replay_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';

/// The mobile-side chat id the UI knows; resolved to [_runtimeSessionId] by
/// the gateway, and remembered as [_storedSessionId] for reconnects.
const _mobileSessionId = 'mob-1';
const _runtimeSessionId = 'gw-runtime-1';
const _storedSessionId = 'stored-1';

/// Server-process identity advertised in `gateway.ready` and in every
/// `session.events.since` answer. Constant across the reconnect, so adopting
/// it must NOT drop the watermarks.
const _replayEpoch = 'epoch-1';

void main() {
  test(
    'a reconnect keeps the replay watermark and asks session.events.since '
    'for the missed frames',
    () async {
      final gateway = await _ReconnectFakeGateway.start();
      addTearDown(gateway.stop);
      final client = DesktopGatewayClient.fromConnection(
        _connection(gateway.baseUrl),
      );
      addTearDown(client.close);
      final delivered = <String>[];
      client.setAsyncEventListener((mobileSessionId, event) {
        delivered.add('$mobileSessionId#${event.seq}');
      });

      await client.ensureSession(_mobileSessionId);
      expect(gateway.connectionCount, 1);

      // Three frames streamed on the live socket. They move this client's
      // per-session watermark to 3 — that one number is the whole point.
      for (final seq in <int>[1, 2, 3]) {
        await gateway.sendEvent(seq: seq, text: 'live-$seq');
      }
      // Delivered through the DesktopGatewayClient bridge, so the watermark
      // was really advanced by the frames the user would have seen.
      await _waitFor(() => delivered.length == 3);
      expect(delivered, <String>[
        '$_mobileSessionId#1',
        '$_mobileSessionId#2',
        '$_mobileSessionId#3',
      ]);

      // The gateway (or the network) drops the socket.
      await gateway.dropSocket();

      // The client reopens on its own — first backoff hop is 2s.
      await _waitFor(
        () => gateway.connectionCount >= 2,
        timeout: const Duration(seconds: 8),
      );

      // ...and the reopened socket asks for exactly the frames it missed.
      // A reconnect that swapped in a new WsClient would never send this:
      // its watermark map starts empty, so the fetch has nothing to name.
      await _waitFor(
        () => gateway.replayRequests.isNotEmpty,
        timeout: const Duration(seconds: 8),
        describe: () =>
            'sockets opened: ${gateway.connectionCount}, '
            'replay requests: ${gateway.replayRequests.length}',
      );

      for (final replay in gateway.replayRequests) {
        expect(replay.connection, 2, reason: 'asked on the reopened socket');
        expect(replay.params['session_id'], _runtimeSessionId);
        expect(replay.params['last_seen'], 3, reason: 'watermark survived');
      }

      // The single-use ticket is consumed by the first upgrade: a reconnect
      // that reused it would never get a socket at all (the fixture rejects a
      // replayed ticket), and the fresh one must be the one it dialled with.
      expect(gateway.socketTickets, <String>['TICKET-1', 'TICKET-2']);
    },
  );
}

SavedConnection _connection(String baseUrl) => SavedConnection(
  id: 'conn-reconnect-replay',
  label: 'Reconnect replay gateway',
  // The override host must differ from [host]: that is what makes the client
  // treat [baseUrl] as the gateway origin instead of falling back to the
  // default dashboard topology (port 9119) and bypassing this fixture.
  host: 'localhost',
  port: 8642,
  apiKey: 'fixture-key',
  desktopGatewayUrl: baseUrl,
  dashboardUsername: 'u',
  dashboardPassword: 'p',
);

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String Function()? describe,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError(
        'condition not met within $timeout'
        '${describe == null ? '' : ' (${describe()})'}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// One recorded `session.events.since` request.
class _ReplayRequest {
  _ReplayRequest(this.connection, this.params);

  /// 1-based ordinal of the socket the request arrived on.
  final int connection;
  final Map<String, dynamic> params;
}

/// A minimal secured gateway: REST for the password login and the single-use
/// WebSocket ticket, then JSON-RPC over the socket. Tickets are enforced —
/// a consumed ticket cannot open a second socket — so the reconnect has to
/// rotate it, exactly like a real Hermes dashboard.
class _ReconnectFakeGateway {
  _ReconnectFakeGateway(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final List<WebSocket> _sockets = [];
  final Set<String> _consumedTickets = {};

  /// Tickets the client dialled `/api/ws` with, in connection order.
  final List<String> socketTickets = [];

  /// Every `session.events.since` request, in arrival order.
  final List<_ReplayRequest> replayRequests = [];

  int ticketCount = 0;
  int connectionCount = 0;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  static Future<_ReconnectFakeGateway> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _ReconnectFakeGateway(server);
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
        ticketCount++;
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"ticket":"TICKET-$ticketCount"}');
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
    socketTickets.add(ticket);
    socket.add(
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
        // Connection-scoped handshake: the client advertises that it can
        // answer server→client requests. Answering is what a real gateway does.
        reply(<String, dynamic>{'ok': true});
      case 'session.resume':
        // The mobile id is not a stored key yet on the first touch; the
        // gateway mints the pair below via `session.create`.
        if (params['session_id'] == _storedSessionId) {
          reply(<String, dynamic>{
            'session_id': _runtimeSessionId,
            'stored_session_id': _storedSessionId,
          });
        } else {
          reply(null, error: {'code': 4007, 'message': 'session not found'});
        }
      case 'session.create':
        reply(<String, dynamic>{
          'session_id': _runtimeSessionId,
          'stored_session_id': _storedSessionId,
        });
      case 'session.events.since':
        replayRequests.add(_ReplayRequest(connectionCount, params));
        reply(<String, dynamic>{
          'epoch': _replayEpoch,
          'events': const <Object>[],
          'latest_seq': 3,
          'truncated': false,
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
    _sockets.last.add(
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
