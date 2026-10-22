import 'package:flutter/material.dart';

import '../models/gateway_insight.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

class GatewayReasoningCard extends StatelessWidget {
  final String text;
  final bool initiallyExpanded;

  /// Stable identity of the reasoning block (see [ChatReasoningItem.identity]).
  /// An empty value keeps the tile unkeyed (single-card embeds and tests).
  final String identity;

  const GatewayReasoningCard({
    required this.text,
    this.initiallyExpanded = false,
    this.identity = '',
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: identity.isEmpty
            ? null
            : PageStorageKey<String>('gateway-reasoning-$identity'),
        initiallyExpanded: initiallyExpanded,
        leading: const Icon(Icons.psychology_outlined),
        title: Text(context.l10n.reasoning),
        subtitle: Text(context.l10n.hermes_reasoning_details),
        children: [
          const Divider(height: 1),
          SelectionArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(alignment: Alignment.centerLeft, child: Text(text)),
            ),
          ),
        ],
      ),
    );
  }
}

class GatewayNoticeCard extends StatelessWidget {
  final GatewayNotice notice;

  /// Closes the card. A null callback leaves the card without the affordance
  /// (single-card embeds and tests).
  final VoidCallback? onDismiss;

  const GatewayNoticeCard({required this.notice, this.onDismiss, super.key});

  @override
  Widget build(BuildContext context) {
    if (notice.isReview) return _buildReview(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.task_alt_outlined, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notice.title,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(notice.text),
                  ],
                ),
              ),
            ),
            if (onDismiss != null) _dismissButton(context),
          ],
        ),
      ),
    );
  }

  /// One card for every review pass of the session: the title counts them and
  /// the body expands to the individual summaries.
  ///
  /// Reviews used to append one card per pass, so a chat that reviewed its
  /// memory/skills repeatedly filled its tail with them and the only way out
  /// was restarting the app.
  Widget _buildReview(BuildContext context) {
    final details = notice.details;
    final count = notice.updateCount;
    // A single pass needs no count — "Hermes review: 1 updates" reads worse
    // than the plain heading with its one line of detail underneath.
    final title = count > 1
        ? '${context.l10n.review_summary_title}: '
              '${context.l10n.review_updates_count(count)}'
        : context.l10n.review_summary_title;
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.fact_check_outlined, size: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        if (onDismiss != null) _dismissButton(context),
      ],
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: details.length <= 1
          ? Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: SelectionArea(child: Text(details.join('\n'))),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 4, 2),
                  child: header,
                ),
                ExpansionTile(
                  // The count already says "more than one"; the collapsed
                  // subtitle is the newest line, the body lists them all.
                  tilePadding: const EdgeInsets.only(left: 47, right: 8),
                  title: Text(
                    details.last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  children: [
                    for (final line in details.reversed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SelectionArea(child: Text(line)),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _dismissButton(BuildContext context) => IconButton(
    icon: const Icon(Icons.close, size: 18),
    tooltip: context.l10n.dismiss,
    visualDensity: VisualDensity.compact,
    onPressed: onDismiss,
  );
}

class GatewaySubagentCard extends StatelessWidget {
  final List<GatewaySubagentActivity> activities;

  const GatewaySubagentCard({required this.activities, super.key});

  @override
  Widget build(BuildContext context) {
    final complete = activities.every((activity) => activity.isComplete);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ExpansionTile(
        initiallyExpanded: !complete,
        leading: Icon(
          complete ? Icons.hub_outlined : Icons.account_tree_outlined,
        ),
        title: Text(
          complete
              ? context.l10n.delegated_tasks_completed(activities.length)
              : context.l10n.delegated_tasks_active(
                  activities.where((item) => !item.isComplete).length,
                ),
        ),
        children: [
          for (final activity in activities)
            ListTile(
              dense: true,
              leading: activity.isComplete
                  ? const Icon(Icons.check_circle_outline, color: Colors.green)
                  : const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
              title: Text(activity.goal),
              subtitle: Text(
                [
                  activity.phase.name,
                  if (activity.model != null) activity.model!,
                  if (activity.detail != null) activity.detail!,
                ].join(' • '),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
