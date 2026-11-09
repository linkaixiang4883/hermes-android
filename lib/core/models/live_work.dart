/// Session-scoped Live Work models matching the stock gateway contracts.
///
/// `process.session_id` is a PROCESS id, not a chat id. The model renames it to
/// [LiveProcess.processId] so no caller can accidentally route on it.
class LiveWorkCounts {
  final int subagents;
  final int background;

  const LiveWorkCounts({this.subagents = 0, this.background = 0});

  bool get hasWork => subagents > 0 || background > 0;

  factory LiveWorkCounts.fromJson(Map<String, dynamic> json) {
    return LiveWorkCounts(
      subagents: _int(json['subagents']),
      background: _int(json['background']),
    );
  }
}

class LiveSubagent {
  final String id;
  final String parentId;
  final int depth;
  final String goal;
  final String? delegationId;
  final String? model;
  final DateTime? startedAt;
  final String status;
  final int toolCount;
  final String? lastTool;
  final bool acceptingSteer;

  const LiveSubagent({
    required this.id,
    this.parentId = '',
    this.depth = 0,
    this.goal = '',
    this.delegationId,
    this.model,
    this.startedAt,
    this.status = 'running',
    this.toolCount = 0,
    this.lastTool,
    this.acceptingSteer = false,
  });

  bool get isRunning => !_terminalStatus(status);

  factory LiveSubagent.fromJson(Map<String, dynamic> json) {
    return LiveSubagent(
      id: _text(json['subagent_id']) ?? _text(json['id']) ?? '',
      parentId: _text(json['parent_id']) ?? '',
      depth: _int(json['depth']),
      goal: _text(json['goal']) ?? '',
      delegationId: _text(json['delegation_id']),
      model: _text(json['model']),
      startedAt: _date(json['started_at']),
      status: _text(json['status']) ?? 'running',
      toolCount: _int(json['tool_count']),
      lastTool: _text(json['last_tool']),
      acceptingSteer: json['accepting_steer'] == true,
    );
  }
}

class LiveProcess {
  final String processId;
  final String command;
  final String status;
  final int? exitCode;
  final DateTime? startedAt;
  final DateTime? exitedAt;
  final String? completionReason;
  final String? outputTail;

  const LiveProcess({
    required this.processId,
    required this.command,
    required this.status,
    this.exitCode,
    this.startedAt,
    this.exitedAt,
    this.completionReason,
    this.outputTail,
  });

  bool get isRunning => status == 'running';

  Duration? uptime(DateTime now) {
    final started = startedAt;
    if (started == null) return null;
    return now.difference(started);
  }

  factory LiveProcess.fromJson(Map<String, dynamic> json) {
    return LiveProcess(
      // The server's session_id here is the process id.
      processId: _text(json['session_id']) ?? _text(json['process_id']) ?? '',
      command: _text(json['command']) ?? '',
      status: _text(json['status']) ?? 'running',
      exitCode: (json['exit_code'] as num?)?.toInt(),
      startedAt: _date(json['started_epoch']),
      exitedAt: _date(json['exited_at']),
      completionReason: _text(json['completion_reason']),
      outputTail: _text(json['output_tail']),
    );
  }
}

class LiveWorkSnapshot {
  final List<LiveSubagent> subagents;
  final List<LiveProcess> processes;
  final DateTime fetchedAt;
  final bool stale;

  const LiveWorkSnapshot({
    this.subagents = const [],
    this.processes = const [],
    required this.fetchedAt,
    this.stale = false,
  });

  bool get hasWork => subagents.isNotEmpty || processes.isNotEmpty;
}

bool _terminalStatus(String status) {
  final normalized = status.trim().toLowerCase();
  return normalized == 'completed' ||
      normalized == 'complete' ||
      normalized == 'failed' ||
      normalized == 'error' ||
      normalized == 'cancelled' ||
      normalized == 'canceled';
}

String? _text(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _date(dynamic value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      value > 100000000000 ? value.toInt() : (value * 1000).round(),
    );
  }
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  final numeric = double.tryParse(text);
  if (numeric != null) return _date(numeric);
  return DateTime.tryParse(text);
}
