import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/models/session_search_hit.dart';

Session _session(String id, {bool pinned = false}) => Session.fromJson({
  'id': id,
  'title': 'Chat $id',
  'model': 'gpt-5',
  'source': 'gateway',
  'message_count': 1,
  'preview': 'hello',
  'started_at': 1,
  'pinned': pinned,
});

SessionSearchHit _hit(String id) => SessionSearchHit.fromJson({
  'session_id': id,
  'title': 'Chat $id',
  'snippet': 'match',
  'role': 'assistant',
});

void main() {
  test('search hits borrow a loaded pinned row by id', () {
    final hit = _hit('pinned');
    expect(hit.session.pinKnown, isFalse);

    final merged = inheritLoadedSessionPins([hit], [_session('pinned', pinned: true)]);
    expect(merged.single.session.pinned, isTrue);
    expect(merged.single.session.pinKnown, isTrue);
    expect(merged.single.snippet, 'match');
    expect(merged.single.role, 'assistant');
  });

  test('a loaded unpinned row makes the pin state known and false', () {
    final merged = inheritLoadedSessionPins([_hit('plain')], [_session('plain')]);
    expect(merged.single.session.pinned, isFalse);
    expect(merged.single.session.pinKnown, isTrue);
  });

  test('a hit absent from loaded rows keeps its pin state unknown', () {
    final merged = inheritLoadedSessionPins([_hit('missing')], [_session('other')]);
    expect(merged.single.session.pinKnown, isFalse);
  });
}
