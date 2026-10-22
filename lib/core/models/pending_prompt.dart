// One blocking prompt the gateway is waiting on — regardless of whether any
// chat screen is showing it.
//
/// Before this registry existed, a prompt for a session with no mounted
/// ChatScreen was answered `-32601` by this client, which the gateway treats as
/// "nobody can answer" and *withdraws* the request. A phone that merely was not
/// looking at that chat therefore killed the approval for everyone on that
/// session — including a desktop that could have answered.
///
// Now every supported prompt is registered here first; the UI either shows a
// dialog (session visible), posts a notification (session not visible) or —
// when this client explicitly cannot show it — declines with the protocol's
// `4404 NOT_SHOWN`, which lets the desktop owner answer.
library;

import 'package:flutter/foundation.dart';

@immutable
class PendingPrompt {
  /// Registry key (stable across replays of the same wire request).
  final String id;

  /// `approval` | `clarify` | `sudo` | `secret`.
  final String method;

  /// The local session id, when this client has already mapped the gateway
  /// session; null for a session it has never bound.
  final String? mobileSessionId;

  /// The gateway's runtime session id, always present.
  final String gatewaySessionId;

  /// One-line human summary: the command, or the first question.
  final String summary;

  /// Approval choices the gateway offered (`once`, `session`, `always`, `deny`).
  final List<String> choices;

  final DateTime createdAt;

  const PendingPrompt({
    required this.id,
    required this.method,
    required this.mobileSessionId,
    required this.gatewaySessionId,
    required this.summary,
    required this.choices,
    required this.createdAt,
  });

  bool get isApproval => method == 'approval';
}
