// Cron job browser — list and manage Hermes scheduled cron jobs.
//
// API: GET /api/cron/jobs — returns JSON array of job objects
//      POST /api/cron/jobs/{id}/pause | resume | trigger
//      DELETE /api/cron/jobs/{id}
//      POST /api/cron/jobs — create new job
//      PUT /api/cron/jobs/{id} — update existing job
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../services/connection_manager.dart';

class CronScreen extends StatefulWidget {
  final SavedConnection connection;
  const CronScreen({required this.connection, super.key});

  @override
  State<CronScreen> createState() => _CronScreenState();
}

class _CronScreenState extends State<CronScreen> {
  late DashboardClient _client;
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = DashboardClient(
      host: widget.connection.host,
      port: widget.connection.dashboardPort,
      pathPrefix: widget.connection.dashboardPrefix ?? "",
      proxied: widget.connection.dashboardProxied,
      useHttps: widget.connection.useHttps,
      username: widget.connection.dashboardUsername,
      password: widget.connection.dashboardPassword,
    );
    _loadJobs();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _client.apiGetList('cron/jobs');
      final items = <Map<String, dynamic>>[];
      for (final item in data) {
        if (item is Map<String, dynamic>) items.add(item);
      }

      if (!mounted) return;
      setState(() {
        _jobs = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool _isPaused(Map<String, dynamic> job) {
    return job['paused_at'] != null ||
        job['state'] == 'paused' ||
        job['enabled'] == false;
  }

  String _scheduleDisplay(Map<String, dynamic> job) {
    final display = job['schedule_display'] as String?;
    if (display != null && display.isNotEmpty) return display;

    final schedule = job['schedule'];
    if (schedule is String) return schedule;
    if (schedule is Map) {
      return schedule['display'] as String? ??
          schedule['run_at'] as String? ??
          schedule.toString();
    }
    return '';
  }

  String _jobName(Map<String, dynamic> job) {
    return job['name'] as String? ?? job['id'] as String? ?? 'Untitled';
  }

  String _jobPrompt(Map<String, dynamic> job) {
    final prompt = job['prompt'] as String? ?? '';
    if (prompt.length > 120) return '${prompt.substring(0, 120)}…';
    return prompt;
  }

  Future<void> _togglePause(Map<String, dynamic> job) async {
    final jobId = job['id'] as String? ?? '';
    if (jobId.isEmpty) return;
    final paused = _isPaused(job);
    final action = paused ? 'resume' : 'pause';

    try {
      await _client.apiPost('cron/jobs/$jobId/$action');
      if (paused) {
        job.remove('paused_at');
        job['state'] = 'active';
        job['enabled'] = true;
      } else {
        job['paused_at'] = DateTime.now().toIso8601String();
        job['state'] = 'paused';
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(paused ? context.l10n.jobResumed : context.l10n.jobPaused)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.failed(e.toString())), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<void> _deleteJob(Map<String, dynamic> job) async {
    final jobId = job['id'] as String? ?? '';
    if (jobId.isEmpty) return;
    final name = _jobName(job);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteCronJob),
        content: Text(context.l10n.deleteJobConfirm(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _client.apiDelete('cron/jobs/$jobId');
      if (mounted) {
        setState(() => _jobs.removeWhere((j) => j['id'] == jobId));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.deletedJob(name))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.deleteFailed(e.toString())),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _triggerJob(Map<String, dynamic> job) async {
    final jobId = job['id'] as String? ?? '';
    if (jobId.isEmpty) return;
    try {
      await _client.apiPost('cron/jobs/$jobId/trigger');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.jobTriggered)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.failed(e.toString())), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<void> _showAddJobDialog() async {
    final result = await _showJobDialog(
      title: context.l10n.addCronJob,
      actionLabel: context.l10n.add,
    );
    if (result == null || !mounted) return;

    try {
      final created = await _client.createJob(
        name: result['name']?.toString() ?? '',
        prompt: result['prompt']?.toString() ?? '',
        schedule: result['schedule']?.toString() ?? '',
      );
      if (result['no_agent'] == true) {
        final jobId =
            created['id']?.toString() ?? created['job_id']?.toString() ?? '';
        if (jobId.isNotEmpty) {
          await _client.updateJob(jobId, {'no_agent': true});
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.cronJobAdded)));
      await _loadJobs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.failedToAddJob(e.toString())),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _showEditJobDialog(Map<String, dynamic> job) async {
    final result = await _showJobDialog(
      title: context.l10n.editCronJob,
      actionLabel: context.l10n.save,
      initialName: _jobName(job),
      initialPrompt: job['prompt'] as String? ?? '',
      initialSchedule: _scheduleDisplay(job),
      initialNoAgent: job['no_agent'] == true,
    );
    if (result == null || !mounted) return;

    final jobId = job['id'] as String? ?? '';
    if (jobId.isEmpty) return;

    try {
      await _client.updateJob(jobId, result);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.cronJobUpdated)));
      await _loadJobs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.failedToUpdateJob(e.toString())),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _showJobDialog({
    required String title,
    required String actionLabel,
    String initialName = '',
    String initialPrompt = '',
    String initialSchedule = '',
    bool initialNoAgent = false,
  }) async {
    final nameCtrl = TextEditingController(text: initialName);
    final promptCtrl = TextEditingController(text: initialPrompt);
    final scheduleCtrl = TextEditingController(text: initialSchedule);
    var noAgent = initialNoAgent;

    try {
      return await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.name,
                      hintText: context.l10n.egDailyBackup,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: promptCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.prompt,
                      hintText: context.l10n.whatShouldAgentDo,
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: scheduleCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.schedule,
                      hintText: context.l10n.egCronSchedule,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: noAgent,
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.l10n.scriptOnly),
                    subtitle: Text(context.l10n.scriptOnlyHelp),
                    onChanged: (value) => setDialogState(() => noAgent = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final prompt = promptCtrl.text.trim();
                  final schedule = scheduleCtrl.text.trim();

                  if (name.isEmpty || prompt.isEmpty || schedule.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.l10n.requiredFields,
                        ),
                      ),
                    );
                    return;
                  }

                  Navigator.pop(ctx, {
                    'name': name,
                    'prompt': prompt,
                    'schedule': schedule,
                    'no_agent': noAgent,
                  });
                },
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      );
    } finally {
      nameCtrl.dispose();
      promptCtrl.dispose();
      scheduleCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(context.l10n.cronJobs),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadJobs,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        tooltip: context.l10n.addNewCronJob,
        onPressed: _loading ? null : _showAddJobDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                context.l10n.failedToLoadCronJobs,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _loadJobs, child: Text(context.l10n.retry)),
            ],
          ),
        ),
      );
    }

    if (_jobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(context.l10n.noCronJobs, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadJobs,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _jobs.length,
        itemBuilder: (context, index) {
          final job = _jobs[index];
          final name = _jobName(job);
          final prompt = _jobPrompt(job);
          final schedule = _scheduleDisplay(job);
          final paused = _isPaused(job);
          final lastRun = job['last_run_at'] as String?;
          final nextRun = job['next_run_at'] as String?;
          final isNoAgent = job['no_agent'] == true;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => _showEditJobDialog(job),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          paused ? Icons.pause_circle : Icons.play_circle,
                          color: paused ? Colors.orange : Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isNoAgent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'script',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'trigger') _triggerJob(job);
                            if (action == 'edit') _showEditJobDialog(job);
                            if (action == 'toggle') _togglePause(job);
                            if (action == 'delete') _deleteJob(job);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'trigger',
                              child: Row(
                                children: [
                                  Icon(Icons.play_arrow, size: 18),
                                  SizedBox(width: 8),
                                  Text(context.l10n.triggerNow),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 18),
                                  SizedBox(width: 8),
                                  Text(context.l10n.edit),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'toggle',
                              child: Row(
                                children: [
                                  Icon(
                                    paused ? Icons.play_arrow : Icons.pause,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(paused ? context.l10n.resume : context.l10n.pause),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    context.l10n.delete,
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (prompt.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        prompt,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (schedule.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              schedule,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (lastRun != null && lastRun.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.lastRun(lastRun),
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                    if (nextRun != null && nextRun.isNotEmpty)
                      Text(
                        context.l10n.nextRun(nextRun),
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
