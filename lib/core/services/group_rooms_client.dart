// Hosted group rooms (`groups.*`) — Bot Mode's server-owned chat rooms.
//
// A room is not a session: the gateway persists the room, its members, and an
// append-only event log, and a Discussion driver decides which member answers
// each turn. The client's whole job is therefore
//
//   * `groups.state` — room snapshot + driver status (approvals/retries),
//   * `groups.log {since_seq}` — incremental replay from a cursor,
//   * `groups.send` — one message, idempotent on (room_id, event_id).
//
// Everything here is transport + tolerant parsing: no polling timers, no
// widget state. The screens own cadence so they can stop when unmounted.
//
// Composition, not inheritance: this client holds a [DesktopGatewayClient]
// and borrows its control socket through `callControl`, the same socket every
// other connection-scoped call uses. It deliberately owns no socket of its
// own — a second connection would double authentication and strand cursors
// across reconnects.

import 'package:uuid/uuid.dart';

import 'desktop_gateway_client.dart';

/// Sends one JSON-RPC call and returns the raw envelope.
///
/// A function type rather than a class so the room screens can be tested
/// against a scripted responder without a gateway.
typedef GroupRpcCall =
    Future<Map<String, dynamic>> Function(
      String method,
      Map<String, dynamic> params,
    );

/// A stable, client-minted identifier (room ids and event ids).
///
/// The gateway treats both as identity, so they must be UUIDs and must be
/// minted BEFORE the first attempt — a retry reuses the same value.
String newGroupIdentifier() => const Uuid().v4();

/// A gateway refusal or transport failure for one `groups.*` call.
class GroupRoomException implements Exception {
  final String method;
  final String message;

  const GroupRoomException(this.method, this.message);

  @override
  String toString() => '$method failed: $message';
}

// ── Tolerant decoding helpers ────────────────────────────────────────────
//
// Room payloads come from a server that adds fields over time, and a single
// unexpected null must never blank a room view. Every decoder below reads
// defensively and never throws.

String _text(Object? value) => value == null ? '' : value.toString();

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_text(value).trim()) ?? 0;
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(_text(value).trim()) ?? 0;
}

bool _flag(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final raw = _text(value).trim().toLowerCase();
  return raw == 'true' || raw == '1' || raw == 'yes';
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map) return const <String, dynamic>{};
  final out = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) out[key] = entry.value;
  }
  return out;
}

List<Map<String, dynamic>> _objects(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return [
    for (final row in value)
      if (row is Map) _object(row),
  ];
}

List<String> _strings(Object? value) {
  if (value is! List) return const <String>[];
  return [
    for (final row in value)
      if (row != null && _text(row).trim().isNotEmpty) _text(row).trim(),
  ];
}

Map<String, int> _counts(Object? value) {
  final out = <String, int>{};
  if (value is! Map) return out;
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) continue;
    out[key] = _integer(entry.value);
  }
  return out;
}

// ── Valuation models ─────────────────────────────────────────────────────

/// One bot seated in a room. [profile] is what the gateway routes on;
/// [handle] is what `@mention` resolves against.
class GroupRoomMember {
  final String profile;
  final String handle;
  final String displayName;

  const GroupRoomMember({
    required this.profile,
    this.handle = '',
    this.displayName = '',
  });

  factory GroupRoomMember.fromJson(Map<String, dynamic> json) {
    return GroupRoomMember(
      profile: _text(json['profile']).trim(),
      handle: _text(json['handle']).trim(),
      displayName: _text(json['display_name'] ?? json['displayName']).trim(),
    );
  }

  /// The name a human should read: display name, else handle, else profile.
  String get label {
    if (displayName.isNotEmpty) return displayName;
    if (handle.isNotEmpty) return handle;
    return profile;
  }

  Map<String, dynamic> toJson() => {
    'profile': profile,
    'handle': handle.isEmpty ? profile : handle,
    'display_name': label,
  };

  @override
  String toString() => 'GroupRoomMember($profile)';
}

/// A hosted room as `groups.list` / `groups.create` / `groups.state` show it.
///
/// [disbandedAt] is a tombstone marker, not a deletion: a disbanded room still
/// lists, so the phone can show it greyed out instead of pretending it never
/// existed.
class GroupRoom {
  final String roomId;
  final String name;
  final List<GroupRoomMember> members;
  final int latestSeq;
  final double updatedAt;
  final double? disbandedAt;

  const GroupRoom({
    required this.roomId,
    required this.name,
    this.members = const [],
    this.latestSeq = 0,
    this.updatedAt = 0,
    this.disbandedAt,
  });

  factory GroupRoom.fromJson(Map<String, dynamic> json) {
    final rawDisbanded = json['disbanded_at'];
    return GroupRoom(
      roomId: _text(json['room_id'] ?? json['roomId']).trim(),
      name: _text(json['name']).trim(),
      members: [
        for (final row in _objects(json['members']))
          GroupRoomMember.fromJson(row),
      ],
      latestSeq: _integer(json['latest_seq'] ?? json['latestSeq']),
      updatedAt: _double(json['updated_at'] ?? json['updatedAt']),
      disbandedAt: rawDisbanded == null ? null : _double(rawDisbanded),
    );
  }

  bool get isDisbanded => disbandedAt != null;

  String get title => name.isEmpty ? roomId : name;

  /// @-mention handles, in seating order — the room's composer hint.
  List<String> get handles => [
    for (final member in members)
      if (member.handle.isNotEmpty) member.handle,
  ];

  GroupRoom copyWith({
    String? name,
    List<GroupRoomMember>? members,
    int? latestSeq,
    double? updatedAt,
    double? disbandedAt,
  }) {
    return GroupRoom(
      roomId: roomId,
      name: name ?? this.name,
      members: members ?? this.members,
      latestSeq: latestSeq ?? this.latestSeq,
      updatedAt: updatedAt ?? this.updatedAt,
      disbandedAt: disbandedAt ?? this.disbandedAt,
    );
  }

  @override
  String toString() => 'GroupRoom($roomId "$name" seq=$latestSeq)';
}

/// Everything a room list needs: the rooms, plus whether this gateway can
/// actually run a Discussion driver for them.
///
/// Discovery mirrors the desktop plugin: ask `groups.capabilities` first, then
/// page `groups.list` until `next_offset` ends. A phone that only asked for one
/// page used to truncate installs with more than [pageSize] rooms.
class GroupDiscovery {
  final List<GroupRoom> rooms;
  final GroupCapabilities capabilities;

  const GroupDiscovery({
    this.rooms = const [],
    this.capabilities = const GroupCapabilities(),
  });

  bool get driverAvailable => capabilities.driver;
}

/// `groups.list` page. [nextOffset] is null at the end of the listing.
class GroupRoomPage {
  final List<GroupRoom> rooms;
  final int? nextOffset;

  const GroupRoomPage({this.rooms = const [], this.nextOffset});

  factory GroupRoomPage.fromJson(Map<String, dynamic> json) {
    final rawNext = json['next_offset'] ?? json['nextOffset'];
    return GroupRoomPage(
      rooms: [for (final row in _objects(json['rooms'])) GroupRoom.fromJson(row)],
      nextOffset: rawNext == null ? null : _integer(rawNext),
    );
  }
}

/// What this gateway can seat and how far `groups.log` may page.
class GroupCapabilities {
  final bool driver;
  final List<String> seatableProfiles;
  final List<String> methods;
  final int maxLogLimit;

  const GroupCapabilities({
    this.driver = false,
    this.seatableProfiles = const [],
    this.methods = const [],
    this.maxLogLimit = 0,
  });

  factory GroupCapabilities.fromJson(Map<String, dynamic> json) {
    return GroupCapabilities(
      driver: _flag(json['driver']),
      seatableProfiles: _strings(json['seatable_profiles']),
      methods: _strings(json['methods']),
      maxLogLimit: _integer(json['max_log_limit']),
    );
  }

  bool supports(String method) => methods.contains(method);

  /// The page size to ask for, honouring a server that advertises a cap.
  int get effectiveLogLimit =>
      maxLogLimit > 0 ? maxLogLimit.clamp(1, 500) : 200;
}

/// One item the driver is waiting on the human for.
///
/// Approval cards carry the exact tuple `groups.approve` needs
/// (`member_id` + `task_id` + `execution_generation` + `request_id`); retries
/// only need the task. Both are echoed verbatim, never reconstructed.
class PendingRoomAction {
  static const String kindApproval = 'approval';
  static const String kindRetry = 'retry';

  final String kind;
  final String memberId;
  final String taskId;
  final String executionGeneration;
  final String requestId;

  /// The raw action, for anything a newer gateway adds (labels, deadlines).
  final Map<String, dynamic> raw;

  const PendingRoomAction({
    required this.kind,
    this.memberId = '',
    this.taskId = '',
    this.executionGeneration = '',
    this.requestId = '',
    this.raw = const {},
  });

  factory PendingRoomAction.fromJson(Map<String, dynamic> json) {
    return PendingRoomAction(
      kind: _text(json['kind']).trim(),
      memberId: _text(json['member_id']).trim(),
      taskId: _text(json['task_id']).trim(),
      executionGeneration: _text(json['execution_generation']).trim(),
      requestId: _text(json['request_id']).trim(),
      raw: json,
    );
  }

  bool get isApproval => kind == kindApproval;
  bool get isRetry => kind == kindRetry;

  /// A stable widget/test key: one card per pending decision.
  String get identity => [
    kind,
    memberId,
    taskId,
    executionGeneration,
    requestId,
  ].join('|');
}

/// `driver_status` — whether the room's Discussion driver is alive and what
/// it is blocked on.
class RoomDriverStatus {
  final bool running;
  final bool working;
  final bool blocked;
  final Map<String, int> counts;
  final List<PendingRoomAction> pendingActions;
  final List<Map<String, dynamic>> peerRoutes;

  const RoomDriverStatus({
    this.running = false,
    this.working = false,
    this.blocked = false,
    this.counts = const {},
    this.pendingActions = const [],
    this.peerRoutes = const [],
  });

  factory RoomDriverStatus.fromJson(Map<String, dynamic> json) {
    return RoomDriverStatus(
      running: _flag(json['running']),
      working: _flag(json['working']),
      blocked: _flag(json['blocked']),
      counts: _counts(json['counts']),
      pendingActions: [
        for (final row in _objects(json['pending_actions']))
          PendingRoomAction.fromJson(row),
      ],
      peerRoutes: _objects(json['peer_routes']),
    );
  }

  List<PendingRoomAction> get approvals => [
    for (final action in pendingActions)
      if (action.isApproval) action,
  ];

  List<PendingRoomAction> get retries => [
    for (final action in pendingActions)
      if (action.isRetry) action,
  ];

  /// True when the driver is doing something the user should see a spinner for.
  bool get busy => running && (working || blocked);
}

/// `groups.state` — room snapshot plus driver status.
class GroupRoomState {
  final GroupRoom room;
  final RoomDriverStatus driverStatus;

  const GroupRoomState({required this.room, required this.driverStatus});

  factory GroupRoomState.fromJson(Map<String, dynamic> json) {
    return GroupRoomState(
      room: GroupRoom.fromJson(_object(json['room'])),
      driverStatus: RoomDriverStatus.fromJson(_object(json['driver_status'])),
    );
  }
}

/// The actor on an event: `user`, `member`, `gateway`, or `system`.
class GroupEventActor {
  final String kind;
  final String id;
  final String handle;
  final String displayName;
  final String profile;

  const GroupEventActor({
    this.kind = '',
    this.id = '',
    this.handle = '',
    this.displayName = '',
    this.profile = '',
  });

  factory GroupEventActor.fromJson(Map<String, dynamic> json) {
    return GroupEventActor(
      kind: _text(json['kind']).trim(),
      id: _text(json['id']).trim(),
      handle: _text(json['handle']).trim(),
      displayName: _text(json['display_name'] ?? json['displayName']).trim(),
      profile: _text(json['profile']).trim(),
    );
  }

  String get label {
    if (displayName.isNotEmpty) return displayName;
    if (handle.isNotEmpty) return handle;
    if (profile.isNotEmpty) return profile;
    return id;
  }

  bool get isUser => kind == 'user';
}

/// One row of the room log. [kind] stays a string on purpose: a future event
/// kind must render as a plain system line, not throw during decode.
class GroupEvent {
  static const String messageUser = 'message.user';
  static const String messageMember = 'message.member';
  static const String turnStarted = 'turn.started';
  static const String turnSettled = 'turn.settled';
  static const String turnFailed = 'turn.failed';
  static const String turnCancelled = 'turn.cancelled';
  static const String turnDeferred = 'turn.deferred';
  static const String turnReassigned = 'turn.reassigned';
  static const String roomActivity = 'room.activity';
  static const String memberUnavailable = 'member.unavailable';
  static const String roomStopRequested = 'room.stop_requested';
  static const String roomCreated = 'room.created';
  static const String roomRenamed = 'room.renamed';
  static const String roomMembersChanged = 'room.members_changed';
  static const String roomDisbanded = 'room.disbanded';

  final int seq;
  final String kind;
  final GroupEventActor actor;
  final String text;
  final List<Map<String, dynamic>> attachments;
  final String discussionEventId;
  final double ts;

  /// The untouched event, so nothing the server sends is lost.
  final Map<String, dynamic> raw;

  const GroupEvent({
    required this.seq,
    required this.kind,
    this.actor = const GroupEventActor(),
    this.text = '',
    this.attachments = const [],
    this.discussionEventId = '',
    this.ts = 0,
    this.raw = const {},
  });

  factory GroupEvent.fromJson(Map<String, dynamic> json) {
    final payload = _object(json['payload']);
    final rawTs = json['ts'] ?? json['created_at'] ?? payload['ts'];
    return GroupEvent(
      seq: _integer(json['seq'] ?? json['sequence'] ?? json['id']),
      kind: _text(json['kind']).trim(),
      actor: GroupEventActor.fromJson(_object(json['actor'])),
      text: _text(payload['text'] ?? json['text']),
      attachments: _objects(payload['attachments']),
      discussionEventId: _text(
        payload['discussion_event_id'] ?? json['discussion_event_id'],
      ).trim(),
      ts: rawTs == null ? 0 : _double(rawTs),
      raw: json,
    );
  }

  bool get isUserMessage => kind == messageUser;

  bool get isMemberMessage => kind == messageMember;

  bool get isMessage => isUserMessage || isMemberMessage;

  bool get isTurn => kind.startsWith('turn.');

  bool get isRoomLifecycle => kind.startsWith('room.');

  /// `authority.*` events are bookkeeping about who owns the room; the phone
  /// folds them away rather than printing owner churn into the transcript.
  bool get isAuthority => kind.startsWith('authority.');

  /// Whether this event deserves a line in the transcript at all.
  bool get isRenderable => !isAuthority;

  /// Room-scoped notices that must read as system lines, not messages.
  bool get isNotice =>
      kind == memberUnavailable ||
      kind == roomStopRequested ||
      isRoomLifecycle;

  /// Display name for a message bubble's header.
  String get authorLabel => actor.label;

  @override
  String toString() => 'GroupEvent($seq $kind)';
}

/// `groups.log` page. [cursor] is the server's resume point; [latestSeq] is
/// where the room actually is, so a caller can tell whether it is caught up.
class GroupLogPage {
  final List<GroupEvent> events;
  final int cursor;
  final int latestSeq;
  final bool hasMore;

  const GroupLogPage({
    this.events = const [],
    this.cursor = 0,
    this.latestSeq = 0,
    this.hasMore = false,
  });

  factory GroupLogPage.fromJson(Map<String, dynamic> json) {
    return GroupLogPage(
      events: [
        for (final row in _objects(json['events'])) GroupEvent.fromJson(row),
      ],
      cursor: _integer(json['cursor']),
      latestSeq: _integer(json['latest_seq'] ?? json['latestSeq']),
      hasMore: _flag(json['has_more'] ?? json['hasMore']),
    );
  }
}

/// `groups.send` result. [accepted] false means the server stored nothing
/// (usually the text was empty or over the room's bound) — do not retry that
/// with a fresh id; surface it and let the user edit.
class GroupSendResult {
  final GroupEvent? event;
  final bool accepted;
  final bool driverStarted;

  const GroupSendResult({
    this.event,
    this.accepted = false,
    this.driverStarted = false,
  });

  factory GroupSendResult.fromJson(Map<String, dynamic> json) {
    final rawEvent = json['event'];
    return GroupSendResult(
      event: rawEvent is Map ? GroupEvent.fromJson(_object(rawEvent)) : null,
      accepted: _flag(json['accepted']),
      driverStarted: _flag(json['driver_started'] ?? json['driverStarted']),
    );
  }
}

/// Choices `groups.approve` accepts.
abstract final class GroupApproval {
  static const String once = 'once';
  static const String deny = 'deny';
}

// ── Client ───────────────────────────────────────────────────────────────

/// Typed access to the gateway's hosted rooms.
///
/// Every call is connection-scoped (no session binding): the same socket that
/// lists profiles can create a room, because rooms live in the gateway, not in
/// a chat runtime.
class GroupRoomsClient {
  final GroupRpcCall _call;

  /// Optional profile scope. Rooms belong to the gateway installation, so this
  /// is only forwarded when a caller really wants a profile's view.
  final String? profile;

  GroupRoomsClient(this._call, {this.profile});

  /// Borrows [client]'s shared control socket.
  factory GroupRoomsClient.forGateway(
    DesktopGatewayClient client, {
    String? profile,
  }) {
    return GroupRoomsClient(client.callControl, profile: profile);
  }

  /// `groups.capabilities` — who can be seated and how far the log pages.
  Future<GroupCapabilities> capabilities() async {
    return GroupCapabilities.fromJson(
      await _request('groups.capabilities', const {}),
    );
  }

  /// `groups.capabilities` + every `groups.list` page.
  ///
  /// Matches the desktop discovery loop: no fixed single page, and the
  /// capabilities answer travels with the rooms so the caller can warn when
  /// the gateway has no Discussion driver.
  Future<GroupDiscovery> discover({
    bool includeDisbanded = false,
    int pageSize = 100,
  }) async {
    final capabilities = await this.capabilities();
    final rooms = <GroupRoom>[];
    var offset = 0;
    for (;;) {
      final page = await list(
        includeDisbanded: includeDisbanded,
        limit: pageSize,
        offset: offset,
      );
      rooms.addAll(page.rooms);
      final next = page.nextOffset;
      if (next == null || next <= offset || page.rooms.isEmpty) break;
      offset = next;
    }
    return GroupDiscovery(rooms: rooms, capabilities: capabilities);
  }

  /// `groups.list` — live rooms by default; disbanded ones only on request.
  Future<GroupRoomPage> list({
    bool includeDisbanded = false,
    int? limit,
    int? offset,
  }) async {
    final params = <String, dynamic>{};
    if (includeDisbanded) params['include_disbanded'] = true;
    if (limit != null) params['limit'] = limit;
    if (offset != null) params['offset'] = offset;
    return GroupRoomPage.fromJson(await _request('groups.list', params));
  }

  /// `groups.create` — idempotent on [roomId].
  ///
  /// The id is minted by the caller (`newGroupIdentifier()`) and reused if the
  /// first attempt's response is lost, so a retry cannot open a second room.
  Future<GroupRoom> create({
    required String roomId,
    required String name,
    required List<GroupRoomMember> members,
  }) async {
    final result = await _request('groups.create', {
      'room_id': roomId,
      'name': name,
      'members': [for (final member in members) member.toJson()],
    });
    final room = result['room'];
    return GroupRoom.fromJson(room is Map ? _object(room) : result);
  }

  /// `groups.state` — room snapshot + driver status (approvals, retries).
  Future<GroupRoomState> state(String roomId) async {
    return GroupRoomState.fromJson(
      await _request('groups.state', {'room_id': roomId}),
    );
  }

  /// `groups.log` — events strictly after [sinceSeq].
  ///
  /// [limit] is omitted unless given, so the server's own default stands.
  Future<GroupLogPage> log(String roomId, {required int sinceSeq, int? limit}) async {
    final params = <String, dynamic>{
      'room_id': roomId,
      'since_seq': sinceSeq,
    };
    if (limit != null) params['limit'] = limit;
    return GroupLogPage.fromJson(await _request('groups.log', params));
  }

  /// `groups.send` — one message, idempotent on (room_id, event_id).
  ///
  /// [eventId] MUST be reused verbatim when retrying the same text; a fresh id
  /// on retry is what produces duplicate messages in the room.
  Future<GroupSendResult> send({
    required String roomId,
    required String eventId,
    required String text,
    required String threadId,
  }) async {
    final result = await _request('groups.send', {
      'room_id': roomId,
      'event_id': eventId,
      'payload': {'thread_id': threadId, 'text': text},
    });
    return GroupSendResult.fromJson(result);
  }

  /// `groups.approve` — answers the driver's approval request.
  ///
  /// The identifying tuple comes from [PendingRoomAction] untouched: the
  /// member/task/generation triple is what makes the approval unambiguous when
  /// several bots are blocked at once.
  Future<void> approve({
    required String roomId,
    required PendingRoomAction action,
    required String choice,
  }) async {
    final params = <String, dynamic>{
      'room_id': roomId,
      if (action.memberId.isNotEmpty) 'member_id': action.memberId,
      if (action.taskId.isNotEmpty) 'task_id': action.taskId,
      if (action.executionGeneration.isNotEmpty)
        'execution_generation': action.executionGeneration,
      if (action.requestId.isNotEmpty) 'request_id': action.requestId,
      'choice': choice,
    };
    await _request('groups.approve', params);
  }

  /// `groups.retry` — re-runs a failed member task.
  Future<void> retry({required String roomId, required String taskId}) async {
    await _request('groups.retry', {
      'room_id': roomId,
      if (taskId.isNotEmpty) 'task_id': taskId,
    });
  }

  /// `groups.stop` — asks the driver to cancel in-flight turns.
  Future<void> stop(String roomId) async {
    await _request('groups.stop', {'room_id': roomId});
  }

  /// `groups.rename` — atomic, replayed as a `room.renamed` event.
  Future<void> rename({
    required String roomId,
    required String name,
    required String eventId,
  }) async {
    await _request('groups.rename', {
      'room_id': roomId,
      'event_id': eventId,
      'name': name,
    });
  }

  /// `groups.disband` — tombstones the room; history stays readable.
  Future<void> disband(String roomId) async {
    await _request('groups.disband', {'room_id': roomId});
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final scoped = Map<String, dynamic>.from(params);
    final scope = profile?.trim();
    if (scope != null && scope.isNotEmpty && !scoped.containsKey('profile')) {
      scoped['profile'] = scope;
    }
    final response = await _call(method, scoped);
    final error = response['error'];
    if (error != null) {
      final message = error is Map ? _text(error['message']).trim() : '';
      throw GroupRoomException(
        method,
        message.isEmpty ? 'the gateway rejected the call' : message,
      );
    }
    final result = response['result'];
    return result is Map ? _object(result) : const <String, dynamic>{};
  }
}
