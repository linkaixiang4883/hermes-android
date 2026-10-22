import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/pending_prompt.dart';
import 'package:hermes_android/core/services/prompt_notifier.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingSink implements TurnNotificationSink {
  final List<TurnNotification> shown = [];
  final List<int> cancelled = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool?> requestPermission() async => true;

  @override
  Future<NotificationResponse?> takeInitialLaunchResponse() async => null;

  @override
  Future<void> show(TurnNotification notification) async {
    shown.add(notification);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }

  @override
  Future<void> cancelAll() async {}
}

PendingPrompt _prompt(String id, {String method = 'approval'}) => PendingPrompt(
  id: id,
  method: method,
  mobileSessionId: 'mobile-b',
  gatewaySessionId: 'g-b',
  summary: 'rm -rf build',
  choices: const ['once', 'deny'],
  createdAt: DateTime(2026),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('posts one notification per prompt and cancels when it resolves',
      () async {
    final sink = _RecordingSink();
    final service = TurnNotificationService(sink: sink);
    await service.ensureInitialized();
    final prompts = ValueNotifier<List<PendingPrompt>>(const []);
    final notifier = PromptNotifier(
      notifications: service,
      titleFor: (_) => 'Bot Chat',
      formatTitle: ({required approval, sessionTitle}) =>
          '${approval ? 'Approval' : 'Input'} — $sessionTitle',
      approveLabel: () => 'Allow',
      denyLabel: () => 'Deny',
    )..attach(prompts, connectionId: 'conn-1');

    prompts.value = [_prompt('r1')];
    await Future<void>.delayed(Duration.zero);
    expect(sink.shown, hasLength(1));
    expect(sink.shown.single.title, 'Approval — Bot Chat');
    expect(sink.shown.single.actions.map((a) => a.id), ['approve', 'reject']);

    // The same prompt re-published must not buzz twice.
    prompts.value = [_prompt('r1')];
    await Future<void>.delayed(Duration.zero);
    expect(sink.shown, hasLength(1));

    // Resolving anywhere (answer, cancel, other client) removes the card.
    prompts.value = const [];
    await Future<void>.delayed(Duration.zero);
    expect(sink.cancelled, hasLength(1));

    notifier.detach();
  });

  test('input prompts carry no action buttons', () async {
    final sink = _RecordingSink();
    final service = TurnNotificationService(sink: sink);
    await service.ensureInitialized();
    final prompts = ValueNotifier<List<PendingPrompt>>(const []);
    final notifier = PromptNotifier(
      notifications: service,
      titleFor: (_) => null,
      formatTitle: ({required approval, sessionTitle}) => 'Input',
      approveLabel: () => 'Allow',
      denyLabel: () => 'Deny',
    )..attach(prompts, connectionId: 'conn-1');

    prompts.value = [_prompt('c1', method: 'clarify')];
    await Future<void>.delayed(Duration.zero);
    expect(sink.shown.single.actions, isEmpty);
    notifier.detach();
  });
}
