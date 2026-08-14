import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/l10n.dart';
import '../services/connection_manager.dart';
import '../services/desktop_gateway_client.dart';
import '../services/gateway_turn_application_controller.dart';
import '../services/ws_client.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'memory_screen.dart';
import 'cron_screen.dart';
import 'skills_screen.dart';

Future<String?> showSessionNameDialog({
  required BuildContext context,
  required String title,
  required String initialValue,
  required String actionLabel,
}) async {
  var draft = initialValue;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        initialValue: initialValue,
        autofocus: true,
        maxLength: 120,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onChanged: (value) => draft = value,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, draft.trim()),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
  return result?.trim().isEmpty == true ? null : result;
}

class SessionListScreen extends StatefulWidget {
  final SavedConnection connection;
  final GatewayTurnApplicationController turnApplicationController;

  const SessionListScreen({
    required this.connection,
    required this.turnApplicationController,
    super.key,
  });

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  late final ApiClient _client;
  DesktopGatewayClient? _desktopGateway;
  final _searchController = TextEditingController();
  List<SavedConnection> _profiles = const [];
  List<Session> _sessions = [];
  bool _loading = true;
  String? _error;
  bool _healthOk = false;
  final Set<String> _deletingSessionIds = {};
  final Set<String> _branchingSessionIds = {};

  @override
  void initState() {
    super.initState();
    _client = ApiClient(
      baseUrl: widget.connection.baseUrl,
      apiKey: widget.connection.apiKey,
      pathPrefix: widget.connection.gatewayPrefix ?? '',
    );
    if (widget.connection.desktopGatewayUrl?.trim().isNotEmpty == true) {
      try {
        _desktopGateway = DesktopGatewayClient.fromConnection(
          widget.connection,
        );
      } on ArgumentError {
        _desktopGateway = null;
      }
    }
    _loadProfiles();
    _checkHealth();
  }

  Future<void> _loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _profiles = ConnectionManager(prefs).getConnections());
  }

  Future<void> _switchProfile(String profileId) async {
    if (profileId == widget.connection.id) return;
    final profile = _profiles.where((item) => item.id == profileId).firstOrNull;
    if (profile == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_connection_id', profile.id);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SessionListScreen(
          connection: profile,
          turnApplicationController: widget.turnApplicationController,
        ),
      ),
    );
  }

  PopupMenuButton<String> _buildProfileSelector() {
    return PopupMenuButton<String>(
      tooltip: context.l10n.switchProfile,
      icon: const Icon(Icons.account_tree_outlined),
      onSelected: _switchProfile,
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(context.l10n.profile, style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        ..._profiles.map(
          (profile) => PopupMenuItem<String>(
            value: profile.id,
            child: Row(
              children: [
                Icon(
                  profile.id == widget.connection.id
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(profile.label, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _checkHealth() async {
    final ok = await _client.healthCheck();
    setState(() => _healthOk = ok);
    if (ok) _fetchSessions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _desktopGateway?.close();
    _client.close();
    super.dispose();
  }

  Future<String?> _askForName({
    required String title,
    required String initialValue,
    required String actionLabel,
  }) => showSessionNameDialog(
    context: context,
    title: title,
    initialValue: initialValue,
    actionLabel: actionLabel,
  );

  Future<void> _renameSession(Session session) async {
    final gateway = _desktopGateway;
    if (gateway == null) return;
    final title = await _askForName(
      title: context.l10n.renameChat,
      initialValue: session.title,
      actionLabel: context.l10n.rename,
    );
    if (title == null || !mounted) return;
    try {
      await gateway.renameSession(sessionId: session.id, title: title);
      await _fetchSessions();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.couldNotRenameChat(error.toString()))));
    }
  }

  Future<void> _branchSession(Session session) async {
    final gateway = _desktopGateway;
    if (gateway == null || _branchingSessionIds.contains(session.id)) return;
    final knownSessionIds = _sessions.map((item) => item.id).toSet();
    String? requestedName;
    setState(() => _branchingSessionIds.add(session.id));
    try {
      final name = await _askForName(
        title: context.l10n.branchChat,
        initialValue: context.l10n.sessionTitleBranch(session.title),
        actionLabel: context.l10n.createBranch,
      );
      if (name == null || !mounted) return;
      requestedName = name;
      await gateway.branchSession(sessionId: session.id, name: name);
      await _fetchSessions();
      if (!mounted) return;
      _showBranchCreated();
    } catch (error) {
      if (!mounted) return;
      await _fetchSessions();
      if (!mounted) return;
      final branchAppeared = _sessions.any(
        (item) =>
            !knownSessionIds.contains(item.id) &&
            requestedName != null &&
            item.title.trim().toLowerCase() ==
                requestedName.trim().toLowerCase(),
      );
      if (branchAppeared) {
        _showBranchCreated();
        return;
      }
      final message = error is JsonRpcError && error.code == 4008
          ? context.l10n.noMessagesInDesktopSession
          : context.l10n.couldNotBranchChat(error.toString());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _branchingSessionIds.remove(session.id));
      }
    }
  }

  void _showBranchCreated() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.branchCreated)),
    );
  }

  Future<void> _handleSessionAction(String action, Session session) async {
    // PopupMenuButton invokes this while its route is still being removed.
    // Defer route-producing actions so Flutter has completed that teardown.
    await Future<void>.delayed(kThemeAnimationDuration);
    if (!mounted) return;
    switch (action) {
      case 'rename':
        await _renameSession(session);
      case 'branch':
        await _branchSession(session);
      case 'delete':
        await _confirmDeleteSession(session);
    }
  }

  Future<void> _fetchSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await _client.getSessions();
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final key = 'excluded_session_sources_${widget.connection.id}';
      final excluded = prefs.getStringList(key) ?? [];
      final filtered = sessions
          .where((s) => !excluded.contains(s.source))
          .toList();
      if (!mounted) return;
      setState(() {
        _sessions = filtered;
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

  Future<void> _confirmDeleteSession(Session session) async {
    final title = session.title.trim().isEmpty
        ? context.l10n.untitledSession
        : session.title;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.deleteSessionTitle),
        content: Text(
          context.l10n.deleteSessionConfirm(title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteSession(session);
    }
  }

  Future<void> _deleteSession(Session session) async {
    if (_deletingSessionIds.contains(session.id)) return;
    setState(() => _deletingSessionIds.add(session.id));

    try {
      await _client.deleteSession(session.id);
      if (!mounted) return;
      setState(() {
        _sessions.removeWhere((item) => item.id == session.id);
        _deletingSessionIds.remove(session.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.sessionDeleted)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingSessionIds.remove(session.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.couldNotDeleteSession(e.toString()))));
    }
  }

  void _createNewSession() {
    final sessionId = GatewayChatClient.generateSessionId();
    final session = Session(
      id: sessionId,
      title: context.l10n.newChat,
      model: 'hermes-agent',
      source: 'mobile',
      messageCount: 0,
      isActive: true,
      preview: '',
      startedAt: DateTime.now().millisecondsSinceEpoch.toDouble() / 1000,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          connection: widget.connection,
          session: session,
          turnApplicationController: widget.turnApplicationController,
        ),
      ),
    );
  }

  String _formatTime(double ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt());
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month}';
  }

  void _openScreen(Widget screen) {
    Navigator.pop(context); // close drawer
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'HERMES',
          style: TextStyle(fontFamily: 'Cinzel', 
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
        actions: [
          _buildProfileSelector(),
          if (!_healthOk)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchSessions,
          ),
        ],
      ),
      drawer: _buildDrawer(),
      floatingActionButton: FloatingActionButton(
        tooltip: context.l10n.newChat,
        onPressed: _createNewSession,
        child: const Icon(Icons.chat, color: Colors.black),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Brand header in drawer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              color: Colors.black,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'HERMES',
                    style: TextStyle(fontFamily: 'Cinzel', 
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFD4AF37),
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.connection.label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.memory),
              title: Text(context.l10n.memoryTab),
              onTap: () =>
                  _openScreen(MemoryScreen(connection: widget.connection)),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(context.l10n.cronJobsTab),
              onTap: () =>
                  _openScreen(CronScreen(connection: widget.connection)),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text(context.l10n.skillsTab),
              onTap: () =>
                  _openScreen(SkillsScreen(connection: widget.connection)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text(context.l10n.settingsTab),
              onTap: () =>
                  _openScreen(SettingsScreen(connection: widget.connection)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_healthOk) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.connectingTo(widget.connection.baseUrl),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.gatewayMustBeRunning,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _checkHealth, child: Text(context.l10n.retry)),
          ],
        ),
      );
    }

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              context.l10n.connectionIssue,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fetchSessions,
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      );
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              context.l10n.noSessionsYet,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.tapPlusNewChat,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    final query = _searchController.text.trim().toLowerCase();
    final visibleSessions = query.isEmpty
        ? _sessions
        : _sessions
              .where(
                (session) =>
                    session.title.toLowerCase().contains(query) ||
                    session.preview.toLowerCase().contains(query) ||
                    session.model.toLowerCase().contains(query),
              )
              .toList();

    return RefreshIndicator(
      onRefresh: _fetchSessions,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: visibleSessions.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SearchBar(
                controller: _searchController,
                leading: const Icon(Icons.search),
                hintText: context.l10n.searchChats,
                trailing: [
                  if (query.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
                ],
                onChanged: (_) => setState(() {}),
              ),
            );
          }
          final session = visibleSessions[index - 1];
          final isDeleting = _deletingSessionIds.contains(session.id);
          final isBranching = _branchingSessionIds.contains(session.id);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              enabled: !isDeleting && !isBranching,
              leading: Icon(
                session.isActive ? Icons.chat : Icons.chat_bubble_outline,
                color: session.isActive ? const Color(0xFFD4AF37) : Colors.grey,
              ),
              trailing: isDeleting || isBranching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : PopupMenuButton<String>(
                      tooltip: context.l10n.chatActions,
                      onSelected: (action) =>
                          _handleSessionAction(action, session),
                      itemBuilder: (_) => [
                        if (_desktopGateway != null)
                          PopupMenuItem(
                            value: 'rename',
                            child: ListTile(
                              leading: Icon(Icons.edit_outlined),
                              title: Text(context.l10n.rename),
                            ),
                          ),
                        if (_desktopGateway != null)
                          PopupMenuItem(
                            value: 'branch',
                            child: ListTile(
                              leading: Icon(Icons.call_split_outlined),
                              title: Text(context.l10n.branch),
                            ),
                          ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text(context.l10n.delete),
                          ),
                        ),
                      ],
                    ),
              title: Text(
                session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.sessionMeta(session.messageCount, session.model, _formatTime(session.startedAt)),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (session.preview.isNotEmpty)
                    Text(
                      session.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
                    ),
                ],
              ),
              isThreeLine: session.preview.isNotEmpty,
              onLongPress: isDeleting ? null : () => _renameSession(session),
              onTap: isDeleting
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            connection: widget.connection,
                            session: session,
                            turnApplicationController:
                                widget.turnApplicationController,
                          ),
                        ),
                      );
                    },
            ),
          );
        },
      ),
    );
  }
}
