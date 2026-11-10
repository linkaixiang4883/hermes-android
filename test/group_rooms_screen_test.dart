// The hosted-room list: listing, empty state, and the create sheet's
// uuid + seating contract.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/models/bot_profile.dart';
import 'package:hermes_android/core/models/legacy_group_chat.dart';
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
  GroupProfilesLoader? testProfiles,
  GroupRoomCreator? create,
  LegacyGroupsLoader? legacy,
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
        testProfiles: testProfiles,
        testCreate: create,
        testLegacy: legacy,
        onOpenRoom: onOpenRoom,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('surfaces desktop-local rooms read-only, with their history', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: () async => const GroupRoomPage(),
      legacy: () async => const [
        LegacyGroupChat(
          key: 'id:rmvhpz399-lgucn',
          roomId: 'rmvhpz399-lgucn',
          name: 'cjh项目讨论组',
          messages: [
            LegacyGroupMessage(
              id: 'm1',
              author: 'default',
              fromMember: true,
              text: 'hello from the desktop mirror',
              atMs: 1792585862692,
            ),
          ],
        ),
      ],
    );

    expect(find.text('cjh项目讨论组'), findsOneWidget);
    await tester.tap(find.text('cjh项目讨论组'));
    await tester.pumpAndSettle();

    expect(find.text('hello from the desktop mirror'), findsOneWidget);
    expect(find.textContaining('read-only'), findsWidgets);
  });

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
        seatableProfilesKnown: true,
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
    await tester.tap(find.widgetWithText(FilterChip, 'writer'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(capturedName, 'Design room');
    expect(capturedId, isNotNull);
    expect(capturedId, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(capturedMembers, hasLength(2));
    expect(capturedMembers!.map((member) => member.profile), [
      'research',
      'writer',
    ]);
    expect(capturedMembers!.map((member) => member.routeId), [
      'research',
      'writer',
    ]);
    expect(capturedMembers!.map((member) => member.target), [
      {'kind': 'local', 'profile': 'research'},
      {'kind': 'local', 'profile': 'writer'},
    ]);
    // The created room is inserted without waiting for the next poll.
    expect(find.text('Design room'), findsOneWidget);
  });

  testWidgets('creating a room needs at least two members', (tester) async {
    await _pump(
      tester,
      loader: () async => const GroupRoomPage(),
      capabilities: () async => const GroupCapabilities(
        seatableProfiles: ['research', 'writer'],
        methods: ['groups.list', 'groups.create'],
        seatableProfilesKnown: true,
      ),
    );

    await tester.tap(find.text('New group'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'Team');
    await tester.tap(find.widgetWithText(FilterChip, 'research'));
    await tester.pump();

    expect(find.text('Choose at least two bots'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.widgetWithText(FilterChip, 'writer'));
    await tester.pump();

    expect(find.text('Choose at least two bots'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('creating a room refuses more than six members', (tester) async {
    await _pump(
      tester,
      loader: () async => const GroupRoomPage(),
      capabilities: () async => const GroupCapabilities(
        seatableProfiles: ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'],
        methods: ['groups.list', 'groups.create'],
        seatableProfilesKnown: true,
      ),
    );

    await tester.tap(find.text('New group'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'Team');
    for (final profile in ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7']) {
      final chip = find.widgetWithText(FilterChip, profile);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
    }

    expect(find.text('A group chat can hold at most six bots'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a gateway without seatable_profiles seats from profiles.list', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: () async => const GroupRoomPage(),
      // An older gateway: capabilities answers, but never lists a roster.
      capabilities: () async => const GroupCapabilities(driver: true),
      testProfiles: () async => const [
        BotProfile(
          name: 'research',
          displayName: 'Research',
          model: '',
          description: '',
        ),
        BotProfile(
          name: 'writer',
          displayName: 'Writer',
          model: '',
          description: '',
        ),
      ],
    );

    await tester.tap(find.text('New group'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.widgetWithText(FilterChip, 'research'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'writer'), findsOneWidget);
  });

  testWidgets('an empty roster says so instead of a dead create sheet', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: () async => const GroupRoomPage(),
      capabilities: () async => const GroupCapabilities(driver: true),
      testProfiles: () async => const [],
    );

    await tester.tap(find.text('New group'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FilterChip), findsNothing);
    expect(
      find.text('This gateway does not advertise a seating roster'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'))
          .onPressed,
      isNull,
    );
  });
}
