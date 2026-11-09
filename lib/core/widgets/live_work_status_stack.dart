import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/live_work.dart';
import '../services/live_work_store.dart';

/// Compact, collapsible Live Work stack above the composer.
///
/// The transcript's GatewaySubagentCard remains the in-turn detail view; this
/// stack is the session-level roster of work that is still running (or just
/// finished), including background processes that never produce a transcript
/// card.
class LiveWorkStatusStack extends StatefulWidget {
  final LiveWorkStore store;

  const LiveWorkStatusStack({super.key, required this.store});

  @override
  State<LiveWorkStatusStack> createState() => _LiveWorkStatusStackState();
}

class _LiveWorkStatusStackState extends State<LiveWorkStatusStack> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final store = widget.store;
        if (!store.hasWork) return const SizedBox.shrink();
        final total = store.subagents.length + store.processes.length;
        final rows = <Widget>[
          for (final agent in store.subagents.take(3))
            _LiveWorkRow(
              icon: Icons.hub_outlined,
              title: agent.goal.isEmpty ? agent.id : agent.goal,
              subtitle: agent.lastTool ?? agent.model,
              status: agent.isRunning
                  ? context.l10n.status_running
                  : context.l10n.status_done,
              failed: _failed(agent.status),
            ),
          for (final process in store.processes.take(3))
            _LiveWorkRow(
              icon: Icons.terminal_outlined,
              title: process.command.isEmpty
                  ? process.processId
                  : process.command,
              subtitle: _uptimeLabel(process),
              status: process.isRunning
                  ? context.l10n.status_running
                  : _failed(process.status)
                  ? context.l10n.status_failed
                  : context.l10n.status_done,
              failed: _failed(process.status),
            ),
        ];

        return Container(
          key: const Key('live-work-status-stack'),
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(4, 2, 4, 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                key: const Key('live-work-toggle'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bolt_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.live_work_summary(
                            store.subagents.length,
                            store.processes.length,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...rows.take(4),
                      if (total > 4)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 28, top: 2),
                            child: Text(
                              context.l10n.live_work_more(total - 4),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static bool _failed(String status) {
    final value = status.toLowerCase();
    return value.contains('fail') || value.contains('error');
  }

  String? _uptimeLabel(LiveProcess process) {
    if (!process.isRunning) return process.completionReason;
    final uptime = process.uptime(DateTime.now());
    if (uptime == null) return null;
    if (uptime.inMinutes < 1) return '${uptime.inSeconds}s';
    if (uptime.inHours < 1) return '${uptime.inMinutes}m';
    return '${uptime.inHours}h ${uptime.inMinutes.remainder(60)}m';
  }
}

class _LiveWorkRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String status;
  final bool failed;

  const _LiveWorkRow({
    required this.icon,
    required this.title,
    required this.status,
    this.subtitle,
    this.failed = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = failed
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            status,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
