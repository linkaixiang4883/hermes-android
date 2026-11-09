import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/gateway_insight.dart';
import '../models/live_work.dart';

typedef LiveSubagentLoader = Future<List<LiveSubagent>> Function();
typedef LiveProcessLoader = Future<List<LiveProcess>> Function();

/// Foreground-only snapshot of the session's live work.
///
/// `subagent.list` is the authoritative snapshot; `subagent.*` events update
/// it immediately. `process.list` is an event-armed safety net: silent exits
/// have no event, so we only poll it once a tool/background/subagent event has
/// shown that work may exist. Nothing here is persisted.
class LiveWorkStore extends ChangeNotifier {
  final LiveSubagentLoader loadSubagents;
  final LiveProcessLoader loadProcesses;
  final Duration interval;
  final DateTime Function() clock;

  LiveWorkStore({
    required this.loadSubagents,
    required this.loadProcesses,
    this.interval = const Duration(seconds: 5),
    DateTime Function()? clock,
    List<LiveSubagent> initialSubagents = const [],
    List<LiveProcess> initialProcesses = const [],
  }) : clock = clock ?? DateTime.now,
       _subagents = initialSubagents,
       _processes = initialProcesses {
    _processArmed = initialProcesses.isNotEmpty || initialSubagents.isNotEmpty;
  }

  List<LiveSubagent> _subagents = const [];
  List<LiveProcess> _processes = const [];
  DateTime? _fetchedAt;
  bool _stale = false;
  bool _active = false;
  bool _foreground = true;
  bool _processArmed = false;
  bool _processProbeDone = false;
  bool _loading = false;
  int _generation = 0;
  Timer? _timer;

  List<LiveSubagent> get subagents => _subagents;
  List<LiveProcess> get processes => _processes;
  DateTime? get fetchedAt => _fetchedAt;
  bool get stale => _stale;
  bool get hasWork => _subagents.isNotEmpty || _processes.isNotEmpty;

  void start() {
    if (_active) return;
    _active = true;
    _processArmed = _processes.isNotEmpty || _subagents.isNotEmpty;
    _schedule(immediate: true);
  }

  void stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!_active) return;
    if (foreground) {
      _schedule(immediate: true);
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Clears a disconnected session's rows so a reconnect cannot show a dead
  /// process or subagent as if it were still running.
  void clear() {
    if (_subagents.isEmpty && _processes.isEmpty && !_stale) return;
    _subagents = const [];
    _processes = const [];
    _fetchedAt = null;
    _stale = true;
    notifyListeners();
  }

  /// Feeds a gateway event into the live snapshot.
  ///
  /// The event stream is authoritative while the turn runs; the next
  /// `subagent.list` snapshot reconciles anything the client missed.
  void noteGatewayEvent(String type, Map<String, dynamic> data) {
    if (type == 'subagent.complete' ||
        type == 'subagent.start' ||
        type == 'subagent.spawn_requested' ||
        type == 'subagent.thinking' ||
        type == 'subagent.tool' ||
        type == 'subagent.progress') {
      _processArmed = true;
      _upsertEvent(type, data);
    } else if (type.startsWith('tool.') || type.startsWith('background.')) {
      _processArmed = true;
      if (type == 'background.complete') {
        unawaited(_refreshProcesses());
      }
    }
  }

  void _upsertEvent(String type, Map<String, dynamic> data) {
    final activity = GatewaySubagentActivity.fromGatewayEvent(type, data);
    if (activity == null) return;
    final id = activity.id;
    final index = _subagents.indexWhere((item) => item.id == id);
    final update = LiveSubagent(
      id: id,
      goal: activity.goal,
      model: activity.model,
      status: activity.isComplete ? 'completed' : 'running',
      lastTool: activity.phase == GatewaySubagentPhase.tool
          ? activity.detail
          : null,
    );
    if (index < 0) {
      _subagents = [..._subagents, update];
    } else {
      final old = _subagents[index];
      _subagents = [
        for (var i = 0; i < _subagents.length; i++)
          if (i == index)
            LiveSubagent(
              id: old.id,
              parentId: old.parentId,
              depth: old.depth,
              goal: update.goal.isEmpty ? old.goal : update.goal,
              delegationId: old.delegationId,
              model: update.model ?? old.model,
              startedAt: old.startedAt,
              status: update.status,
              toolCount: old.toolCount,
              lastTool: update.lastTool ?? old.lastTool,
              acceptingSteer: old.acceptingSteer,
            )
          else
            _subagents[i],
      ];
    }
    notifyListeners();
  }

  void _schedule({bool immediate = false}) {
    _timer?.cancel();
    if (!_active || !_foreground) return;
    if (immediate) {
      unawaited(_tick());
    }
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (!_active || !_foreground || _loading) return;
    _loading = true;
    final generation = ++_generation;
    try {
      final agents = await loadSubagents();
      final processes =
          !_processProbeDone ||
              _processArmed ||
              agents.isNotEmpty ||
              _processes.isNotEmpty
          ? await _refreshProcessList()
          : _processes;
      _processProbeDone = true;
      if (generation != _generation || !_active || !_foreground) return;
      final nextProcesses = _trimProcesses(processes);
      final changed =
          !_sameSubagents(_subagents, agents) ||
          !_sameProcesses(_processes, nextProcesses) ||
          _stale;
      _subagents = agents;
      _processes = nextProcesses;
      _fetchedAt = clock();
      _stale = false;
      if (changed) notifyListeners();
    } catch (_) {
      if (generation != _generation) return;
      // A missing capability or a reaped session is not a user-facing error.
      if (!_stale) {
        _stale = true;
        notifyListeners();
      }
    } finally {
      if (generation == _generation) _loading = false;
    }
  }

  Future<void> _refreshProcesses() async {
    if (!_active || !_foreground) return;
    try {
      final processes = await _refreshProcessList();
      if (!_active || !_foreground) return;
      _processes = _trimProcesses(processes);
      _fetchedAt = clock();
      notifyListeners();
    } catch (_) {
      _stale = true;
      notifyListeners();
    }
  }

  Future<List<LiveProcess>> _refreshProcessList() async {
    final processes = await loadProcesses();
    _processArmed = processes.any((process) => process.isRunning);
    return processes;
  }

  bool _sameSubagents(List<LiveSubagent> left, List<LiveSubagent> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      final a = left[i];
      final b = right[i];
      if (a.id != b.id ||
          a.goal != b.goal ||
          a.model != b.model ||
          a.status != b.status ||
          a.lastTool != b.lastTool ||
          a.toolCount != b.toolCount) {
        return false;
      }
    }
    return true;
  }

  bool _sameProcesses(List<LiveProcess> left, List<LiveProcess> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      final a = left[i];
      final b = right[i];
      if (a.processId != b.processId ||
          a.command != b.command ||
          a.status != b.status ||
          a.exitCode != b.exitCode ||
          a.completionReason != b.completionReason) {
        return false;
      }
    }
    return true;
  }

  List<LiveProcess> _trimProcesses(List<LiveProcess> processes) {
    final running = processes.where((process) => process.isRunning).toList();
    final finished = processes
        .where((process) => !process.isRunning)
        .take(2)
        .toList(growable: false);
    return [...running, ...finished];
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
