// Bot Mode's roster, natively.
//
// A bot is a Hermes profile. Its one permanent conversation is a hidden
// session titled exactly `Bot Chat`, resolved by title on every open — the
// client never stores a session id, so the relationship cannot dangle.
//
// Nothing here writes transcripts: the ChatScreen the roster opens does the
// real work, with `Session.profile` carrying the bot's scope.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

import '../models/bot_profile.dart';
import '../services/connection_manager.dart';
import '../services/desktop_gateway_client.dart';
import '../services/group_rooms_client.dart';
import '../theme/hermes_theme.dart';
import 'group_room_screen.dart';
import 'group_rooms_screen.dart';

/// Reads the roster. Injectable so the pane is testable without a gateway.
typedef BotsRosterLoader = Future<List<BotProfile>> Function();

/// Resolves (and, first time, creates) one bot's canonical chat.
typedef BotChatOpener = Future<Session> Function(BotProfile bot);

/// Reads the hosted-room roster shown beside the bots, like the desktop
/// roster's group rows. Injectable so the pane stays testable without a
/// gateway.
typedef BotsGroupsLoader = Future<GroupRoomPage> Function();

class BotsScreen extends StatefulWidget {
  final SavedConnection connection;

  /// The shared gateway client. Null only in tests, which inject [testLoader]
  /// and [testOpener] instead.
  final DesktopGatewayClient? client;

  /// True when this screen built the client itself and must close it.
  final bool ownsClient;

  /// Navigation stays with the host: it knows how to push a ChatScreen.
  final ValueChanged<Session>? onOpenSession;

  @visibleForTesting
  final BotsRosterLoader? testLoader;

  @visibleForTesting
  final BotChatOpener? testOpener;

  /// Poll cadence while visible — the desktop roster uses the same window.
  final Duration refreshInterval;

  @visibleForTesting
  final BotsGroupsLoader? testGroups;

  const BotsScreen({
    super.key,
    required this.connection,
    this.client,
    this.ownsClient = false,
    this.onOpenSession,
    this.testLoader,
    this.testOpener,
    this.testGroups,
    this.refreshInterval = const Duration(seconds: 5),
  });

  @override
  State<BotsScreen> createState() => _BotsScreenState();
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;

  const _SectionHeader({required this.icon, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HermesSpacing.md,
        HermesSpacing.md,
        HermesSpacing.md,
        HermesSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: HermesSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _BotsScreenState extends State<BotsScreen> {
  List<BotProfile> _bots = const [];
  List<GroupRoom> _groups = const [];
  bool _loading = true;
  String? _error;
  String? _groupsError;
  String? _opening;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(widget.refreshInterval, (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (widget.ownsClient) widget.client?.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final loader =
          widget.testLoader ??
          () => widget.client!.listProfiles();
      final bots = await loader();
      if (!mounted) return;
      setState(() {
        _bots = bots;
        _error = null;
        _loading = false;
      });
      await _loadGroups();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        // A later failure keeps the last roster behind the notice; only a
        // first read with nothing to show becomes an error state.
        _error = error.toString();
        _loading = false;
      });
    }
  }

  /// Rooms are listed next to the bots (desktop roster parity), so an existing
  /// group is one tap away instead of hidden behind the app-bar icon. A room
  /// failure never blanks the bot roster: it keeps its own error line.
  Future<void> _loadGroups() async {
    final injected = widget.testGroups;
    final client = widget.client;
    if (injected == null && client == null) return;
    try {
      final GroupRoomPage page;
      if (injected != null) {
        page = await injected();
      } else {
        final discovery = await GroupRoomsClient.forGateway(client!).discover();
        page = GroupRoomPage(rooms: discovery.rooms);
      }
      if (!mounted) return;
      setState(() {
        _groups = page.rooms;
        _groupsError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _groupsError = error.toString();
      });
    }
  }

  Future<void> _openGroup(GroupRoom room) async {
    final client = widget.client;
    if (client == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupRoomScreen(
          connection: widget.connection,
          room: room,
          rooms: GroupRoomsClient.forGateway(client),
        ),
      ),
    );
  }

  Future<void> _open(BotProfile bot) async {
    if (_opening != null) return;
    setState(() => _opening = bot.name);
    try {
      final opener =
          widget.testOpener ??
          (bot) => widget.client!.resolveBotChat(bot.name);
      final session = await opener(bot);
      if (!mounted) return;
      widget.onOpenSession?.call(session);
      if (mounted) Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.l10n.bot_chat_open_failed(error.toString())),
          ),
        );
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  /// Opens the hosted rooms list. Rooms are gateway-owned, so the same client
  /// is handed down unchanged — this screen keeps ownership of its socket.
  Future<void> _openGroupRooms() async {
    final client = widget.client;
    if (client == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupRoomsScreen(
          connection: widget.connection,
          client: client,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.bots),
        actions: [
          // Hosted group rooms live beside the roster: both are Bot Mode
          // surfaces, and the rooms client borrows the same socket.
          IconButton(
            tooltip: context.l10n.groups,
            icon: const Icon(Icons.groups_outlined),
            onPressed: widget.client == null
                ? null
                : () => unawaited(_openGroupRooms()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _bots.isEmpty && _groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_bots.isEmpty && _error != null) {
      return ListView(
        padding: const EdgeInsets.all(HermesSpacing.lg),
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: HermesSpacing.md),
          Text(
            context.l10n.bots_load_failed,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: HermesSpacing.sm),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: HermesSpacing.lg),
          Center(
            child: FilledButton(
              onPressed: _load,
              child: Text(context.l10n.retry),
            ),
          ),
        ],
      );
    }
    if (_bots.isEmpty && _groups.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(HermesSpacing.lg),
        children: [
          Icon(
            Icons.smart_toy_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: HermesSpacing.md),
          Text(
            context.l10n.bots_empty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: HermesSpacing.sm),
          Text(
            context.l10n.bots_subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }
    final theme = Theme.of(context);
    return ListView(
      children: [
        if (_groups.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.forum_outlined,
            label: context.l10n.groups,
            trailing: Text(
              '${_groups.length}',
              style: theme.textTheme.labelSmall,
            ),
          ),
          for (final room in _groups)
            ListTile(
              key: ValueKey('bots-group-${room.roomId}'),
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.tertiaryContainer,
                child: Text(
                  room.title.isEmpty
                      ? '?'
                      : room.title.substring(0, 1).toUpperCase(),
                  style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
                ),
              ),
              title: Text(room.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  context.l10n.group_members,
                  if (room.members.isNotEmpty)
                    room.members.map((member) => member.label).join(' · '),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.client == null
                  ? null
                  : () => unawaited(_openGroup(room)),
            ),
          const Divider(height: 1),
        ],
        if (_groupsError != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: HermesSpacing.md,
              vertical: HermesSpacing.sm,
            ),
            child: Text(
              context.l10n.failed(_groupsError!),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (_bots.isNotEmpty)
          _SectionHeader(
            icon: Icons.smart_toy_outlined,
            label: context.l10n.bots,
          ),
        for (final bot in _bots) ...[
          ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Text(bot.initial),
            ),
            title: Text(bot.title),
            subtitle: Text(
              [
                if (bot.model.trim().isNotEmpty) bot.model.trim(),
                if (bot.preview.isNotEmpty) bot.preview,
                if (bot.preview.isEmpty && bot.description.isNotEmpty)
                  bot.description,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _opening == bot.name
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _opening == bot.name ? null : () => unawaited(_open(bot)),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}
