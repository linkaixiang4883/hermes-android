import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/live_work.dart';

void main() {
  group('LiveSubagent', () {
    test('parses the authority snapshot and keeps running state', () {
      final agent = LiveSubagent.fromJson({
        'subagent_id': 'sub-1',
        'parent_id': 'root',
        'depth': 1,
        'goal': 'inspect the repo',
        'model': 'deepseek-v4.1-flash',
        'status': 'running',
        'tool_count': 3,
        'last_tool': 'read_file',
        'accepting_steer': true,
        'started_at': 1770000000,
      });

      expect(agent.id, 'sub-1');
      expect(agent.parentId, 'root');
      expect(agent.depth, 1);
      expect(agent.goal, 'inspect the repo');
      expect(agent.toolCount, 3);
      expect(agent.lastTool, 'read_file');
      expect(agent.acceptingSteer, isTrue);
      expect(agent.isRunning, isTrue);
    });

    test('completed and failed are terminal', () {
      expect(
        LiveSubagent.fromJson({
          'subagent_id': 'a',
          'status': 'completed',
        }).isRunning,
        isFalse,
      );
      expect(
        LiveSubagent.fromJson({
          'subagent_id': 'b',
          'status': 'failed',
        }).isRunning,
        isFalse,
      );
    });
  });

  group('LiveProcess', () {
    test('maps process session_id to processId and computes uptime', () {
      final process = LiveProcess.fromJson({
        'session_id': 'proc-77',
        'command': 'sleep 300',
        'status': 'running',
        'started_epoch': 1770000000,
      });

      expect(process.processId, 'proc-77');
      expect(process.command, 'sleep 300');
      expect(process.isRunning, isTrue);
      expect(
        process.uptime(DateTime.fromMillisecondsSinceEpoch(1770000060000)),
        const Duration(minutes: 1),
      );
    });

    test('exited process is not running and keeps completion metadata', () {
      final process = LiveProcess.fromJson({
        'session_id': 'proc-88',
        'command': 'false',
        'status': 'exited',
        'exit_code': 1,
        'completion_reason': 'exit 1',
      });

      expect(process.isRunning, isFalse);
      expect(process.exitCode, 1);
      expect(process.completionReason, 'exit 1');
    });
  });

  test('LiveWorkCounts parses roster rows and exposes hasWork', () {
    final counts = LiveWorkCounts.fromJson({'subagents': 2, 'background': 1});
    expect(counts.subagents, 2);
    expect(counts.background, 1);
    expect(counts.hasWork, isTrue);
    expect(const LiveWorkCounts().hasWork, isFalse);
  });
}
