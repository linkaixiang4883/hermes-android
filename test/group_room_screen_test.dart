// One hosted room: transcript rendering, the send path's single-flight +
// idempotent retry, driver approval/retry frames, and the empty/error states.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/screens/group_room_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/group_rooms_client.dart';

SavedConnection _connection() => SavedConnection(
  id: 'groups-fixture',
  label: 'Groups fixture',
  host: 'groups.fixture',
  port: 8642,
  apiKey: 'test-key',
);

GroupRoom _room({
  String roomId = 'room-1',
  String name = 'Launch room',
  double? disbandedAt,
  List<GroupRoomMember> members = const [
    GroupRoomMember(profile: 'research', handle: 'research', displayName: 'Research'),
    GroupRoomMember(profile: 'writer', handle: 'writer', displayName: 'Writer'),
  ],
}) => GroupRoom(
  roomId: roomId,
  name: name,
  members: members,
  latestSeq: 2,
  updatedAt: 1761000000,
  disbandedAt: disbandedAt,
);

GroupEvent _userEvent(int seq, String text, {String author = 'LKX'}) =>
    GroupEvent(
      seq: seq,
      kind: GroupEvent.messageUser,
      actor: GroupEventActor(kind: 'user', id: 'u1', displayName: author),
      text: text,
      raw: {
        'seq': seq,
        'kind': GroupEvent.messageUser,
        'payload': {'text': text},
      },
    );

GroupEvent _memberEvent(int seq, String text, {String author = 'Research'}) =>
    GroupEvent(
      seq: seq,
      kind: GroupEvent.messageMember,
      actor: GroupEventActor(
        kind: 'member',
        id: 'm1',
        handle: author.toLowerCase(),
        displayName: author,
      ),
      text: text,
      raw: {
        'seq': seq,
        'kind': GroupEvent.messageMember,
        'payload': {'text': text},
      },
    );

GroupLogPage _page(List<GroupEvent> events, {int? cursor, bool hasMore = false}) {
  return GroupLogPage(
    events: events,
    cursor: cursor ?? (events.isEmpty ? 0 : events.last.seq),
    latestSeq: events.isEmpty ? 0 : events.last.seq,
    hasMore: hasMore,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required GroupRoomStateLoader stateLoader,
  required GroupRoomLogLoader logLoader,
  GroupMessageSender? sender,
  GroupApprovalAction? approval,
  GroupRetryAction? retry,
  GroupCapabilities? capabilities,
  GroupCapabilities? seededCapabilities,
  GroupRoomsClient? rooms,
  GroupContinueAction? continueDiscussion,
  GroupDiscardAction? discard,
  GroupRoomAction? stop,
  GroupRoomAction? disband,
  Future<void> Function(String name)? rename,
  GroupRoom? room,
  GroupPendingSendStore? store,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: preferredSupportedLocales(),
      locale: const Locale('en'),
      home: GroupRoomScreen(
        connection: _connection(),
        room: room ?? _room(),
        rooms: rooms,
        capabilities: seededCapabilities,
        pendingStore: store ?? MemoryGroupPendingSendStore(),
        pollInterval: const Duration(hours: 1),
        testStateLoader: stateLoader,
        testLogLoader: logLoader,
        testSender: sender,
        testApproval: approval,
        testRetry: retry,
        testCapabilities: capabilities == null ? null : () async => capabilities,
        testContinue: continueDiscussion,
        testDiscard: discard,
        testStop: stop,
        testDisband: disband,
        testRename: rename,
      ),
    ),
  );
  // Bootstrap: state, then the history page.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('renders user and member messages under their actor names', (
    tester,
  ) async {
    await _pump(
      tester,
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(running: true),
      ),
      logLoader: (_) async => _page([
        _userEvent(1, 'kick off'),
        _memberEvent(2, 'on it'),
      ]),
    );

    expect(find.text('kick off'), findsOneWidget);
    expect(find.text('on it'), findsOneWidget);
    expect(find.text('LKX'), findsOneWidget);
    expect(find.text('Research'), findsOneWidget);
  });

  testWidgets('renders turn progress and room lifecycle as status lines', (
    tester,
  ) async {
    await _pump(
      tester,
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(running: true),
      ),
      logLoader: (_) async => _page([
        _userEvent(1, 'kick off'),
        const GroupEvent(
          seq: 2,
          kind: GroupEvent.turnStarted,
          actor: GroupEventActor(kind: 'member', id: 'm1', displayName: 'Research'),
        ),
        const GroupEvent(
          seq: 3,
          kind: GroupEvent.roomRenamed,
          raw: {
            'seq': 3,
            'kind': GroupEvent.roomRenamed,
            'payload': {'name': 'Launch v2'},
          },
        ),
        const GroupEvent(
          seq: 4,
          kind: 'authority.claimed',
          actor: GroupEventActor(kind: 'system', id: 'srv'),
        ),
      ]),
    );

    expect(find.text('Research · started'), findsOneWidget);
    expect(find.textContaining('Launch v2'), findsOneWidget);
    // Authority bookkeeping stays folded away.
    expect(find.textContaining('authority'), findsNothing);
  });

  testWidgets('send is single-flight and reuses the event id on retry', (
    tester,
  ) async {
    final ids = <String>[];
    final gate = Completer<GroupSendResult>();
    final store = MemoryGroupPendingSendStore();

    await _pump(
      tester,
      store: store,
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(running: true),
      ),
      logLoader: (_) async => _page([_userEvent(1, 'kick off')]),
      sender: ({required eventId, required text}) {
        ids.add(eventId);
        if (ids.length == 1) return gate.future;
        return Future.value(
          const GroupSendResult(accepted: true, event: null),
        );
      },
    );

    await tester.enterText(find.byType(TextField), 'hello team');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    // A second tap while the first request is in flight is swallowed.
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(ids, hasLength(1));

    gate.completeError(StateError('offline'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Could not send'), findsOneWidget);
    final journaled = await store.read('room-1');
    expect(journaled?.eventId, ids.single);
    expect(journaled?.text, 'hello team');

    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(ids, hasLength(2));
    expect(ids[1], ids[0], reason: 'a retry must replay the same event id');
    expect(await store.read('room-1'), isNull);
  });

  testWidgets('an approval pending action posts once and deny choices', (
    tester,
  ) async {
    final approvals = <(String memberId, String taskId, String choice)>[];

    await _pump(
      tester,
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(
          running: true,
          blocked: true,
          pendingActions: [
            PendingRoomAction(
              kind: PendingRoomAction.kindApproval,
              memberId: 'research',
              taskId: 'task-7',
              executionGeneration: '3',
              requestId: 'req-2',
            ),
          ],
        ),
      ),
      logLoader: (_) async => _page([_userEvent(1, 'kick off')]),
      approval: (action, choice) async {
        approvals.add((action.memberId, action.taskId, choice));
      },
    );

    expect(find.text('A member is waiting for approval'), findsOneWidget);
    expect(find.textContaining('task-7'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Allow once'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.widgetWithText(TextButton, 'Deny'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(approvals, [
      ('research', 'task-7', GroupApproval.once),
      ('research', 'task-7', GroupApproval.deny),
    ]);
  });

  testWidgets('a retry pending action offers the retry button', (tester) async {
    final retried = <String>[];

    await _pump(
      tester,
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(
          running: true,
          pendingActions: [
            PendingRoomAction(
              kind: PendingRoomAction.kindRetry,
              memberId: 'writer',
              taskId: 'task-8',
            ),
          ],
        ),
      ),
      logLoader: (_) async => _page([_userEvent(1, 'kick off')]),
      retry: (action) async => retried.add(action.taskId),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(retried, ['task-8']);
  });

  testWidgets('an empty room shows its members, not an invented transcript', (
    tester,
  ) async {
    await _pump(
      tester,
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(),
      ),
      logLoader: (_) async => _page([], cursor: 0, hasMore: false),
    );

    expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
    expect(find.text('Research · Writer'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a failed bootstrap surfaces the error, retry included', (
    tester,
  ) async {
    await _pump(
      tester,
      stateLoader: () async => throw StateError('boom'),
      logLoader: (_) async => _page([]),
    );

    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('stopping asks first and then posts groups.stop', (tester) async {
    var stops = 0;

    await _pump(
      tester,
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(running: true, working: true),
      ),
      logLoader: (_) async => _page([_userEvent(1, 'kick off')]),
      stop: () async => stops++,
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Stop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(stops, 0, reason: 'stop is destructive enough to confirm');

    await tester.tap(find.widgetWithText(FilledButton, 'Stop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(stops, 1);
    expect(find.text('Group stopped'), findsOneWidget);
  });

  testWidgets('disbanding confirms, marks the room and leaves it', (
    tester,
  ) async {
    var disbands = 0;

    await _pump(
      tester,
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(running: true),
      ),
      logLoader: (_) async => _page([_userEvent(1, 'kick off')]),
      disband: () async => disbands++,
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group disbanded'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(disbands, 1);
  });

  testWidgets('a disbanded room cannot be posted to', (tester) async {
    await _pump(
      tester,
      room: _room(disbandedAt: 1761000500),
      stateLoader: () async => GroupRoomState(
        room: _room(disbandedAt: 1761000500),
        driverStatus: const RoomDriverStatus(),
      ),
      logLoader: (_) async => _page([]),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
    final sendButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_upward),
    );
    expect(sendButton.onPressed, isNull);
  });

  testWidgets('a bounded room offers Continue with its discussion event', (
    tester,
  ) async {
    String? continued;
    await _pump(
      tester,
      capabilities: const GroupCapabilities(
        methods: ['groups.continue'],
        methodsKnown: true,
      ),
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(running: true),
      ),
      logLoader: (_) async => _page([
        const GroupEvent(
          seq: 1,
          kind: GroupEvent.roomActivity,
          status: 'bounded',
          discussionEventId: 'disc-1',
        ),
      ]),
      continueDiscussion: (discussionEventId) async {
        continued = discussionEventId;
      },
    );

    expect(find.text('Paused after the message limit'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(continued, 'disc-1');
  });

  testWidgets('a discard pending action confirms and sends the exact action', (
    tester,
  ) async {
    PendingRoomAction? discarded;
    await _pump(
      tester,
      capabilities: const GroupCapabilities(
        methods: ['groups.discard'],
        methodsKnown: true,
      ),
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(
          running: true,
          pendingActions: [
            PendingRoomAction(
              kind: PendingRoomAction.kindDiscard,
              memberId: 'research',
              taskId: 'task-9',
              executionGeneration: '4',
            ),
          ],
        ),
      ),
      logLoader: (_) async => _page([]),
      discard: (action) async => discarded = action,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('group-discard-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(discarded?.identity, 'discard|research|task-9|4|');
  });

  testWidgets('shows context and live member activity', (tester) async {
    await _pump(
      tester,
      capabilities: const GroupCapabilities(methodsKnown: true),
      stateLoader: () async => GroupRoomState(
        room: _room(),
        context: const RoomContext(
          purpose: 'Plan the launch',
          notes: 'Keep replies short',
          routing: 'lead',
          leadMemberId: 'research',
        ),
        driverStatus: const RoomDriverStatus(
          running: true,
          memberActivity: [
            RoomMemberActivity(
              memberId: 'research',
              status: 'running',
              tool: 'terminal',
              roundIndex: 0,
            ),
          ],
        ),
      ),
      logLoader: (_) async => _page([]),
    );

    expect(find.textContaining('Plan the launch'), findsOneWidget);
    expect(find.textContaining('terminal'), findsOneWidget);
  });

  testWidgets('renders assignment and routed payload member_ids', (
    tester,
  ) async {
    await _pump(
      tester,
      capabilities: const GroupCapabilities(methodsKnown: true),
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(running: true),
      ),
      logLoader: (_) async => _page([
        GroupEvent.fromJson({
          'seq': 1,
          'kind': GroupEvent.roomAssignment,
          'payload': {
            'lead_member_id': 'research',
            'member_ids': ['research', 'writer'],
            'fallback': false,
          },
        }),
        GroupEvent.fromJson({
          'seq': 2,
          'kind': GroupEvent.roomRouted,
          'payload': {
            'member_ids': ['writer'],
            'everyone': false,
            'fallback': false,
          },
        }),
      ]),
    );

    expect(find.textContaining('Research'), findsWidgets);
    expect(find.textContaining('Writer'), findsWidgets);
  });

  testWidgets('a default context does not add a routing strip', (tester) async {
    await _pump(
      tester,
      capabilities: const GroupCapabilities(methodsKnown: true),
      stateLoader: () async => GroupRoomState(
        room: _room(),
        context: const RoomContext(),
        driverStatus: const RoomDriverStatus(running: true),
      ),
      logLoader: (_) async => _page([]),
    );

    expect(find.textContaining('Who answers'), findsNothing);
  });

  testWidgets('a continued discussion hides its bounded banner', (
    tester,
  ) async {
    await _pump(
      tester,
      capabilities: const GroupCapabilities(
        methods: ['groups.continue'],
        methodsKnown: true,
      ),
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(running: true),
      ),
      logLoader: (_) async => _page([
        const GroupEvent(
          seq: 1,
          kind: GroupEvent.roomActivity,
          status: 'bounded',
          discussionEventId: 'disc-1',
        ),
        const GroupEvent(
          seq: 2,
          kind: GroupEvent.roomContinued,
          discussionEventId: 'disc-1',
        ),
      ]),
    );

    expect(find.byKey(const ValueKey('group-continue')), findsNothing);
  });

  testWidgets('the round-limit pause uses the round copy', (tester) async {
    await _pump(
      tester,
      capabilities: const GroupCapabilities(
        methods: ['groups.continue'],
        methodsKnown: true,
      ),
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(running: true),
      ),
      logLoader: (_) async => _page([
        const GroupEvent(
          seq: 1,
          kind: GroupEvent.roomActivity,
          status: 'bounded',
          reasonCode: 'max_rounds',
          discussionEventId: 'disc-1',
        ),
      ]),
    );

    expect(find.text('Paused after the round limit'), findsOneWidget);
  });

  testWidgets('the banner disappears after the continue budget is spent', (
    tester,
  ) async {
    final events = <GroupEvent>[
      const GroupEvent(
        seq: 1,
        kind: GroupEvent.roomActivity,
        status: 'bounded',
        discussionEventId: 'disc-1',
      ),
      for (var i = 0; i < 5; i++)
        GroupEvent(
          seq: 2 + i,
          kind: GroupEvent.roomContinued,
          discussionEventId: 'disc-1',
        ),
    ];
    await _pump(
      tester,
      capabilities: const GroupCapabilities(
        methods: ['groups.continue'],
        methodsKnown: true,
      ),
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(running: true, maxContinues: 5),
      ),
      logLoader: (_) async => _page(events),
    );

    expect(find.byKey(const ValueKey('group-continue')), findsNothing);
  });

  testWidgets('capabilities without continue/discard hide both actions', (
    tester,
  ) async {
    await _pump(
      tester,
      capabilities: const GroupCapabilities(methodsKnown: true),
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(
          running: true,
          pendingActions: [
            PendingRoomAction(
              kind: PendingRoomAction.kindDiscard,
              memberId: 'research',
              taskId: 'task-9',
              executionGeneration: '4',
            ),
          ],
        ),
      ),
      logLoader: (_) async => _page([
        const GroupEvent(
          seq: 1,
          kind: GroupEvent.roomActivity,
          status: 'bounded',
          discussionEventId: 'disc-1',
        ),
      ]),
    );

    expect(find.byKey(const ValueKey('group-continue')), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Discard'), findsNothing);
  });

  testWidgets('a host-seeded capability enables Continue without a read', (
    tester,
  ) async {
    await _pump(
      tester,
      seededCapabilities: const GroupCapabilities(
        methods: ['groups.continue'],
        methodsKnown: true,
      ),
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(running: true),
      ),
      logLoader: (_) async => _page([
        const GroupEvent(
          seq: 1,
          kind: GroupEvent.roomActivity,
          status: 'bounded',
          discussionEventId: 'disc-1',
        ),
      ]),
    );

    expect(find.byKey(const ValueKey('group-continue')), findsOneWidget);
  });

  testWidgets('stopping mints a fresh cancel id for the wire', (tester) async {
    final calls = <({String method, Map<String, dynamic> params})>[];
    final rooms = GroupRoomsClient((method, params) async {
      calls.add((method: method, params: params));
      return {'result': <String, dynamic>{}};
    });
    await _pump(
      tester,
      rooms: rooms,
      stateLoader: () async => GroupRoomState(
        room: _room(),
        driverStatus: const RoomDriverStatus(running: true),
      ),
      logLoader: (_) async => _page([]),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Stop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final stop = calls.singleWhere((call) => call.method == 'groups.stop');
    expect(stop.params['cancel_id'], isNotEmpty);
  });
}
