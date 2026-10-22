import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/live_session_watcher.dart';

List<Map<String, dynamic>> _rows(List<(String, String, String)> rows) => [
  for (final (id, title, status) in rows)
    {'id': id, 'title': title, 'status': status},
];

void main() {
  test('attaches only running sessions and never twice', () async {
    final activated = <String>[];
    var rows = _rows([
      ('s-idle', 'Idle chat', 'idle'),
      ('s-working', 'Working chat', 'working'),
      ('s-waiting', 'Waiting chat', 'waiting'),
    ]);
    final watcher = LiveSessionWatcher(

      activeSessionLoader: () async => rows,
      sessionActivator: (id) async => activated.add(id),
    );

    await watcher.tick();
    expect(activated, ['s-working', 's-waiting']);
    expect(watcher.titleFor('s-working'), 'Working chat');

    await watcher.tick();
    expect(activated, ['s-working', 's-waiting'], reason: 'no re-attach');

    // A session that went idle and runs again needs a fresh attach.
    rows = _rows([
      ('s-working', 'Working chat', 'idle'),
      ('s-waiting', 'Waiting chat', 'working'),
    ]);
    await watcher.tick();
    expect(activated, ['s-working', 's-waiting'], reason: 'idle detaches');
    rows = _rows([('s-working', 'Working chat', 'working')]);
    await watcher.tick();
    expect(activated, ['s-working', 's-waiting', 's-working']);
  });

  test('one refused attach does not stop the rest', () async {
    final activated = <String>[];
    final watcher = LiveSessionWatcher(

      activeSessionLoader: () async => _rows([
        ('bad', 'Finalized', 'working'),
        ('good', 'Live', 'working'),
      ]),
      sessionActivator: (id) async {
        if (id == 'bad') throw StateError('4007');
        activated.add(id);
      },
    );
    await watcher.tick();
    expect(activated, ['good']);
  });

  test('a failed poll leaves state alone', () async {
    final watcher = LiveSessionWatcher(

      activeSessionLoader: () async => throw StateError('offline'),
      sessionActivator: (_) async {},
    );
    await watcher.tick(); // must not throw
    expect(watcher.attachedSessions, isEmpty);
  });
}
