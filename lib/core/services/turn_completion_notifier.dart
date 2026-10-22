import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'desktop_gateway_client.dart';
import 'notification_prefs.dart';
import 'turn_notification_service.dart';
import 'ws_client.dart' show StreamEvent;

/// Posts a native notification when a turn settles — for ANY session.
///
/// The previous implementation hung off the turn-recovery state stream, which
/// only exists on gateways that advertise `turn_recovery`; on a stock gateway
/// it never emitted, so completion notifications never fired at all. Terminal
/// fan-out frames (`message.complete`, `turn.end`, `turn.error`) exist
/// everywhere and reach this listener through the client's global event door —
/// including sessions the user never opened, provided the watcher attached
/// them.
class TurnCompletionNotifier {
  TurnCompletionNotifier({
    required this.notifications,
    required this.titleFor,
    required this.isSessionVisible,
    required this.formatTitle,
  });

  final TurnNotificationService notifications;

  /// Gateway runtime session id -> chat title, or null when unknown.
  final String? Function(String gatewaySessionId) titleFor;

  /// True when the user is currently looking at that chat (no notification).
  final bool Function(String gatewaySessionId) isSessionVisible;

  /// Localized title line for a settled/failed turn.
  final String Function({required bool failed, String? sessionTitle})
  formatTitle;

  DesktopGatewayClient? _client;
  Object? _token;
  String? _connectionId;
  final Set<String> _seen = <String>{};

  static const Set<String> _terminalTypes = {
    'message.complete',
    'turn.end',
    'turn.error',
    'error',
  };

  void attach(DesktopGatewayClient client, {required String connectionId}) {
    detach(client);
    _client = client;
    _connectionId = connectionId;
    _token = client.addGlobalEventListener(_onEvent);
  }

  void detach([DesktopGatewayClient? client]) {
    final owner = client ?? _client;
    final token = _token;
    if (owner != null && token != null) {
      owner.removeGlobalEventListener(token);
    }
    _token = null;
    _client = null;
    _connectionId = null;
  }

  @visibleForTesting
  void handleEvent(StreamEvent event, String? mobileSessionId) =>
      _onEvent(event, mobileSessionId);

  void _onEvent(StreamEvent event, String? mobileSessionId) {
    if (!_terminalTypes.contains(event.type)) return;
    final gatewaySessionId = event.data['session_id']?.toString() ?? '';
    if (gatewaySessionId.isEmpty) return;
    final turnId =
        (event.data['turn_id'] ??
                event.data['message_id'] ??
                event.data['id'] ??
                '')
            .toString();
    final dedupeKey =
        '${_connectionId ?? ''}|$gatewaySessionId|'
        '${turnId.isEmpty ? event.type : turnId}';
    if (!_seen.add(dedupeKey)) return;
    if (isSessionVisible(gatewaySessionId)) return;

    final failed = event.type.contains('error');
    final raw =
        (event.data['rendered'] ??
                event.data['text'] ??
                event.data['message'] ??
                '')
            .toString();
    final body = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    unawaited(
      notifications.showKind(
        kind: failed
            ? HermesNotificationKind.turnError
            : HermesNotificationKind.turnDone,
        title: formatTitle(
          failed: failed,
          sessionTitle: titleFor(gatewaySessionId),
        ),
        body: body.isEmpty
            ? ''
            : (body.length <= 140 ? body : '${body.substring(0, 139)}…'),
        eventId: dedupeKey,
        sessionId: mobileSessionId ?? gatewaySessionId,
        connectionId: _connectionId,
        payload: jsonEncode({
          'sessionId': mobileSessionId ?? gatewaySessionId,
          'connectionId': _connectionId,
        }),
      ),
    );
  }
}
