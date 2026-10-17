// Phase 2B-ii of the mobile live-follow plan: one application-scoped
// DesktopGatewayClient per connection.
//
// A long turn has to outlive the screen that started it. Phase 2A lifted the
// socket so a reconnect reuses the same WsClient and its replay watermarks
// survive; Phase 2B-i multiplexed the listeners so several consumers can share
// that socket at once. What remains is *ownership*: the socket must belong to
// the application, not to a route. `GatewayClientRegistry` is that owner —
// `main.dart` builds it, hands the same instance to every chat screen and to
// the draft/notification controller, and closes it with the app. A chat screen
// only borrows: entering attaches listeners, leaving detaches them, and never
// closes the connection.
//
// These tests drive the REAL DesktopGatewayClient against a fake gateway, the
// way desktop_gateway_multiplex_listeners_test.dart does. Real local WS traffic
// cannot share a suite with TestWidgetsFlutterBinding, so the widget-level half
// of the ownership contract lives in chat_gateway_client_ownership_test.dart.
// Pinned here:
//   * registry identity — one instance per connection id, until it is dropped
//   * a borrowed client survives its borrower's detach: the socket it opened
//     stays open and keeps delivering frames
//   * the no-registry fallback the chat screen keeps still tears its own client
//     — and its socket — down
//   * the draft/notification owner lands on the very same instance as the chat
//     borrow (one socket per connection), and closing that owner never closes a
//     client it does not own
//   * connection-state listeners are token-based: they coexist, every one sees
//     every transition, and removing one leaves the others attached

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_client_registry.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';

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

/// Mobile-side chat id the UI knows; the fake gateway resolves it to
/// `runtime-1` / `stored-1`.
const _mobile = 'mob-registry';

String _runtimeSession(int ordinal) => 'runtime-$ordinal';
String _storedSession(int ordinal) => 'stored-$ordinal';

void main() {
  group('gatewayClientIdentityChanged', () {
    test('every field the shared client is built from counts as identity', () {
      final base = _identityConnection();
      final varied = <String, SavedConnection>{
        'host': base.copyWith(host: 'other.example'),
        'port': base.copyWith(port: 9999),
        'https flag': base.copyWith(useHttps: true),
        'dashboard port': base.copyWith(dashboardPortOverride: 4119),
        'dashboard prefix': base.copyWith(dashboardPrefix: '/dashboard'),
        'dashboard proxied': base.copyWith(dashboardProxied: true),
        'desktop gateway override': base.copyWith(
          desktopGatewayUrl: 'https://override.example:9443',
        ),
        'dashboard username': base.copyWith(dashboardUsername: 'someone'),
        'dashboard password': base.copyWith(dashboardPassword: 'something'),
        'gateway profile': base.copyWith(gatewayProfile: 'sol'),
      };

      varied.forEach((field, edited) {
        expect(
          gatewayClientIdentityChanged(base, edited),
          isTrue,
          reason: 'a $field edit must drop the client built from the old one',
        );
        expect(
          gatewayClientIdentityChanged(edited, base),
          isTrue,
          reason: 'reversing a $field edit must be detected too',
        );
      });
    });

    test('a cosmetic edit leaves the shared client alone', () {
      final base = _identityConnection();
      final cosmetic = <String, SavedConnection>{
        'label': base.copyWith(label: 'Renamed gateway'),
        'label and nothing else': base.copyWith(label: 'Moved to the study'),
        // The REST API Server key is read per request by ApiClient; the
        // WebSocket transport authenticates with a dashboard ticket instead.
        'api key': base.copyWith(apiKey: 'rest-key'),
        // The gateway path prefix belongs to the REST surface.
        'gateway path prefix': base.copyWith(gatewayPrefix: '/gateway'),
      };

      cosmetic.forEach((field, edited) {
        expect(
          gatewayClientIdentityChanged(base, edited),
          isFalse,
          reason:
              'a $field edit must not tear down a socket the connection '
              'still needs',
        );
      });
      expect(
        gatewayClientIdentityChanged(base, base),
        isFalse,
        reason: 'an unchanged connection keeps its client',
      );
    });

    test('a different connection id is never the same client', () {
      final base = _identityConnection();
      expect(
        gatewayClientIdentityChanged(base, _identityConnection(id: 'other')),
        isTrue,
      );
    });
  });

  group('GatewayClientRegistry', () {
    test('hands one client to every borrower of the same connection', () {
      final registry = GatewayClientRegistry();
      addTearDown(registry.close);
      final first = _connection('http://127.0.0.1:1', id: 'conn-a');
      final second = _connection('http://127.0.0.1:2', id: 'conn-b');

      expect(registry.existingFor(first.id), isNull);

      final client = registry.clientFor(first);
      expect(
        identical(registry.clientFor(first), client),
        isTrue,
        reason:
            'a second borrower of the same connection must reuse the socket, '
            'not open a second one',
      );
      expect(
        identical(registry.clientFor(second), client),
        isFalse,
        reason: 'connections stay independent',
      );
      expect(registry.existingFor(first.id), same(client));
      expect(registry.existingFor(second.id), isNotNull);
    });

    test('drops a connection so the next borrower builds a fresh client', () {
      final registry = GatewayClientRegistry();
      addTearDown(registry.close);
      final connection = _connection('http://127.0.0.1:1');
      final first = registry.clientFor(connection);

      registry.closeConnection(connection.id);

      expect(first.isClosed, isTrue, reason: 'the dropped client is released');
      expect(registry.existingFor(connection.id), isNull);

      final second = registry.clientFor(connection);
      expect(identical(first, second), isFalse);
      expect(second.isClosed, isFalse);
    });

    test('refuses to hand out clients once the application owner is closed', () {
      final registry = GatewayClientRegistry();
      final connection = _connection('http://127.0.0.1:1');
      final client = registry.clientFor(connection);

      registry.close();

      expect(client.isClosed, isTrue);
      expect(registry.existingFor(connection.id), isNull);
      expect(() => registry.clientFor(connection), throwsStateError);
    });
  });

  group('a shared connection outlives its borrower', () {
    test('a borrowed client keeps its socket open after the borrower detaches',
        () async {
      final gateway = await _RegistryFakeGateway.start();
      addTearDown(gateway.stop);
      final registry = GatewayClientRegistry();
      addTearDown(registry.close);
      final connection = _connection(gateway.baseUrl);
      final client = registry.clientFor(connection);
      addTearDown(client.close);

      // What a chat screen does while it is mounted: attach, then bring the
      // socket up.
      final detachedFrames = <String>[];
      final borrowToken = client.addAsyncEventListener(
        (sessionId, event) => detachedFrames.add('$sessionId#${event.type}'),
      );
      await client.ensureSession(_mobile);
      await _waitFor(() => gateway.openSockets.length == 1);

      // What its dispose does: detach only.
      client.removeAsyncEventListener(borrowToken);
      await _settle();

      expect(
        client.isClosed,
        isFalse,
        reason: 'leaving a chat must not close the connection it borrowed',
      );
      expect(gateway.openSockets, hasLength(1));

      // The detached socket is still live: a later consumer on the same
      // instance still receives frames pushed by the gateway.
      final laterFrames = <String>[];
      client.addAsyncEventListener(
        (sessionId, event) => laterFrames.add('$sessionId#${event.seq}'),
      );
      await gateway.sendEvent(
        sessionId: _runtimeSession(1),
        seq: 1,
        text: 'still live',
      );
      await _waitFor(() => laterFrames.isNotEmpty);

      expect(laterFrames, ['$_mobile#1']);
      expect(
        detachedFrames,
        isEmpty,
        reason: 'the detached listener is gone, not merely silenced',
      );
    });

    test('the owner still tears the borrowed socket down', () async {
      final gateway = await _RegistryFakeGateway.start();
      addTearDown(gateway.stop);
      final registry = GatewayClientRegistry();
      final connection = _connection(gateway.baseUrl);
      final client = registry.clientFor(connection);

      await client.ensureSession(_mobile);
      await _waitFor(() => gateway.openSockets.length == 1);

      registry.closeConnection(connection.id);

      expect(client.isClosed, isTrue);
      await _waitFor(() => gateway.openSockets.isEmpty);
    });

    test('a client built without a registry is torn down by its owner',
        () async {
      // The route-local fallback the chat screen keeps when no registry is
      // injected still owns and closes its own connection.
      final gateway = await _RegistryFakeGateway.start();
      addTearDown(gateway.stop);
      final client = DesktopGatewayClient.fromConnection(
        _connection(gateway.baseUrl),
      );
      addTearDown(client.close);

      await client.ensureSession(_mobile);
      await _waitFor(() => gateway.openSockets.length == 1);

      client.close();

      expect(client.isClosed, isTrue);
      await _waitFor(() => gateway.openSockets.isEmpty);
    });
  });

  group('connection-state listeners', () {
    test('every registered listener sees every transition', () async {
      final gateway = await _RegistryFakeGateway.start();
      addTearDown(gateway.stop);
      final client = DesktopGatewayClient.fromConnection(
        _connection(gateway.baseUrl),
      );
      addTearDown(client.close);

      final first = <DesktopConnectionState>[];
      final second = <DesktopConnectionState>[];
      client.addConnectionListener(first.add);
      client.addConnectionListener(second.add);

      await client.ensureSession(_mobile);
      await _waitFor(
        () =>
            first.contains(DesktopConnectionState.connected) &&
            second.contains(DesktopConnectionState.connected),
      );

      expect(first, [
        DesktopConnectionState.connecting,
        DesktopConnectionState.connected,
      ]);
      expect(second, first, reason: 'a later registration is not evicted');

      await gateway.dropSockets();
      await _waitFor(
        () =>
            first.contains(DesktopConnectionState.disconnected) &&
            second.contains(DesktopConnectionState.disconnected),
      );
    });

    test('removing one token leaves the other listener attached', () async {
      final gateway = await _RegistryFakeGateway.start();
      addTearDown(gateway.stop);
      final client = DesktopGatewayClient.fromConnection(
        _connection(gateway.baseUrl),
      );
      addTearDown(client.close);

      final dropped = <DesktopConnectionState>[];
      final kept = <DesktopConnectionState>[];
      final droppedToken = client.addConnectionListener(dropped.add);
      client.addConnectionListener(kept.add);

      await client.ensureSession(_mobile);
      await _waitFor(() => kept.contains(DesktopConnectionState.connected));
      expect(dropped, contains(DesktopConnectionState.connected));

      client.removeConnectionListener(droppedToken);
      final droppedCount = dropped.length;

      await gateway.dropSockets();
      await _waitFor(
        () => kept.contains(DesktopConnectionState.disconnected),
      );
      await _settle();

      expect(
        dropped,
        hasLength(droppedCount),
        reason: 'a detached listener stops receiving transitions',
      );
      expect(kept.last, DesktopConnectionState.disconnected);

      // A stale token — already removed, or spent on a closed client — is a
      // no-op, so a teardown path can run twice safely.
      client.removeConnectionListener(droppedToken);
      expect(client.connectionListenerCount, 1);
    });
  });

  group('the draft/notification owner', () {
    test('borrows the registry client and leaves it open when it closes',
        () async {
      final registry = GatewayClientRegistry();
      addTearDown(registry.close);
      final connection = _connection('http://127.0.0.1:1');
      final controller = GatewayTurnApplicationController(
        registry: registry,
      );

      controller.sessionFor(connection);
      final client = registry.existingFor(connection.id);
      expect(
        client,
        isNotNull,
        reason:
            'the application session must run on the registry client, not on '
            'a second socket built for the same connection',
      );

      await controller.close();

      expect(
        client!.isClosed,
        isFalse,
        reason:
            'a client this owner does not own must survive its close: the '
            'chat screens are still mounted on it',
      );
      expect(registry.existingFor(connection.id), same(client));

      registry.close();
      expect(client.isClosed, isTrue);
    });

    test('shares one socket with the chat borrow on the same connection',
        () async {
      final gateway = await _RegistryFakeGateway.start();
      addTearDown(gateway.stop);
      final registry = GatewayClientRegistry();
      addTearDown(registry.close);
      final connection = _connection(gateway.baseUrl);

      // The chat screen's borrow: it opens the socket and listens on it.
      final chatClient = registry.clientFor(connection);
      final chatToken = chatClient.addAsyncEventListener((_, _) {});
      await chatClient.ensureSession(_mobile);
      await _waitFor(() => gateway.openSockets.length == 1);

      // The draft/notification owner asks for the same connection: same
      // instance, and its own listener receives frames off that one socket.
      final controller = GatewayTurnApplicationController(
        registry: registry,
      );
      addTearDown(controller.close);
      final session = controller.sessionFor(connection);
      expect(identical(registry.existingFor(connection.id), chatClient), isTrue);

      final delivered = <String>[];
      session.setAsyncEventListener(
        _mobile,
        (sessionId, event) => delivered.add('$sessionId#${event.type}'),
      );

      expect(gateway.openSockets, hasLength(1));
      await gateway.sendEvent(
        sessionId: _runtimeSession(1),
        seq: 1,
        text: 'fan out',
      );
      await _waitFor(() => delivered.isNotEmpty);

      expect(delivered, ['$_mobile#notification.show']);
      chatClient.removeAsyncEventListener(chatToken);
    });
  });
}

SavedConnection _connection(String baseUrl, {String id = 'conn-registry'}) =>
    SavedConnection(
      id: id,
      label: 'Registry gateway',
      // The override host must differ from [host]: that is what makes the
      // client treat [baseUrl] as the gateway origin instead of falling back
      // to the default dashboard topology and bypassing this fixture.
      host: 'localhost',
      port: 8642,
      apiKey: 'fixture-key',
      desktopGatewayUrl: baseUrl,
      dashboardUsername: 'u',
      dashboardPassword: 'p',
    );

/// A connection whose every field sits at its default, so an identity test can
/// vary exactly one of them and attribute the result to that change.
SavedConnection _identityConnection({String id = 'conn-identity'}) =>
    SavedConnection(
      id: id,
      label: 'Identity fixture',
      host: 'identity.example',
      port: 8642,
      apiKey: '',
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

/// A minimal secured gateway: REST for the password login and the single-use
/// WebSocket ticket, then JSON-RPC over the socket.
///
/// Sessions are minted on demand in `session.create` order, so the Nth created
/// session is always `runtime-N` / `stored-N` — tests name those ids instead of
/// scraping them off the client.
class _RegistryFakeGateway {
  _RegistryFakeGateway(this._server) {
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

  /// Sockets the gateway currently has open, so a test can tell a live
  /// connection from a torn-down one.
  List<WebSocket> get openSockets => List.unmodifiable(_sockets);

  static Future<_RegistryFakeGateway> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _RegistryFakeGateway(server);
  }

  Future<void> stop() async {
    for (final socket in List.of(_sockets)) {
      await socket.close();
    }
    _sockets.clear();
    await _server.close(force: true);
  }

  /// Drops every live socket, the way a gateway restart or a phone sleep does.
  Future<void> dropSockets() async {
    for (final socket in List.of(_sockets)) {
      await socket.close();
    }
    _sockets.clear();
    await _waitFor(() => _sockets.isEmpty);
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
    _safeAdd(socket,
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'event',
        'params': <String, dynamic>{
          'type': 'gateway.ready',
          'payload': <String, dynamic>{'heartbeat': true},
        },
      }),
    );
    socket.listen(
      (raw) => _answer(socket, jsonDecode(raw as String) as Map<String, dynamic>),
      onDone: () => _sockets.remove(socket),
      onError: (_) => _sockets.remove(socket),
      cancelOnError: true,
    );
  }

  void _answer(WebSocket socket, Map<String, dynamic> frame) {
    final method = frame['method'];
    final params = (frame['params'] as Map?)?.cast<String, dynamic>() ?? {};

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
    _safeAdd(_sockets.last,
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
