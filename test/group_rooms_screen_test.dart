// The hosted-room list: listing, empty state, and the create sheet's
// uuid + seating contract.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/screens/group_rooms_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/group_rooms_client.dart';

SavedConnection _connection() => SavedConnection(
  id: 'groups-fixture',
  label: 'Groups fixture',
  host: 'groups.fixture',
  port: 8642,
  apiKey: 'test-key',
);

GroupRoom _room({String roomId = 'room-1', String name = 'Launch room'}) =>
    GroupRoom(
      roomId: roomId,
      name: name,
      members: const [
        GroupRoomMember(
          profile: 'research',
          handle: 'research',
          displayName: 'Research',
        ),
      ],
      latestSeq: 3,
      updatedAt: 1761000000,
    );

Future<void> _pump(
  WidgetTester tester, {
  required GroupRoomsLoader loader,
  GroupCapabilitiesLoader? capabilities,
  GroupRoomCreator? create,
  ValueChanged<GroupRoom>? onOpenRoom,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: preferredSupportedLocales(),
      locale: const Locale('en'),
      home: GroupRoomsScreen(
        connection: _connection(),
        refreshInterval: const Duration(hours: 1),
        testLoader: loader,
        testCapabilities: capabilities,
        testCreate: create,
        onOpenRoom: onOpenRoom,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('lists rooms with their members and hands one to the host', (
    tester,
  ) async {
    GroupRoom? opened;
    await _pump(
      tester,
      loader: () async => GroupRoomPage(
        rooms: [_room(), _room(roomId: 'room-2', name: 'Second room')],
      ),
      onOpenRoom: (room) => opened = room,
    );

    expect(find.text('Launch room'), findsOneWidget);
    expect(find.text('Second room'), findsOneWidget);
    expect(find.text('Research'), findsNWidgets(2));

    await tester.tap(find.text('Second room'));
    await tester.pump();

    expect(opened?.roomId, 'room-2');
  });

  testWidgets('an empty listing says so instead of showing nothing', (
    tester,
  ) async {
    await _pump(tester, loader: () async => const GroupRoomPage());

    expect(find.text('No groups yet'), findsOneWidget);
  });

  testWidgets('creating a room mints a uuid and seats the picked profiles', (
    tester,
  ) async {
    String? capturedId;
    String? capturedName;
    List<GroupRoomMember>? capturedMembers;
    GroupRoom? created;

    await _pump(
      tester,
      loader: () async =>
          GroupRoomPage(rooms: created == null ? const [] : [created!]),
      capabilities: () async => const GroupCapabilities(
        seatableProfiles: ['research', 'writer'],
        methods: ['groups.list', 'groups.create'],
        maxLogLimit: 200,
      ),
      create:
          ({
            required String roomId,
            required String name,
            required List<GroupRoomMember> members,
          }) async {
            capturedId = roomId;
            capturedName = name;
            capturedMembers = members;
            created = _room(roomId: roomId, name: name);
            return created!;
          },
    );

    await tester.tap(find.text('New group'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'Design room');
    await tester.tap(find.widgetWithText(FilterChip, 'research'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(capturedName, 'Design room');
    expect(capturedId, isNotNull);
    expect(capturedId, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(capturedMembers, hasLength(1));
    expect(capturedMembers!.single.profile, 'research');
    expect(capturedMembers!.single.handle, 'research');
    expect(capturedMembers!.single.displayName, 'research');
    // The created room is inserted without waiting for the next poll.
    expect(find.text('Design room'), findsOneWidget);
  });
}
