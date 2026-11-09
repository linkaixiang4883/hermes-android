import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/live_work.dart';
import 'package:hermes_android/core/services/live_work_store.dart';
import 'package:hermes_android/core/widgets/live_work_status_stack.dart';

import 'support/l10n_test_utils.dart';

void main() {
  testWidgets('renders a collapsed count and expands to the work rows', (
    tester,
  ) async {
    final store = LiveWorkStore(
      interval: const Duration(hours: 1),
      initialSubagents: const [
        LiveSubagent(
          id: 'sub-1',
          goal: 'inspect the repository',
          status: 'running',
        ),
      ],
      initialProcesses: const [
        LiveProcess(
          processId: 'proc-1',
          command: 'sleep 300',
          status: 'running',
        ),
      ],
      loadSubagents: () async => const [],
      loadProcesses: () async => const [],
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(
      testAppWithL10n(Scaffold(body: LiveWorkStatusStack(store: store))),
    );
    await tester.pump();

    expect(find.byKey(const Key('live-work-status-stack')), findsOneWidget);
    expect(find.textContaining('Live work'), findsOneWidget);
    expect(find.text('inspect the repository'), findsNothing);

    await tester.tap(find.byKey(const Key('live-work-toggle')));
    await tester.pump();

    expect(find.text('inspect the repository'), findsOneWidget);
    expect(find.text('sleep 300'), findsOneWidget);
  });

  testWidgets('renders nothing when the session has no live work', (
    tester,
  ) async {
    final store = LiveWorkStore(
      interval: const Duration(hours: 1),
      loadSubagents: () async => const [],
      loadProcesses: () async => const [],
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(
      testAppWithL10n(Scaffold(body: LiveWorkStatusStack(store: store))),
    );

    expect(find.byKey(const Key('live-work-status-stack')), findsNothing);
  });
}
