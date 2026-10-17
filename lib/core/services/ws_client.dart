// WebSocket client for the Hermes gateway JSON-RPC API (/api/ws).
// Supports both request-response calls AND server-pushed streaming events.
//
// Wire protocol: newline-delimited JSON-RPC 2.0, same as the TUI gateway.
// After submitting a prompt, the server pushes stream events and finally
// a JSON-RPC response with the same id.
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';

Object? _deepFreezeJson(Object? value) {
  if (value is Map) {
    final copy = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) continue;
      copy[entry.key as String] = _deepFreezeJson(entry.value);
    }
    return Map<String, dynamic>.unmodifiable(copy);
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(value.map(_deepFreezeJson));
  }
  return value;
}

Map<String, dynamic> _deepFreezeJsonMap(Map<String, dynamic> value) {
  return _deepFreezeJson(value)! as Map<String, dynamic>;
}

Object? _canonicalJsonValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.whereType<String>().toList()..sort();
    return <String, dynamic>{
      for (final key in keys) key: _canonicalJsonValue(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalJsonValue).toList();
  return value;
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalJsonValue(value));

/// A JSON-RPC error response from the gateway.
class JsonRpcError implements Exception {
  final String method;
  final String message;
  final int? code;
  final String? reason;
  final Map<String, dynamic> data;

  JsonRpcError(
    this.method,
    this.message, {
    this.code,
    this.reason,
    Map<String, dynamic>? data,
  }) : data = _deepFreezeJsonMap(data ?? const <String, dynamic>{});

  factory JsonRpcError.fromGateway(
    String method,
    Map<dynamic, dynamic> error, {
    required String fallbackMessage,
  }) {
    final rawData = error['data'];
    final data = rawData is Map
        ? <String, dynamic>{
            for (final entry in rawData.entries)
              if (entry.key is String) entry.key as String: entry.value,
          }
        : const <String, dynamic>{};
    return JsonRpcError(
      method,
      error['message'] is String ? error['message'] as String : fallbackMessage,
      code: error['code'] is int ? error['code'] as int : null,
      reason: data['reason'] is String ? data['reason'] as String : null,
      data: data,
    );
  }

  /// Server guidance only. Callers must never automatically resubmit a turn.
  bool get safeToResubmit => data['safe_to_resubmit'] == true;

  @override
  String toString() => 'JsonRpcError($method): $message';
}

JsonRpcError _gatewayResponseError(
  String method,
  Object? error, {
  required String fallbackMessage,
}) {
  if (error is Map) {
    return JsonRpcError.fromGateway(
      method,
      error,
      fallbackMessage: fallbackMessage,
    );
  }
  return JsonRpcError(method, fallbackMessage);
}

/// Event types streamed from the gateway during a prompt submission.
class StreamEvent {
  final String type; // 'tool_call', 'tool_result', 'assistant', 'session', etc.
  final Map<String, dynamic> data;
  final bool isComplete; // true when the assistant message is done
  final String? sessionId;
  final String? turnId;
  final int? seq;
  final String? messageId;
  final Map<String, dynamic> envelope;

  StreamEvent({
    required this.type,
    required Map<String, dynamic> data,
    this.isComplete = false,
    this.sessionId,
    this.turnId,
    this.seq,
    this.messageId,
    Map<String, dynamic>? envelope,
  }) : data = _deepFreezeJsonMap(data),
       envelope = _deepFreezeJsonMap(envelope ?? const <String, dynamic>{});
}

/// Gateway-side file reference returned by `file.attach`.
class RemoteFileAttachment {
  final String name;
  final String path;
  final String refText;
  final bool uploaded;
  final bool? atlasIntakeAccepted;
  final String? atlasIntakeStatus;
  final String? atlasRelativePath;

  const RemoteFileAttachment({
    required this.name,
    required this.path,
    required this.refText,
    required this.uploaded,
    this.atlasIntakeAccepted,
    this.atlasIntakeStatus,
    this.atlasRelativePath,
  });
}

/// Both identities minted by the stock Hermes `session.create` contract.
///
/// The runtime id addresses calls on the current socket. The stored id is the
/// durable identity required by `session.resume` after that socket disconnects.
class CreatedGatewaySession {
  final String runtimeSessionId;
  final String storedSessionId;

  const CreatedGatewaySession({
    required this.runtimeSessionId,
    required this.storedSessionId,
  });
}

/// Runtime binding and recovery state returned by `session.resume`.
///
/// Stock Hermes includes retained in-flight failure details here so a client
/// that missed the terminal event while disconnected can stop recovery and
/// surface the failure instead of polling history forever.
class ResumedGatewaySession {
  final String runtimeSessionId;
  final bool? running;
  final String? status;
  final Map<String, dynamic>? inflight;
  final List<dynamic> openRequests;

  const ResumedGatewaySession({
    required this.runtimeSessionId,
    this.running,
    this.status,
    this.inflight,
    this.openRequests = const [],
  });
}

typedef StreamCallback = void Function(StreamEvent event);
typedef ConnectionCallback = void Function(bool connected);
typedef GatewayReadyCallback = void Function(Map<String, dynamic> frame);
typedef ServerRequestCallback = bool Function(GatewayServerRequest request);

/// A JSON-RPC request initiated by the Hermes gateway.
///
/// Unlike an `event` notification, this frame carries a string request ID and
/// must be answered with a JSON-RPC response carrying that same ID. The first
/// [respond] or [fail] call wins so a replayed card cannot answer twice.
class GatewayServerRequest {
  final String id;
  final String method;
  final Map<String, dynamic> params;
  final bool replayed;
  final bool Function(Map<String, dynamic> result) _respond;
  final bool Function(int code, String message) _fail;
  bool _settled = false;

  GatewayServerRequest._({
    required this.id,
    required this.method,
    required this.params,
    required this.replayed,
    required this._respond,
    required this._fail,
  });

  bool respond(Map<String, dynamic> result) {
    if (_settled) return false;
    if (!_respond(result)) return false;
    _settled = true;
    return true;
  }

  bool fail(int code, String message) {
    if (_settled) return false;
    if (!_fail(code, message)) return false;
    _settled = true;
    return true;
  }
}

/// WebSocket client for the Hermes JSON-RPC gateway.
class WsClient {
  final String baseUrl;
  final String? _token;
  final String? _ticket;
  final String? _profile;
  IOWebSocketChannel? _channel;
  bool _connected = false;
  int _nextId = 1;
  int _connectionGeneration = 0;
  int _nextConnectionClosedListenerToken = 1;

  /// Pending requests: id -> (completer, timer).
  final Map<int, _Pending> _pending = {};

  /// Active stream subscriptions: id -> callback.
  final Map<int, List<StreamCallback>> _streams = {};

  /// Gateway events are emitted independently of a JSON-RPC request ID. Keep
  /// per-session listeners so one active session cannot consume another one's
  /// streamed response.
  final Map<String, List<StreamCallback>> _sessionStreams = {};

  /// Per-session high-water mark of the `seq`s already dispatched. It outlives
  /// a dropped socket so a reconnect can ask `session.events.since` for exactly
  /// the frames this client missed; only [close] and a replay-epoch change
  /// clear it (a dropped socket never means "resynchronised").
  final Map<String, int> _lastSeenSeq = {};

  /// High-water marks for frames that carry a `turn_id`, keyed
  /// `sessionId\u0000turnId`. The gateway's transport stream numbers one
  /// sequence per session, but the turn-recovery protocol numbers events per
  /// turn from 1 again (`turn.reconcile` cursors, `GatewayTurnRecoveryState`),
  /// so a turn-scoped seq must never be compared against — or advance — the
  /// session watermark. Kept separate for the same reason: mixing the two
  /// numbering spaces silently swallows a live turn's frames. Bounded by
  /// [_maxTurnWatermarks], oldest turn evicted first.
  final Map<String, int> _lastSeenTurnSeq = {};

  /// Live frames parked while their session's replay window is in flight. A
  /// frame racing the answer must not dispatch ahead of the gap it would then
  /// suppress as a duplicate (desktop `replayHold` in json-rpc-gateway.ts).
  final Map<String, List<StreamEvent>> _replayHold = {};

  /// Sessions whose parked-frame buffer overflowed during the window in flight:
  /// the frames evicted to keep the hold bounded were never delivered, so their
  /// seqs are a hole in the dispatched stream. Reported once the surviving
  /// frames have flushed (see [_flushReplayHold]).
  final Set<String> _replayHoldOverflowed = {};

  /// Sessions whose current replay round already reported a hole (a truncated
  /// window). Truncation and overflow describe one and the same gap, so a round
  /// reports at most once ([_reportReplayHole]); the round's end consumes the
  /// marker, so it cannot leak into a later round.
  final Set<String> _replayHoleReported = {};

  /// Sessions whose replay window is currently being fetched.
  final Set<String> _replaying = {};

  /// Round counter for replay windows. A window belongs to the socket that
  /// started it: [close] and every [connect] invalidate the rounds in flight, so
  /// their completion can neither dispatch parked frames nor report a hole into
  /// a client that has already moved on (desktop `replayGeneration` in
  /// json-rpc-gateway.ts). A round only ever touches the session barrier it
  /// still owns (see [_fetchReplay]), which is what makes that guard exact.
  int _replayGeneration = 0;

  /// Server-process identity from `gateway.ready`. Seq counters live in the
  /// gateway process, so a restart resets them to 1 while this client still
  /// holds high watermarks — a change means the held numbers describe a
  /// numbering that no longer exists.
  String? _replayEpoch;

  final Map<int, _ConnectionClosedListener> _connectionClosedListeners = {};
  Completer<Map<String, dynamic>>? _gatewayReadyCompleter;
  Map<String, dynamic>? _gatewayReadyFrame;
  String? _gatewayReadyCanonical;
  JsonRpcError? _gatewayReadyFailure;
  bool _serverRequestsAdvertised = false;

  /// Global stream listener (receives all untargeted events).
  StreamCallback? onStreamEvent;
  ServerRequestCallback? onServerRequest;
  ConnectionCallback? onConnectionChanged;
  void Function()? onConnectionClosed;
  GatewayReadyCallback? onGatewayReady;

  /// Called with the session id when a replay round could not deliver a
  /// hole-free stream, because the gap needs a history re-read to be repaired:
  /// either the gateway's ring no longer holds the whole gap (`truncated`), or
  /// the parked-frame buffer overflowed and a frame was evicted before it could
  /// be dispatched. Both are reported at most once per round; nothing else will
  /// repair the gap, so the caller must re-read history.
  void Function(String sessionId)? onReplayTruncated;

  factory WsClient(
    String baseUrl, {
    String? token,
    String? ticket,
    String? profile,
    Duration heartbeatInterval = defaultHeartbeatInterval,
    Duration heartbeatDeadline = defaultHeartbeatDeadline,
  }) {
    return WsClient._(
      baseUrl,
      token,
      ticket,
      profile,
      heartbeatInterval,
      heartbeatDeadline,
    );
  }

  WsClient._(
    this.baseUrl,
    this._token,
    this._ticket,
    this._profile,
    this.heartbeatInterval,
    this.heartbeatDeadline,
  );

  /// Keepalive cadence mirroring the desktop client
  /// (`apps/shared/src/json-rpc-channel.ts` DEFAULT_HEARTBEAT_*): a
  /// `gateway.ping` every 15s, dead-socket verdict after 45s of silence.
  static const defaultHeartbeatInterval = Duration(seconds: 15);
  static const defaultHeartbeatDeadline = Duration(seconds: 45);

  final Duration heartbeatInterval;
  final Duration heartbeatDeadline;
  Timer? _heartbeatTimer;
  int _heartbeatSeq = 0;
  int _lastLivenessMs = 0;

  /// Connect to the WebSocket gateway.
  Future<void> connect() async {
    if (_connected) return;
    if (_channel != null) {
      throw StateError('A WebSocket connection is already in progress');
    }
    final generation = ++_connectionGeneration;
    // This socket starts a new replay round: rounds still in flight belong to
    // the socket they were asked on, and must not dispatch into this one.
    _replayGeneration++;
    _gatewayReadyFrame = null;
    _gatewayReadyCanonical = null;
    _gatewayReadyFailure = null;
    _serverRequestsAdvertised = false;
    final readyCompleter = Completer<Map<String, dynamic>>();
    _gatewayReadyCompleter = readyCompleter;
    // A transport can close before a caller starts waiting for gateway.ready.
    // Observe that error future immediately; the waiter still receives it.
    readyCompleter.future.ignore();
    final wsUrl = buildWebSocketUrl(baseUrl, token: _token, ticket: _ticket);
    final channel = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    _channel = channel;
    channel.stream.listen(
      (message) => _handleMessage(message, generation),
      onError: (_) => _handleClosedConnection(generation),
      onDone: () {
        _handleClosedConnection(generation);
      },
    );
    try {
      await channel.ready.timeout(const Duration(seconds: 15));
      if (generation != _connectionGeneration || _channel != channel) {
        throw JsonRpcError(
          'connect',
          'Connection closed during WebSocket setup',
          reason: 'connection_closed',
        );
      }
      _connected = true;
      _startHeartbeat(generation);
      // Install this socket's replay barrier before any open observer can start
      // history reads (desktop does the same), and keep the fetch itself
      // fire-and-forget so connect latency is unchanged.
      _scheduleReplay(generation);
      try {
        onConnectionChanged?.call(true);
      } catch (_) {
        // Transport observers cannot turn a live socket into setup failure.
      }
    } catch (_) {
      _handleClosedConnection(generation);
      try {
        await channel.sink.close();
      } catch (_) {
        // Preserve the original setup failure after closing this exact socket.
      }
      rethrow;
    }
  }

  void _handleClosedConnection(int generation) {
    if (generation != _connectionGeneration) return;
    // Invalidate this socket before any completion or observer can enqueue
    // more work. Buffered callbacks from it now fail the generation guard.
    _connectionGeneration = generation + 1;
    _stopHeartbeat();
    final wasConnected = _connected || _channel != null;
    _connected = false;
    _channel = null;
    // Reject all pending request-response calls.
    for (var entry in _pending.values) {
      entry.timer?.cancel();
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(
          JsonRpcError(
            entry.method,
            'Desktop gateway connection closed',
            reason: 'connection_closed',
          ),
        );
      }
    }
    _pending.clear();
    final closeError =
        _gatewayReadyFailure ??
        JsonRpcError(
          'gateway.ready',
          'Connection closed before gateway.ready',
          reason: 'connection_closed',
        );
    _gatewayReadyFailure = closeError;
    _gatewayReadyFrame = null;
    _gatewayReadyCanonical = null;
    final ready = _gatewayReadyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(closeError);
    }
    _gatewayReadyCompleter = null;
    final listenersToNotify = _connectionClosedListeners.entries
        .where((entry) => entry.value.generation == generation)
        .map((entry) => entry.value.callback)
        .toList(growable: false);
    _connectionClosedListeners.removeWhere(
      (_, listener) => listener.generation == generation,
    );
    _streams.clear();
    _sessionStreams.clear();
    for (final listener in listenersToNotify) {
      try {
        listener();
      } catch (_) {
        // One watcher cannot prevent the remaining close cleanup.
      }
    }
    if (wasConnected) {
      try {
        onConnectionClosed?.call();
      } catch (_) {
        // Cleanup observers cannot keep a rejected socket logically active.
      }
      try {
        onConnectionChanged?.call(false);
      } catch (_) {
        // Observer failures cannot keep a rejected socket logically active.
      }
    }
  }

  int _addConnectionClosedListener(void Function() callback) {
    final token = _nextConnectionClosedListenerToken++;
    _connectionClosedListeners[token] = _ConnectionClosedListener(
      _connectionGeneration,
      callback,
    );
    return token;
  }

  void _removeConnectionClosedListener(int token) {
    _connectionClosedListeners.remove(token);
  }

  /// Keepalive loop mirroring the desktop `JsonRpcChannel.startHeartbeat`.
  /// Every [heartbeatInterval] sends a `gateway.ping` (answered cheaply on
  /// the gateway's WS reader thread, even while every agent is mid-turn);
  /// if nothing has been received for [heartbeatDeadline] the socket is
  /// declared half-open and torn down, which starts the owner's reconnect
  /// instead of leaving later RPCs parked on a dead pipe.
  void _startHeartbeat(int generation) {
    _stopHeartbeat();
    if (heartbeatInterval.inMilliseconds <= 0 ||
        heartbeatDeadline.inMilliseconds <= 0) {
      return;
    }
    _lastLivenessMs = DateTime.now().millisecondsSinceEpoch;
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (generation != _connectionGeneration || !_connected) return;
      final silenceMs = DateTime.now().millisecondsSinceEpoch - _lastLivenessMs;
      if (silenceMs >= heartbeatDeadline.inMilliseconds) {
        // Half-open socket (phone slept, NAT dropped the mapping, proxy
        // died): close it so the close path rejects pending calls and the
        // owner can reconnect on a fresh ticket. 4000 = private close
        // code (the channel rejects 1001).
        _channel?.sink.close(4000, 'heartbeat timeout');
        _handleClosedConnection(generation);
        return;
      }
      _heartbeatSeq++;
      try {
        _channel?.sink.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 'heartbeat-$_heartbeatSeq',
            'method': 'gateway.ping',
            'params': <String, dynamic>{},
          }),
        );
      } catch (_) {
        _channel?.sink.close(4000, 'heartbeat send failed');
        _handleClosedConnection(generation);
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Produces the gateway `/api/ws` URL. Secured Desktop gateways use a
  /// single-use ticket; insecure legacy gateways still use a session token.
  static String buildWebSocketUrl(
    String baseUrl, {
    String? token,
    String? ticket,
  }) {
    final socketBase = baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final uri = Uri.parse('$socketBase/api/ws');
    final credential = ticket?.trim().isNotEmpty == true
        ? {'ticket': ticket!.trim()}
        : token?.trim().isNotEmpty == true
        ? {'token': token!.trim()}
        : const <String, String>{};
    return uri.replace(queryParameters: credential).toString();
  }

  /// Adds the connection's Hermes profile to a JSON-RPC params map.
  ///
  /// A machine-level `hermes dashboard` / `hermes serve` hosts every profile
  /// on the machine and scopes each RPC by `params['profile']`
  /// (`_profile_db` / `_profile_scoped` on the server; `session.create` and
  /// `session.resume` store it on the session so later turns re-bind to that
  /// profile's home). The socket URL carries no profile. Hermes Desktop sends
  /// the field on every scoped request, so this does the same. A blank
  /// profile sends nothing and the server keeps its own default; a caller that
  /// already set `profile` wins.
  static Map<String, dynamic> withProfile(
    Map<String, dynamic> params,
    String? profile,
  ) {
    final name = profile?.trim() ?? '';
    if (name.isEmpty || params.containsKey('profile')) return params;
    return <String, dynamic>{...params, 'profile': name};
  }

  /// Handle inbound messages.
  void _handleMessage(dynamic msg, int generation) {
    if (generation != _connectionGeneration) return;
    // Any inbound frame proves the socket is alive ('any-inbound' liveness,
    // matching the desktop channel): streaming events keep the heartbeat
    // deadline reset even if the pong for one ping raced past it.
    _lastLivenessMs = DateTime.now().millisecondsSinceEpoch;
    try {
      Map<String, dynamic> data;
      if (msg is String) {
        data = jsonDecode(msg) as Map<String, dynamic>;
      } else if (msg is Map<String, dynamic>) {
        data = msg;
      } else {
        return;
      }

      final id = data['id'];
      final method = data['method'] as String?;
      final params = data['params'];

      // JSON-RPC is peer-to-peer. Hermes uses string IDs (`srq-...`) for
      // server→client requests so they cannot collide with our integer IDs.
      // Route these before the normal response path; treating them as an
      // unknown response silently drops clarify/approval/secret prompts.
      if (id is String && method != null && method != 'event') {
        _deliverServerRequest(
          id,
          method,
          params is Map<String, dynamic> ? params : const {},
        );
        return;
      }

      // Server-pushed events have the JSON-RPC method `event` and carry their
      // actual type/session/payload inside params.
      if (method == 'event' && id == null && params is Map<String, dynamic>) {
        if (params['type'] == 'gateway.ready') {
          _handleGatewayReady(data, generation);
          _advertiseServerRequestSupport();
          return;
        }
        final event = parseGatewayEvent(params);
        if (event != null) {
          final sessionId = event.sessionId;
          if (sessionId != null &&
              event.seq != null &&
              _replaying.contains(sessionId)) {
            // This session's replay window is still in flight: park the frame
            // so it dispatches after the replayed gap instead of advancing the
            // watermark past events that are about to be delivered.
            _holdReplayFrame(sessionId, event);
            return;
          }
          if (_passSeqGate(event)) _deliverEvent(event);
        }
        return;
      }

      // Response to a request (has id, may have method for streaming completion)
      if (id != null) {
        final pending = _pending[id];
        if (pending != null) {
          _pending.remove(id);
          pending.timer?.cancel();
          if (method == null || params == null) {
            _streams.remove(id);
          }
          pending.completer.complete(data);
          // Internal request state is terminal before observers see the final
          // stream event. Observer failures cannot retain a pending request.
          if (method != null && params != null) {
            _dispatchStreamEvent(
              id,
              method,
              params is Map<String, dynamic> ? params : {},
            );
          }
          return;
        }
      }
    } catch (_) {
      // Ignore parse errors
    }
  }

  void _advertiseServerRequestSupport() {
    // Never claim support unless this socket can actually route the requests.
    // A recovery socket without a handler would otherwise make the gateway
    // send prompts that this client immediately rejects with -32601.
    if (_serverRequestsAdvertised || onServerRequest == null) return;
    _serverRequestsAdvertised = true;
    // This method is connection-scoped, not profile-scoped. Older gateways
    // answer -32601; deliberately ignore that response so they keep working.
    unawaited(
      send('client.capabilities', const {
        'server_requests': true,
      }, includeProfile: false).then<void>((_) {}, onError: (_, _) {}),
    );
  }

  void _deliverServerRequest(
    String id,
    String method,
    Map<String, dynamic> params, {
    bool replayed = false,
  }) {
    final request = GatewayServerRequest._(
      id: id,
      method: method,
      params: Map<String, dynamic>.from(params),
      replayed: replayed,
      respond: (result) => _sendServerResponse(id, result: result),
      fail: (code, message) =>
          _sendServerResponse(id, error: {'code': code, 'message': message}),
    );
    final listener = onServerRequest;
    if (listener == null) {
      request.fail(-32601, 'no handler for server request: $method');
      return;
    }
    try {
      if (!listener(request)) {
        request.fail(-32601, 'no handler for server request: $method');
      }
    } catch (_) {
      request.fail(-32603, 'server request handler crashed: $method');
    }
  }

  /// Re-deliver unanswered requests returned by `session.resume` or event
  /// replay after the caller has restored its runtime-to-local session map.
  void deliverOpenRequests(Iterable<dynamic> snapshots) {
    for (final raw in snapshots) {
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      final id = entry['id'];
      final method = entry['method'];
      final rawParams = entry['params'];
      if (id is! String || method is! String) continue;
      _deliverServerRequest(
        id,
        method,
        rawParams is Map ? Map<String, dynamic>.from(rawParams) : const {},
        replayed: true,
      );
    }
  }

  bool _sendServerResponse(
    String id, {
    Map<String, dynamic>? result,
    Map<String, dynamic>? error,
  }) {
    final channel = _channel;
    if (channel == null || channel.closeCode != null) return false;
    channel.sink.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        if (error != null) 'error': error else 'result': result ?? const {},
      }),
    );
    return true;
  }

  void _handleGatewayReady(Map<String, dynamic> data, int generation) {
    if (generation != _connectionGeneration) return;
    final frame = _deepFreezeJsonMap(data);
    final canonical = _canonicalJson(frame);
    final pinned = _gatewayReadyCanonical;
    if (pinned == null) {
      _gatewayReadyCanonical = canonical;
      _gatewayReadyFrame = frame;
      // The greeting names the gateway process's seq numbering. Adopt it here,
      // on the frame this socket is pinned to, before the replay fetch decides
      // what to ask for.
      _adoptReplayEpoch(frame);
      final ready = _gatewayReadyCompleter;
      if (ready != null && !ready.isCompleted) ready.complete(frame);
      try {
        onGatewayReady?.call(frame);
      } catch (_) {
        // Capability observers cannot change the pinned socket authority.
      }
      return;
    }
    if (pinned == canonical) return;

    _gatewayReadyFailure = JsonRpcError(
      'gateway.ready',
      'Gateway ready frame changed on the active connection',
      reason: 'gateway_ready_drift',
    );
    final channel = _channel;
    _handleClosedConnection(generation);
    channel?.sink.close();
  }

  /// Parse one server-pushed `event` frame's params into a [StreamEvent], or
  /// null when the frame carries no usable type. Live and replayed frames are
  /// parsed here, so handlers cannot tell one from the other.
  static StreamEvent? parseGatewayEvent(Map<String, dynamic> params) {
    final rawType = params['type'];
    if (rawType is! String || rawType.isEmpty) return null;
    final payload = params['payload'];
    final data = payload is Map<String, dynamic>
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};
    final sessionCandidates = <Object?>[params['session_id'], params['sid']];
    String? sessionId;
    for (final candidate in sessionCandidates) {
      if (candidate is String &&
          candidate.isNotEmpty &&
          candidate.length <= 256 &&
          candidate.trim() == candidate &&
          !candidate.codeUnits.any(
            (unit) => unit < 32 || unit >= 127 && unit <= 159,
          )) {
        sessionId = candidate;
        break;
      }
    }
    if (sessionId != null && sessionId.isNotEmpty) {
      data['session_id'] = sessionId;
    }
    final rawTurnId = params['turn_id'];
    final rawSeq = params['seq'];
    final rawMessageId = params['message_id'];
    final turnId =
        rawTurnId is String &&
            rawTurnId.isNotEmpty &&
            rawTurnId.length <= 256 &&
            rawTurnId.trim() == rawTurnId &&
            !rawTurnId.codeUnits.any(
              (unit) => unit < 32 || unit >= 127 && unit <= 159,
            )
        ? rawTurnId
        : null;
    final messageId =
        rawMessageId is String &&
            rawMessageId.isNotEmpty &&
            rawMessageId.length <= 256 &&
            rawMessageId.trim() == rawMessageId &&
            !rawMessageId.codeUnits.any(
              (unit) => unit < 32 || unit >= 127 && unit <= 159,
            )
        ? rawMessageId
        : null;
    return StreamEvent(
      type: rawType,
      data: data,
      isComplete:
          rawType == 'message.complete' ||
          rawType == 'error' ||
          rawType == 'turn.end' ||
          rawType == 'turn.error',
      sessionId: sessionId,
      turnId: turnId,
      seq: rawSeq is int && rawSeq > 0 ? rawSeq : null,
      messageId: messageId,
      envelope: params,
    );
  }

  /// Wait for the capability-bearing greeting emitted by this exact socket.
  Future<Map<String, dynamic>> waitForGatewayReady({
    Duration timeout = const Duration(seconds: 15),
  }) {
    final failure = _gatewayReadyFailure;
    if (failure != null) return Future<Map<String, dynamic>>.error(failure);
    final frame = _gatewayReadyFrame;
    if (frame != null) return Future<Map<String, dynamic>>.value(frame);
    final ready = _gatewayReadyCompleter;
    if (ready == null) {
      throw StateError('connect must run before waiting for gateway.ready');
    }
    return ready.future.timeout(timeout);
  }

  /// Dispatch a server-pushed event to registered listeners.
  ///
  /// The single delivery path for live AND replayed frames: replay must not
  /// grow a second fan-out that could drift from this one.
  void _deliverEvent(StreamEvent event) {
    try {
      onStreamEvent?.call(event);
    } catch (_) {
      // Global observers cannot block the session-scoped listener chain.
    }
    final sessionId = event.sessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    final listeners = _sessionStreams[sessionId];
    if (listeners == null) return;
    for (final listener in List<StreamCallback>.from(listeners)) {
      try {
        listener(event);
      } catch (_) {
        // One session observer cannot block other listeners or cleanup.
      }
    }
  }

  /// Bound on live frames parked per session while its replay is in flight.
  /// The hold only lives for one replay request; a pathological stream must not
  /// grow it without limit, so the oldest parked frame is dropped first — and
  /// that eviction is reported, since a dropped frame leaves a seq hole in the
  /// dispatched stream that nothing but a history re-read can repair.
  static const _maxReplayHoldPerSession = 256;

  /// Bound on the turn-scoped watermarks ([_lastSeenTurnSeq]). A turn's
  /// watermark only matters while that turn is live — recovery reconciles per
  /// turn and the gateway never renumbers a finished one — so evicting the
  /// oldest turn is safe. It keeps a long-lived client from holding one entry
  /// per turn ever seen (64 matches `GatewayTurnJournal.maxBindings`).
  static const _maxTurnWatermarks = 64;

  /// Replay is an optimization over a lossy reconnect: a window that outlives
  /// its socket (a hung session) is abandoned, not waited on.
  static const _replayRequestTimeout = Duration(seconds: 10);

  /// Seq gate shared by live and replayed frames: true when [event] advances
  /// its session's watermark. A frame without a session id or without a seq has
  /// no ordering contract to violate and always passes (legacy gateways,
  /// session-less global events).
  ///
  /// Frames carrying a `turn_id` are gated inside that turn's own numbering
  /// (see [_lastSeenTurnSeq]) — only frames with no turn scope, which is what
  /// the gateway's transport stream emits, move the per-session watermark that
  /// [fetchReplay] sends as `last_seen`.
  bool _passSeqGate(StreamEvent event) {
    final sessionId = event.sessionId;
    final seq = event.seq;
    if (sessionId == null || sessionId.isEmpty || seq == null) return true;
    final turnId = event.turnId;
    if (turnId != null && turnId.isNotEmpty) {
      final key = '$sessionId\u0000$turnId';
      final last = _lastSeenTurnSeq[key];
      if (last == null && _lastSeenTurnSeq.length >= _maxTurnWatermarks) {
        // A new turn while the map is full: drop the oldest turn's watermark,
        // which is the one least likely to still be reconciling.
        _lastSeenTurnSeq.remove(_lastSeenTurnSeq.keys.first);
      }
      if (seq <= (last ?? 0)) return false;
      _lastSeenTurnSeq[key] = seq;
      return true;
    }
    if (seq <= (_lastSeenSeq[sessionId] ?? 0)) return false;
    _lastSeenSeq[sessionId] = seq;
    return true;
  }

  /// Park one live frame while its session's replay window is in flight.
  void _holdReplayFrame(String sessionId, StreamEvent event) {
    final held = _replayHold.putIfAbsent(sessionId, () => <StreamEvent>[]);
    if (held.length >= _maxReplayHoldPerSession) {
      // Bounded hold: the oldest frame goes. Its seq is never delivered, so the
      // flush that follows will jump it — remember the hole for the round so the
      // caller is told to re-read history instead of trusting the watermarks.
      _replayHoldOverflowed.add(sessionId);
      held.removeAt(0);
    }
    held.add(event);
  }

  /// Release this session's parked frames in arrival order, through the same
  /// seq gate: frames the replay window already delivered stay dropped. Reports
  /// the round's hole, if any, once the surviving frames are out.
  void _flushReplayHold(String sessionId) {
    final held = _replayHold.remove(sessionId);
    final overflowed = _replayHoldOverflowed.remove(sessionId);
    if (held != null) {
      for (final event in held) {
        if (_passSeqGate(event)) _deliverEvent(event);
      }
    }
    if (overflowed) _reportReplayHole(sessionId);
    // This round is over: a later round starts from a clean slate.
    _replayHoleReported.remove(sessionId);
  }

  /// Drop this session's parked frames without dispatching or reporting them.
  /// The round that parked them belongs to a socket that has been torn down or
  /// replaced, so its frames died with it; whatever was truly missed is asked
  /// for again from the watermark they never advanced.
  void _discardReplayHold(String sessionId) {
    _replayHold.remove(sessionId);
    _replayHoldOverflowed.remove(sessionId);
    _replayHoleReported.remove(sessionId);
  }

  /// Tell the caller this session's stream has a hole no replay covered, so
  /// history has to be re-read. At most one report per round: a truncated window
  /// reports as it is skipped, a hold overflow reports at flush, and both mean
  /// the same thing. Observer failures cannot break the replay teardown.
  void _reportReplayHole(String sessionId) {
    if (!_replayHoleReported.add(sessionId)) return;
    try {
      onReplayTruncated?.call(sessionId);
    } catch (_) {
      // A hole observer cannot break the replay teardown.
    }
  }

  /// Record the gateway's replay epoch. A change means the gateway restarted
  /// and reset its in-process seq counters: every held watermark then describes
  /// a numbering that no longer exists, so drop them instead of letting a
  /// replay believe nothing was missed.
  void _adoptReplayEpoch(Map<String, dynamic> readyFrame) {
    final params = readyFrame['params'];
    final payload = params is Map ? params['payload'] : null;
    final raw = payload is Map ? payload['replay_epoch'] : null;
    final epoch = raw is String ? raw.trim() : '';
    if (epoch.isEmpty || epoch == _replayEpoch) return;
    final changed = _replayEpoch != null;
    _replayEpoch = epoch;
    if (changed) {
      _lastSeenSeq.clear();
      _lastSeenTurnSeq.clear();
    }
  }

  /// Start this socket's replay window once its greeting has been folded in.
  ///
  /// `gateway.ready` carries `replay_epoch`, and adopting a *changed* epoch
  /// clears every watermark — so the fetch must not decide what to ask for
  /// before that frame has been processed, whatever order the handshake and the
  /// greeting arrive in (the greeting can beat `connect()`'s own completion).
  void _scheduleReplay(int generation) {
    unawaited(_replayWhenGreeted(generation));
  }

  Future<void> _replayWhenGreeted(int generation) async {
    if (_gatewayReadyFrame == null) {
      try {
        await waitForGatewayReady();
      } catch (_) {
        // Closed before its greeting: this socket has nothing to resume.
        return;
      }
    }
    if (generation != _connectionGeneration) return;
    try {
      await _fetchReplay();
    } catch (_) {
      // Replay is best-effort and can never fail a live connection.
    }
  }

  /// After a reconnect, ask the gateway to replay every event newer than our
  /// per-session watermarks (mirrors `fetchReplay` in the desktop
  /// json-rpc-gateway.ts). Replayed frames run through the SAME gate and
  /// delivery path as live ones, so de-duplication and ordering are shared.
  Future<void> _fetchReplay() async {
    if (_lastSeenSeq.isEmpty) return;
    // Snapshot: each window updates the watermark it is catching up.
    final entries = List<MapEntry<String, int>>.from(_lastSeenSeq.entries);
    final pending = <Future<void>>[];
    for (final entry in entries) {
      // Exactly one `session.events.since` per session per reconnect: a window
      // already in flight for this session covers it, and a second one would
      // ask for the same gap while more live frames sit parked.
      if (!_replaying.add(entry.key)) continue;
      pending.add(_fetchSessionReplay(entry.key, entry.value));
    }
    if (pending.isEmpty) return;
    // A hung session must not hold another one's replay: ask in parallel.
    await Future.wait(pending);
  }

  Future<void> _fetchSessionReplay(String sessionId, int lastSeen) async {
    // This window belongs to the round (and so to the socket) that started it.
    // [close] and the next [connect] bump the generation: a round whose
    // generation is gone must neither dispatch nor report anything, because the
    // client it would report to has moved on.
    final replayGeneration = _replayGeneration;
    try {
      final response = await send('session.events.since', <String, dynamic>{
        'session_id': sessionId,
        'last_seen': lastSeen,
      }, timeout: _replayRequestTimeout);
      if (replayGeneration != _replayGeneration) return;
      final rawResult = response['result'];
      if (response['error'] != null || rawResult is! Map) return;
      final result = Map<String, dynamic>.from(rawResult);
      final rawEpoch = result['epoch'];
      final epoch = rawEpoch is String ? rawEpoch.trim() : '';
      if (epoch.isNotEmpty) {
        if (_replayEpoch == null) {
          _replayEpoch = epoch;
        } else if (epoch != _replayEpoch) {
          // The gateway restarted while this socket was down: these seqs belong
          // to the new numbering and the watermark we asked with to the old one.
          // Adopt the new epoch, drop every watermark (both numbering spaces —
          // a turn-scoped one describes the same gone process) and paint nothing.
          _replayEpoch = epoch;
          _lastSeenSeq.clear();
          _lastSeenTurnSeq.clear();
          return;
        }
      }
      if (result['truncated'] == true) {
        // The ring evicted part of the gap: the retained tail has a hole
        // (missing message prefix, tool state or terminal frame), so skip the
        // whole window and let the caller re-read history instead.
        _skipTruncatedWindow(sessionId, result);
        return;
      }
      final rawEvents = result['events'];
      if (rawEvents is! List) return;
      for (final rawEvent in rawEvents) {
        // A frame handler can close the client or replace its socket while a
        // window is being applied: the rest of that window died with it.
        if (replayGeneration != _replayGeneration) return;
        if (rawEvent is! Map) continue;
        // Built exactly like a live frame, `isComplete` included, so handlers
        // cannot tell a replayed event from a streamed one.
        final event = parseGatewayEvent(Map<String, dynamic>.from(rawEvent));
        if (event == null) continue;
        if (_passSeqGate(event)) _deliverEvent(event);
      }
    } catch (_) {
      // An older gateway answers -32601, a dropped socket rejects the call, a
      // hung one times out: none of it is worth surfacing, and the next
      // reconnect retries.
    } finally {
      // Frames parked for this session wait for the window above, so they flush
      // only once it has been applied (or abandoned) — never before the gap.
      _replaying.remove(sessionId);
      if (replayGeneration == _replayGeneration) {
        _flushReplayHold(sessionId);
      } else {
        // The socket this window belongs to was torn down or replaced while the
        // answer was in flight: its parked frames died with it, and a newer
        // round owns whatever is left to catch up on.
        _discardReplayHold(sessionId);
      }
    }
  }

  /// Advance the watermark past a truncated replay window without dispatching
  /// any of it, so the holed frames stay gone and only genuinely newer ones
  /// land. Reports the skip so the caller can re-read history.
  void _skipTruncatedWindow(String sessionId, Map<String, dynamic> result) {
    var head = _lastSeenSeq[sessionId] ?? 0;
    final latest = result['latest_seq'];
    if (latest is int && latest > head) head = latest;
    final rawEvents = result['events'];
    if (rawEvents is List) {
      for (final rawEvent in rawEvents) {
        if (rawEvent is! Map) continue;
        final seq = rawEvent['seq'];
        if (seq is int && seq > head) head = seq;
      }
    }
    _lastSeenSeq[sessionId] = head;
    _reportReplayHole(sessionId);
  }

  /// Dispatch a streaming event to a specific request's subscribers.
  void _dispatchStreamEvent(int id, String type, Map<String, dynamic> data) {
    final listeners = _streams.remove(id);
    if (listeners == null) return;
    final event = StreamEvent(
      type: type,
      data: data,
      isComplete: type == 'done' || type == 'error',
    );
    for (final listener in List<StreamCallback>.from(listeners)) {
      try {
        listener(event);
      } catch (_) {
        // Stream observers run only after internal completion and cleanup.
      }
    }
  }

  /// Send a JSON-RPC method call and wait for response.
  Future<Map<String, dynamic>> send(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 30),
    void Function()? onSent,
    bool includeProfile = true,
  }) async {
    if (!_connected || _channel == null) {
      throw Exception('Not connected');
    }

    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    final timer = Timer(timeout, () {
      _pending.remove(id);
      if (!completer.isCompleted) {
        completer.completeError(JsonRpcError(method, 'Timeout'));
      }
    });

    _pending[id] = _Pending(method, completer, timer);
    try {
      _channel!.sink.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': method,
          'params': includeProfile ? withProfile(params, _profile) : params,
          'id': id,
        }),
      );
    } catch (_) {
      timer.cancel();
      _pending.remove(id);
      rethrow;
    }
    try {
      onSent?.call();
    } catch (_) {
      // A local observer must not turn a successfully emitted RPC into an
      // apparent transport failure.
    }
    return completer.future;
  }

  /// Send a JSON-RPC method call and receive streaming events.
  /// Returns the final response when the stream completes.
  Future<Map<String, dynamic>> sendStreaming(
    String method,
    Map<String, dynamic> params, {
    StreamCallback? onEvent,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (!_connected || _channel == null) {
      throw Exception('Not connected');
    }

    final id = _nextId++;
    if (onEvent != null) {
      _streams[id] = [onEvent];
    }
    final completer = Completer<Map<String, dynamic>>();
    final timer = Timer(timeout, () {
      _pending.remove(id);
      _streams.remove(id);
      if (!completer.isCompleted) {
        completer.completeError(JsonRpcError(method, 'Timeout'));
      }
    });

    _pending[id] = _Pending(method, completer, timer);
    _channel!.sink.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': method,
        'params': withProfile(params, _profile),
        'id': id,
      }),
    );
    return completer.future;
  }

  /// Sends `prompt.submit`, then waits for the gateway's terminal turn event.
  /// The RPC acknowledgement only confirms that the turn was accepted; it is
  /// not the end of streamed model output.
  Future<void> submitPrompt(
    String message, {
    required String sessionId,
    required StreamCallback onEvent,
    void Function()? onSent,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final completion = Completer<void>();
    final terminalFuture = completion.future;
    // A close before the RPC acknowledgement rejects both the pending request
    // and this terminal watcher. Observe the secondary future immediately so
    // the request error remains the single surfaced failure.
    terminalFuture.ignore();
    late final StreamCallback listener;
    Timer? timer;
    final closeListenerToken = _addConnectionClosedListener(() {
      if (!completion.isCompleted) {
        completion.completeError(
          JsonRpcError(
            'prompt.submit',
            'Desktop gateway connection closed',
            reason: 'connection_closed',
          ),
        );
      }
    });

    listener = (event) {
      if (event.isComplete && !completion.isCompleted) {
        if (event.type == 'error' || event.type == 'turn.error') {
          completion.completeError(
            JsonRpcError(
              'prompt.submit',
              event.data['message']?.toString() ?? 'Gateway turn failed',
            ),
          );
        } else {
          completion.complete();
        }
      }
      try {
        onEvent(event);
      } catch (_) {
        // Terminal state and other session listeners remain authoritative.
      }
    };

    final listeners = _sessionStreams.putIfAbsent(sessionId, () => []);
    listeners.add(listener);
    timer = Timer(timeout, () {
      if (!completion.isCompleted) {
        completion.completeError(JsonRpcError('prompt.submit', 'Timeout'));
      }
    });

    try {
      final response = await send('prompt.submit', {
        'session_id': sessionId,
        'text': message,
      }, onSent: onSent);
      final error = response['error'];
      if (error != null) {
        throw _gatewayResponseError(
          'prompt.submit',
          error,
          fallbackMessage: 'Unknown error',
        );
      }
      await terminalFuture;
    } finally {
      timer.cancel();
      _removeConnectionClosedListener(closeListenerToken);
      final current = _sessionStreams[sessionId];
      current?.remove(listener);
      if (current != null && current.isEmpty) {
        _sessionStreams.remove(sessionId);
      }
    }
  }

  /// Cooperatively interrupts the active turn for one gateway session.
  Future<void> interruptSession(String sessionId) async {
    final response = await send('session.interrupt', {'session_id': sessionId});
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'session.interrupt',
        error,
        fallbackMessage: 'Gateway interrupt failed',
      );
    }
  }

  /// Resolves the single in-flight Hermes approval for one gateway session.
  Future<void> respondToApproval({
    required String sessionId,
    required String choice,
  }) async {
    const allowedChoices = {'once', 'session', 'always', 'deny'};
    if (!allowedChoices.contains(choice)) {
      throw ArgumentError.value(
        choice,
        'choice',
        'Unsupported approval choice',
      );
    }
    final response = await send('approval.respond', {
      'session_id': sessionId,
      'choice': choice,
    });
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'approval.respond',
        error,
        fallbackMessage: 'Gateway approval failed',
      );
    }
  }

  Future<void> respondToSudo({
    required String requestId,
    required String password,
  }) {
    return _respondToSensitivePrompt(
      method: 'sudo.respond',
      requestId: requestId,
      valueKey: 'password',
      value: password,
    );
  }

  Future<void> respondToSecret({
    required String requestId,
    required String value,
  }) {
    return _respondToSensitivePrompt(
      method: 'secret.respond',
      requestId: requestId,
      valueKey: 'value',
      value: value,
    );
  }

  Future<Map<String, dynamic>> respondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
    bool lockAnswer = false,
  }) async {
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'A Hermes request ID is required',
      );
    }
    final params = <String, dynamic>{'request_id': requestId, 'answer': answer};
    final hasQuestionId = questionId != null && questionId.trim().isNotEmpty;
    if (hasQuestionId) {
      params['question_id'] = questionId;
    }
    if (lockAnswer && !hasQuestionId) {
      throw ArgumentError('questionId is required to lock a clarify answer');
    }
    final method = lockAnswer ? 'clarify.lock' : 'clarify.respond';
    final response = await send(method, params);
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        method,
        error,
        fallbackMessage: 'Gateway clarification failed',
      );
    }
    final rawResult = response['result'];
    return rawResult is Map
        ? Map<String, dynamic>.from(rawResult)
        : const <String, dynamic>{};
  }

  Future<void> _respondToSensitivePrompt({
    required String method,
    required String requestId,
    required String valueKey,
    required String value,
  }) async {
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'A Hermes request ID is required',
      );
    }
    final response = await send(method, {
      'request_id': requestId,
      valueKey: value,
    });
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        method,
        error,
        fallbackMessage: 'Gateway response failed',
      );
    }
  }

  /// Resume an existing session while preserving retained turn state.
  Future<ResumedGatewaySession> resumeSessionDetails(String sessionId) async {
    final result = await send('session.resume', {
      'session_id': sessionId,
      // Session attachment must not carry the rendered transcript. Android
      // hydrates its visible history through bounded REST requests; returning
      // it here duplicates a potentially multi-megabyte transfer and can make
      // the attach RPC itself exceed the request deadline.
      'omit_messages': true,
      'defer_history': true,
      'inline_images': false,
    });
    if (result['error'] != null) {
      throw _gatewayResponseError(
        'session.resume',
        result['error'],
        fallbackMessage: 'Unknown error',
      );
    }
    final rawPayload = result['result'];
    if (rawPayload is! Map) {
      throw StateError('session.resume succeeded without a result payload.');
    }
    final payload = Map<String, dynamic>.from(rawPayload);
    final runtimeSessionId = payload['session_id'] as String?;
    if (runtimeSessionId == null || runtimeSessionId.isEmpty) {
      throw StateError(
        'session.resume succeeded without a session_id — refusing to bind '
        'the caller-supplied id, which may not be the runtime session the '
        'gateway resumed.',
      );
    }
    final rawInflight = payload['inflight'];
    return ResumedGatewaySession(
      runtimeSessionId: runtimeSessionId,
      running: payload['running'] as bool?,
      status: payload['status']?.toString(),
      inflight: rawInflight is Map
          ? Map<String, dynamic>.from(rawInflight)
          : null,
      openRequests: payload['open_requests'] is List
          ? List<dynamic>.from(payload['open_requests'] as List)
          : const [],
    );
  }

  /// Backward-compatible runtime-id-only resume helper.
  Future<String> resumeSession(String sessionId) async {
    return (await resumeSessionDetails(sessionId)).runtimeSessionId;
  }

  Future<void> setSessionTitle(String sessionId, String title) async {
    final response = await send('session.title', {
      'session_id': sessionId,
      'title': title,
    });
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'session.title',
        error,
        fallbackMessage: 'Could not rename session',
      );
    }
  }

  Future<Map<String, dynamic>> branchSession(
    String sessionId, {
    required String name,
  }) async {
    final response = await send('session.branch', {
      'session_id': sessionId,
      'name': name,
    });
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'session.branch',
        error,
        fallbackMessage: 'Could not branch session',
      );
    }
    final result = response['result'];
    if (result is Map<String, dynamic>) return result;
    throw JsonRpcError('session.branch', 'Gateway returned no branch');
  }

  /// Submit a message to the active session with streaming.
  /// Returns the final response and streams events via callback.
  Future<String> sendMessageStreaming(
    String message, {
    required String sessionId,
    StreamCallback? onEvent,
  }) async {
    await submitPrompt(
      message,
      sessionId: sessionId,
      onEvent: onEvent ?? (_) {},
    );
    return sessionId;
  }

  /// Submit a message to the active session (non-streaming, backward-compatible).
  Future<String> sendMessage(String message) async {
    throw UnsupportedError(
      'Use sendMessageStreaming with a gateway session ID instead.',
    );
  }

  /// Uploads one file or image to a remote Desktop gateway and returns the
  /// canonical `@file:` reference that must be included in the following turn.
  ///
  /// The wire params are exactly the stock gateway's `FileAttachParams`
  /// (`extra="forbid"`: session_id/profile/path/data_url/name). An earlier
  /// revision also sent `source_channel`/`source_profile`; those exist only
  /// in the repo's fixture gateway and stock Hermes rejects them with
  /// "invalid params for file.attach: source_channel: Extra inputs are not
  /// permitted", so they must never go on the wire.
  Future<RemoteFileAttachment> attachFile({
    required String sessionId,
    required String name,
    required String dataUrl,
    String path = '',
  }) async {
    final params = <String, dynamic>{
      'session_id': sessionId,
      'name': name,
      'path': path,
      'data_url': dataUrl,
    };
    final response = await send('file.attach', params);
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'file.attach',
        error,
        fallbackMessage: 'Unknown error',
      );
    }
    final result = response['result'];
    if (result is! Map<String, dynamic> || result['attached'] != true) {
      throw JsonRpcError('file.attach', 'Gateway did not attach the file');
    }
    final refText = result['ref_text']?.toString() ?? '';
    if (refText.isEmpty) {
      throw JsonRpcError('file.attach', 'Gateway returned no file reference');
    }
    final atlasIntake = result['atlas_intake'];
    return RemoteFileAttachment(
      name: result['name']?.toString() ?? name,
      path: result['path']?.toString() ?? path,
      refText: refText,
      uploaded: result['uploaded'] == true,
      atlasIntakeAccepted: atlasIntake is Map<String, dynamic>
          ? atlasIntake['accepted'] == true
          : null,
      atlasIntakeStatus: atlasIntake is Map<String, dynamic>
          ? atlasIntake['status']?.toString()
          : null,
      atlasRelativePath: atlasIntake is Map<String, dynamic>
          ? atlasIntake['relative_path']?.toString()
          : null,
    );
  }

  /// Create a new chat session using the stock Hermes `session.create`
  /// contract.
  ///
  /// The gateway owns the new runtime session id. [workingDirectory] is sent
  /// as `cwd` so Hermes can associate the session with the matching Project.
  Future<CreatedGatewaySession> createSession({
    String? model,
    String? workingDirectory,
  }) async {
    final params = <String, dynamic>{};
    if (model != null) params['model'] = model;
    final cwd = workingDirectory?.trim();
    if (cwd != null && cwd.isNotEmpty) params['cwd'] = cwd;
    final result = await send('session.create', params);
    if (result['error'] != null) {
      throw _gatewayResponseError(
        'session.create',
        result['error'],
        fallbackMessage: 'Unknown error',
      );
    }
    final payload = result['result'];
    if (payload is! Map) {
      throw JsonRpcError('session.create', 'Gateway returned no session');
    }
    final runtimeSessionId = payload['session_id']?.toString().trim() ?? '';
    final storedSessionId =
        payload['stored_session_id']?.toString().trim() ?? '';
    if (runtimeSessionId.isEmpty || storedSessionId.isEmpty) {
      throw JsonRpcError(
        'session.create',
        'Gateway returned incomplete session identities',
      );
    }
    return CreatedGatewaySession(
      runtimeSessionId: runtimeSessionId,
      storedSessionId: storedSessionId,
    );
  }

  /// Applies a model only to one live gateway session.  Hermes interprets the
  /// `--session` flag as a persistent per-session override; it must never be
  /// replaced with a profile-wide config write from the mobile client.
  Future<void> setSessionModel({
    required String sessionId,
    required String provider,
    required String model,
  }) async {
    final result = await send('config.set', {
      'session_id': sessionId,
      'key': 'model',
      'value': buildSessionModelValue(provider: provider, model: model),
    });
    if (result['error'] != null) {
      throw _gatewayResponseError(
        'config.set',
        result['error'],
        fallbackMessage: 'Model switch failed',
      );
    }
    final payload = result['result'];
    if (payload is Map && payload['confirm_required'] == true) {
      throw JsonRpcError(
        'config.set',
        payload['confirm_message']?.toString() ??
            'This model needs confirmation before it can be selected.',
      );
    }
  }

  /// Returns the effective reasoning effort for one live gateway session.
  Future<String> getSessionReasoning(String sessionId) async {
    final response = await send('config.get', {
      'session_id': sessionId,
      'key': 'reasoning',
    });
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'config.get',
        error,
        fallbackMessage: 'Could not read reasoning effort',
      );
    }
    final result = response['result'];
    if (result is! Map) {
      throw JsonRpcError('config.get', 'Gateway returned no reasoning effort');
    }
    return normalizeReasoningEffort(result['value']);
  }

  /// Applies reasoning effort only to one live gateway session.
  Future<void> setSessionReasoning({
    required String sessionId,
    required String effort,
  }) async {
    final normalized = effort.trim().toLowerCase();
    if (!validReasoningEfforts.contains(normalized)) {
      throw ArgumentError.value(
        effort,
        'effort',
        'Unsupported reasoning effort',
      );
    }
    final response = await send('config.set', {
      'session_id': sessionId,
      'key': 'reasoning',
      'value': normalized,
    });
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'config.set',
        error,
        fallbackMessage: 'Reasoning effort switch failed',
      );
    }
  }

  static const validReasoningEfforts = <String>{
    'none',
    'minimal',
    'low',
    'medium',
    'high',
    'xhigh',
    'max',
    'ultra',
  };

  static String normalizeReasoningEffort(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return validReasoningEfforts.contains(normalized) ? normalized : 'medium';
  }

  /// Builds the gateway `/model` value used for one live session.
  ///
  /// A bare `custom` provider represents the endpoint already stored in the
  /// profile's `model.base_url`; it is not a resolvable named provider before
  /// the deferred agent build finishes. Omitting the redundant provider flag
  /// lets Hermes resolve that endpoint from the active profile immediately.
  static String buildSessionModelValue({
    required String provider,
    required String model,
  }) {
    final normalizedProvider = provider.trim();
    final modelValue = model.trim();
    if (normalizedProvider.isEmpty || normalizedProvider == 'custom') {
      return '$modelValue --session';
    }
    return '$modelValue --provider $normalizedProvider --session';
  }

  bool get isConnected => _connected;

  /// Close the connection.
  void close() {
    // A deliberate teardown is the one disconnect that means "start over": a
    // dropped or lost socket must keep its watermarks so the next connect can
    // replay the gap (see [_fetchReplay]). Clearing happens before the early
    // return below, so "close always clears" holds even when the socket is
    // already gone — a teardown is a teardown.
    _lastSeenSeq.clear();
    _lastSeenTurnSeq.clear();
    _replayHoldOverflowed.clear();
    _replayHoleReported.clear();
    // Rounds still in flight belong to the socket being torn down: their
    // completion must not flush parked frames into the closed client.
    _replayGeneration++;
    if (!_connected && _channel == null) return;
    final generation = _connectionGeneration;
    final channel = _channel;
    _handleClosedConnection(generation);
    channel?.sink.close();
  }
}

class _Pending {
  final String method;
  final Completer<Map<String, dynamic>> completer;
  final Timer? timer;
  _Pending(this.method, this.completer, this.timer);
}

class _ConnectionClosedListener {
  final int generation;
  final void Function() callback;

  const _ConnectionClosedListener(this.generation, this.callback);
}
