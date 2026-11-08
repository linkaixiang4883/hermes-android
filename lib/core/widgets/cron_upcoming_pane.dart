/// The **Upcoming** half of the Crons destination.
///
/// Reads scheduled job definitions from the cron manager's dashboard route
/// (`GET /api/cron/jobs`) and shows what will run. Run output stays in the
/// History view, and all creation/editing stays in `CronScreen`; this pane is
/// a reader plus a link to that manager. No message or approval transport is
/// involved.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

import '../services/connection_manager.dart';
import '../services/connection_rest_client.dart';
import '../theme/hermes_theme.dart';
import '../utils/cron_schedule.dart';
import 'hermes_shell.dart';

typedef CronJobsLoader = Future<List<Map<String, dynamic>>> Function();

const Key kCronUpcomingListKey = Key('cron-upcoming-list');

class CronUpcomingPane extends StatefulWidget {
  const CronUpcomingPane({
    required this.connection,
    this.loadJobs,
    this.active = true,
    this.refreshInterval,
    this.onOpenManager,
    super.key,
  });

  final SavedConnection connection;

  /// Test seam; production reads through [DashboardClient.getCronJobs].
  final CronJobsLoader? loadJobs;

  /// Whether the host's destination is selected.
  final bool active;

  /// Periodic refresh while visible. Null disables it.
  final Duration? refreshInterval;

  /// Opens the full cron manager, which owns every schedule mutation.
  final VoidCallback? onOpenManager;

  @override
  State<CronUpcomingPane> createState() => CronUpcomingPaneState();
}

class CronUpcomingPaneState extends State<CronUpcomingPane>
    with WidgetsBindingObserver {
  DashboardClient? _client;
  Object? _clientError;
  List<Map<String, dynamic>>? _jobs;
  String? _error;
  bool _loading = false;
  bool _visible = false;
  Timer? _timer;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openClient();
  }

  void _openClient() {
    if (widget.loadJobs != null || !usesDashboardRest(widget.connection)) return;
    try {
      _client = DashboardClient(
        host: widget.connection.host,
        port: widget.connection.dashboardPort,
        pathPrefix: widget.connection.dashboardPrefix ?? '',
        proxied: widget.connection.dashboardProxied,
        useHttps: widget.connection.useHttps,
        username: widget.connection.dashboardUsername,
        password: widget.connection.dashboardPassword,
        gatewayProfile: widget.connection.gatewayProfile,
      );
      _clientError = null;
    } catch (error) {
      _client = null;
      _clientError = error;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncVisibility();
  }

  @override
  void didUpdateWidget(CronUpcomingPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final connectionChanged = !identical(
      oldWidget.connection,
      widget.connection,
    );
    if (connectionChanged) {
      ++_generation;
      _client?.close();
      _client = null;
      _clientError = null;
      _jobs = null;
      _error = null;
      _loading = false;
      _openClient();
    }
    _syncVisibility(resetTimer: connectionChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _syncVisibility();

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    _client?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _computeVisible() {
    if (!widget.active) return false;
    if (!HermesPaneVisibility.of(context)) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  void _syncVisibility({bool resetTimer = false}) {
    final visible = _computeVisible();
    final becameVisible = visible && !_visible;
    if (visible == _visible && !resetTimer) return;
    _visible = visible;
    _timer?.cancel();
    _timer = null;
    if (!visible) return;
    if ((becameVisible || _jobs == null) && !_loading) unawaited(_load());
    final interval = widget.refreshInterval;
    if (interval != null && interval > Duration.zero) {
      _timer = Timer.periodic(interval, (_) {
        if (_visible && !_loading) unawaited(_load());
      });
    }
  }

  /// Re-reads the schedule. Used when returning from the cron manager.
  Future<void> refresh() {
    if (!mounted || !_computeVisible()) return Future<void>.value();
    return _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loadJobs;
      final client = _client;
      if (loader == null && client == null) {
        throw _clientError ?? StateError('No Dashboard connection');
      }
      final jobs = loader != null ? await loader() : await client!.getCronJobs();
      if (!mounted || generation != _generation) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Widget _managerButton() {
    final onOpenManager = widget.onOpenManager;
    if (onOpenManager == null) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: onOpenManager,
      icon: const Icon(Icons.tune, size: 18),
      label: Text(context.l10n.cron_open_manager),
    );
  }

  Widget _message({
    required IconData icon,
    required String message,
    bool retry = false,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(HermesSpacing.xl),
      children: [
        const SizedBox(height: HermesSpacing.xxl),
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: HermesSpacing.lg),
        Text(message, textAlign: TextAlign.center),
        if (retry) ...[
          const SizedBox(height: HermesSpacing.lg),
          Center(
            child: ElevatedButton(
              onPressed: _load,
              child: Text(context.l10n.retry),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loadJobs == null && !usesDashboardRest(widget.connection)) {
      return _message(
        icon: Icons.dashboard_outlined,
        message: context.l10n.cron_needs_dashboard,
      );
    }

    final jobs = _jobs;
    if (jobs == null) {
      if (_error != null) {
        return RefreshIndicator(
          onRefresh: refresh,
          child: _message(
            icon: Icons.error_outline,
            message: context.l10n.failed_to_load_cron_jobs,
            retry: true,
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(alignment: Alignment.centerRight, child: _managerButton()),
        Expanded(
          child: RefreshIndicator(
            onRefresh: refresh,
            child: jobs.isEmpty
                ? _message(
                    icon: Icons.schedule_outlined,
                    message: context.l10n.cron_upcoming_empty,
                  )
                : ListView.separated(
                    key: kCronUpcomingListKey,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      HermesSpacing.lg,
                      0,
                      HermesSpacing.lg,
                      HermesSpacing.xl,
                    ),
                    itemCount: jobs.length + (_error == null ? 0 : 1),
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: HermesSpacing.sm),
                    itemBuilder: (context, index) {
                      if (_error != null && index == 0) {
                        return _StaleNotice(message: _error!);
                      }
                      return _CronJobCard(
                        job: jobs[index - (_error == null ? 0 : 1)],
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(HermesSpacing.md),
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

class _CronJobCard extends StatelessWidget {
  const _CronJobCard({required this.job});

  final Map<String, dynamic> job;

  String get _name {
    final name = job['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    return job['id']?.toString() ?? '—';
  }

  bool get _paused =>
      job['enabled'] == false ||
      job['state'] == 'paused' ||
      job['paused_at'] != null;

  String get _prompt {
    final prompt = job['prompt'];
    if (prompt is! String) return '';
    final trimmed = prompt.trim();
    return trimmed.length > 160 ? '${trimmed.substring(0, 160)}…' : trimmed;
  }

  String get _deliver {
    final deliver = job['deliver'];
    return deliver is String ? deliver.trim() : '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final schedule = cronScheduleDisplay(job);
    final nextRun = parseCronNextRun(job['next_run_at']);
    final statusColor = _paused
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(HermesSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _paused ? Icons.pause_circle_outline : Icons.schedule,
                  color: statusColor,
                  size: 20,
                ),
                const SizedBox(width: HermesSpacing.sm),
                Expanded(
                  child: Text(
                    _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HermesSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _paused
                        ? context.l10n.cron_status_paused
                        : context.l10n.cron_status_enabled,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (schedule.isNotEmpty) ...[
              const SizedBox(height: HermesSpacing.sm),
              Row(
                children: [
                  Icon(
                    Icons.repeat,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: HermesSpacing.xs),
                  Expanded(
                    child: Text(
                      '${context.l10n.schedule}: $schedule',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: HermesSpacing.xs),
            Text(
              _nextRunText(context, nextRun),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_prompt.isNotEmpty) ...[
              const SizedBox(height: HermesSpacing.xs),
              Text(
                _prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_deliver.isNotEmpty) ...[
              const SizedBox(height: HermesSpacing.xs),
              Text(
                context.l10n.cron_deliver_to(_deliver),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _nextRunText(BuildContext context, CronNextRun? nextRun) {
    if (nextRun == null) return context.l10n.cron_no_next_run;
    final zone = nextRun.zoneLabel ?? context.l10n.cron_timezone_unknown;
    return '${context.l10n.next(nextRun.wallClock)} ($zone)';
  }
}
