import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/pending_prompt.dart';
import 'notification_prefs.dart';
import 'turn_notification_service.dart';

/// Mirrors blocking prompts to native notifications — app level, any session.
///
/// Before this existed the mirror lived inside ChatScreen and only ran while
/// that screen was mounted and the app was backgrounded. A prompt raised by a
/// session the user was not looking at had no owner at all: the client
/// answered `-32601` and the gateway *withdrew* it.
///
/// Notifications carry the registry request id, so a tap or an action button
/// can answer through `DesktopGatewayClient.respondToPendingPrompt` without a
/// chat screen, and a prompt is cancelled the moment it resolves anywhere.
class PromptNotifier {
  PromptNotifier({
    required this.notifications,
    required this.titleFor,
    required this.formatTitle,
    required this.approveLabel,
    required this.denyLabel,
    this.isSessionVisible,
  });

  final TurnNotificationService notifications;

  /// Gateway runtime session id -> chat title (the watcher learns these).
  final String? Function(String gatewaySessionId) titleFor;

  /// Localized title line, e.g. `审批 — <title>`.
  final String Function({required bool approval, String? sessionTitle})
  formatTitle;

  final String Function() approveLabel;
  final String Function() denyLabel;

  /// True when that chat is on screen. A prompt already visible as a dialog
  /// must not also ring the notification shade (the completion notifier
  /// already suppresses the visible session this way).
  final bool Function(String? mobileSessionId)? isSessionVisible;

  ValueListenable<List<PendingPrompt>>? _prompts;
  String? _connectionId;
  VoidCallback? _listener;
  final Map<String, PendingPrompt> _shown = <String, PendingPrompt>{};

  void attach(
    ValueListenable<List<PendingPrompt>> prompts, {
    required String connectionId,
  }) {
    detach();
    _prompts = prompts;
    _connectionId = connectionId;
    void listener() => _sync();
    _listener = listener;
    prompts.addListener(listener);
    _sync();
  }

  void detach() {
    final prompts = _prompts;
    final listener = _listener;
    if (prompts != null && listener != null) {
      prompts.removeListener(listener);
    }
    _prompts = null;
    _listener = null;
    _connectionId = null;
    _shown.clear();
  }

  void _sync() {
    final prompts = _prompts;
    final connectionId = _connectionId;
    if (prompts == null || connectionId == null) return;
    final current = <String, PendingPrompt>{
      for (final prompt in prompts.value) prompt.id: prompt,
    };

    for (final entry in List.of(_shown.entries)) {
      if (current.containsKey(entry.key)) continue;
      final gone = entry.value;
      _shown.remove(entry.key);
      unawaited(
        notifications.cancelKind(
          kind: gone.isApproval
              ? HermesNotificationKind.approval
              : HermesNotificationKind.input,
          eventId: gone.id,
          sessionId: gone.mobileSessionId ?? gone.gatewaySessionId,
          connectionId: connectionId,
        ),
      );
    }

    for (final prompt in current.values) {
      if (_shown.containsKey(prompt.id)) continue;
      if (isSessionVisible?.call(prompt.mobileSessionId) ?? false) {
        _shown[prompt.id] = prompt;
        continue;
      }
      _shown[prompt.id] = prompt;
      final sessionTitle = titleFor(prompt.gatewaySessionId);
      final body = prompt.summary.isEmpty
          ? prompt.method
          : (prompt.summary.length <= 160
                ? prompt.summary
                : '${prompt.summary.substring(0, 159)}…');
      unawaited(
        notifications.showKind(
          kind: prompt.isApproval
              ? HermesNotificationKind.approval
              : HermesNotificationKind.input,
          title: formatTitle(
            approval: prompt.isApproval,
            sessionTitle: sessionTitle,
          ),
          body: body,
          eventId: prompt.id,
          sessionId: prompt.mobileSessionId ?? prompt.gatewaySessionId,
          connectionId: connectionId,
          actions: prompt.isApproval
              ? [
                  TurnNotificationAction(
                    id: 'approve',
                    label: approveLabel(),
                  ),
                  TurnNotificationAction(id: 'reject', label: denyLabel()),
                ]
              : const [],
          payload: jsonEncode({
            'sessionId': prompt.mobileSessionId ?? prompt.gatewaySessionId,
            'connectionId': connectionId,
            'requestId': prompt.id,
            'wireRequestId': prompt.wireRequestId,
          }),
        ),
      );
    }
  }
}
