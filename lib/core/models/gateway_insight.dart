enum GatewayReasoningEventMode { append, replace }

class GatewayReasoningUpdate {
  static const _maxTextLength = 20000;

  final String text;
  final GatewayReasoningEventMode mode;
  final bool verbose;

  const GatewayReasoningUpdate({
    required this.text,
    required this.mode,
    required this.verbose,
  });

  static GatewayReasoningUpdate? fromGatewayEvent(
    String eventType,
    Map<String, dynamic> data,
  ) {
    if (eventType != 'reasoning.delta' && eventType != 'reasoning.available') {
      return null;
    }
    final text = _safeText(data['text']?.toString(), _maxTextLength);
    if (text == null) return null;
    return GatewayReasoningUpdate(
      text: text,
      mode: eventType == 'reasoning.available'
          ? GatewayReasoningEventMode.replace
          : GatewayReasoningEventMode.append,
      verbose: data['verbose'] == true,
    );
  }

  String applyTo(String current) {
    final combined = mode == GatewayReasoningEventMode.replace
        ? text
        : '$current$text';
    if (combined.length <= _maxTextLength) return combined;
    return '${combined.substring(0, _maxTextLength - 1)}…';
  }

  /// Whether a `reasoning.available` payload is really an answer preview.
  ///
  /// Hermes broadcasts `reasoning.available` at the end of every assistant
  /// message carrying the first 500 characters of the REPLY text, not the
  /// model's thinking (`agent/turn_response_intake.py` `_relay_thinking`).
  /// Applying that as a replacement wipes the streamed [reasoning.delta]
  /// content with an echo of the answer, so callers drop it instead.
  ///
  /// Only a positive match counts: with nothing streamed yet, or with text
  /// that is not the reply's own opening, the update keeps its normal
  /// replacement behaviour.
  static bool isAnswerPreview(String text, String assistantText) {
    final preview = _normalizeForComparison(text);
    if (preview.isEmpty) return false;
    final content = _normalizeForComparison(assistantText);
    if (content.isEmpty) return false;
    return content == preview || content.startsWith(preview);
  }

  /// Whitespace-insensitive comparison key: the gateway builds its preview
  /// from the same reply the client assembled out of streamed deltas, but the
  /// two can differ in insignificant spacing.
  static String _normalizeForComparison(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? _safeText(String? value, int maxLength) {
    if (value == null) return null;
    final safe = value.replaceAll('\u0000', '');
    if (safe.trim().isEmpty) return null;
    return safe.length <= maxLength
        ? safe
        : '${safe.substring(0, maxLength - 1)}…';
  }
}

class GatewayInterimTransition {
  final String sealedText;
  final bool startsNewMessage;

  const GatewayInterimTransition({
    required this.sealedText,
    required this.startsNewMessage,
  });

  factory GatewayInterimTransition.resolve({
    required String currentText,
    required String interimText,
    required bool alreadyStreamed,
  }) {
    final safeInterim = interimText.replaceAll('\u0000', '');
    var sealed = currentText;
    if (safeInterim.isNotEmpty &&
        currentText != safeInterim &&
        !currentText.endsWith(safeInterim)) {
      if (!alreadyStreamed) {
        sealed = '$currentText$safeInterim';
      } else if (currentText.isEmpty || safeInterim.startsWith(currentText)) {
        sealed = safeInterim;
      }
    }
    return GatewayInterimTransition(
      sealedText: sealed,
      startsNewMessage: sealed.trim().isNotEmpty,
    );
  }
}

enum GatewayNoticeKind { background, review }

class GatewayNotice {
  static const _maxTextLength = 4000;
  static const _maxTaskIdLength = 120;

  /// Detail lines a review card carries. A long-lived session reviews over and
  /// over; the card shows the newest [_maxReviewUpdates] lines.
  static const _maxReviewUpdates = 20;

  final GatewayNoticeKind kind;
  final String text;
  final String? taskId;

  /// Every distinct summary line this review card speaks for, oldest first.
  ///
  /// `review.summary` fires once per background memory/skill pass. Each frame
  /// used to append another card, so a session that reviewed repeatedly ended
  /// with a transcript tail made only of notices; the screen folds the passes
  /// into this list instead and renders a single card.
  final List<String> updates;

  const GatewayNotice({
    required this.kind,
    required this.text,
    this.taskId,
    this.updates = const [],
  });

  bool get isReview => kind == GatewayNoticeKind.review;

  /// How many review passes this card speaks for (1 for a single pass).
  int get updateCount => isReview ? (updates.isEmpty ? 1 : updates.length) : 0;

  /// The lines the expanded review card lists.
  List<String> get details => isReview
      ? (updates.isEmpty ? <String>[text] : updates)
      : const <String>[];

  /// This card after another review pass reported [next].
  GatewayNotice withReviewUpdate(GatewayNotice next) {
    final lines = List<String>.from(details);
    if (!lines.contains(next.text)) lines.add(next.text);
    final trimmed = lines.length <= _maxReviewUpdates
        ? lines
        : lines.sublist(lines.length - _maxReviewUpdates);
    return GatewayNotice(
      kind: GatewayNoticeKind.review,
      text: next.text,
      updates: List<String>.unmodifiable(trimmed),
    );
  }

  String get identity => switch (kind) {
    GatewayNoticeKind.background => '${kind.name}|${taskId ?? ''}|$text',
    // A review card's identity moves with its count and its newest line: a
    // dismissed card stays dismissed until another pass brings news, then it
    // earns its place back at the bottom of the timeline.
    GatewayNoticeKind.review =>
      '${kind.name}||$updateCount|${details.isEmpty ? '' : details.last}',
  };

  String get title => switch (kind) {
    GatewayNoticeKind.background =>
      taskId == null
          ? 'Background task completed'
          : 'Background task $taskId completed',
    GatewayNoticeKind.review => 'Hermes review',
  };

  static GatewayNotice? fromGatewayEvent(
    String eventType,
    Map<String, dynamic> data,
  ) {
    if (eventType != 'background.complete' && eventType != 'review.summary') {
      return null;
    }
    final text = safeLine(data['text']?.toString(), _maxTextLength);
    if (text == null) return null;
    return GatewayNotice(
      kind: eventType == 'background.complete'
          ? GatewayNoticeKind.background
          : GatewayNoticeKind.review,
      text: text,
      taskId: eventType == 'background.complete'
          ? safeLine(data['task_id']?.toString(), _maxTaskIdLength)
          : null,
    );
  }

  static String? safeLine(String? value, int maxLength) {
    if (value == null) return null;
    final safe = value.replaceAll('\u0000', '').trim();
    if (safe.isEmpty) return null;
    return safe.length <= maxLength
        ? safe
        : '${safe.substring(0, maxLength - 1)}…';
  }
}

enum GatewayNotificationLevel { info, success, warning, error }

class GatewayNotification {
  final String key;
  final String text;
  final GatewayNotificationLevel level;
  final Duration? ttl;

  const GatewayNotification({
    required this.key,
    required this.text,
    required this.level,
    this.ttl,
  });

  static GatewayNotification? fromEventData(Map<String, dynamic> data) {
    final text = GatewayNotice.safeLine(data['text']?.toString(), 1000);
    if (text == null) return null;
    final key =
        GatewayNotice.safeLine((data['key'] ?? data['id'])?.toString(), 120) ??
        'latest';
    final ttlMs = switch (data['ttl_ms']) {
      int value when value > 0 => value,
      num value when value > 0 => value.toInt(),
      _ => null,
    };
    return GatewayNotification(
      key: key,
      text: text,
      level: switch (data['level']?.toString()) {
        'success' => GatewayNotificationLevel.success,
        'warn' => GatewayNotificationLevel.warning,
        'error' => GatewayNotificationLevel.error,
        _ => GatewayNotificationLevel.info,
      },
      ttl: ttlMs == null ? null : Duration(milliseconds: ttlMs),
    );
  }
}

enum GatewaySubagentPhase { requested, running, thinking, tool, completed }

class GatewaySubagentActivity {
  final String id;
  final String goal;
  final String? model;
  final String? detail;
  final GatewaySubagentPhase phase;
  final int? taskIndex;
  final int? taskCount;

  const GatewaySubagentActivity({
    required this.id,
    required this.goal,
    required this.phase,
    this.model,
    this.detail,
    this.taskIndex,
    this.taskCount,
  });

  bool get isComplete => phase == GatewaySubagentPhase.completed;

  GatewaySubagentActivity merge(GatewaySubagentActivity next) {
    return GatewaySubagentActivity(
      id: id,
      goal: next.goal.isEmpty ? goal : next.goal,
      phase: next.phase,
      model: next.model ?? model,
      detail: next.detail ?? detail,
      taskIndex: next.taskIndex ?? taskIndex,
      taskCount: next.taskCount ?? taskCount,
    );
  }

  static GatewaySubagentActivity? fromGatewayEvent(
    String eventType,
    Map<String, dynamic> data,
  ) {
    if (!eventType.startsWith('subagent.')) return null;
    final id =
        GatewayNotice.safeLine(data['subagent_id']?.toString(), 120) ??
        'task-${data['task_index'] ?? 0}';
    final goal =
        GatewayNotice.safeLine(data['goal']?.toString(), 500) ??
        'Delegated task';
    final detail = GatewayNotice.safeLine(
      (data['summary'] ??
              data['text'] ??
              data['tool_preview'] ??
              data['tool_name'])
          ?.toString(),
      1000,
    );
    return GatewaySubagentActivity(
      id: id,
      goal: goal,
      model: GatewayNotice.safeLine(data['model']?.toString(), 120),
      detail: detail,
      taskIndex: (data['task_index'] as num?)?.toInt(),
      taskCount: (data['task_count'] as num?)?.toInt(),
      phase: switch (eventType) {
        'subagent.spawn_requested' => GatewaySubagentPhase.requested,
        'subagent.thinking' => GatewaySubagentPhase.thinking,
        'subagent.tool' => GatewaySubagentPhase.tool,
        'subagent.complete' => GatewaySubagentPhase.completed,
        _ => GatewaySubagentPhase.running,
      },
    );
  }
}
