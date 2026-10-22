import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/turn_completion_notifier.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/core/services/ws_client.dart' show StreamEvent;
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingSink implements TurnNotificationSink {
  final List<TurnNotification> shown = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool?> requestPermission() async => true;

  @override
  Future<NotificationResponse?> takeInitialLaunchResponse() async => null;

  @override
  Future<void> show(TurnNotification notification) async => shown.add(notification);

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}
}

StreamEvent _terminal(String type, {String text = 'answer text'}) => StreamEvent(
  type: type,
  data: {'session_id': 'g-1', 'turn_id': 'turn-1', 'text': text},
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a completed turn notifies once, with the session title', () async {
    final sink = _RecordingSink();
    final service = TurnNotificationService(sink: sink);
    await service.ensureInitialized();
    final notifier = TurnCompletionNotifier(
      notifications: service,
      titleFor: (_) => 'Research Bot',
      isSessionVisible: (_) => false,
      formatTitle: ({required failed, sessionTitle}) =>
          '${failed ? 'Failed' : 'Ready'} — $sessionTitle',
    );

    notifier.handleEvent(_terminal('message.complete'), null);
    notifier.handleEvent(_terminal('message.complete'), null); // replay
    await Future<void>.delayed(Duration.zero);

    expect(sink.shown, hasLength(1));
    expect(sink.shown.single.title, 'Ready — Research Bot');
    expect(sink.shown.single.body, 'answer text');
  });

  test('the chat on screen is not news', () async {
    final sink = _RecordingSink();
    final service = TurnNotificationService(sink: sink);
    await service.ensureInitialized();
    final notifier = TurnCompletionNotifier(
      notifications: service,
      titleFor: (_) => 'Research Bot',
      isSessionVisible: (_) => true,
      formatTitle: ({required failed, sessionTitle}) => 'Ready',
    );

    notifier.handleEvent(_terminal('message.complete'), null);
    await Future<void>.delayed(Duration.zero);
    expect(sink.shown, isEmpty);
  });

  test('failures post the error kind', () async {
    final sink = _RecordingSink();
    final service = TurnNotificationService(sink: sink);
    await service.ensureInitialized();
    final notifier = TurnCompletionNotifier(
      notifications: service,
      titleFor: (_) => 'Bot',
      isSessionVisible: (_) => false,
      formatTitle: ({required failed, sessionTitle}) => failed ? 'Failed' : 'Ready',
    );

    notifier.handleEvent(_terminal('turn.error', text: 'boom'), null);
    await Future<void>.delayed(Duration.zero);
    expect(sink.shown.single.channel.id, 'hermes_turn_notifications');
    expect(sink.shown.single.title, 'Failed');
  });
}
