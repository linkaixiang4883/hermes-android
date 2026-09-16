// The Project folder must survive every way a new chat can reach the gateway.
//
// A Project chat is filed by being CREATED in its project's folder
// (`session.create {cwd}`), and creation can be driven by any call that needs
// the session first: the open-time preflight, the first prompt, an attachment,
// a model change. These tests pin the two ends of that contract:
//
// * a preflight that fails transiently must not lose the folder — the call
//   that creates the session afterwards still carries it (the Hermes
//   automation review of upstream PR #102 named exactly this leak); and
// * a chat that already exists on the gateway is never re-homed: the folder
//   only ever rides a CREATE.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';

/// A minimal gateway: REST for the WebSocket ticket, then JSON-RPC over the
/// socket. Records every `session.create` / `session.resume` and answers with
/// the stock-Hermes shapes the client expects.
class _FakeGateway {
  _FakeGateway(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final List<Map<String, dynamic>> creates = [];
  final List<Map<String, dynamic>> resumes = [];

  /// Answers the first `session.create` with an error, then succeeds.
  bool failFirstCreate = false;

  /// When set, `session.resume` succeeds for this id instead of 4007.
  String? liveSessionId;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);

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
      socket.add(
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
          reply({'session_id': live, 'stored_session_id': live});
        } else {
          reply(null, error: {'code': 4007, 'message': 'session not found'});
        }
      case 'session.create':
        creates.add(params);
        if (failFirstCreate) {
          failFirstCreate = false;
          reply(null, error: {'code': -32603, 'message': 'gateway hiccup'});
        } else {
          reply({'session_id': 'runtime-1', 'stored_session_id': 'stored-1'});
        }
      case 'file.attach':
        reply({
          'attached': true,
          'ref_text': '@file:one',
          'name': params['name'],
          'path': '',
        });
      default:
        reply(null, error: {'code': -32601, 'message': 'method not found'});
    }
  }
}

SavedConnection _connection(String baseUrl) => SavedConnection(
  id: 'conn-1',
  label: 'Test gateway',
  // The override host must differ from [host]: that is what makes the client
  // treat [baseUrl] as the gateway origin instead of falling back to the
  // default dashboard topology (port 9119).
  host: 'gateway.test',
  port: 8642,
  apiKey: 'test-key-0123456789',
  desktopGatewayUrl: baseUrl,
  dashboardUsername: 'misha',
  dashboardPassword: 'secret',
);

void main() {
  test(
    'a failed preflight keeps the Project folder for the call that creates '
    'the session',
    () async {
      final gateway = _FakeGateway(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      );
      gateway.failFirstCreate = true;
      final client = DesktopGatewayClient.fromConnection(
        _connection(gateway.baseUrl),
      );
      addTearDown(() async {
        client.close();
        await gateway.close();
      });

      // The open-time preflight — the gateway hiccups on its first create.
      await expectLater(
        client.ensureSession('mob-1', cwd: '/srv/p1'),
        throwsA(anything),
      );

      // The first action after the failure drives the retry that creates the
      // session. It must still be born in the project's folder.
      final attachment = await client.attachFile(
        sessionId: 'mob-1',
        name: 'notes.txt',
        dataUrl: 'data:text/plain;base64,aGk=',
      );

      expect(attachment.refText, '@file:one');
      expect(gateway.creates, hasLength(2));
      expect(gateway.creates.first, {'cwd': '/srv/p1'});
      expect(gateway.creates.last, {'cwd': '/srv/p1'});
    },
  );

  test('a chat that already exists is never re-homed by the remembered '
      'folder', () async {
    final gateway = _FakeGateway(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    gateway.liveSessionId = 'mob-2';
    final client = DesktopGatewayClient.fromConnection(
      _connection(gateway.baseUrl),
    );
    addTearDown(() async {
      client.close();
      await gateway.close();
    });

    await client.ensureSession('mob-2', cwd: '/srv/p2');
    await client.attachFile(
      sessionId: 'mob-2',
      name: 'notes.txt',
      dataUrl: 'data:text/plain;base64,aGk=',
    );

    // Resuming an existing chat never creates — and never moves — anything:
    // the folder is only ever applied at creation.
    expect(gateway.creates, isEmpty);
    expect(gateway.resumes, hasLength(1));
  });
}
