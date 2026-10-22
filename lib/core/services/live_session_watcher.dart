import 'dart:async';

import 'package:flutter/foundation.dart';

import 'desktop_gateway_client.dart';

/// Keeps this client attached to the sessions that are RUNNING.
///
/// The gateway routes a session's events only to that session's transport, so
/// "notifications for any session" is not free: it requires an attachment.
/// The desktop gets it by opening chats; this watcher gets it without a UI by
/// polling `session.active_list` and calling
/// `session.activate {omit_messages: true}` for every non-idle session.
///
/// Idle sessions are skipped (nothing streams, so there is nothing to hear),
/// and the attached set is dropped on reconnect because a new socket starts
/// with no attachments.
class LiveSessionWatcher {
  LiveSessionWatcher({
    this.client,
    this.interval = const Duration(seconds: 5),
    this.onTitlesChanged,
    @visibleForTesting this.activeSessionLoader,
    @visibleForTesting this.sessionActivator,
  });

  final DesktopGatewayClient? client;
  final Duration interval;
  final VoidCallback? onTitlesChanged;

  /// Test seams: resolve the same two calls without a socket.
  final Future<List<Map<String, dynamic>>> Function()? activeSessionLoader;
  final Future<void> Function(String sessionId)? sessionActivator;

  Timer? _timer;
  bool _running = false;
  Future<void>? _tickInFlight;
  final Set<String> _attached = <String>{};
  final Map<String, String> _titles = <String, String>{};

  /// Gateway runtime session id -> title, learned from the active list.
  String? titleFor(String gatewaySessionId) => _titles[gatewaySessionId];

  @visibleForTesting
  Set<String> get attachedSessions => Set.unmodifiable(_attached);

  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(interval, (_) => unawaited(tick()));
    unawaited(tick());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// A new socket has no attachments; the next tick re-establishes them.
  void resetAttachments() {
    _attached.clear();
  }

  Future<void> tick() {
    final inFlight = _tickInFlight;
    if (inFlight != null) return inFlight;
    final future = _tick();
    _tickInFlight = future;
    return future.whenComplete(() {
      if (identical(_tickInFlight, future)) _tickInFlight = null;
    });
  }

  Future<void> _tick() async {
    try {
      final rows = await (activeSessionLoader ?? client!.listActiveSessions)();
      var titlesChanged = false;
      for (final row in rows) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final title = (row['title'] ?? '').toString();
        if (title.isNotEmpty && _titles[id] != title) {
          _titles[id] = title;
          titlesChanged = true;
        }
        if ((row['status'] ?? '').toString() == 'idle') {
          // No turn is running; nothing to receive and no approval can exist.
          _attached.remove(id);
          continue;
        }
        if (_attached.contains(id)) continue;
        try {
          await (sessionActivator ?? client!.activateSession)(id);
          _attached.add(id);
        } catch (_) {
          // A finalized/compute-host session refuses the attach; it cannot be
          // watched from this client. Never let one row kill the whole tick.
        }
      }
      if (titlesChanged) onTitlesChanged?.call();
    } catch (_) {
      // A failed poll leaves the previous attachments alone; the next tick
      // retries. Connection loss clears them via [resetAttachments].
    }
  }
}
