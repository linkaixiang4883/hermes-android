// Hosted group rooms, listed.
//
// Rooms are server-owned (`groups.list`), so this pane is a 5s poll and a
// create sheet — no local persistence, no session bookkeeping. Opening a room
// hands the gateway room to [GroupRoomScreen], which owns the log cursor.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

import '../services/connection_manager.dart';
import '../services/desktop_gateway_client.dart';
import '../services/group_rooms_client.dart';
import '../theme/hermes_theme.dart';
import 'group_room_screen.dart';

/// Reads one page of rooms. Injectable for tests and for a host that caches.
typedef GroupRoomsLoader = Future<GroupRoomPage> Function();

/// Reads the seating roster (`capabilities.seatable_profiles`).
typedef GroupCapabilitiesLoader = Future<GroupCapabilities> Function();

/// Creates a room. The id is minted by the caller and reused on retry.
typedef GroupRoomCreator =
    Future<GroupRoom> Function({
      required String roomId,
      required String name,
      required List<GroupRoomMember> members,
    });

class GroupRoomsScreen extends StatefulWidget {
  final SavedConnection connection;

  /// Typed gateway client. Built from [client] when null.
  final GroupRoomsClient? rooms;

  /// Shared desktop-gateway client; the rooms client borrows its socket.
  final DesktopGatewayClient? client;

  /// Host-supplied navigation, so this screen can stay a plain page.
  final ValueChanged<GroupRoom>? onOpenRoom;

  /// Poll cadence while visible — the desktop room list uses the same window.
  final Duration refreshInterval;

  @visibleForTesting
  final GroupRoomsLoader? testLoader;

  @visibleForTesting
  final GroupCapabilitiesLoader? testCapabilities;

  @visibleForTesting
  final GroupRoomCreator? testCreate;

  const GroupRoomsScreen({
    super.key,
    required this.connection,
    this.rooms,
    this.client,
    this.onOpenRoom,
    this.refreshInterval = const Duration(seconds: 5),
    this.testLoader,
    this.testCapabilities,
    this.testCreate,
  }) : assert(
         rooms != null || client != null || testLoader != null,
         'GroupRoomsScreen needs a rooms client, a gateway client, or a test loader',
       );

  @override
  State<GroupRoomsScreen> createState() => _GroupRoomsScreenState();
}

class _GroupRoomsScreenState extends State<GroupRoomsScreen> {
  List<GroupRoom> _rooms = const [];
  GroupCapabilities? _capabilities;
  bool _loading = true;
  bool _creating = false;
  String? _error;

  /// Null until a live discovery answers; a test loader leaves it unknown.
  bool? _driverAvailable;
  Timer? _poll;

  GroupRoomsClient? _roomsClient;

  @override
  void initState() {
    super.initState();
    _roomsClient = widget.rooms ??
        (widget.client == null
            ? null
            : GroupRoomsClient.forGateway(widget.client!));
    unawaited(_load());
    _poll = Timer.periodic(widget.refreshInterval, (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<GroupRoomPage> _readRooms() async {
    final injected = widget.testLoader;
    if (injected != null) return injected();
    final discovery = await _roomsClient!.discover();
    _driverAvailable = discovery.driverAvailable;
    return GroupRoomPage(rooms: discovery.rooms);
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final page = await _readRooms();
      if (!mounted) return;
      setState(() {
        _rooms = page.rooms;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        // Keep the last listing behind the notice; only a first read with
        // nothing to show becomes a full error state.
        _error = error.toString();
        _loading = false;
      });
    }
  }

  /// Loaded lazily: the create sheet is the only consumer, and a gateway
  /// without `groups.capabilities` must not break the list.
  Future<GroupCapabilities?> _loadCapabilities() async {
    final cached = _capabilities;
    if (cached != null) return cached;
    final loader = widget.testCapabilities ?? () => _roomsClient!.capabilities();
    try {
      final loaded = await loader();
      if (!mounted) return loaded;
      setState(() => _capabilities = loaded);
      return loaded;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openCreate() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final capabilities = await _loadCapabilities();
      if (!mounted) return;
      final draft = await showDialog<_NewRoomDraft>(
        context: context,
        builder: (_) => _CreateRoomDialog(
          seatableProfiles: capabilities?.seatableProfiles ?? const [],
        ),
      );
      if (draft == null || !mounted) return;
      final creator = widget.testCreate ?? _createOnGateway;
      final created = await creator(
        roomId: newGroupIdentifier(),
        name: draft.name,
        members: [
          for (final profile in draft.profiles)
            GroupRoomMember(
              profile: profile,
              handle: profile,
              displayName: profile,
            ),
        ],
      );
      if (!mounted) return;
      setState(() {
        _rooms = [
          created,
          for (final room in _rooms)
            if (room.roomId != created.roomId) room,
        ];
        _error = null;
      });
      unawaited(_load());
    } catch (error) {
      if (!mounted) return;
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<GroupRoom> _createOnGateway({
    required String roomId,
    required String name,
    required List<GroupRoomMember> members,
  }) {
    return _roomsClient!.create(
      roomId: roomId,
      name: name,
      members: members,
    );
  }

  Future<void> _open(GroupRoom room) async {
    final host = widget.onOpenRoom;
    if (host != null) {
      host(room);
      return;
    }
    final client = _roomsClient;
    if (client == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupRoomScreen(
          connection: widget.connection,
          rooms: client,
          room: room,
        ),
      ),
    );
    if (mounted) unawaited(_load());
  }

  void _showError(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(context.l10n.failed(message))),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.groups)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating ? null : () => unawaited(_openCreate()),
        icon: _creating
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(context.l10n.group_new),
      ),
      body: Column(
        children: [
          if (_driverAvailable == false)
            _DriverOfflineStrip(
              key: const ValueKey('group-driver-offline'),
              text: context.l10n.group_driver_offline,
            ),
          Expanded(
            child: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading && _rooms.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rooms.isEmpty && _error != null) {
      return ListView(
        padding: const EdgeInsets.all(HermesSpacing.lg),
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 44,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: HermesSpacing.md),
          Text(
            context.l10n.failed(''),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: HermesSpacing.sm),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: HermesSpacing.lg),
          Center(
            child: FilledButton(
              onPressed: () => unawaited(_load()),
              child: Text(context.l10n.retry),
            ),
          ),
        ],
      );
    }
    if (_rooms.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(HermesSpacing.lg),
        children: [
          Icon(
            Icons.forum_outlined,
            size: 44,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: HermesSpacing.md),
          Text(
            context.l10n.group_empty,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: _rooms.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final room = _rooms[index];
        final members = room.members.map((member) => member.label).toList();
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: room.isDisbanded
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.secondaryContainer,
            child: Icon(
              room.isDisbanded ? Icons.group_off_outlined : Icons.groups_outlined,
              size: 20,
            ),
          ),
          title: Text(
            room.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: room.isDisbanded
                ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
                : null,
          ),
          subtitle: Text(
            members.isEmpty
                ? context.l10n.group_members
                : members.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: room.isDisbanded
              ? Text(
                  context.l10n.group_disbanded,
                  style: theme.textTheme.labelSmall,
                )
              : const Icon(Icons.chevron_right),
          onTap: () => unawaited(_open(room)),
        );
      },
    );
  }
}

class _NewRoomDraft {
  final String name;
  final List<String> profiles;

  const _NewRoomDraft(this.name, this.profiles);
}

/// Name + seating. The room id is not asked for: it is a UUID minted by the
/// caller, because `groups.create` is idempotent on it and a human-chosen id
/// would collide across attempts.
class _CreateRoomDialog extends StatefulWidget {
  final List<String> seatableProfiles;

  const _CreateRoomDialog({required this.seatableProfiles});

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  late final TextEditingController _name = TextEditingController();
  final Set<String> _selected = {};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _name.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(context.l10n.group_new),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: context.l10n.name),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: HermesSpacing.lg),
            Text(
              context.l10n.group_members,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: HermesSpacing.sm),
            Wrap(
              spacing: HermesSpacing.sm,
              runSpacing: HermesSpacing.xs,
              children: [
                for (final profile in widget.seatableProfiles)
                  FilterChip(
                    label: Text(profile),
                    selected: _selected.contains(profile),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _selected.add(profile);
                      } else {
                        _selected.remove(profile);
                      }
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: canCreate
              ? () => Navigator.of(context).pop(
                    _NewRoomDraft(_name.text.trim(), _selected.toList()),
                  )
              : null,
          child: Text(context.l10n.create),
        ),
      ],
    );
  }
}

/// The gateway answered `groups.capabilities` with `driver: false`: rooms may
/// exist but no member will ever answer. Say so instead of letting the user
/// type into a dead room.
class _DriverOfflineStrip extends StatelessWidget {
  final String text;

  const _DriverOfflineStrip({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HermesSpacing.md,
          vertical: HermesSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              Icons.portable_wifi_off_outlined,
              size: 16,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: HermesSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
