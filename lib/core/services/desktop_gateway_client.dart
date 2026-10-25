import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;

import '../models/bot_profile.dart';
import '../models/pending_prompt.dart';

import 'capability_registry.dart';
import 'connection_manager.dart';
import 'gateway_live_turn.dart';
import 'gateway_turn_coordinator.dart';
import 'gateway_turn_journal.dart';
import 'projects_gateway_client.dart';
import 'ws_client.dart';

typedef DesktopAsyncEventCallback =
    void Function(String mobileSessionId, StreamEvent event);
typedef DesktopAsyncEventSessionPredicate = bool Function(String sessionId);
typedef DesktopConnectionCallback =
    void Function(DesktopConnectionState connectionState);

/// A live-turn update for one mobile session, or null when the gateway no
/// longer reports a turn for it (which is what ends a follow).
typedef DesktopLiveTurnCallback =
    void Function(String mobileSessionId, LiveTurnProjection? projection);

/// A replay window the gateway could not deliver hole-free, reported with the
/// mobile session id whose transcript has to be re-read to repair it.
///
/// The transport asks nothing further and delivers nothing else for that gap,
/// so a re-read of history is the only repair there is.
typedef DesktopReplayTruncatedCallback =
    void Function(String mobileSessionId);

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
/// A `slash.exec` refusal or failure, carrying the gateway's own wording.
class SlashExecFailure implements Exception {
  final String message;

  const SlashExecFailure(this.message);

  @override
  String toString() => message;
}

class DesktopGatewayClient {
  static int _nextServerRequestNamespace = 1;

  final int _serverRequestNamespace = _nextServerRequestNamespace++;
  final String _connectionId;
  final String _baseUrl;
  final DashboardClient _dashboard;

  /// Hermes profile the gateway socket should run chats under, or null to
  /// let the server use its own. See [SavedConnection.gatewayProfile].
  final String? _gatewayProfile;
  WsClient? _ws;
  Future<WsClient>? _socketInFlight;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  final Map<String, Future<_DesktopGatewayBinding>> _bindingInFlight = {};
  bool _closed = false;
  final Map<String, String> _gatewaySessionIds = {};
  final Map<String, String> _storedSessionIds = {};
  final Map<String, String> _workingDirectories = {};

  /// Last `info.yolo` each mobile session reported (attach payload). Null until
  /// a resume has answered for that session.
  final Map<String, bool> _sessionYolo = {};

  /// Profile scope per mobile session id (Bot Mode: a bot's chat lives in
  /// another profile). Absent/null = the connection's own default profile.
  ///
  /// Publicly the client stays keyed by [Session.id]; this map only supplies
  /// the `profile` field on resume/create, whose stored ids are per-profile.
  final Map<String, String?> _sessionProfiles = {};
  final Map<String, GatewayServerRequest> _serverRequests = {};

  /// When each prompt was FIRST registered. `_publishPendingPrompts` used to
  /// stamp every row with "now", so a long-pending approval always read "just
  /// now" and the Activity ordering reset on every unrelated prompt change.
  final Map<String, DateTime> _serverRequestRegisteredAt = {};

  /// Every supported blocking prompt this client accepted, in arrival order.
  ///
  /// A prompt is registered here whether or not a ChatScreen is mounted; the
  /// notification layer and the Activity inbox read this, and answering goes
  /// through [respondToPendingPrompt] instead of a screen.
  final ValueNotifier<List<PendingPrompt>> pendingPrompts =
      ValueNotifier<List<PendingPrompt>>(const []);
  final Map<String, WsClient> _serverRequestClients = {};
  final Map<String, String?> _serverRequestMobileSessionIds = {};
  final Map<String, StreamEvent> _serverRequestEvents = {};
  final Map<WsClient, int> _serverRequestClientOrdinals = Map.identity();
  int _nextServerRequestClientOrdinal = 1;
  final Map<String, Set<String>> _serverClarifyRemaining = {};
  final Map<String, String> _serverApprovalByMobileSession = {};
  /// Async-event listeners keyed by their registration token.
  ///
  /// A map, not a slot: the Phase 2B application-wide socket is shared, so a
  /// mounted chat screen, the turn-coordinator dispatcher and the
  /// notification/approval path all observe the same connection at once. The
  /// last registration must never evict an earlier one. Map insertion order is
  /// the delivery order.
  final Map<Object, DesktopAsyncEventCallback> _asyncListeners = {};

  /// Per-token `acceptsSession` predicates, absent for uncapped listeners.
  final Map<Object, DesktopAsyncEventSessionPredicate> _asyncListenerAccepts = {};

  /// Connection-state listeners keyed by their registration token, in delivery
  /// order.
  ///
  /// Multiplexed for the same reason as [_asyncListeners]: with one shared
  /// socket per connection, a screen that is disposed while another consumer
  /// (or a later screen) is attached must detach only its own callback instead
  /// of leaving a stale one behind or evicting a live one.
  final Map<Object, DesktopConnectionCallback> _connectionListeners = {};

  /// The last dispatched connection state, kept even with no listener
  /// attached: a borrowed client may connect before any screen registers.
  DesktopConnectionState _connectionState = DesktopConnectionState.disconnected;

  /// Session-bound listeners keyed by their registration token, in delivery
  /// order. Shared for the same reason as [_asyncListeners].
  final Map<Object, GatewayTurnSessionBoundCallback> _sessionBoundListeners = {};

  /// The latest live-turn projection per mobile session.
  ///
  /// Populated from every `session.resume` answer (see [_rememberBinding]) and
  /// read back when a chat screen mounts onto a connection that was already
  /// attached — the socket, and with it the last snapshot, outlive the page.
  /// A session with no running turn is absent, never present with an empty
  /// projection: absence is the signal that ends a follow.
  final Map<String, LiveTurnProjection> _liveProjections = {};

  /// Live-turn listeners keyed by their registration token, in delivery order.
  ///
  /// Multiplexed for the same reason as [_asyncListeners]: the shared
  /// connection is observed by the mounted chat screen and, later, by whatever
  /// else follows the same session.
  final Map<Object, DesktopLiveTurnCallback> _liveTurnListeners = {};

  /// Per-token `acceptsSession` predicates, absent for uncapped listeners.
  final Map<Object, DesktopAsyncEventSessionPredicate>
  _liveTurnListenerAccepts = {};

  /// Replay-truncation listeners keyed by their registration token, in
  /// delivery order.
  ///
  /// Multiplexed for the same reason as [_liveTurnListeners]: the shared
  /// connection is observed by the mounted chat screen and, later, by whatever
  /// else reads history for the same session.
  final Map<Object, DesktopReplayTruncatedCallback> _replayTruncatedListeners =
      {};

  /// Gateway session ids whose replay window was reported truncated before this
  /// client could name their mobile chat.
  ///
  /// A hole is reported by the socket while its greeting folds in — i.e. during
  /// a reconnect, right after [_openSocket] dropped the runtime bindings — so a
  /// report can arrive for a session this client cannot name yet. Nothing
  /// replays that report, so the gateway id is parked here and delivered the
  /// moment the binding that names it appears (see [_rememberBinding]). Every
  /// reconnect starts a new numbering and drops the parked ids with it, and
  /// [close] clears them.
  final Set<String> _unmappedReplayTruncations = {};
  GatewayTurnCoordinatorRegistry? _turnCoordinatorRegistry;
  ProjectsGatewayClient? _projects;
  final CapabilityRegistry _capabilities = CapabilityRegistry();

  static const _asyncEventTypes = {
    'background.complete',
    'review.summary',
    'notification.show',
    'notification.clear',
    'subagent.spawn_requested',
    'subagent.start',
    'subagent.thinking',
    'subagent.tool',
    'subagent.progress',
    'subagent.complete',
    // A detached legacy turn can settle after its prompt.submit listener was
    // rejected by socket close. Route its terminal frame to ChatScreen's
    // recovery controller; live turns ignore this duplicate async delivery.
    'message.complete',
    'turn.end',
    'turn.error',
    'error',
    'request.cancel',
    // Stream frames of a turn this client did NOT submit. These are the
    // frames a screen following a remote turn renders: without them the
    // rebuilt bubble would freeze at its resume snapshot. Consumers that are
    // not following a live turn drop them, which is the pre-Phase-4 behavior
    // (they used to stop at the socket).
    'message.delta',
    'message.interim',
    'reasoning.delta',
    'thinking.delta',
    'reasoning.available',
  };

  /// Whether a socket event belongs on the async bridge.
  ///
  /// The named set above plus the tool family, matched by prefix: `tool.start`,
  /// `tool.complete` and their siblings are one activity card on screen, so a
  /// name this client has not heard of must still reach it. Everything else is
  /// dropped here, before any listener sees it.
  @visibleForTesting
  static bool shouldBridgeAsyncEvent(String type) =>
      _asyncEventTypes.contains(type) || type.startsWith('tool.');

  DesktopGatewayClient._({
    required this._connectionId,
    required this._baseUrl,
    required this._dashboard,
    this._gatewayProfile,
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
        proxied: connection.dashboardProxied,
        username: connection.dashboardUsername,
        password: connection.dashboardPassword,
      ),
      gatewayProfile: connection.gatewayProfile,
    );
  }

  Future<_DesktopGatewaySession> _connect(
    String mobileSessionId, {
    String? workingDirectory,
    String? profile,
  }) async {
    final requestedWorkingDirectory = workingDirectory?.trim();
    if (requestedWorkingDirectory != null &&
        requestedWorkingDirectory.isNotEmpty) {
      _workingDirectories[mobileSessionId] = requestedWorkingDirectory;
    }
    final effectiveWorkingDirectory = _workingDirectories[mobileSessionId];
    final existing = _ws;
    if (existing != null && existing.isConnected) {
      final mappedSessionId = _gatewaySessionIds[mobileSessionId];
      if (mappedSessionId != null) {
        return _DesktopGatewaySession(existing, mappedSessionId);
      }
      final binding = await _resumeOrCreateSingle(
        existing,
        mobileSessionId,
        workingDirectory: effectiveWorkingDirectory,
        profile: profile,
      );
      _rememberBinding(mobileSessionId, binding);
      return _DesktopGatewaySession(existing, binding.runtimeSessionId);
    }

    final client = await _ensureSocket();
    final binding = await _resumeOrCreateSingle(
      client,
      mobileSessionId,
      workingDirectory: effectiveWorkingDirectory,
      profile: profile,
    );
    _rememberBinding(mobileSessionId, binding);
    return _DesktopGatewaySession(client, binding.runtimeSessionId);
  }

  /// Single-flight wrapper for `_resumeOrCreate`: two concurrent callers for
  /// the same mobile session must not each issue a `session.create` and leave
  /// one gateway session orphaned.
  Future<_DesktopGatewayBinding> _resumeOrCreateSingle(
    WsClient client,
    String mobileSessionId, {
    String? workingDirectory,
    String? profile,
  }) {
    final inFlight = _bindingInFlight[mobileSessionId];
    if (inFlight != null) return inFlight;
    final future = _resumeOrCreate(
      client,
      mobileSessionId,
      workingDirectory: workingDirectory,
      profile: profile,
    );
    _bindingInFlight[mobileSessionId] = future;
    future.whenComplete(() {
      if (identical(_bindingInFlight[mobileSessionId], future)) {
        _bindingInFlight.remove(mobileSessionId);
      }
    }).ignore();
    return future;
  }

  /// Single-flight socket establishment shared by `_connect` and
  /// `_connectControl`. Without this, concurrent callers both pass the
  /// `isConnected` check, both mint tickets, and both build sockets: the
  /// last assignment wins and the loser's socket leaks with the async-event
  /// bridge attached.
  Future<WsClient> _ensureSocket() {
    final existing = _ws;
    if (existing != null && existing.isConnected) {
      return Future.value(existing);
    }
    final inFlight = _socketInFlight;
    if (inFlight != null) return inFlight;
    final future = _openSocket(existing);
    _socketInFlight = future;
    future.whenComplete(() {
      if (identical(_socketInFlight, future)) _socketInFlight = null;
    }).ignore();
    return future;
  }

  Future<WsClient> _openSocket(WsClient? existing) async {
    if (_closed) throw StateError('DesktopGatewayClient is closed.');
    _dispatchConnectionState(
      existing == null
          ? DesktopConnectionState.connecting
          : DesktopConnectionState.reconnecting,
    );
    // Do NOT clear `_gatewaySessionIds` here. A runtime session id outlives
    // the socket (the server keeps the session, and a reconnect resumes the
    // same one). Clearing it made every prompt that arrived after a reconnect
    // unroutable: `_mobileSessionIdFor` got the runtime id, both maps were
    // empty, so the prompt was registered with a null mobile session — visible
    // in notifications/Activity but never dispatched to the open chat.
    // A parked truncation names a numbering of the socket that is being
    // replaced; the new socket reports the holes it finds on its own round.
    _unmappedReplayTruncations.clear();
    _serverRequests.clear();
    _serverRequestRegisteredAt.clear();
    _serverRequestClients.clear();
    _serverRequestMobileSessionIds.clear();
    _serverRequestEvents.clear();
    _serverClarifyRemaining.clear();
    _serverApprovalByMobileSession.clear();
    // The registry is empty now; publish so notifications/Activity drop
    // prompts this socket can no longer answer instead of showing them until
    // the next unrelated registry change.
    _publishPendingPrompts();
    // A fresh socket means a possibly-replaced server: forget old
    // -32601 verdicts so an upgraded gateway's methods are re-discovered
    // instead of staying short-circuited until app restart. gateway.ready
    // on the new socket re-populates protocol/advertisement.
    _capabilities.reset();
    final ticket = await _dashboard.mintWebSocketTicket();
    if (_closed) throw StateError('DesktopGatewayClient is closed.');
    // A reconnect keeps the SAME WsClient and rotates only its ticket.
    //
    // The per-session replay watermarks that `session.events.since` names its
    // gap with live on the instance, so replacing the client on every
    // reconnect (and closing the old one, which clears watermarks by design)
    // makes the replay fetch a silent no-op: the new client has nothing to
    // ask for, and a long turn that streamed while the phone was asleep is
    // never caught up. The ticket is the one thing that cannot be carried
    // over — it is single-use and the previous upgrade consumed it.
    //
    // Re-entering connect() on a dropped client is safe: its close handling
    // cleared _connected and _channel and left the watermarks alone, and the
    // single-flight in _ensureSocket keeps a second connect from starting
    // while one is in flight.
    final client =
        existing ??
        WsClient(_baseUrl, ticket: ticket, profile: _gatewayProfile);
    if (existing == null) {
      // Handlers are instance fields, so both bindings stay valid for every
      // later reconnect on this same client; installing them again would
      // stack duplicate bridges.
      _installAsyncEventBridge(client);
      _bindConnectionListener(client);
    } else {
      client.rotateTicket(ticket);
    }
    try {
      await client.connect();
    } catch (_) {
      // A reconnect attempt that never came up keeps its client: close()
      // clears the replay watermarks and this instance is their only carrier,
      // so the next backoff attempt must retry on it (see _scheduleReconnect).
      // Only a client born in this call is torn down here.
      if (existing == null) {
        client.close();
        if (identical(_ws, client)) _ws = null;
      }
      _dispatchConnectionState(DesktopConnectionState.disconnected);
      rethrow;
    }
    if (_closed) {
      client.close();
      throw StateError('DesktopGatewayClient is closed.');
    }
    _ws = client;
    return client;
  }

  /// Wires the reconnect/rebind reactions onto [client].
  ///
  /// Installed exactly once per client, at first connect: the handlers below
  /// are instance fields of [client], so they keep firing for every later
  /// reconnect on that same instance.
  void _bindConnectionListener(WsClient client) {
    final inheritedConnectionListener = client.onConnectionChanged;
    client.onConnectionChanged = (connected) {
      inheritedConnectionListener?.call(connected);
      if (connected) {
        // Fires inside connect() before _ws is assigned, so no identical()
        // guard is possible here. The single-flight in _ensureSocket keeps
        // loser sockets from being built concurrently.
        _reconnectAttempts = 0;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        // The drop cleared every runtime binding and the server forgot the
        // old socket's sessions. Re-bind each stored session on this
        // fresh socket immediately — a turn that completed detached during
        // the outage must be addressable (and its history refetchable)
        // without waiting for the next user action. Initial connects have
        // no stored ids, so this is a no-op there. Individual resume
        // failures are swallowed: a later explicit call retries the same
        // single-flight path.
        if (!_closed && _storedSessionIds.isNotEmpty) {
          unawaited(_rebindStoredSessions(client));
        }
        _dispatchConnectionState(DesktopConnectionState.connected);
      } else if (identical(_ws, client)) {
        _gatewaySessionIds.clear();
        _dispatchConnectionState(DesktopConnectionState.disconnected);
        // A socket that was once live and then dropped (phone sleep,
        // heartbeat timeout, gateway restart) must come back on its own:
        // the user is often not looking at the chat window when it dies,
        // and every later RPC would otherwise fail until app restart.
        // Stored session ids survive the drop, so the reopened socket
        // re-binds each session via session.resume on next use.
        _scheduleReconnect();
      }
    };
  }

  /// Exponential-backoff reconnect loop, started when a previously-live
  /// socket drops. Runs independently of the UI: the socket is back before
  /// the user opens the chat again. Retries until success or client close;
  /// detached-turn recovery has no safe deadline after which a reply may be
  /// abandoned. The delay remains capped so a long outage does not spin.
  void _scheduleReconnect() {
    if (_closed || _reconnectTimer != null) return;
    _reconnectAttempts++;
    final exponent = _reconnectAttempts.clamp(1, 5);
    final delay = Duration(seconds: (1 << (exponent - 1)).clamp(2, 30));
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (_closed) return;
      _dispatchConnectionState(DesktopConnectionState.reconnecting);
      try {
        await _ensureSocket();
      } catch (_) {
        if (!_closed) _scheduleReconnect();
      }
    });
  }

  /// Re-establish the runtime binding for every stored session on a fresh
  /// socket. Runs fire-and-forget from the connected callback so a reply
  /// that finished server-side during an outage is immediately addressable
  /// on the new socket; the UI's resync (ensureSession + history refetch)
  /// then single-flights with these resumes instead of racing them.
  Future<void> _rebindStoredSessions(WsClient client) async {
    // The connected callback fires inside WsClient.connect() before the
    // await returns; hop off that frame so the socket's message pump is
    // fully live before we issue session.resume over it.
    await Future<void>.delayed(Duration.zero);
    // Snapshot: the map may mutate while resumes are in flight.
    final mobileIds = List<String>.from(_storedSessionIds.keys);
    for (final mobileId in mobileIds) {
      if (_closed || !client.isConnected) return;
      // _ws is null only while this client's own connect() is still
      // returning — that is this socket's own pending assignment, not a
      // replacement. A non-null different client means we were superseded.
      final current = _ws;
      if (current != null && !identical(current, client)) return;
      try {
        final binding = await _resumeOrCreateSingle(
          client,
          mobileId,
          workingDirectory: _workingDirectories[mobileId],
          profile: _sessionProfiles[mobileId],
        );
        final after = _ws;
        if (_closed || (after != null && !identical(after, client))) return;
        _rememberBinding(mobileId, binding);
      } catch (_) {
        // Swallow: a later explicit action retries the same single-flight
        // resume path; a resume error must never escape the socket callback.
      }
    }
  }

  Future<_DesktopGatewayBinding> _resumeOrCreate(
    WsClient client,
    String mobileSessionId, {
    String? workingDirectory,
    String? profile,
  }) async {
    final storedSessionId =
        _storedSessionIds[mobileSessionId] ?? mobileSessionId;
    try {
      final resumed = await client.resumeSessionDetails(
        storedSessionId,
        profile: profile,
      );
      return _DesktopGatewayBinding(
        runtimeSessionId: resumed.runtimeSessionId,
        storedSessionId: storedSessionId,
        resumed: resumed,
      );
    } on JsonRpcError catch (error) {
      if (error.code != 4007 &&
          !error.message.toLowerCase().contains('session not found')) {
        rethrow;
      }
      // New mobile chats do not exist in Hermes yet. Stock Hermes rejects a
      // client-supplied `session_id` on session.create, so retain both gateway-
      // minted identities: runtime for this socket and stored for reconnect.
      final created = await _createSessionWithCwdProvenance(
        client,
        workingDirectory: workingDirectory,
        profile: profile,
      );
      return _DesktopGatewayBinding(
        runtimeSessionId: created.runtimeSessionId,
        storedSessionId: created.storedSessionId,
      );
    }
  }

  /// `session.create` with `cwd_explicit`, dropped once for older gateways.
  ///
  /// Desktop does the same (its DROPPABLE_CREATE_FIELDS): a backend predating
  /// #122899 rejects the whole create at admission, so the field is retried
  /// away instead of losing the chat.
  Future<CreatedGatewaySession> _createSessionWithCwdProvenance(
    WsClient client, {
    required String? workingDirectory,
    required String? profile,
  }) async {
    final hasCwd = workingDirectory?.trim().isNotEmpty == true;
    try {
      return await client.createSession(
        workingDirectory: workingDirectory,
        profile: profile,
        cwdExplicit: hasCwd ? true : null,
      );
    } on JsonRpcError catch (error) {
      if (!hasCwd || !error.message.contains('cwd_explicit')) rethrow;
      return client.createSession(
        workingDirectory: workingDirectory,
        profile: profile,
      );
    }
  }

  Future<bool> setSessionYolo({
    required String sessionId,
    required bool enabled,
  }) async {
    final effective = await _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.setSessionYolo(
        sessionId: gateway.sessionId,
        enabled: enabled,
      ),
    );
    _sessionYolo[sessionId] = effective;
    return effective;
  }

  void _rememberBinding(
    String mobileSessionId,
    _DesktopGatewayBinding binding,
  ) {
    final bindingChanged =
        _gatewaySessionIds[mobileSessionId] != binding.runtimeSessionId ||
        _storedSessionIds[mobileSessionId] != binding.storedSessionId;
    _gatewaySessionIds[mobileSessionId] = binding.runtimeSessionId;
    _storedSessionIds[mobileSessionId] = binding.storedSessionId;
    final resumedYolo = binding.resumed?.info['yolo'];
    if (resumedYolo is bool) {
      _sessionYolo[mobileSessionId] = resumedYolo;
    }
    // A prompt that arrived while this chat had no mapping was registered with
    // a null mobile id. Now that the binding names it, backfill the id so the
    // registry (and the replay below) can route the prompt to this screen.
    var adopted = false;
    for (final entry in _serverRequestMobileSessionIds.entries) {
      if (entry.value != null) continue;
      final request = _serverRequests[entry.key];
      if (request == null) continue;
      final requestSession = request.params['session_id']?.toString();
      if (requestSession == binding.runtimeSessionId ||
          requestSession == binding.storedSessionId) {
        _serverRequestMobileSessionIds[entry.key] = mobileSessionId;
        adopted = true;
      }
    }
    if (adopted) _publishPendingPrompts();
    if (bindingChanged) {
      _dispatchSessionBound(mobileSessionId, binding.storedSessionId);
    }
    // A hole the socket reported while this session was still nameless — the
    // reconnect re-binds after its replay round has already started, and the
    // report names a runtime id nothing maps yet — is delivered here, the
    // moment that report can name the chat whose transcript has to be re-read.
    if (_unmappedReplayTruncations.remove(binding.runtimeSessionId)) {
      _dispatchReplayTruncated(mobileSessionId);
    }
    final resumed = binding.resumed;
    if (resumed != null && resumed.openRequests.isNotEmpty) {
      // The resume payload carries unanswered server→client requests. Deliver
      // only after the runtime sid is mapped back to this mobile chat.
      _ws?.deliverOpenRequests(resumed.openRequests);
    }
    final inflight = resumed?.inflight;
    final error = inflight?['error']?.toString().trim() ?? '';
    final status = (inflight?['status'] ?? resumed?.status)
        ?.toString()
        .trim()
        .toLowerCase();
    const terminalFailures = {
      'error',
      'failed',
      'interrupted',
      'cancelled',
      'canceled',
    };
    if (resumed != null &&
        (error.isNotEmpty || terminalFailures.contains(status))) {
      if (binding.resumeStateDelivered) return;
      binding.resumeStateDelivered = true;
      // Deliver after the binding maps are authoritative. The UI may already
      // have begun a history fetch from the connected callback; its recovery
      // generation makes that fetch harmless once this failure clears it.
      scheduleMicrotask(() {
        _dispatchAsyncEvent(
          mobileSessionId,
          StreamEvent(
            type: 'turn.error',
            data: {
              'session_id': binding.runtimeSessionId,
              'message': error.isNotEmpty ? error : 'Detached turn $status',
              if (status != null && status.isNotEmpty) 'status': status,
            },
            isComplete: true,
            sessionId: binding.runtimeSessionId,
          ),
        );
      });
    }
    // Publish the live-turn projection for whoever follows this session.
    //
    // A resume is the only authority on whether a turn is running, so every
    // binding refreshes the store: a projection left over from an earlier
    // attach would keep a screen "following" a turn that has already settled.
    // A create (no `resumed` payload) is the one answer that proves there is
    // no turn to follow — the gateway held no such session at all.
    final resumedForProjection = binding.resumed;
    _publishLiveTurn(
      mobileSessionId,
      resumedForProjection == null
          ? null
          : LiveTurnProjection.fromResume(_resumePayload(resumedForProjection)),
    );
  }

  /// Re-shapes a typed resume answer back into the wire payload the projection
  /// parses, so the parse rules live in exactly one place
  /// ([LiveTurnProjection.fromResume]).
  static Map<String, dynamic> _resumePayload(ResumedGatewaySession resumed) => {
    if (resumed.running != null) 'running': resumed.running,
    if (resumed.status != null) 'status': resumed.status,
    if (resumed.inflight != null) 'inflight': resumed.inflight,
  };

  /// Stores the latest live-turn projection for [mobileSessionId] and fans it
  /// out to every live-turn listener.
  ///
  /// A null [projection] means the gateway reports no turn for that session:
  /// the stored entry is dropped — so a screen mounting later reads "nothing
  /// live" instead of a settled turn's leftovers — and listeners are told, so
  /// a screen that is following can leave follow mode.
  ///
  /// Registration order is delivery order, and a listener that throws is
  /// swallowed: the same contract as [_dispatchAsyncEvent]. The store is
  /// already authoritative when this runs, so one observer must not strand the
  /// others nor abort the resume that reported the state.
  void _publishLiveTurn(
    String mobileSessionId,
    LiveTurnProjection? projection,
  ) {
    if (projection == null) {
      _liveProjections.remove(mobileSessionId);
    } else {
      _liveProjections[mobileSessionId] = projection;
    }
    if (_liveTurnListeners.isEmpty) return;
    for (final entry in List.of(_liveTurnListeners.entries)) {
      final acceptsSession = _liveTurnListenerAccepts[entry.key];
      if (acceptsSession != null && !acceptsSession(mobileSessionId)) continue;
      try {
        entry.value(mobileSessionId, projection);
      } catch (_) {
        // Swallowed on purpose: see the contract above.
      }
    }
  }

  /// The gateway's stored session key bound to a mobile session id, when a
  /// binding exists. Stored keys address rows in the session DB (move,
  /// resume); mobile ids do not survive into gateway-side lookups.
  String? storedSessionKeyFor(String mobileSessionId) =>
      _storedSessionIds[mobileSessionId];

  /// True when [error] says the runtime session id the gateway was handed no
  /// longer exists — the detached/orphan-reap or eviction signature. The
  /// gateway's own rejection text tells the client to resume the STORED id
  /// (`_sess_nowait`, 4001), so this is a recoverable stale-binding, not a
  /// hard failure.
  static bool _isStaleRuntimeSession(JsonRpcError error) {
    if (error.code == 4001) return true;
    final message = error.message.toLowerCase();
    return message.contains('session not found') ||
        message.contains('not in memory');
  }

  /// Runs a session-scoped gateway call with one automatic recovery from a
  /// stale runtime binding.
  ///
  /// The gateway orphan-reaps detached runtimes and LRU-evicts idle ones, so
  /// a cached runtime sid can name a session the server no longer holds even
  /// while the stored row lives on. Every session-scoped RPC then fails with
  /// 4001 "session not found" and the UI shows a dropped chat. Recovery is
  /// exactly what the gateway's rejection asks for: drop the stale runtime
  /// mapping, `session.resume` the stored key on the live socket, and retry
  /// the call once with the fresh runtime sid. A second stale failure is a
  /// real one (stored row gone too) and propagates.
  Future<T> _callSessionScoped<T>(
    String mobileSessionId,
    Future<T> Function(_DesktopGatewaySession session) call, {
    String? workingDirectory,
  }) async {
    final session = await _connect(
      mobileSessionId,
      workingDirectory: workingDirectory,
    );
    try {
      return await call(session);
    } on JsonRpcError catch (error) {
      if (!_isStaleRuntimeSession(error)) rethrow;
      final client = _ws;
      if (client == null ||
          !client.isConnected ||
          !_rememberedRuntimeIsStale(mobileSessionId, session.sessionId)) {
        rethrow;
      }
      _gatewaySessionIds.remove(mobileSessionId);
      final binding = await _resumeOrCreateSingle(
        client,
        mobileSessionId,
        workingDirectory: _workingDirectories[mobileSessionId],
      );
      _rememberBinding(mobileSessionId, binding);
      return call(_DesktopGatewaySession(client, binding.runtimeSessionId));
    }
  }

  /// Guard against retrying a call whose sid was not the one we cached: if
  /// some other path already re-bound the session while the call was in
  /// flight, the error came from a different generation and a blind retry
  /// could double-execute against the new binding.
  bool _rememberedRuntimeIsStale(
    String mobileSessionId,
    String usedRuntimeId,
  ) => _gatewaySessionIds[mobileSessionId] == usedRuntimeId;

  Future<void> ensureSession(
    String sessionId, {
    String? workingDirectory,
    String? profile,
    bool refresh = false,
  }) async {
    final scopedProfile = profile?.trim();
    if (scopedProfile != null && scopedProfile.isNotEmpty) {
      _sessionProfiles[sessionId] = scopedProfile;
    }
    final effectiveProfile = _sessionProfiles[sessionId];
    if (!refresh) {
      await _connect(
        sessionId,
        workingDirectory: workingDirectory,
        profile: effectiveProfile,
      );
      return;
    }
    await _refreshSession(
      sessionId,
      workingDirectory: workingDirectory,
      profile: effectiveProfile,
    );
  }

  /// Registers a live-turn listener and returns its removal token.
  ///
  /// A live-turn listener is told the projection of a session's running turn
  /// every time a resume reports one — including the resume that re-attaches
  /// an already-mapped session — and is told null when the gateway reports no
  /// turn, which is what ends a follow. Listeners coexist instead of replacing
  /// one another: delivery order is registration order.
  ///
  /// [acceptsSession] caps which mobile session ids this listener receives.
  Object addLiveTurnListener(
    DesktopLiveTurnCallback callback, {
    DesktopAsyncEventSessionPredicate? acceptsSession,
  }) {
    final token = Object();
    _liveTurnListeners[token] = callback;
    if (acceptsSession != null) {
      _liveTurnListenerAccepts[token] = acceptsSession;
    }
    return token;
  }

  /// Detaches exactly the listener [token] was returned for.
  ///
  /// A stale token — one already removed, or belonging to a closed client — is
  /// a no-op, so a teardown path can run twice safely.
  void removeLiveTurnListener(Object token) {
    _liveTurnListeners.remove(token);
    _liveTurnListenerAccepts.remove(token);
  }

  /// How many live-turn listeners are attached.
  ///
  /// Exposed for the same reason as [connectionListenerCount]: "the disposed
  /// screen detached its own listener" has no other observable, because a
  /// callback that fires into a disposed screen returns immediately anyway.
  @visibleForTesting
  int get liveTurnListenerCount => _liveTurnListeners.length;

  /// Registers a replay-truncation listener and returns its removal token.
  ///
  /// The listener is told the mobile session id whose replay window the
  /// gateway's ring evicted: the retained tail has a hole (a missing message
  /// prefix, tool state or terminal frame), so this chat's transcript has to be
  /// re-read — the transport asks nothing further and delivers nothing else for
  /// that gap. Listeners coexist instead of replacing one another, delivery
  /// order is registration order, and each detaches by its own token: the same
  /// contract as [addLiveTurnListener].
  Object addReplayTruncatedListener(DesktopReplayTruncatedCallback callback) {
    final token = Object();
    _replayTruncatedListeners[token] = callback;
    return token;
  }

  /// Detaches exactly the listener [token] was returned for.
  ///
  /// A stale token — one already removed, or belonging to a closed client — is
  /// a no-op, so a teardown path can run twice safely.
  void removeReplayTruncatedListener(Object token) {
    _replayTruncatedListeners.remove(token);
  }

  /// How many replay-truncation listeners are attached.
  ///
  /// Exposed for the same reason as [liveTurnListenerCount].
  @visibleForTesting
  int get replayTruncatedListenerCount => _replayTruncatedListeners.length;

  /// Fans a truncated-replay report out to every listener.
  ///
  /// Registration order is delivery order. The set is snapshotted first, and a
  /// listener that throws is swallowed: the same contract as
  /// [_dispatchAsyncEvent]. Unlike the async bridge there is no
  /// `acceptsSession` predicate — the report names the mobile session, and the
  /// consumer that owns its transcript is the one that can act on it.
  void _dispatchReplayTruncated(String mobileSessionId) {
    if (_replayTruncatedListeners.isEmpty) return;
    for (final listener in List.of(_replayTruncatedListeners.values)) {
      try {
        listener(mobileSessionId);
      } catch (_) {
        // Swallowed on purpose: see the contract above.
      }
    }
  }

  /// Reports a replay hole the socket found on [gatewaySessionId]'s window.
  ///
  /// The socket names the session the way the gateway does (its runtime id);
  /// listeners are told the mobile chat id they know. A session this client
  /// cannot name yet — the reconnect reports the hole before it has re-bound
  /// anything — is parked and delivered by [_rememberBinding].
  void _handleReplayTruncated(String gatewaySessionId) {
    final mobileSessionId = _mobileSessionIdFor(gatewaySessionId);
    if (mobileSessionId == null) {
      _unmappedReplayTruncations.add(gatewaySessionId);
      return;
    }
    _dispatchReplayTruncated(mobileSessionId);
  }

  /// The gateway's latest live-turn projection for [mobileSessionId], or null
  /// when it reports no running turn.
  ///
  /// Read-through companion to [addLiveTurnListener]: a chat screen mounting
  /// onto a connection that is already attached reads the snapshot taken by
  /// the last resume instead of waiting for the next one.
  LiveTurnProjection? liveTurnProjectionFor(String mobileSessionId) =>
      _liveProjections[mobileSessionId];

  /// Re-attaches [mobileSessionId] and re-publishes its live-turn projection.
  ///
  /// A mapped session is not enough for a screen that is opening onto a turn
  /// that may still be running: the binding it holds can predate the turn
  /// entirely, and the snapshot the screen needs is the current one. So this
  /// path always issues `session.resume` — on a live session that is an
  /// idempotent attach (the gateway adds this caller to the session's
  /// fan-out), not a takeover — and then lets [_rememberBinding] publish.
  ///
  /// It deliberately never creates: `session.create` is the NEW-chat
  /// semantics, and answering "session not found" with it would mint a second
  /// session where the user expects the one they came back for. A gone durable
  /// row means there is no live turn, so the projection is cleared and the
  /// caller is left with an unbound-but-usable session; any later real action
  /// re-binds through the normal path, which may create.
  Future<void> _refreshSession(
    String mobileSessionId, {
    String? workingDirectory,
    String? profile,
  }) async {
    final requestedWorkingDirectory = workingDirectory?.trim();
    if (requestedWorkingDirectory != null &&
        requestedWorkingDirectory.isNotEmpty) {
      _workingDirectories[mobileSessionId] = requestedWorkingDirectory;
    }
    final client = await _ensureSocket();
    final storedSessionId =
        _storedSessionIds[mobileSessionId] ?? mobileSessionId;
    try {
      final resumed = await client.resumeSessionDetails(
        storedSessionId,
        profile: profile,
      );
      _rememberBinding(
        mobileSessionId,
        _DesktopGatewayBinding(
          runtimeSessionId: resumed.runtimeSessionId,
          storedSessionId: storedSessionId,
          resumed: resumed,
        ),
      );
    } on JsonRpcError catch (error) {
      if (error.code != 4007 &&
          !error.message.toLowerCase().contains('session not found')) {
        rethrow;
      }
      // The runtime mapping is stale; drop it so the next session-scoped call
      // goes through the normal resume-or-create path.
      _gatewaySessionIds.remove(mobileSessionId);
      _publishLiveTurn(mobileSessionId, null);
    }
  }

  /// The dashboard client backing this gateway's auth/ticket flow.
  ///
  /// Exposed so collaborators (e.g. the Projects folder provisioner) can
  /// reuse this connection's cached auth and single-flight login instead of
  /// standing up a second unauthenticated HTTP client.
  DashboardClient get dashboard => _dashboard;

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

  // ── Bots (Bot Mode's roster over profiles) ───────────────────────────

  static const String botChatTitle = 'Bot Chat';

  /// Lists this machine's Hermes profiles with their canonical chat rows.
  ///
  /// A bot IS a profile; `canonical_session` is resolved server-side on every
  /// listing (the client never carries a session-id pointer).
  Future<List<BotProfile>> listProfiles() async {
    final client = await _connectControl();
    final response = await client.send('profiles.list', const {
      'include_sessions': true,
    });
    final error = response['error'];
    if (error != null) {
      throw StateError(_controlErrorMessage('profiles.list', error));
    }
    final result = response['result'];
    final rows = result is Map ? result['profiles'] : null;
    if (rows is! List) return const [];
    return [
      for (final row in rows.whereType<Map>())
        BotProfile.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  /// Stored sessions matching a title — the canonical-chat registry lookup.
  Future<List<Map<String, dynamic>>> listSessions({
    String? profile,
    String? title,
    bool includeHidden = false,
    int? limit,
  }) async {
    final client = await _connectControl();
    final params = <String, dynamic>{};
    final scopedProfile = profile?.trim();
    if (scopedProfile != null && scopedProfile.isNotEmpty) {
      params['profile'] = scopedProfile;
    }
    if (title != null && title.isNotEmpty) {
      params['title'] = title;
    }
    if (includeHidden) {
      params['include_hidden'] = true;
    }
    if (limit != null) {
      params['limit'] = limit;
    }
    final response = await client.send('session.list', params);
    final error = response['error'];
    if (error != null) {
      throw StateError(_controlErrorMessage('session.list', error));
    }
    final result = response['result'];
    final rows = result is Map ? result['sessions'] : null;
    if (rows is! List) return const [];
    return [
      for (final row in rows.whereType<Map>())
        Map<String, dynamic>.from(row),
    ];
  }

  /// The bot's ONE canonical chat, resolved by title — never by a stored id.
  ///
  /// Resolution order mirrors the desktop plugin: look up the hidden
  /// `Bot Chat` row; create it when absent (hidden, with a stable
  /// idempotency key); then look AGAIN so a concurrent creator wins and both
  /// callers land on the same row instead of forking the relationship.
  Future<Session> resolveBotChat(String profile) async {
    final scope = profile.trim();
    if (scope.isEmpty) throw ArgumentError('profile is required');
    final existing = await _findCanonicalBotChat(scope);
    if (existing != null) return existing;

    final client = await _connectControl();
    final created = await client.send('session.create', {
      'profile': scope,
      'title': botChatTitle,
      'hidden': true,
      'idempotency_key': 'hermes-android-bot-chat-$scope',
    });
    if (created['error'] != null) {
      throw StateError(_controlErrorMessage('session.create', created['error']));
    }
    final adopted = await _findCanonicalBotChat(scope);
    if (adopted != null) return adopted;
    throw StateError(
      'The gateway created no "$botChatTitle" session for $scope',
    );
  }

  Future<Session?> _findCanonicalBotChat(String profile) async {
    final rows = await listSessions(
      profile: profile,
      title: botChatTitle,
      includeHidden: true,
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final id = (row['resolved_id'] ?? row['id'])?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    return Session(
      id: id,
      title: (row['title'] ?? botChatTitle).toString(),
      model: (row['model'] ?? 'Default').toString(),
      source: (row['source'] ?? 'bot').toString(),
      messageCount: (row['message_count'] as num?)?.toInt() ?? 0,
      isActive: row['is_active'] == true,
      preview: (row['preview'] ?? '').toString(),
      startedAt: (row['started_at'] as num?)?.toDouble() ?? 0,
      profile: profile,
    );
  }

  String _controlErrorMessage(String method, Object error) {
    if (error is Map) {
      final message = error['message']?.toString().trim() ?? '';
      if (message.isNotEmpty) return message;
    }
    return '$method failed';
  }

  /// Listeners that see EVERY bridged event, mapped to a local session or not.
  ///
  /// The per-session listeners require a bound mobile id; notifications for a
  /// session the user never opened have only the gateway id, so the central
  /// notifier needs this door. Delivery order is registration order.
  final Map<Object, void Function(StreamEvent event, String? mobileSessionId)>
      _globalEventListeners = {};

  Object addGlobalEventListener(
    void Function(StreamEvent event, String? mobileSessionId) callback,
  ) {
    final token = Object();
    _globalEventListeners[token] = callback;
    return token;
  }

  void removeGlobalEventListener(Object token) {
    _globalEventListeners.remove(token);
  }

  void _dispatchGlobalEvent(StreamEvent event, String? mobileSessionId) {
    if (_globalEventListeners.isEmpty) return;
    for (final listener in List.of(_globalEventListeners.values)) {
      try {
        listener(event, mobileSessionId);
      } catch (_) {
        // One observer must not strand the others.
      }
    }
  }

  /// Live sessions in the gateway process (`session.active_list`).
  Future<List<Map<String, dynamic>>> listActiveSessions() async {
    final client = await _connectControl();
    final response = await client.send('session.active_list', const {});
    final error = response['error'];
    if (error != null) {
      throw StateError(_controlErrorMessage('session.active_list', error));
    }
    final result = response['result'];
    final rows = result is Map ? result['sessions'] : null;
    if (rows is! List) return const [];
    return [
      for (final row in rows.whereType<Map>())
        Map<String, dynamic>.from(row),
    ];
  }

  /// What this gateway advertises or has been proven to support.
  ///
  /// Populated from `gateway.ready` on every connect and refined by the
  /// outcome of real calls, so a feature can degrade politely on an older
  /// gateway instead of failing.
  CapabilityRegistry get capabilities => _capabilities;

  /// Opens (or reuses) the gateway socket without binding it to a session.
  Future<WsClient> _connectControl() => _ensureSocket();

  /// Creates the source-only recovery-v2 registry without changing any legacy
  /// session, submit, interrupt, or event route in this client.
  GatewayTurnCoordinatorRegistry enableTurnRecoveryCoordinator({
    GatewayTurnJournal? journal,
  }) {
    return _turnCoordinatorRegistry ??=
        GatewayTurnCoordinatorRegistry(
            connectionId: _connectionId,
            endpointDigest: _endpointDigest(_baseUrl),
            journal: journal ?? GatewayTurnJournal(),
            freshSocketFactory: () async {
              final ticket = await _dashboard.mintWebSocketTicket();
              final client = WsClient(
                _baseUrl,
                ticket: ticket,
                profile: _gatewayProfile,
              );
              _installAsyncEventBridge(client);
              return client;
            },
          )
          ..onRuntimeBound = (localSessionId, runtimeSessionId) {
            _gatewaySessionIds[localSessionId] = runtimeSessionId;
          };
  }

  /// Registers a connection-state listener and returns its removal token.
  ///
  /// The connection is shared (Phase 2B-ii), so listeners coexist instead of
  /// replacing one another: a mounted chat screen observes its state beside
  /// whoever else holds the same connection. Delivery order is registration
  /// order, and a listener removes only its own registration by token.
  Object addConnectionListener(DesktopConnectionCallback callback) {
    final token = Object();
    _connectionListeners[token] = callback;
    return token;
  }

  /// Detaches exactly the listener [token] was returned for.
  ///
  /// A stale token — already removed, or belonging to a closed client — is a
  /// no-op, so a teardown path can run twice safely.
  void removeConnectionListener(Object token) {
    _connectionListeners.remove(token);
  }

  /// Whether [close] has run.
  ///
  /// A borrowed client stays open after the screen that borrowed it is gone;
  /// ownership is what decides, so tests pin that by observing this flag.
  bool get isClosed => _closed;

  /// The canonical gateway origin this client was built from.
  ///
  /// The registry drops a cached client as soon as its connection's identity
  /// changed; it is this string that makes the dropped client observably
  /// different from its replacement, so an invalidation test can tell a client
  /// built from the current definition from one still bound to the old one.
  @visibleForTesting
  String get gatewayBaseUrl => _baseUrl;

  /// The last connection state this client dispatched.
  ///
  /// Listeners only hear transitions. A screen that borrows an
  /// already-connected client (the registry hands out long-lived instances —
  /// the session list or the draft owner opens the connection first) reads
  /// this once at attach so its first paint does not claim offline.
  DesktopConnectionState get connectionState => _connectionState;

  /// Drives a connection-state transition without a socket.
  ///
  /// The widget test binding carries no real transport, so a test that mounts
  /// a screen against an already-connected borrowed client seeds the state
  /// here. Production paths only dispatch through [_dispatchConnectionState].
  @visibleForTesting
  void debugSetConnectionState(DesktopConnectionState state) =>
      _dispatchConnectionState(state);

  /// How many connection-state listeners are attached.
  ///
  /// Exposed for the ownership tests: "the disposed screen detached its own
  /// listener" has no other observable, because a callback that fires into a
  /// disposed screen returns immediately anyway.
  @visibleForTesting
  int get connectionListenerCount => _connectionListeners.length;

  /// Fans [state] out to every connection-state listener.
  ///
  /// Registration order is delivery order. The set is snapshotted first: a
  /// listener is allowed to register or remove listeners re-entrantly (a
  /// disconnected screen can drop its own registration), and the transition in
  /// flight must still reach the listeners that were attached when it was
  /// observed. A listener that throws must not strand its siblings nor abort
  /// the connect path that reported the state, so its failure is swallowed
  /// here — the same contract as [_dispatchAsyncEvent].
  void _dispatchConnectionState(DesktopConnectionState state) {
    // Keep the state even when nobody is listening: a borrowed client can
    // connect while every screen that will ask about it later is unmounted.
    _connectionState = state;
    if (_connectionListeners.isEmpty) return;
    for (final listener in List.of(_connectionListeners.values)) {
      try {
        listener(state);
      } catch (_) {
        // Swallowed on purpose: see the contract above.
      }
    }
  }

  /// Registers an async-event listener and returns its removal token.
  ///
  /// The connection is shared (Phase 2B), so listeners coexist instead of
  /// replacing one another: the chat screen, the turn-coordinator dispatcher
  /// and the notification path each add their own, and each removes only its
  /// own by the returned token. Delivery order is registration order.
  ///
  /// [acceptsSession] caps which mobile session ids this listener receives.
  ///
  /// Callers that leave a screened session unmounted should unregister, or the
  /// client keeps claiming interactive server requests for that session (see
  /// [_acceptsAnyAsyncEvent]) and routes them to a listener that can no longer
  /// answer.
  Object addAsyncEventListener(
    DesktopAsyncEventCallback callback, {
    DesktopAsyncEventSessionPredicate? acceptsSession,
  }) {
    final token = Object();
    _asyncListeners[token] = callback;
    if (acceptsSession != null) {
      _asyncListenerAccepts[token] = acceptsSession;
    }
    return token;
  }

  /// Detaches exactly the listener [token] was returned for.
  ///
  /// A stale token — one already removed, or belonging to a closed client — is
  /// a no-op, so a teardown path can run twice safely.
  void removeAsyncEventListener(Object token) {
    _asyncListeners.remove(token);
    _asyncListenerAccepts.remove(token);
  }

  /// Registers a durable session-binding observer and returns its token.
  ///
  /// A stock gateway can create the durable session lazily during the first
  /// attachment or prompt call, so consumers must not rely on an eager
  /// [ensureSession] having already exposed the stored identity.
  Object addSessionBoundListener(GatewayTurnSessionBoundCallback callback) {
    final token = Object();
    _sessionBoundListeners[token] = callback;
    return token;
  }

  /// Detaches exactly the binding observer [token] was returned for.
  void removeSessionBoundListener(Object token) {
    _sessionBoundListeners.remove(token);
  }

  /// Fans [event] out to every listener that accepts [mobileSessionId].
  ///
  /// Registration order is delivery order. The set is snapshotted first: a
  /// listener is allowed to register or remove listeners re-entrantly, and the
  /// frame in flight must still reach the listeners that were attached when it
  /// arrived. A listener that throws must not steal the frame from its
  /// siblings nor escape into the socket's message pump, so its failure is
  /// swallowed here.
  void _dispatchAsyncEvent(String mobileSessionId, StreamEvent event) {
    if (_asyncListeners.isEmpty) return;
    for (final entry in List.of(_asyncListeners.entries)) {
      final acceptsSession = _asyncListenerAccepts[entry.key];
      if (acceptsSession != null && !acceptsSession(mobileSessionId)) continue;
      try {
        entry.value(mobileSessionId, event);
      } catch (_) {
        // Swallowed on purpose: see the contract above.
      }
    }
  }

  /// Whether some listener would receive an event for [mobileSessionId].
  ///
  /// Interactive server requests (approval, clarify, sudo, secret) are
  /// answered by whoever observes them, so the client only claims one when at
  /// least one listener is attached and none of its predicates rejects the
  /// session. With a single listener this is exactly the old single-slot
  /// gate: no listener, or a rejecting `acceptsSession`, means "not handled".
  bool _acceptsAnyAsyncEvent(String mobileSessionId) {
    for (final token in _asyncListeners.keys) {
      final acceptsSession = _asyncListenerAccepts[token];
      if (acceptsSession == null || acceptsSession(mobileSessionId)) {
        return true;
      }
    }
    return false;
  }

  /// Fans a binding change out to every session-bound listener.
  ///
  /// Registration order is delivery order, and a failure is swallowed for the
  /// same reason as in [_dispatchAsyncEvent]: the binding maps are already
  /// authoritative when this runs, so one observer must not strand the others
  /// nor abort the caller that established the binding.
  void _dispatchSessionBound(String mobileSessionId, String storedSessionId) {
    if (_sessionBoundListeners.isEmpty) return;
    for (final listener in List.of(_sessionBoundListeners.values)) {
      try {
        listener(mobileSessionId, storedSessionId);
      } catch (_) {
        // Swallowed on purpose: see the contract above.
      }
    }
  }

  Future<RemoteFileAttachment> attachFile({
    required String sessionId,
    required String name,
    required String dataUrl,
    String? workingDirectory,
  }) async {
    return _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.attachFile(
        sessionId: gateway.sessionId,
        name: name,
        dataUrl: dataUrl,
      ),
      workingDirectory: workingDirectory,
    );
  }

  Future<void> submitPrompt({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
    required void Function() onSent,
    String? workingDirectory,
  }) async {
    await _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.submitPrompt(
        text,
        sessionId: gateway.sessionId,
        onEvent: onEvent,
        onSent: onSent,
      ),
      // Creation can happen on the FIRST SEND rather than at screen entry
      // (a draft whose ensure was skipped). Without the cwd here the session
      // is born outside its Project folder and Hermes files it elsewhere.
      workingDirectory: workingDirectory,
    );
  }

  /// Remembers the Project folder a chat belongs to, before any RPC needs it.
  void rememberWorkingDirectory(String sessionId, String workingDirectory) {
    final path = workingDirectory.trim();
    if (path.isEmpty) return;
    _workingDirectories[sessionId] = path;
  }

  /// The gateway's last reported YOLO state for [mobileSessionId], or null
  /// when no attach payload has carried `info.yolo` yet.
  bool? sessionYoloFor(String mobileSessionId) => _sessionYolo[mobileSessionId];

  void _installAsyncEventBridge(WsClient client) {
    // Every socket greets us with gateway.ready; that greeting is where the
    // capability registry learns what this Hermes instance offers.
    _capabilities.bindTo(client);
    _serverRequestClientOrdinals.putIfAbsent(
      client,
      () => _nextServerRequestClientOrdinal++,
    );
    client.onServerRequest = (request) => _handleServerRequest(client, request);
    client.onConnectionClosed = () => _forgetServerRequestsFrom(client);
    client.onStreamEvent = (event) {
      if (!shouldBridgeAsyncEvent(event.type)) return;
      // A settled turn cannot still be waiting on a human. Clearing here (not
      // only in a mounted ChatScreen) is what stops a prompt answered on
      // another surface — which the gateway does not cancel cross-client — from
      // lingering in the notification and Activity forever.
      if (event.type == 'message.complete' ||
          event.type == 'turn.end' ||
          event.type == 'turn.error' ||
          event.type == 'error') {
        final settledMobileId = _mobileSessionIdFor(
          event.data['session_id']?.toString(),
        );
        if (settledMobileId != null) {
          dismissPromptsForSession(settledMobileId);
        }
      }
      var deliveredEvent = event;
      if (event.type == 'request.cancel') {
        final wireRequestId = event.data['id']?.toString() ?? '';
        final requestId = _findServerRequestKey(client, wireRequestId);
        if (requestId != null) {
          _forgetServerRequest(requestId);
          deliveredEvent = StreamEvent(
            type: event.type,
            data: {...event.data, 'id': requestId},
            sessionId: event.sessionId,
          );
        }
      }
      final mobileSessionId = _mobileSessionIdFor(
        event.data['session_id']?.toString(),
      );
      _dispatchGlobalEvent(deliveredEvent, mobileSessionId);
      if (mobileSessionId == null) return;
      // Durable session-scoped events plus terminal turn frames. Terminal
      // frames are also delivered through [submitPrompt] while its listener
      // is attached; the async path is required after socket close, when a
      // detached turn can settle on the resumed session, and ChatScreen
      // ignores the duplicate unless legacy reattach recovery is pending.
      _dispatchAsyncEvent(mobileSessionId, deliveredEvent);
    };
    // A replay window the gateway's ring evicted leaves a hole no frame will
    // repair. The socket says so once per round, on the session whose gap it is
    // — and that report is what makes the owning consumer re-read history. The
    // handler is an instance field of [client], so this assignment is the only
    // registration: a reconnect reuses the same WsClient (see [_openSocket])
    // and a later `_installAsyncEventBridge` call would install it on a
    // different socket, never stack a second one here.
    client.onReplayTruncated = _handleReplayTruncated;
  }

  String _serverRequestKey(WsClient client, String wireRequestId) =>
      '$_serverRequestNamespace.${_serverRequestClientOrdinals[client]}:'
      '$wireRequestId';

  String? _findServerRequestKey(WsClient client, String wireRequestId) {
    for (final entry in _serverRequestClients.entries) {
      if (identical(entry.value, client) &&
          _serverRequests[entry.key]?.id == wireRequestId) {
        return entry.key;
      }
    }
    return null;
  }

  /// Reverse of the runtime binding: gateway session id -> local session id.
  String? mobileSessionIdForGateway(String gatewaySessionId) =>
      _mobileSessionIdFor(gatewaySessionId);

  /// The runtime id this chat is bound to, if it has been resumed.
  String? gatewaySessionIdFor(String mobileSessionId) =>
      _gatewaySessionIds[mobileSessionId];

  /// Re-homes an unresolved prompt onto the chat that is now showing it.
  ///
  /// Used when the prompt was registered before its session had a binding
  /// (a reconnect, or a chat opened after the prompt arrived): answering works
  /// by request id either way, but notifications and Activity need the mobile
  /// id to route a tap back to this chat.
  void adoptServerRequest(String requestId, String mobileSessionId) {
    if (!_serverRequests.containsKey(requestId)) return;
    if (_serverRequestMobileSessionIds[requestId] == mobileSessionId) return;
    _serverRequestMobileSessionIds[requestId] = mobileSessionId;
    _publishPendingPrompts();
  }

  String? _mobileSessionIdFor(String? gatewaySessionId) {
    if (gatewaySessionId != null && gatewaySessionId.isNotEmpty) {
      for (final entry in _gatewaySessionIds.entries) {
        if (entry.value == gatewaySessionId) return entry.key;
      }
    } else if (_gatewaySessionIds.length == 1) {
      return _gatewaySessionIds.keys.single;
    }
    // A session the watcher attached but never opened has no runtime mapping;
    // its stored key is what `session.activate` named, so it can still own a
    // prompt (the notification path must be able to name it).
    if (gatewaySessionId != null && gatewaySessionId.isNotEmpty) {
      for (final entry in _storedSessionIds.entries) {
        if (entry.value == gatewaySessionId) return entry.key;
      }
    }
    return null;
  }

  bool _handleServerRequest(WsClient client, GatewayServerRequest request) {
    const supported = {'clarify', 'approval', 'sudo', 'secret'};
    if (!supported.contains(request.method)) return false;

    final gatewaySessionId = request.params['session_id']?.toString() ?? '';
    final mobileSessionId = _mobileSessionIdFor(gatewaySessionId);

    final requestId = _serverRequestKey(client, request.id);
    _serverRequests[requestId] = request;
    _serverRequestRegisteredAt.putIfAbsent(requestId, DateTime.now);
    _serverRequestClients[requestId] = client;
    _serverRequestMobileSessionIds[requestId] = mobileSessionId;
    final data = Map<String, dynamic>.from(request.params);
    data['server_request_id'] = requestId;

    if (request.method == 'clarify') {
      data['request_id'] = requestId;
      final questions = data['questions'];
      final lockedAnswers = data['answers'];
      final lockedQuestionIds = lockedAnswers is Map
          ? lockedAnswers.keys.map((key) => key.toString()).toSet()
          : const <String>{};
      final qids = <String>{};
      final remainingQuestions = <dynamic>[];
      if (questions is List) {
        for (final raw in questions) {
          if (raw is! Map) continue;
          final qid = raw['qid']?.toString().trim() ?? '';
          if (qid.isEmpty || lockedQuestionIds.contains(qid)) continue;
          qids.add(qid);
          remainingQuestions.add(raw);
        }
      }
      if (qids.isEmpty) {
        // Every question was already locked: this endpoint has nothing left to
        // answer. Decline with NOT_SHOWN — `-32601` would withdraw the whole
        // batch for the desktop too.
        request.fail(4404, 'no questions left to answer');
        return true;
      }
      data['questions'] = remainingQuestions;
      _serverClarifyRemaining[requestId] = qids;
    } else if (request.method == 'approval') {
      final scopedSession = mobileSessionId;
      if (scopedSession == null) {
        // A session this client never bound: register it so a notification can
        // answer by request id; there is no screen to route it to.
        _serverRequestEvents[requestId] = StreamEvent(
          type: '${request.method}.request',
          data: data,
          sessionId: gatewaySessionId,
        );
        _publishPendingPrompts();
        return true;
      }
      final previous = _serverApprovalByMobileSession[scopedSession];
      if (previous != null && previous != requestId) {
        // One approval route per session on screen: QUEUE the second instead
        // of rejecting it (a rejection withdraws it for everyone). The event
        // is stored so the queue can dispatch it when the first resolves.
        _serverRequestEvents[requestId] = StreamEvent(
          type: '${request.method}.request',
          data: data,
          sessionId: gatewaySessionId,
        );
        _publishPendingPrompts();
        return true;
      }
      _serverApprovalByMobileSession[scopedSession] = requestId;
    } else {
      // Legacy event models key sensitive prompts by `request_id`; for the
      // peer-to-peer protocol the JSON-RPC id is the response correlation.
      data['request_id'] = requestId;
    }

    final event = StreamEvent(
      type: '${request.method}.request',
      data: data,
      sessionId: gatewaySessionId,
    );
    _serverRequestEvents[requestId] = event;
    if (mobileSessionId != null) {
      _dispatchAsyncEvent(mobileSessionId, event);
    }
    _publishPendingPrompts();
    return true;
  }

  void _forgetServerRequest(String requestId) {
    final mobileSessionId = _serverRequestMobileSessionIds[requestId];
    _serverRequests.remove(requestId);
    _serverRequestRegisteredAt.remove(requestId);
    _serverRequestClients.remove(requestId);
    _serverRequestMobileSessionIds.remove(requestId);
    _serverRequestEvents.remove(requestId);
    _serverClarifyRemaining.remove(requestId);
    _serverApprovalByMobileSession.removeWhere((_, id) => id == requestId);
    _publishPendingPrompts();
    if (mobileSessionId != null) _dispatchQueuedApproval(mobileSessionId);
  }

  /// Publishes the registry snapshot the notification layer and Activity read.
  void _publishPendingPrompts() {
    final now = DateTime.now();
    final prompts = <PendingPrompt>[];
    for (final entry in _serverRequests.entries) {
      final request = entry.value;
      final params = request.params;
      final summary = switch (request.method) {
        'approval' => (params['command'] ?? params['description'] ?? '')
            .toString()
            .trim(),
        'clarify' => _firstClarifyQuestion(params),
        _ => (params['prompt'] ?? params['description'] ?? request.method)
            .toString()
            .trim(),
      };
      final rawChoices = params['choices'];
      prompts.add(
        PendingPrompt(
          id: entry.key,
          method: request.method,
          mobileSessionId: _serverRequestMobileSessionIds[entry.key],
          gatewaySessionId: params['session_id']?.toString() ?? '',
          summary: summary,
          choices: rawChoices is List
              ? [for (final choice in rawChoices) choice.toString()]
              : const [],
          createdAt: _serverRequestRegisteredAt[entry.key] ?? now,
          wireRequestId: request.id,
        ),
      );
    }
    pendingPrompts.value = List.unmodifiable(prompts);
  }

  static String _firstClarifyQuestion(Map<String, dynamic> params) {
    final questions = params['questions'];
    if (questions is List) {
      for (final raw in questions) {
        if (raw is! Map) continue;
        final text = (raw['question'] ?? raw['prompt'] ?? raw['text'] ?? '')
            .toString()
            .trim();
        if (text.isNotEmpty) return text;
      }
    }
    return '';
  }

  /// Routes the next queued approval for a session to its mounted screen.
  void _dispatchQueuedApproval(String mobileSessionId) {
    if (!_acceptsAnyAsyncEvent(mobileSessionId)) return;
    if (_serverApprovalByMobileSession[mobileSessionId] != null) return;
    for (final entry in _serverRequestMobileSessionIds.entries) {
      if (entry.value != mobileSessionId) continue;
      final request = _serverRequests[entry.key];
      if (request == null || request.method != 'approval') continue;
      _serverApprovalByMobileSession[mobileSessionId] = entry.key;
      final event = _serverRequestEvents[entry.key];
      if (event != null) _dispatchAsyncEvent(mobileSessionId, event);
      return;
    }
  }

  /// Answers any registered prompt by request id — no chat screen required.
  /// Answers a registered prompt. Returns false when the request is gone or
  /// the socket refused the frame — in both cases the entry is KEPT, because
  /// deleting it would tell every surface "answered" while the gateway still
  /// waits (and eventually resolves the default, usually deny).
  bool respondToPendingPrompt(String requestId, Map<String, dynamic> result) {
    final request = _serverRequests[requestId];
    if (request == null) return false;
    if (!request.respond(result)) return false;
    _forgetServerRequest(requestId);
    return true;
  }

  /// Attaches this client to a live session without opening it.
  ///
  /// The gateway routes a session's frames only to that session's transport;
  /// notifications for a never-opened chat therefore need this cheap attach
  /// (`omit_messages` skips the history read).
  Future<void> activateSession(String sessionId, {String? profile}) async {
    final scopedProfile = profile?.trim();
    if (scopedProfile != null && scopedProfile.isNotEmpty) {
      _sessionProfiles[sessionId] = scopedProfile;
    }
    final client = await _connectControl();
    final stored = _storedSessionIds[sessionId] ?? sessionId;
    final params = <String, dynamic>{
      'session_id': stored,
      'omit_messages': true,
    };
    if (scopedProfile != null && scopedProfile.isNotEmpty) {
      params['profile'] = scopedProfile;
    }
    final response = await client.send('session.activate', params);
    if (response['error'] != null) return;
    final payload = response['result'];
    if (payload is! Map) return;
    final runtimeId = payload['session_id']?.toString().trim() ?? '';
    if (runtimeId.isEmpty) return;
    // The watcher attaches sessions the user never opened; remembering the ids
    // here is what lets an approval for that chat find its mobile identity, and
    // `open_requests` is the server's replay of prompts raised while the phone
    // was not attached (a missed approval is otherwise invisible until timeout).
    _gatewaySessionIds[sessionId] = runtimeId;
    _storedSessionIds[sessionId] =
        payload['session_key']?.toString().trim().isNotEmpty == true
        ? payload['session_key'].toString().trim()
        : stored;
    final open = payload['open_requests'];
    if (open is List && open.isNotEmpty) {
      client.deliverOpenRequests(open);
    }
  }

  void _forgetServerRequestsFrom(WsClient client) {
    final requestIds = _serverRequestClients.entries
        .where((entry) => identical(entry.value, client))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final requestId in requestIds) {
      final request = _serverRequests[requestId];
      final mobileSessionId = _serverRequestMobileSessionIds[requestId];
      _forgetServerRequest(requestId);
      if (request != null && mobileSessionId != null) {
        _dispatchAsyncEvent(
          mobileSessionId,
          StreamEvent(
            type: 'request.cancel',
            data: {'id': requestId, 'method': request.method},
          ),
        );
      }
    }
    _serverRequestClientOrdinals.remove(client);
  }

  /// Replays unresolved requests when a replacement route mounts.
  ///
  /// Fan-out goes through the same predicate-aware dispatch as live frames, so
  /// a listener attached for another session never sees them.
  void replayServerRequestsForSession(String mobileSessionId) {
    if (_asyncListeners.isEmpty) return;
    for (final entry in _serverRequestMobileSessionIds.entries.toList()) {
      if (entry.value != mobileSessionId) continue;
      final event = _serverRequestEvents[entry.key];
      if (event != null) _dispatchAsyncEvent(mobileSessionId, event);
    }
  }

  /// Called when a route-local owner detaches.
  ///
  /// Requests stay REGISTERED: the app-level notifier can still show and
  /// answer them, and rejecting here used to withdraw the prompt for every
  /// other client on the session. Declining is only ever an explicit 4404.
  void rejectServerRequestsForSession(String mobileSessionId) {}

  /// Drops every still-registered prompt for [mobileSessionId].
  ///
  /// A turn that ended can no longer consume an answer: the server withdrew the
  /// request (timeout, interrupt, another surface resolved it) or stopped
  /// broadcasting the cancel to this client. Keeping the entry would leave a
  /// notification and an Activity row forever, and replaying it on the next
  /// chat mount would show a dead card that blocks the composer.
  void dismissPromptsForSession(String mobileSessionId) {
    final requestIds = <String>[
      for (final entry in _serverRequestMobileSessionIds.entries)
        if (entry.value == mobileSessionId) entry.key,
    ];
    if (requestIds.isEmpty) return;
    for (final requestId in requestIds) {
      _serverRequests.remove(requestId);
      _serverRequestRegisteredAt.remove(requestId);
      _serverRequestClients.remove(requestId);
      _serverRequestMobileSessionIds.remove(requestId);
      _serverRequestEvents.remove(requestId);
      _serverClarifyRemaining.remove(requestId);
    }
    _serverApprovalByMobileSession.remove(mobileSessionId);
    _publishPendingPrompts();
  }

  /// Answers a prompt by the gateway's own wire id (`srq-…`).
  ///
  /// Notification payloads carry both the registry key and the wire id: after a
  /// reconnect the key can have been re-minted, while the gateway's id is the
  /// identity that survives.
  bool respondToPromptWireId(
    String wireRequestId,
    Map<String, dynamic> result,
  ) {
    if (wireRequestId.trim().isEmpty) return false;
    for (final entry in _serverRequests.entries) {
      if (entry.value.id != wireRequestId) continue;
      if (!entry.value.respond(result)) return false;
      _forgetServerRequest(entry.key);
      return true;
    }
    return false;
  }

  /// The event a registered prompt was delivered with, for a screen that
  /// mounted after the prompt arrived (or that lost the original dispatch).
  StreamEvent? serverRequestEventFor(String requestId) =>
      _serverRequestEvents[requestId];

  /// Whether this client owns an unresolved peer-to-peer request.
  bool ownsServerRequest(String requestId, String method) =>
      _serverRequests[requestId]?.method == method;

  /// Whether this client owns the active approval for [sessionId].
  ///
  /// When [requestId] is supplied, both identities must match. This lets a
  /// queued UI callback prove the request was not answered by another route
  /// before it opens a stale approval dialog.
  bool ownsApprovalRequest(String sessionId, {String? requestId}) {
    final activeRequestId = _serverApprovalByMobileSession[sessionId];
    return activeRequestId != null &&
        (requestId == null || activeRequestId == requestId) &&
        _serverRequests[activeRequestId]?.method == 'approval';
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

  /// Resolves an approval against an exact peer request when available, or
  /// falls back to the legacy session-keyed approval method.
  Future<void> respondToApproval({
    required String sessionId,
    required String choice,
    String? serverRequestId,
  }) async {
    final effectiveRequestId =
        serverRequestId ?? _serverApprovalByMobileSession[sessionId];
    final serverRequest = effectiveRequestId == null
        ? null
        : _serverRequests[effectiveRequestId];
    if (serverRequest != null) {
      if (!serverRequest.respond({'choice': choice})) {
        throw StateError('The server request socket is no longer connected');
      }
      _forgetServerRequest(effectiveRequestId!);
      return;
    }
    if (serverRequestId != null) {
      throw StateError('The approval request is no longer active');
    }
    final gatewaySessionId = _gatewaySessionIds[sessionId];
    final client = _ws;
    if (gatewaySessionId == null || client == null || !client.isConnected) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    await client.respondToApproval(sessionId: gatewaySessionId, choice: choice);
  }

  /// True for a registry key (`"<namespace>.<ordinal>:srq-…"`), which must
  /// never be sent to the gateway as if it were the wire request id.
  bool _isServerRequestKey(String id) {
    final colon = id.indexOf(':');
    if (colon <= 0) return false;
    final parts = id.substring(0, colon).split('.');
    return parts.length == 2 &&
        int.tryParse(parts[0]) != null &&
        int.tryParse(parts[1]) != null;
  }

  Future<void> respondToSudo({
    required String requestId,
    required String password,
  }) async {
    final serverRequest = _serverRequests[requestId];
    if (serverRequest?.method == 'sudo') {
      if (!serverRequest!.respond({'value': password})) {
        throw StateError('The server request socket is no longer connected');
      }
      _forgetServerRequest(requestId);
      return;
    }
    if (_isServerRequestKey(requestId)) {
      throw StateError('The sudo prompt is no longer active');
    }
    final client = _connectedClient();
    await client.respondToSudo(requestId: requestId, password: password);
  }

  Future<void> respondToSecret({
    required String requestId,
    required String value,
  }) async {
    final serverRequest = _serverRequests[requestId];
    if (serverRequest?.method == 'secret') {
      if (!serverRequest!.respond({'value': value})) {
        throw StateError('The server request socket is no longer connected');
      }
      _forgetServerRequest(requestId);
      return;
    }
    if (_isServerRequestKey(requestId)) {
      throw StateError('The secret prompt is no longer active');
    }
    final client = _connectedClient();
    await client.respondToSecret(requestId: requestId, value: value);
  }

  Future<void> respondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
  }) async {
    final serverRequest = _serverRequests[requestId];
    if (serverRequest == null && _isServerRequestKey(requestId)) {
      throw StateError('The clarify prompt is no longer active');
    }
    final client = serverRequest?.method == 'clarify'
        ? _serverRequestClients[requestId]
        : _ws;
    if (client == null || !client.isConnected) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    if (serverRequest?.method == 'clarify') {
      final qid = questionId?.trim() ?? '';
      if (qid.isEmpty) {
        throw ArgumentError('questionId is required for a clarify request');
      }
      // Current Hermes locks each batch answer through clarify.lock; the last
      // lock resolves the original server request on the backend.
      final result = await client.respondToClarify(
        requestId: serverRequest!.id,
        answer: answer,
        questionId: qid,
        lockAnswer: true,
      );
      final status = result['status']?.toString();
      final rawRemaining = result['remaining'];
      final remaining =
          rawRemaining is List
                ? rawRemaining.map((value) => value.toString()).toSet()
                : status == 'expired'
                ? <String>{}
                : (_serverClarifyRemaining[requestId] ?? <String>{})
            ..remove(qid);
      _serverClarifyRemaining[requestId] = remaining;
      if (remaining.isNotEmpty) {
        final replayEvent = _serverRequestEvents[requestId];
        final rawQuestions = replayEvent?.data['questions'];
        if (replayEvent != null && rawQuestions is List) {
          _serverRequestEvents[requestId] = StreamEvent(
            type: replayEvent.type,
            data: {
              ...replayEvent.data,
              'questions': rawQuestions
                  .where(
                    (raw) =>
                        raw is Map &&
                        remaining.contains(raw['qid']?.toString()),
                  )
                  .toList(growable: false),
            },
            sessionId: replayEvent.sessionId,
          );
        }
      }
      final mobileSessionId = _serverRequestMobileSessionIds[requestId];
      if (mobileSessionId != null) {
        _dispatchAsyncEvent(
          mobileSessionId,
          StreamEvent(
            type: 'clarify.remaining',
            data: {'id': requestId, 'remaining': remaining.toList()},
          ),
        );
      }
      if (remaining.isEmpty) {
        _forgetServerRequest(requestId);
      }
      return;
    }
    await client.respondToClarify(
      requestId: requestId,
      answer: answer,
      questionId: questionId,
    );
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

  /// Runs one slash command against the session's slash worker.
  ///
  /// `/compress` is what the chat's one-tap compaction uses: the gateway
  /// routes it to `command.dispatch`, which compacts the live session
  /// synchronously — the reply lands once the stored transcript has been
  /// rewritten. The timeout is long on purpose; a large history can take
  /// minutes. Refusals (a busy session, an older gateway) throw
  /// [SlashExecFailure] with the gateway's own wording so the caller can
  /// surface it instead of a generic failure.
  Future<String> slashExec({
    required String sessionId,
    required String command,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final gatewaySessionId = _gatewaySessionIds[sessionId];
    final client = _ws;
    if (gatewaySessionId == null || client == null || !client.isConnected) {
      throw const SlashExecFailure('Not connected to the Desktop gateway');
    }
    final response = await client.send(
      'slash.exec',
      {'session_id': gatewaySessionId, 'command': command},
      timeout: timeout,
    );
    final error = response['error'];
    if (error != null) {
      final message = error is Map
          ? (error['message']?.toString() ?? 'slash.exec failed')
          : error.toString();
      throw SlashExecFailure(message);
    }
    final result = response['result'];
    if (result is Map) {
      final output = result['output']?.toString().trim() ?? '';
      final warning = result['warning']?.toString().trim() ?? '';
      return output.isNotEmpty ? output : warning;
    }
    throw const SlashExecFailure('The gateway did not answer the command');
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
    await _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.setSessionModel(
        sessionId: gateway.sessionId,
        provider: provider,
        model: model,
      ),
    );
  }

  Future<String> getSessionReasoning(String sessionId) {
    return _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.getSessionReasoning(gateway.sessionId),
    );
  }

  Future<void> setSessionReasoning({
    required String sessionId,
    required String effort,
  }) async {
    await _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.setSessionReasoning(
        sessionId: gateway.sessionId,
        effort: effort,
      ),
    );
  }

  Future<void> renameSession({
    required String sessionId,
    required String title,
  }) async {
    await _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.setSessionTitle(gateway.sessionId, title),
    );
  }

  Future<Map<String, dynamic>> branchSession({
    required String sessionId,
    required String name,
  }) async {
    return _callSessionScoped(
      sessionId,
      (gateway) => gateway.client.branchSession(gateway.sessionId, name: name),
    );
  }

  void close() {
    _closed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _asyncListeners.clear();
    _asyncListenerAccepts.clear();
    _sessionBoundListeners.clear();
    _connectionListeners.clear();
    _liveTurnListeners.clear();
    _liveTurnListenerAccepts.clear();
    _liveProjections.clear();
    _replayTruncatedListeners.clear();
    _unmappedReplayTruncations.clear();
    _projects = null;
    _ws?.close();
    _ws = null;
    _gatewaySessionIds.clear();
    _storedSessionIds.clear();
    _workingDirectories.clear();
    _serverRequests.clear();
    _serverRequestClients.clear();
    _serverRequestMobileSessionIds.clear();
    _serverRequestEvents.clear();
    _serverRequestClientOrdinals.clear();
    _serverClarifyRemaining.clear();
    _serverApprovalByMobileSession.clear();
    final turnCoordinatorRegistry = _turnCoordinatorRegistry;
    _turnCoordinatorRegistry = null;
    if (turnCoordinatorRegistry != null) {
      final closing = turnCoordinatorRegistry.closeAll();
      unawaited(closing.then<void>((_) {}, onError: (_, _) {}));
    }
    _dashboard.close();
  }

  /// Sends one control-plane JSON-RPC call over the shared socket.
  ///
  /// The connection-scoped families (`profiles.*`, `session.list`,
  /// `session.active_list`, `projects.*`) each grew their own typed method
  /// here. Hosted rooms (`groups.*`) live in their own collaborator
  /// ([GroupRoomsClient]), so they need the generic door rather than a dozen
  /// pass-throughs: this opens/reuses the SAME socket the rest of the client
  /// uses (never a second connection), leaving auth and reconnection exactly
  /// where they already are. Params are forwarded untouched — callers that
  /// need a `profile` scope add it themselves.
  Future<Map<String, dynamic>> callControl(
    String method,
    Map<String, dynamic> params,
  ) async {
    final client = await _connectControl();
    return client.send(method, params);
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

  const _DesktopGatewaySession(this.client, this.sessionId);
}

class _DesktopGatewayBinding {
  final String runtimeSessionId;
  final String storedSessionId;
  final ResumedGatewaySession? resumed;
  bool resumeStateDelivered = false;

  _DesktopGatewayBinding({
    required this.runtimeSessionId,
    required this.storedSessionId,
    this.resumed,
  });
}
