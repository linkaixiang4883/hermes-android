import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/ws_client.dart';

/// The official session/project writes the app relies on: a chat is filed into
/// a project by its working directory, so these are `session.create` with a
/// `cwd` and `session.workspace.move`.
void main() {
  late _GatewayServer gateway;

  void serve(
    Map<String, dynamic> Function(String method, Map<String, dynamic> params)
    answer,
  ) {
    gateway = _GatewayServer(answer);
  }

  tearDown(() async => gateway.stop());

  test('moves a stored chat with session.workspace.move', () async {
    serve((method, params) => {
      'result': {'cwd': params['cwd'], 'branch': 'main', 'git_repo_root': null},
    });
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);
    try {
      await client.connect();

      final moved = await client.moveSessionWorkspace(
        sessionKey: '20260913_120000_abcdef',
        cwd: 'D:\\work\\app\\flutter\\hermes-android',
      );

      expect(moved, 'D:\\work\\app\\flutter\\hermes-android');
      expect(gateway.requests.single['method'], 'session.workspace.move');
      expect(gateway.params.single, {
        'session_key': '20260913_120000_abcdef',
        'cwd': 'D:\\work\\app\\flutter\\hermes-android',
      });
    } finally {
      client.close();
    }
  });

  test('falls back to the requested folder when the gateway echoes none', () async {
    serve((method, params) => {'result': <String, dynamic>{}});
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);
    try {
      await client.connect();

      expect(
        await client.moveSessionWorkspace(sessionKey: 's-1', cwd: '/srv/p1'),
        '/srv/p1',
      );
    } finally {
      client.close();
    }
  });

  test('surfaces a rejected move as a JSON-RPC error', () async {
    serve((method, params) => {
      'error': {'code': 4017, 'message': 'working directory does not exist: /gone'},
    });
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);
    try {
      await client.connect();

      await expectLater(
        client.moveSessionWorkspace(sessionKey: 's-1', cwd: '/gone'),
        throwsA(
          isA<JsonRpcError>()
              .having((error) => error.code, 'code', 4017)
              .having((error) => error.method, 'method', 'session.workspace.move'),
        ),
      );
    } finally {
      client.close();
    }
  });

  test('creates a session anchored to a folder and returns its ids', () async {
    serve((method, params) => {
      'result': {
        'session_id': 'runtime-9',
        'stored_session_id': '20260913_120000_abcdef',
        'info': {'cwd': params['cwd']},
      },
    });
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);
    try {
      await client.connect();

      final handle = await client.createOrResumeSession(
        'mob-1757000000000',
        cwd: '/srv/p1',
      );

      expect(handle.sessionId, 'runtime-9');
      expect(handle.storedSessionId, '20260913_120000_abcdef');
      expect(gateway.requests.single['method'], 'session.create');
      expect(gateway.params.single, {
        'session_id': 'mob-1757000000000',
        'cwd': '/srv/p1',
      });
    } finally {
      client.close();
    }
  });

  test('creates an ordinary session without a cwd', () async {
    serve((method, params) => {
      'result': {'session_id': 'runtime-9'},
    });
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);
    try {
      await client.connect();

      final handle = await client.createOrResumeSession('mob-1');

      expect(handle.sessionId, 'runtime-9');
      expect(handle.storedSessionId, isNull);
      expect(gateway.params.single, {'session_id': 'mob-1'});
    } finally {
      client.close();
    }
  });

  test('reads the gateway default workspace for the Unassigned target', () async {
    serve((method, params) => {
      'result': {'cwd': 'C:\\Users\\dev', 'branch': null},
    });
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);
    try {
      await client.connect();

      expect(await client.defaultWorkspaceCwd(), 'C:\\Users\\dev');
      expect(gateway.requests.single['method'], 'config.get');
      expect(gateway.params.single, {'key': 'project'});
    } finally {
      client.close();
    }
  });

  test('an unknown config key leaves the Unassigned target unavailable', () async {
    serve((method, params) => {
      'error': {'code': 4002, 'message': 'unknown config key: project'},
    });
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);
    try {
      await client.connect();

      expect(await client.defaultWorkspaceCwd(), isNull);
    } finally {
      client.close();
    }
  });

  test('resumes a session and reports its stored id', () async {
    serve((method, params) => {
      'result': {
        'session_id': 'runtime-9',
        'stored_session_id': '20260913_120000_abcdef',
      },
    });
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);
    try {
      await client.connect();

      final handle = await client.resumeSession('20260913_120000_abcdef');

      expect(handle.sessionId, 'runtime-9');
      expect(handle.storedSessionId, '20260913_120000_abcdef');
    } finally {
      client.close();
    }
  });
}

/// Minimal JSON-RPC gateway over a loopback WebSocket: records every request and
/// answers with whatever the test decided.
class _GatewayServer {
  _GatewayServer(this._answer);

  final Map<String, dynamic> Function(String method, Map<String, dynamic> params)
  _answer;
  final List<Map<String, dynamic>> requests = [];
  final List<Map<String, dynamic>> params = [];

  HttpServer? _server;
  StreamSubscription<WebSocket>? _subscription;

  Future<String> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _subscription = server.transform(WebSocketTransformer()).listen((socket) {
      socket.listen((raw) {
        final request = jsonDecode(raw as String) as Map<String, dynamic>;
        requests.add(request);
        final method = request['method']?.toString() ?? '';
        final requestParams =
            (request['params'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        params.add(requestParams);
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': request['id'],
            ..._answer(method, requestParams),
          }),
        );
      });
    });
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    await _server?.close(force: true);
  }
}
