import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_approval.dart';
import 'package:hermes_android/core/models/gateway_clarify.dart';
import 'package:hermes_android/core/models/gateway_sensitive_prompt.dart';
import 'package:hermes_android/core/services/ws_client.dart';

/// Hermes 0.21.3+ replaced the `*.request` events and `*.respond` methods with
/// server→client JSON-RPC requests: `{"id":"srq-…","method":"approval",…}`
/// frames that must be answered by a response frame carrying the same id.
/// These tests pin that wire contract against a loopback gateway.
void main() {
  late _GatewayServer gateway;

  tearDown(() async => gateway.stop());

  test('an srq frame reaches onServerRequest', () async {
    gateway = _GatewayServer();
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);
    final requests = <GatewayServerRequest>[];
    client.onServerRequest = requests.add;
    try {
      await client.connect();
      await gateway.push({
        'jsonrpc': '2.0',
        'id': 'srq-4f2a1b3c9d8e',
        'method': 'approval',
        'params': {
          'session_id': 'sess-1',
          'request_id': 'req-1',
          'command': 'rm -rf /tmp/x',
          'description': 'Hermes wants to run a command.',
          'choices': ['once', 'deny'],
        },
      });
      await gateway.flush();

      expect(requests, hasLength(1));
      expect(requests.single.id, 'srq-4f2a1b3c9d8e');
      expect(requests.single.method, 'approval');
      expect(requests.single.params['command'], 'rm -rf /tmp/x');
      expect(requests.single.params['session_id'], 'sess-1');
    } finally {
      client.close();
    }
  });

  test('respondToServerRequest writes a response frame with no method', () async {
    gateway = _GatewayServer();
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);
    try {
      await client.connect();

      await client.respondToServerRequest(
        'srq-4f2a1b3c9d8e',
        result: {'choice': 'once'},
      );
      await gateway.flush();

      expect(gateway.frames, hasLength(1));
      expect(gateway.frames.single, {
        'jsonrpc': '2.0',
        'id': 'srq-4f2a1b3c9d8e',
        'result': {'choice': 'once'},
      });
    } finally {
      client.close();
    }
  });

  test('an unsupported request is answered with an error frame', () async {
    gateway = _GatewayServer();
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);
    try {
      await client.connect();

      await client.respondToServerRequest(
        'srq-unsupported',
        errorMessage: 'not supported on Hermes Android',
      );
      await gateway.flush();

      expect(gateway.frames.single, {
        'jsonrpc': '2.0',
        'id': 'srq-unsupported',
        'error': {
          'code': -32601,
          'message': 'not supported on Hermes Android',
        },
      });
    } finally {
      client.close();
    }
  });

  test('an srq frame does not disturb pending RPC calls', () async {
    gateway = _GatewayServer(
      answer: (method, params) => {
        'result': {'ok': method},
      },
    );
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);
    try {
      await client.connect();
      await gateway.push({
        'jsonrpc': '2.0',
        'id': 'srq-keepalive',
        'method': 'clarify',
        'params': {'session_id': 'sess-1', 'question': 'Which?'},
      });

      final response = await client.send('config.get', {'key': 'project'});

      expect((response['result'] as Map)['ok'], 'config.get');
      expect(gateway.requests.single['method'], 'config.get');
    } finally {
      client.close();
    }
  });

  test('resumeSession replays open_requests through onServerRequest', () async {
    gateway = _GatewayServer(
      answer: (method, params) => method == 'session.resume'
          ? {
              'result': {
                'session_id': 'runtime-1',
                'open_requests': [
                  {
                    'id': 'srq-aaa',
                    'method': 'clarify',
                    'params': {
                      'session_id': 'runtime-1',
                      'question': 'Which?',
                    },
                  },
                  {
                    'id': 'srq-bbb',
                    'method': 'sudo',
                    'params': {'session_id': 'runtime-1'},
                  },
                ],
              },
            }
          : {'result': <String, dynamic>{}},
    );
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);
    final requests = <GatewayServerRequest>[];
    client.onServerRequest = requests.add;
    try {
      await client.connect();

      await client.resumeSession('mob-1');

      expect(requests.map((request) => request.id), ['srq-aaa', 'srq-bbb']);
      expect(requests.map((request) => request.method), ['clarify', 'sudo']);
      expect(requests.first.params['question'], 'Which?');
    } finally {
      client.close();
    }
  });

  test('clarify.lock sends the per-question lock and returns the rest', () async {
    gateway = _GatewayServer(
      answer: (method, params) => method == 'clarify.lock'
          ? {
              'result': {
                'status': 'ok',
                'remaining': ['q2'],
              },
            }
          : {'result': <String, dynamic>{}},
    );
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);
    try {
      await client.connect();

      final remaining = await client.lockClarifyAnswer(
        requestId: 'srq-batch',
        questionId: 'q1',
        answer: 'First',
      );

      expect(remaining, ['q2']);
      expect(gateway.requests.single['method'], 'clarify.lock');
      expect(gateway.params.single, {
        'request_id': 'srq-batch',
        'question_id': 'q1',
        'answer': 'First',
      });
    } finally {
      client.close();
    }
  });

  test('the prompt models carry the backend request id', () {
    final clarify = GatewayClarifyRequest.fromEventDataList(
      {
        'request_id': 'srq-1',
        'questions': [
          {
            'qid': 'q1',
            'question': 'Pick one',
            'choices': ['a', 'b'],
          },
        ],
      },
      serverRequestId: 'srq-1',
    );
    expect(clarify.single.serverRequestId, 'srq-1');
    expect(clarify.single.questionId, 'q1');

    final approval = GatewayApprovalRequest.fromEventData(
      {
        'command': 'ls',
        'choices': ['once', 'deny'],
      },
      serverRequestId: 'srq-2',
    );
    expect(approval.serverRequestId, 'srq-2');

    final secret = GatewaySensitivePromptRequest.fromEventData(
      kind: GatewaySensitivePromptKind.secret,
      data: {'request_id': 'srq-3', 'env_var': 'API_KEY', 'prompt': 'Needed'},
      serverRequestId: 'srq-3',
    );
    expect(secret?.serverRequestId, 'srq-3');
  });

  test('answering without a connection fails instead of dropping it', () async {
    gateway = _GatewayServer();
    final baseUrl = await gateway.start();
    final client = WsClient(baseUrl);

    await expectLater(
      client.respondToServerRequest('srq-1', result: const {}),
      throwsA(isA<StateError>()),
    );
    client.close();
  });
}

/// Minimal JSON-RPC gateway over a loopback WebSocket: records every client
/// frame, answers method calls when an answer function is given, and can push
/// server→client frames (the `srq-…` requests under test).
class _GatewayServer {
  _GatewayServer({this.answer});

  final Map<String, dynamic> Function(String method, Map<String, dynamic> params)?
  answer;

  /// Method-carrying frames the client sent.
  final List<Map<String, dynamic>> requests = [];
  final List<Map<String, dynamic>> params = [];

  /// Every frame the client sent, including response frames (which carry no
  /// `method`).
  final List<Map<String, dynamic>> frames = [];

  HttpServer? _server;
  StreamSubscription<WebSocket>? _subscription;
  WebSocket? _socket;
  final Completer<void> _connected = Completer<void>();

  Future<String> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _subscription = server.transform(WebSocketTransformer()).listen((socket) {
      _socket = socket;
      if (!_connected.isCompleted) _connected.complete();
      socket.listen((raw) {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        frames.add(frame);
        final method = frame['method']?.toString() ?? '';
        if (method.isEmpty) return; // a client response frame (srq answer)
        final requestParams =
            (frame['params'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        requests.add(frame);
        params.add(requestParams);
        final reply = answer?.call(method, requestParams);
        if (reply == null) return;
        socket.add(
          jsonEncode({'jsonrpc': '2.0', 'id': frame['id'], ...reply}),
        );
      });
    });
    return 'http://127.0.0.1:${server.port}';
  }

  /// Pushes one server→client frame once the socket is up.
  Future<void> push(Map<String, dynamic> frame) async {
    await _connected.future;
    _socket?.add(jsonEncode(frame));
  }

  /// Waits until the client has processed pushed frames.
  Future<void> flush([int milliseconds = 40]) =>
      Future<void>.delayed(Duration(milliseconds: milliseconds));

  Future<void> stop() async {
    await _subscription?.cancel();
    await _server?.close(force: true);
  }
}
