// Desktop-local ("legacy") group chats, as Desktop mirrors them into the
// `default` profile's `ui_meta['hermes-bots-groups']`.
//
// Desktop's plugin keeps its room log in renderer-local storage and — because
// a phone cannot read another device's localStorage — publishes a bounded,
// display-oriented copy into gateway profile metadata ("so mobile can show the
// same messages"). These rooms have no `groups.*` counterpart: there is no
// hosted room to send to, no driver, and no replay cursor. The phone therefore
// renders them read-only until Desktop promotes one with "Start gateway group".
//
// Wire shape (version 3):
//   {
//     "version": 3,
//     "updatedAt": 1792586838021,
//     "rooms": {
//       "id:<roomId>": {
//         "name": "…", "roomId": "…",
//         "log": [{"id": "…", "at": 1792586837446,
//                  "from": {"kind": "member"|"user", "name": "…", "source": "…"},
//                  "text": "…"}]
//       }
//     },
//     "deleted": {"<name-or-key>": revision}
//   }

/// One mirrored message. [atMs] stays milliseconds: the mirror uses epoch
/// millis, unlike `groups.*` events which use seconds.
class LegacyGroupMessage {
  final String id;
  final String author;
  final String text;
  final int atMs;
  final bool fromMember;
  final String source;

  const LegacyGroupMessage({
    this.id = '',
    this.author = '',
    this.text = '',
    this.atMs = 0,
    this.fromMember = false,
    this.source = '',
  });

  factory LegacyGroupMessage.fromJson(Map<String, dynamic> json) {
    final from = _object(json['from']);
    final kind = _text(from['kind']).trim();
    return LegacyGroupMessage(
      id: _text(json['id']).trim(),
      author: _text(from['name']).trim(),
      text: _text(json['text']),
      atMs: _integer(json['at']),
      fromMember: kind == 'member',
      source: _text(from['source']).trim(),
    );
  }

  DateTime? get sentAt => atMs > 0
      ? DateTime.fromMillisecondsSinceEpoch(atMs)
      : null;
}

/// A Desktop-local group room as seen through the profile mirror.
class LegacyGroupChat {
  final String key;
  final String roomId;
  final String name;
  final List<LegacyGroupMessage> messages;

  const LegacyGroupChat({
    required this.key,
    this.roomId = '',
    this.name = '',
    this.messages = const [],
  });

  String get title => name.isEmpty ? (roomId.isEmpty ? key : roomId) : name;

  bool get isReadOnly => true;

  int get lastAtMs =>
      messages.isEmpty ? 0 : messages.last.atMs;

  /// Decodes the `hermes-bots-groups` snapshot.
  ///
  /// Tombstoned rooms (Desktop's `deleted` map, keyed by room name or room key)
  /// are dropped: Desktop explicitly keeps them out of the mobile projection.
  static List<LegacyGroupChat> listFromSnapshot(Object? snapshot) {
    if (snapshot is! Map) return const [];
    final rooms = snapshot['rooms'];
    if (rooms is! Map) return const [];
    final deleted = snapshot['deleted'];
    final dead = <String>{
      if (deleted is Map)
        for (final entry in deleted.entries)
          if (entry.key is String) entry.key as String,
    };

    final out = <LegacyGroupChat>[];
    for (final entry in rooms.entries) {
      final key = entry.key is String ? entry.key as String : '';
      final raw = entry.value;
      if (key.isEmpty || raw is! Map) continue;
      final room = _object(raw);
      final name = _text(room['name']).trim();
      if (dead.contains(key) || (name.isNotEmpty && dead.contains(name))) {
        continue;
      }
      final log = room['log'];
      final messages = <LegacyGroupMessage>[];
      if (log is List) {
        for (final row in log) {
          if (row is! Map) continue;
          final message = LegacyGroupMessage.fromJson(_object(row));
          if (message.text.trim().isEmpty && message.id.isEmpty) continue;
          messages.add(message);
        }
      }
      if (messages.isEmpty) continue;
      out.add(
        LegacyGroupChat(
          key: key,
          roomId: _text(room['roomId'] ?? room['room_id']).trim(),
          name: name,
          messages: messages,
        ),
      );
    }
    out.sort((left, right) => right.lastAtMs.compareTo(left.lastAtMs));
    return out;
  }
}

// ── Tolerant scalar helpers (shared style with group_rooms_client) ────────

String _text(Object? value) => value == null ? '' : value.toString();

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_text(value).trim()) ?? 0;
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
