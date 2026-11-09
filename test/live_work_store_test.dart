import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/live_work.dart';
import 'package:hermes_android/core/services/live_work_store.dart';

void main() {
  group('LiveWorkStore', () {
    test(
      'loads a snapshot only while started and applies subagent events',
      () async {
        var subagentLoads = 0;
        var processLoads = 0;
        final store = LiveWorkStore(
          interval: const Duration(hours: 1),
          loadSubagents: () async {
            subagentLoads++;
            return const [
              LiveSubagent(id: 'sub-1', goal: 'inspect', status: 'running'),
            ];
          },
          loadProcesses: () async {
            processLoads++;
            return const [];
          },
        );

        store.start();
        await Future<void>.delayed(Duration.zero);
        expect(subagentLoads, 1);
        expect(processLoads, 1);
        expect(store.subagents, hasLength(1));
        expect(store.hasWork, isTrue);

        store.noteGatewayEvent('subagent.complete', {
          'subagent_id': 'sub-1',
          'goal': 'inspect',
        });
        expect(store.subagents.single.status, 'completed');
        expect(store.subagents.single.isRunning, isFalse);

        store.stop();
        store.dispose();
      },
    );

    test('clears rows on disconnect and never resurrects them', () async {
      final store = LiveWorkStore(
        interval: const Duration(hours: 1),
        loadSubagents: () async => const [
          LiveSubagent(id: 'sub-1', goal: 'inspect', status: 'running'),
        ],
        loadProcesses: () async => const [],
      );
      store.start();
      await Future<void>.delayed(Duration.zero);
      expect(store.hasWork, isTrue);

      store.clear();
      expect(store.hasWork, isFalse);
      expect(store.stale, isTrue);

      store.stop();
      store.dispose();
    });

    test('polls processes after a tool event arms the safety net', () async {
      var processLoads = 0;
      final store = LiveWorkStore(
        interval: const Duration(milliseconds: 20),
        loadSubagents: () async => const [],
        loadProcesses: () async {
          processLoads++;
          return const [
            LiveProcess(
              processId: 'proc-1',
              command: 'sleep 300',
              status: 'running',
            ),
          ];
        },
      );
      store.start();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(processLoads, 1);

      store.noteGatewayEvent('tool.start', {'name': 'terminal'});
      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(processLoads, greaterThanOrEqualTo(2));
      expect(store.processes.single.processId, 'proc-1');

      store.stop();
      store.dispose();
    });
  });
}
