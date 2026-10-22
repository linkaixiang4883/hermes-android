import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/pending_prompt.dart';
import 'package:hermes_android/core/services/observed_turn_store.dart';
import 'package:hermes_android/core/utils/activity_feed.dart';

import 'support/l10n_test_utils.dart';

ObservedTurn _turn(String id, String state, {DateTime? at}) => ObservedTurn(
  gatewaySessionId: id,
  mobileSessionId: 'm-$id',
  title: 'Chat $id',
  state: state,
  summary: null,
  updatedAt: at ?? DateTime(2026, 10, 22, 12),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prompts become the needs-you group and drive the badge', () async {
    final l10n = await loadTestL10n();
    final feed = buildObservedActivityFeed(
      turns: [_turn('g-1', 'running')],
      prompts: [
        PendingPrompt(
          id: 'r1',
          method: 'approval',
          mobileSessionId: 'm-1',
          gatewaySessionId: 'g-1',
          summary: 'rm -rf build',
          choices: const ['once', 'deny'],
          createdAt: DateTime(2026, 10, 22, 12),
        ),
      ],
      l10n: l10n,
      now: DateTime(2026, 10, 22, 12),
    );
    expect(feed.blockedCount, 1);
    expect(feed.runningCount, 1);
    expect(feed.groups.first.kind, ActivityGroupKind.needsYou);
    expect(feed.groups.first.items.single.label, 'rm -rf build');
  });

  test('observed turns group by state and drop old completions', () async {
    final l10n = await loadTestL10n();
    final now = DateTime(2026, 10, 22, 12);
    final feed = buildObservedActivityFeed(
      turns: [
        _turn('g-run', 'running', at: now),
        _turn('g-bad', 'failed', at: now),
        _turn('g-new', 'completed', at: now),
        _turn('g-old', 'completed', at: now.subtract(const Duration(days: 8))),
      ],
      prompts: const [],
      l10n: l10n,
      now: now,
    );
    expect(
      feed.groups.map((g) => g.kind),
      [ActivityGroupKind.running, ActivityGroupKind.failed, ActivityGroupKind.completed],
    );
    final completed = feed.groups.last.items.map((i) => i.sessionId);
    expect(completed, ['m-g-new']);
  });
}
