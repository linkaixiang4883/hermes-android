import 'dart:convert';
import 'dart:math' as math;

import 'connection_manager.dart';

/// Raised when the dashboard reports that a profile's state.db is unreadable.
///
/// The dashboard distinguishes "an empty page" from "the store is corrupt"
/// with a non-empty `storage` map. Rendering that as an empty session list
/// would silently tell the user their chats are gone; surface it instead.
class DashboardStorageUnavailable implements Exception {
  const DashboardStorageUnavailable(this.profile);

  final String profile;

  @override
  String toString() => 'Dashboard storage unavailable for profile $profile';
}

/// REST adapter for the Hermes dashboard (port 9119).
///
/// The dashboard serves the same data as the legacy API server but with its own
/// envelopes:
/// * `/api/sessions` → `{sessions, total, limit, offset, storage}`
/// * `/api/sessions/{id}` → a bare session object
/// * `/api/sessions/{id}/messages` → `{messages, pagination, ...}`
///
/// It also owns dashboard authentication through [DashboardClient], which
/// handles the password cookie / session token and single-flight 401 retry.
class DashboardRestClient implements HermesRestClient {
  DashboardRestClient(
    this._dashboard, {
    required this.gatewayProfile,
    this.ownsDashboard = false,
  });

  final DashboardClient _dashboard;
  final String? gatewayProfile;
  final bool ownsDashboard;

  String? _profile(String? explicit) {
    final value = (explicit ?? gatewayProfile)?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Map<String, String> _scope(String? profile) => {
    'profile': ?profile,
  };

  @override
  Future<SessionListPage> getSessionsPage({
    int limit = 50,
    int offset = 0,
    String? title,
    String? profile,
  }) async {
    final scopedProfile = _profile(profile);
    final effectiveLimit = math.min(limit, 100);
    final trimmedTitle = title?.trim() ?? '';
    if (trimmedTitle.isNotEmpty) {
      final matches = await _searchByTitle(
        trimmedTitle,
        limit: effectiveLimit,
        profile: scopedProfile,
      );
      return SessionListPage(sessions: matches, hasMore: false);
    }

    final data = await _dashboard.apiGet(
      'sessions',
      queryParameters: {
        'limit': '$effectiveLimit',
        'offset': '$offset',
        'order': 'recent',
        'archived': 'exclude',
        ..._scope(scopedProfile),
      },
    );
    final storage = data['storage'];
    if (storage is Map && storage.isNotEmpty) {
      final key = storage.keys.isEmpty ? scopedProfile ?? 'default' : '${storage.keys.first}';
      throw DashboardStorageUnavailable(key);
    }
    final rows = data['sessions'];
    final sessions = <Session>[
      for (final row in (rows is List ? rows : const <dynamic>[]).whereType<Map>())
        Session.fromJson(Map<String, dynamic>.from(row)),
    ];
    final total = data['total'];
    final hasMore = total is int
        ? offset + effectiveLimit < total
        : sessions.length >= effectiveLimit;
    return SessionListPage(sessions: sessions, hasMore: hasMore);
  }

  Future<List<Session>> _searchByTitle(
    String title, {
    required int limit,
    String? profile,
  }) async {
    final data = await _dashboard.apiGet(
      'sessions/search',
      queryParameters: {
        'q': title,
        'limit': '$limit',
        ..._scope(profile),
      },
    );
    final results = data['results'];
    final wanted = title.trim().toLowerCase();
    final seen = <String>{};
    final sessions = <Session>[];
    for (final raw in (results is List ? results : const <dynamic>[])
        .whereType<Map>()) {
      final row = Map<String, dynamic>.from(raw);
      final rowTitle = row['title']?.toString().trim() ?? '';
      if (rowTitle.toLowerCase() != wanted) continue;
      // Search returns the compression tip in `session_id` and the root in
      // `lineage_root`. Session.fromJson only understands `_lineage_root_id`.
      row.putIfAbsent('id', () => row['session_id']);
      if (row['_lineage_root_id'] == null && row['lineage_root'] is String) {
        row['_lineage_root_id'] = row['lineage_root'];
      }
      final session = Session.fromJson(row);
      if (session.id.isEmpty || !seen.add(session.id)) continue;
      sessions.add(session);
    }
    return sessions;
  }

  Future<Map<String, dynamic>?> _detail(
    String sessionId, {
    String? profile,
  }) async {
    try {
      final data = await _dashboard.apiGet(
        'sessions/${Uri.encodeComponent(sessionId)}',
        queryParameters: _scope(profile),
      );
      final session = data['session'];
      final row = session is Map
          ? Map<String, dynamic>.from(session)
          : Map<String, dynamic>.from(data);
      // The dashboard detail is a raw row: it carries model_config (where the
      // delegate marker lives) but not the API server's derived
      // is_internal_child. The pin resolver filters delegate children, so
      // derive the same bit here instead of letting those rows surface.
      if (row['is_internal_child'] == null) {
        final rawConfig = row['model_config'];
        if (rawConfig is String && rawConfig.trim().isNotEmpty) {
          try {
            final config = jsonDecode(rawConfig);
            if (config is Map) {
              row['is_internal_child'] = config['_delegate_from'] != null;
            }
          } catch (_) {
            // Leave the field absent; a malformed snapshot is not proof of an
            // ordinary row, but it must not fail the whole detail read.
          }
        }
      }
      return row;
    } on DashboardHttpException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<Session?> getSessionById(
    String sessionId, {
    String? profile,
  }) async {
    final row = await _detail(sessionId, profile: _profile(profile));
    return row == null ? null : Session.fromJson(row);
  }

  @override
  Future<Map<String, dynamic>> getSession(
    String sessionId, {
    String? profile,
  }) async {
    final row = await _detail(sessionId, profile: _profile(profile));
    if (row == null) {
      throw const FormatException('Gateway returned no session metadata');
    }
    return row;
  }

  @override
  Future<String?> resolveLatestDescendant(
    String sessionId, {
    String? profile,
  }) async {
    try {
      final data = await _dashboard.apiGet(
        'sessions/${Uri.encodeComponent(sessionId)}/latest-descendant',
        queryParameters: _scope(_profile(profile)),
      );
      final latest = data['session_id']?.toString().trim() ?? '';
      return latest.isEmpty ? null : latest;
    } on DashboardHttpException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getMessages(
    String sessionId, {
    int? limit,
    int offset = 0,
    bool latest = false,
    String? profile,
  }) async {
    final data = await _dashboard.apiGet(
      'sessions/${Uri.encodeComponent(sessionId)}/messages',
      queryParameters: {
        'limit': ?limit?.toString(),
        if (offset != 0) 'offset': '$offset',
        if (latest) 'order': 'latest',
        ..._scope(_profile(profile)),
      },
    );
    final rows = data['messages'];
    return <Map<String, dynamic>>[
      for (final raw in (rows is List ? rows : const <dynamic>[]).whereType<Map>())
        ?_displayMessage(Map<String, dynamic>.from(raw)),
    ];
  }

  /// Normalizes a dashboard transcript row to the shape the chat renderer
  /// expects.
  ///
  /// The dashboard excludes compaction scaffolding via `display_kind=hidden`
  /// and carries a display-only body in `display_content`; the app reads
  /// `content`, so a projection row would otherwise render its raw storage
  /// form (or a hidden scaffold).
  Map<String, dynamic>? _displayMessage(Map<String, dynamic> row) {
    if (row['display_kind'] == 'hidden') return null;
    final display = row['display_content'];
    if (display is String && display.isNotEmpty) {
      row['raw_content'] = row['content'];
      row['content'] = display;
    }
    return row;
  }

  @override
  Future<void> deleteSession(String sessionId, {String? profile}) async {
    try {
      await _dashboard.apiDelete(
        'sessions/${Uri.encodeComponent(sessionId)}',
        queryParameters: _scope(_profile(profile)),
      );
    } on DashboardHttpException catch (error) {
      if (error.statusCode == 404) return;
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> getModelInfo() => _dashboard.getModelInfo();

  @override
  Future<Map<String, dynamic>> getModelOptions() =>
      _dashboard.getModelOptions();

  @override
  Future<void> setSessionModel({
    required String sessionId,
    required String provider,
    required String model,
    bool createSessionIfMissing = false,
  }) {
    throw UnsupportedError(
      'Dashboard sessions switch models through the gateway WebSocket '
      '(config.set key=model), not REST.',
    );
  }

  @override
  Future<bool> healthCheck() async {
    try {
      await _dashboard.apiGet('status');
      await _dashboard.apiGet(
        'sessions',
        queryParameters: {'limit': '1', ..._scope(_profile(null))},
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void close() {
    if (ownsDashboard) _dashboard.close();
  }
}
