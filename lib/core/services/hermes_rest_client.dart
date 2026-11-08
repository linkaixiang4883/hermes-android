import '../models/session.dart';

/// One page of the session list plus the server's paging signal.
class SessionListPage {
  final List<Session> sessions;
  final bool hasMore;

  const SessionListPage({required this.sessions, required this.hasMore});
}

/// The exact stored session no longer exists on the gateway.
class SessionNotFoundException implements Exception {
  const SessionNotFoundException(this.sessionId);

  final String sessionId;

  @override
  String toString() => 'Session not found: $sessionId';
}

/// The gateway predates server-synced pins and rejects `pinned` in a PATCH.
/// Callers must keep the device-only pin and offer a retry only after an
/// upgrade, never pretend the server accepted it.
class SyncedPinsUnsupportedException implements Exception {
  const SyncedPinsUnsupportedException();

  @override
  String toString() => 'Gateway does not support server-synced chat pins';
}

/// The REST surface a chat screen needs, independent of which Hermes origin
/// serves it.
///
/// Two implementations exist:
/// * [ApiClient] — the legacy API-server transport (Bearer, port 8642), whose
///   endpoints and envelopes are frozen.
/// * [DashboardRestClient] — the dashboard transport (cookie/token, port 9119),
///   which serves the same data with different envelopes.
///
/// Screens must depend on this interface rather than constructing an
/// [ApiClient] from `connection.baseUrl`: a desktop-gateway connection keeps its
/// REST traffic on the dashboard origin and never falls back to the API server.
abstract class HermesRestClient {
  Future<SessionListPage> getSessionsPage({
    int limit = 50,
    int offset = 0,
    String? title,
    String? profile,
  });

  Future<Session?> getSessionById(String sessionId, {String? profile});

  Future<Map<String, dynamic>> getSession(String sessionId, {String? profile});

  /// Resolves a compressed session's visible tip. The legacy transport has no
  /// such endpoint and returns [sessionId] unchanged.
  Future<String?> resolveLatestDescendant(
    String sessionId, {
    String? profile,
  });

  Future<List<Map<String, dynamic>>> getMessages(
    String sessionId, {
    int? limit,
    int offset = 0,
    bool latest = false,
    String? profile,
  });

  Future<void> deleteSession(String sessionId, {String? profile});

  /// Persists the server-owned pin flag shared with Hermes Desktop.
  ///
  /// Implementations must verify both the PATCH response and an exact-id
  /// read-back before returning true. Throws [SyncedPinsUnsupportedException]
  /// when the gateway rejects the `pinned` field.
  Future<bool> setSessionPinned({
    required String sessionId,
    required bool pinned,
    String? profile,
  });

  /// Persists the server-owned archive flag. Archiving with [clearPin] also
  /// unpins, so the chat cannot remain in another client's Pinned section.
  Future<bool> setSessionArchived({
    required String sessionId,
    required bool archived,
    bool clearPin = false,
    String? profile,
  });


  Future<Map<String, dynamic>> getModelInfo();

  Future<Map<String, dynamic>> getModelOptions();

  Future<void> setSessionModel({
    required String sessionId,
    required String provider,
    required String model,
    bool createSessionIfMissing = false,
  });

  Future<bool> healthCheck();

  void close();
}
