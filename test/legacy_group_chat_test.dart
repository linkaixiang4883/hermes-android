// Desktop-local group chats arrive as a bounded profile-metadata mirror, not
// as `groups.*` rows. The parser must survive the mirror's loose shapes and
// keep tombstones out, or the phone shows rooms Desktop already discarded.

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/legacy_group_chat.dart';

Map<String, dynamic> _snapshot() => {
  'version': 3,
  'updatedAt': 1792586838021,
  'rooms': {
    'id:room-old': {
      'name': 'Older room',
      'roomId': 'room-old',
      'log': [
        {
          'id': 'm1',
          'at': 1792580000000,
          'from': {'kind': 'user', 'name': 'LKX'},
          'text': 'kick off',
        },
      ],
    },
    'id:room-new': {
      'name': 'Newer room',
      'roomId': 'room-new',
      'log': [
        {
          'id': 'm2',
          'at': 1792585862692,
          'from': {'kind': 'member', 'name': 'default', 'source': '本机9119'},
          'text': 'on it',
        },
        {
          'id': 'm3',
          'at': 1792586837446,
          'from': {'kind': 'member', 'name': 'writer'},
          'text': 'done',
        },
      ],
    },
    'id:room-empty': {
      'name': 'No history',
      'roomId': 'room-empty',
      'log': <dynamic>[],
    },
    'id:room-dead': {
      'name': 'Disbanded room',
      'roomId': 'room-dead',
      'log': [
        {
          'id': 'm4',
          'at': 1792580000000,
          'from': {'kind': 'user', 'name': 'LKX'},
          'text': 'gone',
        },
      ],
    },
  },
  'deleted': {'Disbanded room': 4},
};

void main() {
  group('legacy group mirror', () {
    test('decodes rooms, newest first, with authors and timestamps', () {
      final rooms = LegacyGroupChat.listFromSnapshot(_snapshot());

      expect(rooms.map((room) => room.title), ['Newer room', 'Older room']);
      expect(rooms.first.roomId, 'room-new');
      expect(rooms.first.messages, hasLength(2));
      expect(rooms.first.messages.first.author, 'default');
      expect(rooms.first.messages.first.fromMember, isTrue);
      expect(rooms.first.messages.first.source, '本机9119');
      expect(rooms.first.messages.last.author, 'writer');
      expect(
        rooms.first.messages.last.sentAt,
        DateTime.fromMillisecondsSinceEpoch(1792586837446),
      );
      expect(rooms.last.messages.single.fromMember, isFalse);
    });

    test('drops tombstoned and empty rooms', () {
      final rooms = LegacyGroupChat.listFromSnapshot(_snapshot());
      final names = rooms.map((room) => room.name).toList();

      expect(names, isNot(contains('Disbanded room')));
      expect(names, isNot(contains('No history')));
    });

    test('tolerates a missing or malformed snapshot', () {
      expect(LegacyGroupChat.listFromSnapshot(null), isEmpty);
      expect(LegacyGroupChat.listFromSnapshot('nope'), isEmpty);
      expect(LegacyGroupChat.listFromSnapshot({'rooms': 'nope'}), isEmpty);
      expect(
        LegacyGroupChat.listFromSnapshot({
          'rooms': {
            'id:x': {'name': 'X', 'log': [null, 'junk', {}]},
          },
        }),
        isEmpty,
      );
    });
  });
}
