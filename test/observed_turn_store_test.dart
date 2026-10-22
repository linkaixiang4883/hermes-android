import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/observed_turn_store.dart';
import 'package:hermes_android/core/services/ws_client.dart' show StreamEvent;
import 'package:shared_preferences/shared_preferences.dart';

StreamEvent _event(String type, {String session = 'g-1', String? text}) =>
    StreamEvent(
      type: type,
      data: {
        'session_id': session,
        'text': ?text,
      },
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('deltas mark running and terminal frames settle the row', () {
    final store = ObservedTurnStore();
    store.observe(_event('message.delta', session: 'g-a'), 'm-a', title: 'A');
    expect(store.forSession('g-a')?.state, 'running');
    expect(store.forSession('g-a')?.title, 'A');

    store.observe(_event('message.complete', session: 'g-a', text: 'done!'), 'm-a');
    expect(store.forSession('g-a')?.state, 'completed');
    expect(store.forSession('g-a')?.summary, 'done!');
  });

  test('one row per chat, newest first', () {
    final store = ObservedTurnStore();
    store.observe(_event('message.delta', session: 'g-a'), 'm-a');
    store.observe(_event('message.delta', session: 'g-b'), 'm-b');
    store.observe(_event('message.delta', session: 'g-a'), 'm-a');
    expect(store.entries.map((e) => e.gatewaySessionId), ['g-a', 'g-b']);
    expect(store.entries, hasLength(2));
  });

  test('the cap evicts the oldest chat', () {
    final store = ObservedTurnStore(maxEntries: 2);
    for (final id in ['g-1', 'g-2', 'g-3']) {
      store.observe(_event('message.delta', session: id), 'm-$id');
    }
    expect(store.entries.map((e) => e.gatewaySessionId), ['g-3', 'g-2']);
  });

  test('persists and reloads', () async {
    final first = ObservedTurnStore();
    await first.load();
    first.observe(_event('message.delta', session: 'g-x'), 'm-x', title: 'X');
    first.observe(_event('turn.error', session: 'g-x', text: 'boom'), 'm-x');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final second = ObservedTurnStore();
    await second.load();
    expect(second.forSession('g-x')?.state, 'failed');
    expect(second.forSession('g-x')?.summary, 'boom');
  });
}
