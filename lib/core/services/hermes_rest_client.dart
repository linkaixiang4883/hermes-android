import '../models/session.dart';

/// One page of the session list plus the server's paging signal.
class SessionListPage {
  final List<Session> sessions;
  final bool hasMore;

  const SessionListPage({required this.sessions, required this.hasMore});
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
