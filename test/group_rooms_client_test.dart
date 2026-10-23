// Hosted rooms over `groups.*`: the wire shapes the gateway requires, and the
// tolerance the phone needs when the server sends more (or less) than the app
// was written against.

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/group_rooms_client.dart';

/// Records calls and replays canned envelopes in order.
class _RecordingRpc {
  final List<({String method, Map<String, dynamic> params})> calls = [];
  final List<Map<String, dynamic>> responses;

  _RecordingRpc([List<Map<String, dynamic>>? responses])
    : responses = responses ?? [];

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params,
  ) async {
    calls.add((method: method, params: params));
    if (responses.isEmpty) {
      throw StateError('no canned response for $method');
    }
    return responses.removeAt(0);
  }
}

Map<String, dynamic> _ok(Map<String, dynamic> result) => {
  'jsonrpc': '2.0',
  'id': 1,
  'result': result,
};

Map<String, dynamic> _error(int code, String message) => {
  'jsonrpc': '2.0',
  'id': 1,
  'error': {'code': code, 'message': message},
};

Map<String, dynamic> _roomJson({
  String roomId = 'room-1',
  String name = 'Launch room',
  int latestSeq = 12,
  double? disbandedAt,
  List<Map<String, dynamic>>? members,
}) => {
  'room_id': roomId,
  'name': name,
  'members':
      members ??
      [
        {'profile': 'research', 'handle': 'research', 'display_name': 'Research'},
        {'profile': 'writer', 'handle': 'writer', 'display_name': 'Writer'},
      ],
  'latest_seq': latestSeq,
  'updated_at': 1761000000.0,
  'disbanded_at': disbandedAt,
};

Map<String, dynamic> _eventJson({
  required int seq,
  required String kind,
  Map<String, dynamic>? actor,
  Map<String, dynamic>? payload,
}) => {
  'seq': seq,
  'kind': kind,
  'actor': ?actor,
  'payload': ?payload,
};

void main() {
  group('groups.capabilities', () {
    test('surfaces the seating roster and the log bound', () async {
      final rpc = _RecordingRpc([
        _ok({
          'seatable_profiles': ['research', 'writer'],
          'methods': ['groups.list', 'groups.log'],
          'max_log_limit': 500,
        }),
      ]);
      final client = GroupRoomsClient(rpc.call);

      final capabilities = await client.capabilities();

      expect(rpc.calls.single.method, 'groups.capabilities');
      expect(rpc.calls.single.params, isEmpty);
      expect(capabilities.seatableProfiles, ['research', 'writer']);
      expect(capabilities.supports('groups.log'), isTrue);
      expect(capabilities.maxLogLimit, 500);
      expect(capabilities.effectiveLogLimit, 500);
    });

    test('a missing roster degrades to empty instead of throwing', () async {
      final rpc = _RecordingRpc([
        _ok({'seatable_profiles': 'nope'}),
      ]);
      final capabilities = await GroupRoomsClient(
        rpc.call,
      ).capabilities();

      expect(capabilities.seatableProfiles, isEmpty);
      expect(capabilities.maxLogLimit, 0);
      expect(capabilities.effectiveLogLimit, 200);
    });
  });

  group('groups.list', () {
    test('omits filters by default and decodes rooms', () async {
      final rpc = _RecordingRpc([
        _ok({
          'rooms': [_roomJson(), _roomJson(roomId: 'room-2', name: 'Second')],
          'next_offset': 2,
        }),
      ]);
      final client = GroupRoomsClient(rpc.call);

      final page = await client.list();

      expect(rpc.calls.single.method, 'groups.list');
      expect(rpc.calls.single.params, isEmpty);
      expect(page.rooms, hasLength(2));
      expect(page.rooms.first.roomId, 'room-1');
      expect(page.rooms.first.title, 'Launch room');
      expect(page.rooms.first.members.map((m) => m.label), [
        'Research',
        'Writer',
      ]);
      expect(page.rooms.first.handles, ['research', 'writer']);
      expect(page.rooms.first.latestSeq, 12);
      expect(page.rooms.first.isDisbanded, isFalse);
      expect(page.nextOffset, 2);
    });

    test('forwards include_disbanded, limit and offset when asked', () async {
      final rpc = _RecordingRpc([_ok({'rooms': <dynamic>[]})]);
      await GroupRoomsClient(rpc.call).list(
        includeDisbanded: true,
        limit: 20,
        offset: 40,
      );

      expect(rpc.calls.single.params, {
        'include_disbanded': true,
        'limit': 20,
        'offset': 40,
      });
    });

    test('a disbanded tombstone keeps its marker', () async {
      final rpc = _RecordingRpc([
        _ok({
          'rooms': [_roomJson(disbandedAt: 1761000500.0)],
        }),
      ]);
      final page = await GroupRoomsClient(rpc.call).list();

      expect(page.rooms.single.isDisbanded, isTrue);
      expect(page.rooms.single.disbandedAt, 1761000500.0);
    });
  });

  group('groups.create', () {
    test('sends a uuid, the name, and handle-bearing members', () async {
      final rpc = _RecordingRpc([
        _ok({'room': _roomJson(roomId: 'room-9', name: 'Design')}),
      ]);
      final client = GroupRoomsClient(rpc.call);

      final room = await client.create(
        roomId: 'room-9',
        name: 'Design',
        members: const [GroupRoomMember(profile: 'research')],
      );

      expect(rpc.calls.single.method, 'groups.create');
      expect(rpc.calls.single.params['room_id'], 'room-9');
      expect(rpc.calls.single.params['name'], 'Design');
      expect(rpc.calls.single.params['members'], [
        {
          'profile': 'research',
          'handle': 'research',
          'display_name': 'research',
        },
      ]);
      expect(room.roomId, 'room-9');
      expect(room.name, 'Design');
    });

    test('accepts an unwrapped room payload', () async {
      final rpc = _RecordingRpc([_ok(_roomJson(roomId: 'room-3'))]);
      final room = await GroupRoomsClient(rpc.call).create(
        roomId: 'room-3',
        name: 'x',
        members: const [],
      );
      expect(room.roomId, 'room-3');
    });
  });

  group('groups.state', () {
    test('decodes driver status and its pending approvals verbatim', () async {
      final rpc = _RecordingRpc([
        _ok({
          'room': _roomJson(),
          'driver_status': {
            'running': true,
            'working': false,
            'blocked': true,
            'counts': {'pending': 1, 'settled': 4},
            'pending_actions': [
              {
                'kind': 'approval',
                'member_id': 'research',
                'task_id': 'task-7',
                'execution_generation': 3,
                'request_id': 'req-2',
                'summary': 'run tests',
              },
              {'kind': 'retry', 'task_id': 'task-8', 'member_id': 'writer'},
            ],
            'peer_routes': [
              {'member_id': 'writer'},
            ],
          },
        }),
      ]);
      final client = GroupRoomsClient(rpc.call);

      final state = await client.state('room-1');

      expect(rpc.calls.single.params, {'room_id': 'room-1'});
      expect(state.room.roomId, 'room-1');
      expect(state.driverStatus.running, isTrue);
      expect(state.driverStatus.blocked, isTrue);
      expect(state.driverStatus.busy, isTrue);
      expect(state.driverStatus.counts, {'pending': 1, 'settled': 4});
      expect(state.driverStatus.peerRoutes, hasLength(1));

      final approval = state.driverStatus.approvals.single;
      expect(approval.memberId, 'research');
      expect(approval.taskId, 'task-7');
      // Generation arrives as a number; the wire call takes it as a string.
      expect(approval.executionGeneration, '3');
      expect(approval.requestId, 'req-2');
      expect(state.driverStatus.retries.single.taskId, 'task-8');
    });

    test('survives a hollow driver_status', () async {
      final rpc = _RecordingRpc([
        _ok({'room': _roomJson(), 'driver_status': 'unknown'}),
      ]);
      final state = await GroupRoomsClient(rpc.call).state('room-1');

      expect(state.driverStatus.running, isFalse);
      expect(state.driverStatus.pendingActions, isEmpty);
      expect(state.driverStatus.busy, isFalse);
    });
  });

  group('groups.log', () {
    test('asks strictly after the cursor and decodes every event kind', () async {
      final rpc = _RecordingRpc([
        _ok({
          'events': [
            _eventJson(
              seq: 13,
              kind: 'message.user',
              actor: {'kind': 'user', 'id': 'u1', 'display_name': 'LKX'},
              payload: {
                'text': 'kick off',
                'thread_id': 'room-1',
              },
            ),
            _eventJson(
              seq: 14,
              kind: 'message.member',
              actor: {
                'kind': 'member',
                'id': 'm1',
                'handle': 'research',
                'display_name': 'Research',
                'profile': 'research',
              },
              payload: {
                'text': 'on it',
                'discussion_event_id': 'd-9',
              },
            ),
            _eventJson(
              seq: 15,
              kind: 'turn.settled',
              actor: {'kind': 'gateway', 'id': 'gw'},
            ),
            _eventJson(
              seq: 16,
              kind: 'authority.claimed',
              actor: {'kind': 'system', 'id': 's'},
            ),
            _eventJson(
              seq: 17,
              kind: 'room.renamed',
              payload: {'name': 'Launch v2'},
            ),
          ],
          'cursor': 17,
          'latest_seq': 17,
          'has_more': false,
        }),
      ]);
      final client = GroupRoomsClient(rpc.call);

      final page = await client.log('room-1', sinceSeq: 12, limit: 50);

      expect(rpc.calls.single.method, 'groups.log');
      expect(rpc.calls.single.params, {
        'room_id': 'room-1',
        'since_seq': 12,
        'limit': 50,
      });
      expect(page.events.map((event) => event.seq), [13, 14, 15, 16, 17]);
      expect(page.cursor, 17);
      expect(page.latestSeq, 17);
      expect(page.hasMore, isFalse);

      final user = page.events[0];
      expect(user.isUserMessage, isTrue);
      expect(user.authorLabel, 'LKX');
      expect(user.text, 'kick off');

      final member = page.events[1];
      expect(member.isMemberMessage, isTrue);
      expect(member.isMessage, isTrue);
      expect(member.authorLabel, 'Research');
      expect(member.discussionEventId, 'd-9');

      expect(page.events[2].isTurn, isTrue);
      expect(page.events[3].isAuthority, isTrue);
      expect(page.events[3].isRenderable, isFalse);
      expect(page.events[4].isRoomLifecycle, isTrue);
      expect(page.events[4].isNotice, isTrue);
    });

    test('omits the limit so the server default stands', () async {
      final rpc = _RecordingRpc([_ok({'events': <dynamic>[]})]);
      await GroupRoomsClient(rpc.call).log('room-1', sinceSeq: 0);
      expect(rpc.calls.single.params, {'room_id': 'room-1', 'since_seq': 0});
    });

    test('a malformed event never throws and never loses its seq', () async {
      final rpc = _RecordingRpc([
        _ok({
          'events': [
            {'seq': '21', 'kind': 42, 'actor': 'nonsense', 'payload': null},
            'not-a-map',
          ],
          'cursor': '21',
          'has_more': 'false',
        }),
      ]);
      final page = await GroupRoomsClient(rpc.call).log('room-1', sinceSeq: 20);

      expect(page.events, hasLength(1));
      expect(page.events.single.seq, 21);
      expect(page.events.single.text, isEmpty);
      expect(page.events.single.authorLabel, isEmpty);
      expect(page.cursor, 21);
      expect(page.hasMore, isFalse);
      expect(page.latestSeq, 0);
    });
  });

  group('groups.send', () {
    test('frames payload.thread_id + text with the caller event id', () async {
      final rpc = _RecordingRpc([
        _ok({
          'event': _eventJson(
            seq: 18,
            kind: 'message.user',
            actor: {'kind': 'user', 'id': 'u1'},
            payload: {'text': 'hello'},
          ),
          'accepted': true,
          'driver_started': true,
        }),
      ]);
      final client = GroupRoomsClient(rpc.call);

      final result = await client.send(
        roomId: 'room-1',
        eventId: 'event-abc',
        text: 'hello',
        threadId: 'room-1',
      );

      expect(rpc.calls.single.method, 'groups.send');
      expect(rpc.calls.single.params, {
        'room_id': 'room-1',
        'event_id': 'event-abc',
        'payload': {'thread_id': 'room-1', 'text': 'hello'},
      });
      expect(result.accepted, isTrue);
      expect(result.driverStarted, isTrue);
      expect(result.event?.seq, 18);
    });

    test('a rejected send keeps accepted false and yields no event', () async {
      final rpc = _RecordingRpc([
        _ok({'accepted': false}),
      ]);
      final result = await GroupRoomsClient(rpc.call).send(
        roomId: 'room-1',
        eventId: 'event-abc',
        text: '   ',
        threadId: 'room-1',
      );

      expect(result.accepted, isFalse);
      expect(result.event, isNull);
    });
  });

  group('driver actions', () {
    test('approve echoes the identity tuple and the choice', () async {
      final rpc = _RecordingRpc([_ok({})]);
      const action = PendingRoomAction(
        kind: 'approval',
        memberId: 'research',
        taskId: 'task-7',
        executionGeneration: '3',
        requestId: 'req-2',
      );

      await GroupRoomsClient(
        rpc.call,
      ).approve(roomId: 'room-1', action: action, choice: GroupApproval.once);

      expect(rpc.calls.single.method, 'groups.approve');
      expect(rpc.calls.single.params, {
        'room_id': 'room-1',
        'member_id': 'research',
        'task_id': 'task-7',
        'execution_generation': '3',
        'request_id': 'req-2',
        'choice': 'once',
      });
    });

    test('approve omits identifiers a gateway did not send', () async {
      final rpc = _RecordingRpc([_ok({})]);
      const action = PendingRoomAction(kind: 'approval', taskId: 'task-1');

      await GroupRoomsClient(
        rpc.call,
      ).approve(roomId: 'room-1', action: action, choice: GroupApproval.deny);

      expect(rpc.calls.single.params, {
        'room_id': 'room-1',
        'task_id': 'task-1',
        'choice': 'deny',
      });
    });

    test('retry, stop, rename and disband keep their documented frames', () async {
      final rpc = _RecordingRpc([
        _ok({}),
        _ok({'cancelled': 2}),
        _ok({}),
        _ok({}),
      ]);
      final client = GroupRoomsClient(rpc.call);

      await client.retry(roomId: 'room-1', taskId: 'task-7');
      await client.stop('room-1');
      await client.rename(roomId: 'room-1', name: 'Launch v2', eventId: 'e-1');
      await client.disband('room-1');

      expect(rpc.calls.map((call) => call.method), [
        'groups.retry',
        'groups.stop',
        'groups.rename',
        'groups.disband',
      ]);
      expect(rpc.calls[0].params, {'room_id': 'room-1', 'task_id': 'task-7'});
      expect(rpc.calls[1].params, {'room_id': 'room-1'});
      expect(rpc.calls[2].params, {
        'room_id': 'room-1',
        'event_id': 'e-1',
        'name': 'Launch v2',
      });
      expect(rpc.calls[3].params, {'room_id': 'room-1'});
    });
  });

  group('transport', () {
    test('a gateway error becomes a typed exception with its message', () async {
      final rpc = _RecordingRpc([
        _error(-32602, 'unknown room'),
      ]);
      final client = GroupRoomsClient(rpc.call);

      await expectLater(
        client.state('missing'),
        throwsA(
          isA<GroupRoomException>()
              .having((error) => error.method, 'method', 'groups.state')
              .having((error) => error.message, 'message', 'unknown room'),
        ),
      );
    });

    test('an error without a message still names the method', () async {
      final rpc = _RecordingRpc([
        {
          'jsonrpc': '2.0',
          'id': 1,
          'error': {'code': -32601},
        },
      ]);
      await expectLater(
        GroupRoomsClient(rpc.call).list(),
        throwsA(
          isA<GroupRoomException>().having(
            (error) => error.message,
            'message',
            contains('rejected'),
          ),
        ),
      );
    });

    test('discovery asks capabilities and follows next_offset to the end', () async {
      final rpc = _RecordingRpc([
        _ok({
          'driver': true,
          'seatable_profiles': ['research'],
          'methods': ['groups.list'],
          'max_log_limit': 50,
        }),
        _ok({
          'rooms': [_roomJson(roomId: 'room-1')],
          'next_offset': 1,
        }),
        _ok({
          'rooms': [_roomJson(roomId: 'room-2', name: 'Second room')],
          'next_offset': null,
        }),
      ]);

      final discovery = await GroupRoomsClient(rpc.call).discover(pageSize: 1);

      expect(
        rpc.calls.map((call) => call.method),
        ['groups.capabilities', 'groups.list', 'groups.list'],
      );
      expect(rpc.calls[1].params['offset'], 0);
      expect(rpc.calls[2].params['offset'], 1);
      expect(
        discovery.rooms.map((room) => room.roomId),
        ['room-1', 'room-2'],
      );
      expect(discovery.driverAvailable, isTrue);
      expect(discovery.capabilities.seatableProfiles, ['research']);
    });

    test('a gateway without a discussion driver says so in discovery', () async {
      final rpc = _RecordingRpc([
        _ok({'driver': false}),
        _ok({'rooms': <dynamic>[], 'next_offset': null}),
      ]);

      final discovery = await GroupRoomsClient(rpc.call).discover();

      expect(discovery.driverAvailable, isFalse);
      expect(discovery.rooms, isEmpty);
    });

    test('the profile scope rides along without clobbering call params', () async {
      final rpc = _RecordingRpc([_ok({'rooms': <dynamic>[]})]);
      await GroupRoomsClient(rpc.call, profile: ' sol ').list(limit: 5);
      expect(rpc.calls.single.params['profile'], 'sol');
      expect(rpc.calls.single.params['limit'], 5);
    });
  });

  group('identifiers', () {
    test('mint distinct uuids a retry can reuse', () {
      final first = newGroupIdentifier();
      final second = newGroupIdentifier();
      expect(first, isNot(second));
      expect(first, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(first.split('-'), hasLength(5));
    });
  });
}
