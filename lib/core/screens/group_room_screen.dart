// One hosted group room: transcript, driver notices, and the human's half of
// the protocol (send / approve / retry / stop / rename / disband).
//
// The gateway owns the room and its event log, so this screen is a cursor
// reader: `groups.state` once for the room + driver status, then
// `groups.log {since_seq}` every 2s (the desktop's cadence). Nothing is
// optimistically invented — a message appears when the server's log says so,
// which keeps retries and multi-client reads identical.
//
// Sending is single-flight and idempotent: the event id is minted before the
// first attempt, persisted, and reused verbatim when the same text is retried,
// so a lost response never becomes two messages.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

import '../services/connection_manager.dart';
import '../services/group_rooms_client.dart';
import '../theme/hermes_theme.dart';

typedef GroupRoomStateLoader = Future<GroupRoomState> Function();
typedef GroupRoomLogLoader = Future<GroupLogPage> Function(int sinceSeq);

typedef GroupMessageSender =
    Future<GroupSendResult> Function({
      required String eventId,
      required String text,
    });

typedef GroupApprovalAction =
    Future<void> Function(PendingRoomAction action, String choice);
typedef GroupRetryAction = Future<void> Function(PendingRoomAction action);
typedef GroupContinueAction = Future<void> Function(String discussionEventId);
typedef GroupDiscardAction = Future<void> Function(PendingRoomAction action);
typedef GroupRoomAction = Future<void> Function();

/// A message that was submitted but never confirmed. It keeps its event id so
/// the retry is the server's no-op instead of a duplicate.
class PendingGroupSend {
  final String eventId;
  final String text;

  const PendingGroupSend({required this.eventId, required this.text});
}

/// Device-local journal of the one in-flight message per room.
abstract class GroupPendingSendStore {
  Future<PendingGroupSend?> read(String roomId);

  Future<void> save(String roomId, PendingGroupSend pending);

  Future<void> clear(String roomId);
}

/// [SharedPreferences] implementation, namespaced by connection so two
/// gateways with the same room id never inherit each other's event id.
class PrefsGroupPendingSendStore implements GroupPendingSendStore {
  final String connectionId;

  const PrefsGroupPendingSendStore({required this.connectionId});

  String _key(String roomId) {
    final namespace = base64Url
        .encode(utf8.encode('$connectionId\u0000$roomId'))
        .replaceAll('=', '');
    return 'group_pending_send.$namespace';
  }

  @override
  Future<PendingGroupSend?> read(String roomId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(roomId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final eventId = (decoded['event_id'] ?? '').toString();
      final text = (decoded['text'] ?? '').toString();
      if (eventId.isEmpty || text.trim().isEmpty) return null;
      return PendingGroupSend(eventId: eventId, text: text);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(String roomId, PendingGroupSend pending) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(roomId),
        jsonEncode({'event_id': pending.eventId, 'text': pending.text}),
      );
    } catch (_) {
      // Best effort: a failed journal write must not block the send.
    }
  }

  @override
  Future<void> clear(String roomId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(roomId));
    } catch (_) {
      // Best effort.
    }
  }
}

/// In-memory journal, for tests and hosts that do not want persistence.
class MemoryGroupPendingSendStore implements GroupPendingSendStore {
  final Map<String, PendingGroupSend> _pending = {};

  @override
  Future<PendingGroupSend?> read(String roomId) async => _pending[roomId];

  @override
  Future<void> save(String roomId, PendingGroupSend pending) async {
    _pending[roomId] = pending;
  }

  @override
  Future<void> clear(String roomId) async {
    _pending.remove(roomId);
  }
}

class GroupRoomScreen extends StatefulWidget {
  final SavedConnection connection;

  /// Typed gateway client; required unless the actions are injected.
  final GroupRoomsClient? rooms;

  /// The room to open, as the list last saw it.
  final GroupRoom room;

  /// Capabilities the host already read. When null the room reads them once.
  final GroupCapabilities? capabilities;

  /// Discussion thread the message belongs to; defaults to the room id.
  final String? threadId;

  /// Desktop-matching cadence for the incremental log read.
  final Duration pollInterval;

  /// Optional journal override (tests inject [MemoryGroupPendingSendStore]).
  final GroupPendingSendStore? pendingStore;

  @visibleForTesting
  final GroupRoomStateLoader? testStateLoader;

  @visibleForTesting
  final GroupRoomLogLoader? testLogLoader;

  @visibleForTesting
  final GroupMessageSender? testSender;

  @visibleForTesting
  final GroupApprovalAction? testApproval;

  @visibleForTesting
  final GroupRetryAction? testRetry;

  @visibleForTesting
  final Future<GroupCapabilities?> Function()? testCapabilities;

  @visibleForTesting
  final GroupContinueAction? testContinue;

  @visibleForTesting
  final GroupDiscardAction? testDiscard;

  @visibleForTesting
  final GroupRoomAction? testStop;

  @visibleForTesting
  final GroupRoomAction? testDisband;

  @visibleForTesting
  final Future<void> Function(String name)? testRename;

  const GroupRoomScreen({
    super.key,
    required this.connection,
    required this.room,
    this.rooms,
    this.capabilities,
    this.threadId,
    this.pollInterval = const Duration(seconds: 2),
    this.pendingStore,
    this.testStateLoader,
    this.testLogLoader,
    this.testSender,
    this.testApproval,
    this.testRetry,
    this.testCapabilities,
    this.testContinue,
    this.testDiscard,
    this.testStop,
    this.testDisband,
    this.testRename,
  }) : assert(
         rooms != null || testStateLoader != null,
         'GroupRoomScreen needs a rooms client or an injected state loader',
       );

  @override
  State<GroupRoomScreen> createState() => _GroupRoomScreenState();
}

class _GroupRoomScreenState extends State<GroupRoomScreen> {
  late GroupRoom _room = widget.room;
  RoomDriverStatus? _driver;
  RoomContext? _context;
  GroupCapabilities? _capabilities;
  final List<GroupEvent> _events = [];
  final Set<int> _seen = {};
  int _cursor = 0;

  bool _bootstrapped = false;
  bool _loading = true;
  bool _polling = false;
  bool _sending = false;
  bool _menuBusy = false;
  bool _continuing = false;
  int _ticks = 0;
  String? _error;

  String? _pendingEventId;
  String? _pendingText;
  String? _stopCancelId;
  String? _disbandCancelId;
  final Set<String> _busyActions = {};

  Timer? _poll;
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late final GroupPendingSendStore _store;

  String get _roomId => _room.roomId;

  GroupRoomStateLoader get _stateLoader =>
      widget.testStateLoader ?? () => widget.rooms!.state(_roomId);

  GroupRoomLogLoader get _logLoader =>
      widget.testLogLoader ??
      (sinceSeq) => widget.rooms!.log(_roomId, sinceSeq: sinceSeq);

  GroupMessageSender get _sender =>
      widget.testSender ??
      ({required eventId, required text}) => widget.rooms!.send(
            roomId: _roomId,
            eventId: eventId,
            text: text,
            threadId: widget.threadId?.trim().isNotEmpty == true
                ? widget.threadId!.trim()
                : _roomId,
          );

  GroupApprovalAction get _approval =>
      widget.testApproval ??
      (action, choice) => widget.rooms!.approve(
            roomId: _roomId,
            action: action,
            choice: choice,
          );

  GroupRetryAction get _retry =>
      widget.testRetry ??
      (action) => widget.rooms!.retry(
            roomId: _roomId,
            taskId: action.taskId,
            memberId: action.memberId,
            executionGeneration: action.executionGeneration,
          );

  GroupContinueAction get _continue =>
      widget.testContinue ??
      (discussionEventId) => widget.rooms!.continueDiscussion(
            roomId: _roomId,
            discussionEventId: discussionEventId,
          );

  GroupDiscardAction get _discard =>
      widget.testDiscard ??
      (action) => widget.rooms!.discard(roomId: _roomId, action: action);

  GroupRoomAction get _stop =>
      widget.testStop ??
      () => widget.rooms!.stop(_roomId, cancelId: _stopCancelId);

  GroupRoomAction get _disband =>
      widget.testDisband ??
      () => widget.rooms!.disband(_roomId, cancelId: _disbandCancelId);

  Future<void> Function(String name) get _rename =>
      widget.testRename ??
      (name) => widget.rooms!.rename(
            roomId: _roomId,
            name: name,
            eventId: newGroupIdentifier(),
          );

  @override
  void initState() {
    super.initState();
    _store =
        widget.pendingStore ??
        PrefsGroupPendingSendStore(connectionId: widget.connection.id);
    unawaited(_bootstrap());
    _poll = Timer.periodic(widget.pollInterval, (_) => unawaited(_tick()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Reading the room ───────────────────────────────────────────────────

  Future<void> _loadCapabilities() async {
    final seeded = widget.capabilities;
    if (seeded != null) {
      if (mounted) setState(() => _capabilities = seeded);
      return;
    }
    final Future<GroupCapabilities?>? pending = widget.testCapabilities != null
        ? widget.testCapabilities!()
        : widget.rooms?.capabilities();
    if (pending == null) return;
    try {
      final loaded = await pending;
      if (mounted) setState(() => _capabilities = loaded);
    } catch (_) {
      // A capability read is advisory; the room itself may still work.
      if (mounted) setState(() => _capabilities = null);
    }
  }

  Future<void> _bootstrap() async {
    try {
      final state = await _stateLoader();
      if (!mounted) return;
      setState(() {
        _room = state.room;
        _driver = state.driverStatus;
        _context = state.context;
      });
      await _loadCapabilities();
      if (!mounted) return;
      await _loadHistory();
      if (!mounted) return;
      setState(() {
        _bootstrapped = true;
        _loading = false;
        _error = null;
      });
      await _restorePending();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  /// Reads the backlog once, then switches to increments. A long room is
  /// paged but bounded: the transcript is a chat, not an archive browser.
  Future<void> _loadHistory() async {
    final collected = <GroupEvent>[];
    var since = 0;
    var cursor = 0;
    for (var page = 0; page < 5; page++) {
      final loaded = await _logLoader(since);
      collected.addAll(loaded.events);
      if (loaded.cursor > 0) cursor = loaded.cursor;
      final lastSeq = collected.isEmpty ? 0 : collected.last.seq;
      if (!loaded.hasMore || lastSeq <= since) break;
      since = lastSeq;
    }
    if (!mounted) return;
    setState(() {
      _events
        ..clear()
        ..addAll(collected);
      _seen
        ..clear()
        ..addAll(collected.map((event) => event.seq));
      if (cursor > 0) _cursor = cursor;
    });
    _scrollToBottom(animate: false);
  }

  Future<void> _tick() async {
    if (!mounted || !_bootstrapped || _polling) return;
    await _pollLog();
    _ticks++;
    // Driver status drives approval cards; the log is what must be live, so
    // status is refreshed less often (every ~6s at the 2s cadence).
    if (_ticks % 3 == 0) unawaited(_pollState());
  }

  Future<void> _pollLog() async {
    if (_polling) return;
    _polling = true;
    try {
      final loaded = await _logLoader(_cursor);
      if (!mounted) return;
      final fresh = [
        for (final event in loaded.events)
          if (_seen.add(event.seq)) event,
      ];
      setState(() {
        _events.addAll(fresh);
        if (loaded.cursor > _cursor) _cursor = loaded.cursor;
        _error = null;
      });
      if (fresh.isNotEmpty) _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      _polling = false;
    }
  }

  Future<void> _pollState() async {
    try {
      final state = await _stateLoader();
      if (!mounted) return;
      setState(() {
        _room = state.room;
        _driver = state.driverStatus;
        _context = state.context;
      });
    } catch (_) {
      // A status read is advisory; the log poll reports real trouble.
    }
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  // ── Sending ────────────────────────────────────────────────────────────

  Future<void> _restorePending() async {
    final pending = await _store.read(_roomId);
    if (!mounted || pending == null) return;
    setState(() {
      _pendingEventId = pending.eventId;
      _pendingText = pending.text;
      if (_composer.text.trim().isEmpty) {
        _composer.text = pending.text;
        _composer.selection = TextSelection.collapsed(
          offset: _composer.text.length,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending || _room.isDisbanded) return;
    // Same text after a failure = same message: keep its id so the server's
    // (room_id, event_id) idempotency collapses the retry instead of doubling.
    final eventId = _pendingText == text && _pendingEventId != null
        ? _pendingEventId!
        : newGroupIdentifier();
    setState(() {
      _sending = true;
      _pendingEventId = eventId;
      _pendingText = text;
    });
    unawaited(
      _store.save(_roomId, PendingGroupSend(eventId: eventId, text: text)),
    );
    try {
      final result = await _sender(eventId: eventId, text: text);
      if (!mounted) return;
      if (!result.accepted) {
        _showNotice(context.l10n.group_send_failed('rejected'));
        return;
      }
      _composer.clear();
      await _store.clear(_roomId);
      if (!mounted) return;
      setState(() {
        _pendingEventId = null;
        _pendingText = null;
      });
      final event = result.event;
      if (event != null && _seen.add(event.seq)) {
        setState(() => _events.add(event));
        _scrollToBottom();
      }
      unawaited(_pollLog());
      unawaited(_pollState());
    } catch (error) {
      if (!mounted) return;
      // The id stays journaled: the next attempt replays it verbatim.
      _showNotice(context.l10n.group_send_failed(error.toString()));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Driver actions ─────────────────────────────────────────────────────

  Future<void> _runApproval(PendingRoomAction action, String choice) async {
    if (!_busyActions.add(action.identity)) return;
    setState(() {});
    try {
      await _approval(action, choice);
      unawaited(_pollState());
    } catch (error) {
      if (mounted) _showNotice(context.l10n.failed(error.toString()));
    } finally {
      if (mounted) {
        setState(() => _busyActions.remove(action.identity));
      }
    }
  }

  Future<void> _runRetry(PendingRoomAction action) async {
    if (!_busyActions.add(action.identity)) return;
    setState(() {});
    try {
      await _retry(action);
      unawaited(_pollState());
    } catch (error) {
      if (mounted) _showNotice(context.l10n.failed(error.toString()));
    } finally {
      if (mounted) {
        setState(() => _busyActions.remove(action.identity));
      }
    }
  }

  bool _offers(String method) =>
      _capabilities != null && _capabilities!.supports(method);

  Future<void> _runContinue(GroupEvent event) async {
    if (_continuing) return;
    setState(() => _continuing = true);
    try {
      await _continue(event.discussionEventId);
      if (!mounted) return;
      _showNotice(context.l10n.group_continued);
      unawaited(_pollLog());
      unawaited(_pollState());
    } catch (error) {
      if (mounted) _showNotice(context.l10n.failed(error.toString()));
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  Future<void> _confirmDiscard(PendingRoomAction action) async {
    if (_busyActions.contains(action.identity)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.group_discard),
        content: Text(context.l10n.group_discard_confirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('group-discard-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.group_discard),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runDiscard(action);
  }

  Future<void> _runDiscard(PendingRoomAction action) async {
    if (!_busyActions.add(action.identity)) return;
    setState(() {});
    try {
      await _discard(action);
      if (!mounted) return;
      _showNotice(context.l10n.group_discarded);
      unawaited(_pollState());
    } catch (error) {
      if (mounted) _showNotice(context.l10n.failed(error.toString()));
    } finally {
      if (mounted) {
        setState(() => _busyActions.remove(action.identity));
      }
    }
  }

  Future<void> _confirmStop() async {
    if (_menuBusy || _room.isDisbanded) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${context.l10n.stop} · ${_room.title}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.stop),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _stopCancelId = newGroupIdentifier();
    setState(() => _menuBusy = true);
    try {
      await _stop();
      if (!mounted) return;
      _stopCancelId = null;
      _showNotice(context.l10n.group_stopped);
      unawaited(_pollState());
    } catch (error) {
      if (mounted) _showNotice(context.l10n.failed(error.toString()));
    } finally {
      if (mounted) setState(() => _menuBusy = false);
    }
  }

  Future<void> _confirmDisband() async {
    if (_menuBusy || _room.isDisbanded) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${context.l10n.group_disbanded} · ${_room.title}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _disbandCancelId = newGroupIdentifier();
    setState(() => _menuBusy = true);
    try {
      await _disband();
      if (!mounted) return;
      _disbandCancelId = null;
      setState(() {
        _room = _room.copyWith(
          disbandedAt: DateTime.now().millisecondsSinceEpoch / 1000,
        );
      });
      _showNotice(context.l10n.group_disbanded);
      Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) _showNotice(context.l10n.failed(error.toString()));
    } finally {
      if (mounted) setState(() => _menuBusy = false);
    }
  }

  Future<void> _openRename() async {
    if (_menuBusy || _room.isDisbanded) return;
    final controller = TextEditingController(text: _room.title);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.rename),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: context.l10n.name),
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(context.l10n.rename),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == _room.title || !mounted) return;
    setState(() => _menuBusy = true);
    try {
      await _rename(trimmed);
      if (!mounted) return;
      setState(() => _room = _room.copyWith(name: trimmed));
      unawaited(_pollLog());
    } catch (error) {
      if (mounted) _showNotice(context.l10n.failed(error.toString()));
    } finally {
      if (mounted) setState(() => _menuBusy = false);
    }
  }

  void _showNotice(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final driver = _driver;
    final bounded = _latestBoundedEvent(driver);
    return Scaffold(
      appBar: AppBar(
        title: Text(_room.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (driver != null && driver.busy)
            const Padding(
              padding: EdgeInsets.only(right: HermesSpacing.sm),
              child: Center(
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            key: const ValueKey('group-info'),
            tooltip: context.l10n.group_info,
            icon: const Icon(Icons.info_outline),
            onPressed: () => unawaited(_openRoomInfo()),
          ),
          PopupMenuButton<_RoomMenuAction>(
            enabled: !_menuBusy,
            onSelected: (action) {
              switch (action) {
                case _RoomMenuAction.stop:
                  unawaited(_confirmStop());
                case _RoomMenuAction.rename:
                  unawaited(_openRename());
                case _RoomMenuAction.disband:
                  unawaited(_confirmDisband());
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _RoomMenuAction.stop,
                enabled: !_room.isDisbanded,
                child: Text(context.l10n.stop),
              ),
              PopupMenuItem(
                value: _RoomMenuAction.rename,
                enabled: !_room.isDisbanded,
                child: Text(context.l10n.rename),
              ),
              PopupMenuItem(
                value: _RoomMenuAction.disband,
                enabled: !_room.isDisbanded,
                child: Text(context.l10n.group_disbanded),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null && _bootstrapped) _buildErrorStrip(context),
          if (bounded != null && _offers('groups.continue'))
            _BoundedBanner(
              reasonCode: bounded.reasonCode,
              busy: _continuing,
              onContinue: () => unawaited(_runContinue(bounded)),
            ),
          if (driver != null) _buildPendingActions(context, driver),
          Expanded(child: _buildTranscript(context)),
          _buildComposer(context),
        ],
      ),
    );
  }

  Future<void> _openRoomInfo() async {
    final infoContext = _context;
    final infoDriver = _driver;
    final infoRoom = _room;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('group-info-sheet'),
          padding: const EdgeInsets.fromLTRB(
            HermesSpacing.lg,
            0,
            HermesSpacing.lg,
            HermesSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sheetContext.l10n.group_info,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: HermesSpacing.xs),
              Text(
                infoRoom.title,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: HermesSpacing.md),
              Text(
                sheetContext.l10n.group_members,
                style: Theme.of(sheetContext).textTheme.labelLarge,
              ),
              const SizedBox(height: HermesSpacing.xs),
              Wrap(
                spacing: HermesSpacing.xs,
                runSpacing: HermesSpacing.xs,
                children: [
                  for (final member in infoRoom.members)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(member.label),
                    ),
                ],
              ),
              if (infoContext != null)
                _buildContextStrip(sheetContext, infoContext),
              if (infoDriver != null)
                _buildMemberActivity(sheetContext, infoDriver),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorStrip(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HermesSpacing.md,
          vertical: HermesSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 16, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: HermesSpacing.sm),
            Expanded(
              child: Text(
                context.l10n.failed(_error ?? ''),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  GroupEvent? _latestBoundedEvent(RoomDriverStatus? driver) {
    final latest = <String, GroupEvent>{};
    final grants = <String, int>{};
    for (final event in _events) {
      final discussionId = event.discussionEventId;
      if (discussionId.isEmpty) continue;
      if (event.isBounded) latest[discussionId] = event;
      if (event.kind == GroupEvent.roomContinued) {
        grants[discussionId] = (grants[discussionId] ?? 0) + 1;
        latest.remove(discussionId);
      }
      if (event.kind == GroupEvent.roomStopRequested) {
        latest.clear();
        grants.clear();
      }
      if (event.isUserMessage) {
        final threadId = _threadId(event);
        if (threadId.isNotEmpty) {
          latest.removeWhere(
            (_, bounded) => _threadId(bounded) == threadId,
          );
        }
      }
    }
    final maxContinues = driver?.maxContinues ?? 0;
    if (maxContinues > 0) {
      latest.removeWhere(
        (discussionId, _) => (grants[discussionId] ?? 0) >= maxContinues,
      );
    }
    if (latest.isEmpty) return null;
    return latest.values.reduce((a, b) => a.seq >= b.seq ? a : b);
  }

  String _threadId(GroupEvent event) {
    final payload = event.raw['payload'];
    if (payload is Map) {
      return (payload['thread_id'] ?? '').toString().trim();
    }
    return '';
  }

  String _memberLabel(String memberId) {
    for (final member in _room.members) {
      if (member.routeId == memberId || member.profile == memberId) {
        return member.label;
      }
    }
    return memberId;
  }

  String _routingLabel(BuildContext context, String routing) {
    switch (routing) {
      case 'lead':
        return context.l10n.group_routing_lead;
      case 'auto':
        return context.l10n.group_routing_auto;
      default:
        return context.l10n.group_routing_everyone;
    }
  }

  Widget _buildContextStrip(BuildContext context, RoomContext roomContext) {
    final hasContext =
        roomContext.purpose.isNotEmpty ||
        roomContext.notes.isNotEmpty ||
        roomContext.routing != 'everyone' ||
        roomContext.leadMemberId.isNotEmpty;
    if (!hasContext) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final rows = <Widget>[
      if (roomContext.purpose.isNotEmpty) ...[
        Text(
          context.l10n.group_purpose,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(roomContext.purpose, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
      if (roomContext.notes.isNotEmpty)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text(
            context.l10n.group_notes,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(roomContext.notes),
            ),
          ],
        ),
      Text(
        '${context.l10n.group_routing}: '
        '${_routingLabel(context, roomContext.routing)}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HermesSpacing.md,
          vertical: HermesSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }

  Widget _buildMemberActivity(
    BuildContext context,
    RoomDriverStatus driver,
  ) {
    if (driver.memberActivity.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HermesSpacing.md,
        vertical: HermesSpacing.xs,
      ),
      child: Wrap(
        spacing: HermesSpacing.xs,
        runSpacing: HermesSpacing.xs,
        children: [
          for (final activity in driver.memberActivity)
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(
                Icons.bolt_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              label: Text(
                context.l10n.group_working(
                  _memberLabel(activity.memberId),
                  activity.tool.isEmpty ? activity.status : activity.tool,
                  activity.startedAt <= 0
                      ? 0
                      : (now - activity.startedAt).clamp(0, 86400).round(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPendingActions(BuildContext context, RoomDriverStatus driver) {
    if (driver.pendingActions.isEmpty) return const SizedBox.shrink();
    final labels = {
      for (final member in _room.members) member.routeId: member.label,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in driver.pendingActions)
          _PendingActionCard(
            key: ValueKey('pending-${action.identity}'),
            action: action,
            memberLabel: labels[action.memberId] ?? action.memberId,
            busy: _busyActions.contains(action.identity),
            onApprove: action.isApproval
                ? (choice) => unawaited(_runApproval(action, choice))
                : null,
            onRetry: action.isRetry
                ? () => unawaited(_runRetry(action))
                : null,
            onDiscard: action.isDiscard && _offers('groups.discard')
                ? () => unawaited(_confirmDiscard(action))
                : null,
          ),
      ],
    );
  }

  Widget _buildTranscript(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_events.isEmpty && _error != null) {
      return ListView(
        padding: const EdgeInsets.all(HermesSpacing.lg),
        children: [
          Text(
            context.l10n.failed(''),
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
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                unawaited(_bootstrap());
              },
              child: Text(context.l10n.retry),
            ),
          ),
        ],
      );
    }
    final renderable = [
      for (final event in _events)
        if (event.isRenderable) event,
    ];
    if (renderable.isEmpty) {
      final members = _room.members.map((member) => member.label).toList();
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(HermesSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              if (members.isNotEmpty) ...[
                const SizedBox(height: HermesSpacing.md),
                Text(
                  members.join(' · '),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(
        horizontal: HermesSpacing.md,
        vertical: HermesSpacing.sm,
      ),
      itemCount: renderable.length,
      itemBuilder: (context, index) {
        final event = renderable[index];
        if (event.isMessage) {
          final previous = index == 0 ? null : renderable[index - 1];
          return _PostTile(
            event: event,
            startsRound:
                event.isUserMessage &&
                previous != null &&
                previous.isMessage &&
                !previous.isUserMessage,
          );
        }
        if (event.isTurn) return _TurnLine(event: event);
        return _SystemLine(text: _systemText(context, event));
      },
    );
  }

  String _systemText(BuildContext context, GroupEvent event) {
    final kind = event.kind;
    final payload = event.raw['payload'];
    if (kind == GroupEvent.roomAssignment) {
      final ids = <String>[];
      if (payload is Map && payload['member_ids'] is List) {
        for (final value in payload['member_ids'] as List) {
          final id = value.toString().trim();
          if (id.isNotEmpty) ids.add(_memberLabel(id));
        }
      }
      if (ids.isEmpty && payload is Map) {
        final lead = (payload['lead_member_id'] ?? '').toString().trim();
        if (lead.isNotEmpty) ids.add(_memberLabel(lead));
      }
      if (ids.isNotEmpty) {
        return context.l10n.group_assigned(ids.join(', '));
      }
    }
    if (kind == GroupEvent.roomRouted) {
      if (payload is Map && payload['everyone'] == true) {
        return context.l10n.group_routing_everyone;
      }
      final ids = <String>[];
      if (payload is Map && payload['member_ids'] is List) {
        for (final value in payload['member_ids'] as List) {
          final id = value.toString().trim();
          if (id.isNotEmpty) ids.add(_memberLabel(id));
        }
      }
      if (ids.isNotEmpty) {
        return context.l10n.group_routed(ids.join(', '));
      }
    }
    if (kind == GroupEvent.roomContinued) return context.l10n.group_continued;
    if (kind == GroupEvent.roomContextSet) {
      return context.l10n.group_context_updated;
    }
    if (kind == GroupEvent.roomDisbanded) return context.l10n.group_disbanded;
    if (kind == GroupEvent.roomStopRequested) return context.l10n.group_stopped;
    final detail = <String>[
      if (payload is Map && (payload['name'] ?? '').toString().trim().isNotEmpty)
        (payload['name'] ?? '').toString().trim(),
      if (event.actor.label.isNotEmpty) event.actor.label,
    ].join(' · ');
    final word = kind.split('.').last.replaceAll('_', ' ');
    return detail.isEmpty ? word : '$word · $detail';
  }

  Widget _buildComposer(BuildContext context) {
    final disbanded = _room.isDisbanded;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          HermesSpacing.md,
          HermesSpacing.sm,
          HermesSpacing.md,
          HermesSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _composer,
                enabled: !disbanded,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: _room.handles.isEmpty
                      ? null
                      : _room.handles.map((handle) => '@$handle').join(' '),
                  border: const OutlineInputBorder(borderRadius: HermesRadius.card),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: HermesSpacing.sm),
            IconButton.filled(
              onPressed: _sending || disbanded ? null : () => unawaited(_send()),
              tooltip: context.l10n.send,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      ),
    );
  }
}

enum _RoomMenuAction { stop, rename, disband }

/// One room post, forum-style: author header, body, attachments.
///
/// Group rooms are long-running discussions, not a 1:1 chat — bubbles hide who
/// said what once several bots answer in a row. A post keeps the author, the
/// @handle and the time on its own line, and [startsRound] draws the seam
/// between a user prompt and the member replies that follow it.
class _PostTile extends StatelessWidget {
  final GroupEvent event;
  final bool startsRound;

  const _PostTile({required this.event, this.startsRound = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = event.isUserMessage;
    final author = event.authorLabel.isEmpty
        ? (isUser ? context.l10n.group_you : '')
        : event.authorLabel;
    final handle = event.actor.handle.trim();
    final initial = author.isEmpty ? '?' : author.substring(0, 1).toUpperCase();
    final time = _formatPostTime(event.ts);
    final bubbleColor = isUser
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
        : theme.colorScheme.surfaceContainerLow;
    final borderColor = isUser
        ? theme.colorScheme.primary.withValues(alpha: 0.35)
        : theme.colorScheme.outlineVariant;

    return Padding(
      padding: EdgeInsets.only(
        top: startsRound ? HermesSpacing.lg : 0,
        bottom: HermesSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: isUser
                ? theme.colorScheme.primary
                : theme.colorScheme.tertiaryContainer,
            child: Text(
              isUser ? context.l10n.group_you.substring(0, 1) : initial,
              style: theme.textTheme.labelMedium?.copyWith(
                color: isUser
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
          const SizedBox(width: HermesSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (handle.isNotEmpty && handle != author) ...[
                      const SizedBox(width: HermesSpacing.xs),
                      Text(
                        '@$handle',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (time.isNotEmpty)
                      Text(
                        time,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: HermesSpacing.md,
                    vertical: HermesSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: SelectableText(
                    event.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isUser
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (event.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: HermesSpacing.xs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.attach_file,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${event.attachments.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatPostTime(double seconds) {
    if (seconds <= 0) return '';
    final at = DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
    final local = at.toLocal();
    final now = DateTime.now();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return '$hh:$mm';
    }
    return '${local.month}/${local.day} $hh:$mm';
  }
}

/// `turn.*` rows: the driver's progress, not a message.
class _TurnLine extends StatelessWidget {
  final GroupEvent event;

  const _TurnLine({required this.event});

  static const Map<String, IconData> _icons = {
    GroupEvent.turnStarted: Icons.more_horiz,
    GroupEvent.turnSettled: Icons.check,
    GroupEvent.turnFailed: Icons.error_outline,
    GroupEvent.turnCancelled: Icons.cancel_outlined,
    GroupEvent.turnDeferred: Icons.schedule,
    GroupEvent.turnReassigned: Icons.swap_horiz,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final word = event.kind.split('.').last.replaceAll('_', ' ');
    final label = event.authorLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            _icons[event.kind] ?? Icons.circle_outlined,
            size: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: HermesSpacing.xs),
          Expanded(
            child: Text(
              label.isEmpty ? word : '$label · $word',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Room lifecycle / notice rows, centered and muted.
class _SystemLine extends StatelessWidget {
  final String text;

  const _SystemLine({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HermesSpacing.xs),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A paused discussion: the server hit its message/round bound and will not
/// continue until the human explicitly asks. Only the newest bounded event is
/// shown; a later `room.continued` clears it.
class _BoundedBanner extends StatelessWidget {
  final String reasonCode;
  final bool busy;
  final VoidCallback onContinue;

  const _BoundedBanner({
    required this.reasonCode,
    required this.busy,
    required this.onContinue,
  });

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
              Icons.pause_circle_outline,
              size: 16,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: HermesSpacing.sm),
            Expanded(
              child: Text(
                reasonCode == 'max_rounds'
                    ? context.l10n.group_paused_rounds
                    : context.l10n.group_paused,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('group-continue'),
              onPressed: busy ? null : onContinue,
              child: Text(context.l10n.group_continue),
            ),
          ],
        ),
      ),
    );
  }
}

/// One driver decision: approve/deny a blocked member, or retry a failed one.
class _PendingActionCard extends StatelessWidget {
  final PendingRoomAction action;
  final String memberLabel;
  final bool busy;
  final ValueChanged<String>? onApprove;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  const _PendingActionCard({
    super.key,
    required this.action,
    required this.memberLabel,
    required this.busy,
    this.onApprove,
    this.onRetry,
    this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = [
      if (memberLabel.isNotEmpty) memberLabel,
      if (action.taskId.isNotEmpty) action.taskId,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HermesSpacing.md,
        HermesSpacing.sm,
        HermesSpacing.md,
        0,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(HermesSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    action.isApproval
                        ? Icons.gavel_outlined
                        : action.isDiscard
                            ? Icons.delete_outline
                            : Icons.refresh,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: HermesSpacing.sm),
                  Expanded(
                    child: Text(
                      action.isApproval
                          ? context.l10n.group_approval_needed
                          : action.isDiscard
                              ? context.l10n.group_discard
                              : context.l10n.retry,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              if (detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: HermesSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onApprove != null) ...[
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => onApprove!(GroupApproval.deny),
                      child: Text(context.l10n.deny),
                    ),
                    const SizedBox(width: HermesSpacing.sm),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => onApprove!(GroupApproval.once),
                      child: Text(context.l10n.allow_once),
                    ),
                  ],
                  if (onRetry != null)
                    FilledButton(
                      onPressed: busy ? null : onRetry,
                      child: Text(context.l10n.retry),
                    ),
                  if (onDiscard != null)
                    FilledButton(
                      onPressed: busy ? null : onDiscard,
                      child: Text(context.l10n.group_discard),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
