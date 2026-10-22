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
        pendingStore: store ?? MemoryGroupPendingSendStore(),
        pollInterval: const Duration(hours: 1),
        testStateLoader: stateLoader,
        testLogLoader: logLoader,
        testSender: sender,
        testApproval: approval,
        testRetry: retry,
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
}
