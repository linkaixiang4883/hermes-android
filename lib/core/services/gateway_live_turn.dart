/// The turn a `session.resume` answer says is still running, projected into
/// the pieces a chat screen rebuilds its bubbles from.
///
/// Stock Hermes attaches a live session without replaying the transcript and
/// instead returns `running`/`status` plus an `inflight` snapshot — the
/// gateway's own contract calls it "the live (or retained failed) turn a
/// reconnecting client rebuilds its bubbles from". That snapshot is text-only
/// (no tool state): tool progress has to come from the event replay or the
/// stored transcript.
///
/// This is a pure value object with no transport in it, so the screen can be
/// handed a projection without a socket (which is also what lets the parse
/// rules be pinned by plain unit tests).
class LiveTurnProjection {
  /// Whether the gateway reports a turn running for this session right now.
  final bool running;

  /// The session's own status string (`running`, `idle`, `interrupted`, …),
  /// normalized to lowercase, when the payload carried one.
  final String? status;

  /// The prompt of the running turn, when the gateway still holds it.
  final String user;

  /// The reply text streamed so far. Empty before the first delta.
  final String assistant;

  /// Whether the gateway is still writing to [assistant].
  final bool streaming;

  /// The retained failure of the last turn, when there was one.
  final String error;

  /// Whether this snapshot is a retained FAILURE rather than a healthy
  /// partial. The gateway keeps a failed turn replayable for a client that
  /// missed the terminal frame, so the UI must be able to say so instead of
  /// rendering the partial as an answer.
  final bool failed;

  const LiveTurnProjection({
    required this.running,
    this.status,
    this.user = '',
    this.assistant = '',
    this.streaming = false,
    this.error = '',
    this.failed = false,
  });

  /// Whether there is a turn worth rebuilding. A settled turn keeps its text
  /// in the transcript, which the history fetch already owns.
  bool get isLive => running || streaming || assistant.isNotEmpty;

  /// Statuses that mean the turn did not finish: the same set the session
  /// recovery path treats as terminal failures.
  static const _terminalFailures = {
    'error',
    'failed',
    'interrupted',
    'cancelled',
    'canceled',
  };

  /// Projects the raw `session.resume` payload, or null when it carries no
  /// turn to rebuild.
  ///
  /// Null is the common case — an idle chat answers with neither `running` nor
  /// an `inflight` snapshot — and it is deliberately distinct from an empty
  /// projection: it means "there is nothing live here", which is what ends a
  /// follow.
  static LiveTurnProjection? fromResume(Map<String, dynamic> payload) {
    final inflight = payload['inflight'];
    final snapshot = inflight is Map
        ? Map<String, dynamic>.from(inflight)
        : const <String, dynamic>{};
    final running = payload['running'] == true;
    final rawStatus = snapshot['status'] ?? payload['status'];
    final status = _normalize(rawStatus);
    final user = snapshot['user']?.toString() ?? '';
    final assistant = snapshot['assistant']?.toString() ?? '';
    final streaming = snapshot['streaming'] == true;
    final error = snapshot['error']?.toString().trim() ?? '';
    final failed =
        error.isNotEmpty ||
        (status != null && _terminalFailures.contains(status));

    if (!running &&
        !streaming &&
        !failed &&
        user.trim().isEmpty &&
        assistant.trim().isEmpty &&
        error.isEmpty) {
      return null;
    }
    return LiveTurnProjection(
      running: running,
      status: status,
      user: user,
      assistant: assistant,
      streaming: streaming,
      error: error,
      failed: failed,
    );
  }

  static String? _normalize(Object? value) {
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text.isEmpty ? null : text;
  }
}
