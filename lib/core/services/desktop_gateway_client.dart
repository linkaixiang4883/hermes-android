import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'capability_registry.dart';
import 'connection_manager.dart';
import 'gateway_turn_coordinator.dart';
import 'gateway_turn_journal.dart';
import 'projects_gateway_client.dart';
import 'ws_client.dart';

typedef DesktopAsyncEventCallback =
    void Function(String mobileSessionId, StreamEvent event);
typedef DesktopServerRequestCallback =
    void Function(String mobileSessionId, GatewayServerRequest request);
typedef DesktopConnectionCallback =
    void Function(DesktopConnectionState connectionState);

enum DesktopConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Authenticated JSON-RPC transport for a Hermes Desktop remote gateway.
///
/// The mobile OpenAI-compatible endpoint remains available for legacy
/// profiles. When a connection supplies [SavedConnection.desktopGatewayUrl],
/// chat writes and interactive events use this one Desktop session transport.
class DesktopGatewayClient {
  final String _connectionId;
  final String _baseUrl;
  final DashboardClient _dashboard;
  final String _documentProfile;
  WsClient? _ws;
  final Map<String, String> _gatewaySessionIds = {};
  DesktopAsyncEventCallback? _asyncEventListener;
  DesktopServerRequestCallback? _serverRequestListener;
  DesktopConnectionCallback? _connectionListener;
  GatewayTurnCoordinatorRegistry? _turnCoordinatorRegistry;
  ProjectsGatewayClient? _projects;
  final CapabilityRegistry _capabilities = CapabilityRegistry();

  static const _asyncEventTypes = {
    'background.complete',
    'review.summary',
    'notification.show',
    'notification.clear',
    'request.cancel',
    'subagent.spawn_requested',
    'subagent.start',
    'subagent.thinking',
    'subagent.tool',
    'subagent.progress',
    'subagent.complete',
  };

  DesktopGatewayClient._({
    required this._connectionId,
    required this._baseUrl,
    required this._dashboard,
    required this._documentProfile,
  });

  /// The canonical gateway origin for [connection].
  ///
  /// Extracted so the recovery-journal scope can be derived without opening a
  /// transport: an omitted default port and an explicit one must resolve to
  /// the same string, or the same gateway would be recorded under two scopes.
  static String normalizedGatewayBaseUrl(SavedConnection connection) {
    final override = connection.desktopGatewayUrl?.trim() ?? '';
    final overrideUri = override.isEmpty
        ? null
        : Uri.tryParse(
            override.contains('://') ? override : 'https://$override',
          );
    final isDistinctOverride =
        overrideUri != null &&
        overrideUri.host.isNotEmpty &&
        overrideUri.host.toLowerCase() != connection.host.toLowerCase();
    final raw = isDistinctOverride
        ? override
        : SavedConnection.joinBaseUrl(
            '${connection.useHttps ? 'https' : 'http'}://'
            '${connection.host}:${connection.dashboardPort}',
            connection.dashboardPrefix ?? '',
          );
    final normalized = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError('Desktop Gateway URL must be an http(s) URL');
    }
    final baseUri = uri.replace(query: '', fragment: '');
    final pathPrefix = baseUri.path == '/' ? '' : baseUri.path;
    final port = baseUri.hasPort
        ? baseUri.port
        : baseUri.scheme == 'https'
        ? 443
        : 80;
    return SavedConnection.joinBaseUrl(
      '${baseUri.scheme}://${baseUri.host}:$port',
      pathPrefix,
    );
  }

  static String _endpointDigest(String baseUrl) =>
      sha256.convert(utf8.encode(baseUrl)).toString();

  /// The recovery-journal endpoint scope for [connection], or `null` when the
  /// connection names no usable Desktop Gateway.
  ///
  /// Returning `null` rather than throwing keeps callers that only want to
  /// *read* journal state — such as the Home digest — free of try/catch around
  /// a plain configuration fact.
  static String? endpointDigestFor(SavedConnection connection) {
    final hasExplicitOverride =
        connection.desktopGatewayUrl?.trim().isNotEmpty == true;
    final hasDashboardAuth =
        connection.dashboardProxied ||
        (connection.dashboardUsername?.trim().isNotEmpty == true &&
            connection.dashboardPassword?.trim().isNotEmpty == true);
    if (!hasExplicitOverride && !hasDashboardAuth) return null;
    try {
      return _endpointDigest(normalizedGatewayBaseUrl(connection));
    } on ArgumentError {
      return null;
    }
  }

  factory DesktopGatewayClient.fromConnection(SavedConnection connection) {
    final baseUrl = normalizedGatewayBaseUrl(connection);
    final baseUri = Uri.parse(baseUrl);
    final pathPrefix = baseUri.path == '/' ? '' : baseUri.path;
    return DesktopGatewayClient._(
      connectionId: connection.id,
      baseUrl: baseUrl,
      dashboard: DashboardClient(
        host: baseUri.host,
        // The normalized base URL always carries an explicit port, so this
        // never falls back to a scheme default.
        port: baseUri.port,
        useHttps: baseUri.scheme == 'https',
        pathPrefix: pathPrefix,
        username: connection.dashboardUsername,
        password: connection.dashboardPassword,
      ),
      documentProfile: documentIntakeProfileForConnection(connection),
    );
  }

  Future<_DesktopGatewaySession> _connect(
    String mobileSessionId, {
    String? cwd,
  }) async {
    final existing = _ws;
    if (existing != null && existing.isConnected) {
      final mappedSessionId = _gatewaySessionIds[mobileSessionId];
      if (mappedSessionId != null) {
        return _DesktopGatewaySession(existing, mappedSessionId);
      }
      final gatewaySession = await _resumeOrCreate(
        existing,
        mobileSessionId,
        cwd: cwd,
      );
      _gatewaySessionIds[mobileSessionId] = gatewaySession.sessionId;
      return gatewaySession;
    }

    _connectionListener?.call(
      existing == null
          ? DesktopConnectionState.connecting
          : DesktopConnectionState.reconnecting,
    );
    existing?.close();
    _gatewaySessionIds.clear();
    final ticket = await _dashboard.mintWebSocketTicket();
    final client = WsClient(_baseUrl, ticket: ticket);
    _installAsyncEventBridge(client);
    client.onConnectionChanged = (connected) {
      if (connected) {
        _connectionListener?.call(DesktopConnectionState.connected);
      } else if (identical(_ws, client)) {
        _gatewaySessionIds.clear();
        _connectionListener?.call(DesktopConnectionState.disconnected);
      }
    };
    try {
      await client.connect();
      _ws = client;
      final gatewaySession = await _resumeOrCreate(
        client,
        mobileSessionId,
        cwd: cwd,
      );
      _gatewaySessionIds[mobileSessionId] = gatewaySession.sessionId;
      return gatewaySession;
    } catch (_) {
      client.close();
      if (identical(_ws, client)) _ws = null;
      _connectionListener?.call(DesktopConnectionState.disconnected);
      rethrow;
    }
  }

  /// Opens the gateway runtime for one mobile chat.
  ///
  /// [cwd] is applied only when this call CREATES the session: an existing chat
  /// keeps the workspace it already has, so merely opening a chat can never
  /// re-home it. A created session is born anchored to [cwd] — that is what
  /// gives a project chat its project, and its project context files.
  Future<_DesktopGatewaySession> _resumeOrCreate(
    WsClient client,
    String mobileSessionId, {
    String? cwd,
  }) async {
    try {
      final resumed = await client.resumeSession(mobileSessionId);
      return _DesktopGatewaySession(client, resumed.sessionId);
    } on JsonRpcError catch (error) {
      if (error.code != 4007 &&
          !error.message.toLowerCase().contains('session not found')) {
        rethrow;
      }
      // New mobile chats do not exist in Hermes yet. Create them with the
      // mobile-generated ID so REST history and the Desktop runtime share one
      // stable identity. Existing sessions always take the resume path.
      final created = await client.createOrResumeSession(
        mobileSessionId,
        cwd: cwd,
      );
      return _DesktopGatewaySession(
        client,
        created.sessionId,
        storedSessionId: created.storedSessionId,
      );
    }
  }

  /// Opens (or reuses) this chat's gateway runtime.
  ///
  /// [cwd] anchors a newly created session to a workspace folder: the project
  /// chat path hands over the project's directory so the session is born inside
  /// the project. An already-existing chat is left exactly as it is.
  Future<GatewaySessionHandle?> ensureSession(
    String sessionId, {
    String? cwd,
  }) async {
    final session = await _connect(sessionId, cwd: cwd);
    return session.handle;
  }

  /// Re-files one stored chat into a project's folder
  /// (`session.workspace.move`).
  ///
  /// A chat belongs to the project whose folders cover its working directory,
  /// so moving the directory is the write that moves the chat: the gateway
  /// re-anchors a live agent's terminal, the database row and the project tree.
  /// The new project's context files load at the next compression or rebuilt
  /// runtime — a live agent's system prompt is already built.
  Future<String> moveSessionToProject({
    required String sessionKey,
    required String cwd,
  }) async {
    final client = await _connectControl();
    return client.moveSessionWorkspace(sessionKey: sessionKey, cwd: cwd);
  }

  /// The gateway's default (no-project) workspace folder, or `null` when this
  /// gateway cannot name one.
  Future<String?> defaultWorkspaceCwd() async {
    try {
      final client = await _connectControl();
      return await client.defaultWorkspaceCwd();
    } catch (_) {
      return null;
    }
  }

  /// Server-owned Hermes Projects for this gateway.
  ///
  /// Projects are connection-scoped, not session-scoped, so this opens the
  /// shared socket without resuming or creating any chat session. An older
  /// gateway without `projects.*` surfaces a [ProjectsUnsupportedException]
  /// instead of an error state, so callers can fall back to local grouping.
  ProjectsGatewayClient get projects {
    return _projects ??= ProjectsGatewayClient((method, params) async {
      final client = await _connectControl();
      return client.send(method, params);
    }, capabilities: _capabilities);
  }

  /// What this gateway advertises or has been proven to support.
  ///
  /// Populated from `gateway.ready` on every connect and refined by the
  /// outcome of real calls, so a feature can degrade politely on an older
  /// gateway instead of failing.
  CapabilityRegistry get capabilities => _capabilities;

  /// Opens (or reuses) the gateway socket without binding it to a session.
  Future<WsClient> _connectControl() async {
    final existing = _ws;
    if (existing != null && existing.isConnected) return existing;

    _connectionListener?.call(
      existing == null
          ? DesktopConnectionState.connecting
          : DesktopConnectionState.reconnecting,
    );
    existing?.close();
    _gatewaySessionIds.clear();
    final ticket = await _dashboard.mintWebSocketTicket();
    final client = WsClient(_baseUrl, ticket: ticket);
    _installAsyncEventBridge(client);
    client.onConnectionChanged = (connected) {
      if (connected) {
        _connectionListener?.call(DesktopConnectionState.connected);
      } else if (identical(_ws, client)) {
        _gatewaySessionIds.clear();
        _connectionListener?.call(DesktopConnectionState.disconnected);
      }
    };
    try {
      await client.connect();
      _ws = client;
      return client;
    } catch (_) {
      client.close();
      if (identical(_ws, client)) _ws = null;
      _connectionListener?.call(DesktopConnectionState.disconnected);
      rethrow;
    }
  }

  /// Creates the source-only recovery-v2 registry without changing any legacy
  /// session, submit, interrupt, or event route in this client.
  GatewayTurnCoordinatorRegistry enableTurnRecoveryCoordinator({
    GatewayTurnJournal? journal,
  }) {
    return _turnCoordinatorRegistry ??= GatewayTurnCoordinatorRegistry(
      connectionId: _connectionId,
      endpointDigest: _endpointDigest(_baseUrl),
      journal: journal ?? GatewayTurnJournal(),
      freshSocketFactory: () async {
        final ticket = await _dashboard.mintWebSocketTicket();
        return WsClient(_baseUrl, ticket: ticket);
      },
    );
  }

  void setConnectionListener(DesktopConnectionCallback? listener) {
    _connectionListener = listener;
  }

  Future<RemoteFileAttachment> attachFile({
    required String sessionId,
    required String name,
    required String dataUrl,
  }) async {
    final gateway = await _connect(sessionId);
    return gateway.client.attachFile(
      sessionId: gateway.sessionId,
      name: name,
      dataUrl: dataUrl,
      sourceChannel: 'hermes_mobile',
      sourceProfile: _documentProfile,
    );
  }

  Future<void> submitPrompt({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
  }) async {
    final gateway = await _connect(sessionId);
    await gateway.client.submitPrompt(
      text,
      sessionId: gateway.sessionId,
      onEvent: onEvent,
    );
  }

  /// Receives only durable, session-scoped events that may arrive after a
  /// prompt's terminal event. Active-turn events continue through [submitPrompt]
  /// so they are never delivered twice.
  void setAsyncEventListener(DesktopAsyncEventCallback? listener) {
    _asyncEventListener = listener;
  }

  /// Receives backend-initiated requests (approval / clarify / sudo / secret /
  /// vault) for the chat that owns the request's gateway session.
  void setServerRequestListener(DesktopServerRequestCallback? listener) {
    _serverRequestListener = listener;
  }

  void _installAsyncEventBridge(WsClient client) {
    // Every socket greets us with gateway.ready; that greeting is where the
    // capability registry learns what this Hermes instance offers.
    _capabilities.bindTo(client);
    client.onStreamEvent = (event) {
      if (!_asyncEventTypes.contains(event.type)) return;
      final mobileSessionId = _mobileSessionFor(
        event.data['session_id']?.toString(),
      );
      if (mobileSessionId == null) return;
      _asyncEventListener?.call(mobileSessionId, event);
    };
    // Hermes 0.21.3+ asks interactive questions (approval / clarify / sudo /
    // secret / vault) as server→client requests instead of `*.request`
    // events. Route each one to the chat that owns the gateway session so it
    // can show its card and answer with a response frame.
    client.onServerRequest = (request) {
      final mobileSessionId = _mobileSessionFor(
        request.params['session_id']?.toString(),
      );
      if (mobileSessionId == null) return;
      _serverRequestListener?.call(mobileSessionId, request);
    };
  }

  /// The mobile chat a gateway session id belongs to, or `null` when this
  /// connection has not mapped it — a request for an unknown session has no
  /// card to show.
  String? _mobileSessionFor(String? gatewaySessionId) {
    if (gatewaySessionId != null && gatewaySessionId.isNotEmpty) {
      for (final entry in _gatewaySessionIds.entries) {
        if (entry.value == gatewaySessionId) return entry.key;
      }
      return null;
    }
    if (_gatewaySessionIds.length == 1) {
      return _gatewaySessionIds.keys.single;
    }
    return null;
  }

  /// Interrupts the active turn in the Desktop gateway runtime.
  Future<bool> interruptPrompt({required String sessionId}) async {
    final gatewaySessionId = _gatewaySessionIds[sessionId];
    final client = _ws;
    if (gatewaySessionId == null || client == null || !client.isConnected) {
      return false;
    }
    await client.interruptSession(gatewaySessionId);
    return true;
  }

  /// Fetches the live context-window breakdown for usage display.
  ///
  /// Returns `null` when there is no mapped/connected gateway session or
  /// the RPC fails, so callers can fall back to the REST stream triple.
  /// Never throws.
  Future<Map<String, dynamic>?> getContextUsage({
    required String sessionId,
  }) async {
    final gatewaySessionId = _gatewaySessionIds[sessionId];
    final client = _ws;
    if (gatewaySessionId == null || client == null || !client.isConnected) {
      return null;
    }
    try {
      final response = await client.send('session.context_breakdown', {
        'session_id': gatewaySessionId,
      });
      final result = response['result'];
      if (result is Map<String, dynamic>) return result;
      if (result is Map) return Map<String, dynamic>.from(result);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Resolves an approval against the gateway session mapped to this mobile
  /// chat. Approval requests are session-keyed and do not carry a request ID.
  Future<void> respondToApproval({
    required String sessionId,
    required String choice,
  }) async {
    final gatewaySessionId = _gatewaySessionIds[sessionId];
    final client = _ws;
    if (gatewaySessionId == null || client == null || !client.isConnected) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    await client.respondToApproval(sessionId: gatewaySessionId, choice: choice);
  }

  Future<void> respondToSudo({
    required String requestId,
    required String password,
  }) async {
    final client = _connectedClient();
    await client.respondToSudo(requestId: requestId, password: password);
  }

  Future<void> respondToSecret({
    required String requestId,
    required String value,
  }) async {
    final client = _connectedClient();
    await client.respondToSecret(requestId: requestId, value: value);
  }

  Future<void> respondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
  }) async {
    final client = _connectedClient();
    await client.respondToClarify(
      requestId: requestId,
      answer: answer,
      questionId: questionId,
    );
  }

  /// Answers one backend-initiated request by its `srq-…` id (Hermes 0.21.3+).
  Future<void> respondToServerRequest(
    String requestId, {
    Map<String, dynamic>? result,
    String? errorMessage,
  }) async {
    final client = _connectedClient();
    await client.respondToServerRequest(
      requestId,
      result: result,
      errorMessage: errorMessage,
    );
  }

  /// Locks one answer of a batch clarify request (`clarify.lock`).
  Future<void> lockClarifyAnswer({
    required String requestId,
    required String questionId,
    required String answer,
  }) async {
    final client = _connectedClient();
    await client.lockClarifyAnswer(
      requestId: requestId,
      questionId: questionId,
      answer: answer,
    );
  }

  WsClient _connectedClient() {
    final client = _ws;
    if (client == null || !client.isConnected) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    return client;
  }

  /// The profile-scoped catalog and default shown by Hermes Desktop.  Keeping
  /// these reads on the Dashboard endpoint means Android never guesses model
  /// names or providers from the OpenAI-compatible API.
  Future<Map<String, dynamic>> getModelInfo() => _dashboard.getModelInfo();

  Future<Map<String, dynamic>> getModelOptions() =>
      _dashboard.getModelOptions();

  Future<void> setSessionModel({
    required String sessionId,
    required String provider,
    required String model,
  }) async {
    final gateway = await _connect(sessionId);
    await gateway.client.setSessionModel(
      sessionId: gateway.sessionId,
      provider: provider,
      model: model,
    );
  }

  Future<String> getSessionReasoning(String sessionId) async {
    final gateway = await _connect(sessionId);
    return gateway.client.getSessionReasoning(gateway.sessionId);
  }

  Future<void> setSessionReasoning({
    required String sessionId,
    required String effort,
  }) async {
    final gateway = await _connect(sessionId);
    await gateway.client.setSessionReasoning(
      sessionId: gateway.sessionId,
      effort: effort,
    );
  }

  Future<void> renameSession({
    required String sessionId,
    required String title,
  }) async {
    final gateway = await _connect(sessionId);
    await gateway.client.setSessionTitle(gateway.sessionId, title);
  }

  Future<Map<String, dynamic>> branchSession({
    required String sessionId,
    required String name,
  }) async {
    final gateway = await _connect(sessionId);
    return gateway.client.branchSession(gateway.sessionId, name: name);
  }

  void close() {
    _asyncEventListener = null;
    _connectionListener = null;
    _projects = null;
    _ws?.close();
    _ws = null;
    _gatewaySessionIds.clear();
    final turnCoordinatorRegistry = _turnCoordinatorRegistry;
    _turnCoordinatorRegistry = null;
    if (turnCoordinatorRegistry != null) {
      final closing = turnCoordinatorRegistry.closeAll();
      unawaited(closing.then<void>((_) {}, onError: (_, _) {}));
    }
    _dashboard.close();
  }
}

String documentIntakeProfileForConnection(SavedConnection connection) {
  final candidates = <String>[
    connection.gatewayPrefix ?? '',
    Uri.tryParse(connection.desktopGatewayUrl ?? '')?.path ?? '',
  ];
  final segments = candidates
      .expand((value) => value.toLowerCase().split('/'))
      .where((value) => value.isNotEmpty)
      .toSet();
  if (segments.contains('personal')) return 'personal';
  if (segments.contains('pro') || segments.contains('professional')) {
    return 'pro';
  }
  return 'organizator';
}

class _DesktopGatewaySession {
  final WsClient client;
  final String sessionId;

  /// The durable row id when this open created the session; `null` for a
  /// reattached session whose row is already keyed by [sessionId].
  final String? storedSessionId;

  const _DesktopGatewaySession(
    this.client,
    this.sessionId, {
    this.storedSessionId,
  });

  GatewaySessionHandle get handle =>
      GatewaySessionHandle(sessionId, storedSessionId);
}
