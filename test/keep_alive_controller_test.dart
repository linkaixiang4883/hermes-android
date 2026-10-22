import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/keep_alive_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(KeepAliveController.channelName);
  late List<String> calls;
  late bool startAccepted;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    startAccepted = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'start' ? startAccepted : true;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  KeepAliveController build() => KeepAliveController.withChannel(channel);

  test('the switch defaults to on without touching the platform', () async {
    final controller = build();
    await controller.load();
    expect(controller.enabled.value, isTrue);
    expect(calls, isEmpty);
  });

  test('a gateway connection starts the service', () async {
    final controller = build();
    await controller.syncForConnections(hasGatewayConnection: true);
    expect(calls, ['start']);
    expect(controller.enabled.value, isTrue);
  });

  test('without a connection the service stays down', () async {
    final controller = build();
    await controller.syncForConnections(hasGatewayConnection: true);
    await controller.syncForConnections(hasGatewayConnection: false);
    expect(calls, ['start', 'stop']);
  });

  test('a running service is not restarted by a repeated sync', () async {
    final controller = build();
    await controller.syncForConnections(hasGatewayConnection: true);
    await controller.syncForConnections(hasGatewayConnection: true);
    expect(calls, ['start']);
  });

  test('turning the switch off stops the service and persists it', () async {
    final controller = build();
    await controller.syncForConnections(hasGatewayConnection: true);

    await controller.setEnabled(false);

    expect(calls, ['start', 'stop']);
    expect(controller.enabled.value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(KeepAliveController.storageKey), isFalse);
  });

  test('the persisted switch is honoured on the next launch', () async {
    SharedPreferences.setMockInitialValues({
      KeepAliveController.storageKey: false,
    });
    final controller = build();
    await controller.syncForConnections(hasGatewayConnection: true);

    expect(controller.enabled.value, isFalse);
    expect(calls, ['stop']);
  });

  test('re-enabling with a live connection starts the service again', () async {
    final controller = build();
    await controller.syncForConnections(hasGatewayConnection: true);
    await controller.setEnabled(false);
    await controller.setEnabled(true);

    expect(calls, ['start', 'stop', 'start']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(KeepAliveController.storageKey), isTrue);
  });

  test('enabling without a connection waits for one to appear', () async {
    final controller = build();
    await controller.setEnabled(true);
    expect(calls, isEmpty);

    await controller.syncForConnections(hasGatewayConnection: true);
    expect(calls, ['start']);
  });

  test('a platform that refuses the start leaves the switch usable', () async {
    startAccepted = false;
    final controller = build();
    await controller.syncForConnections(hasGatewayConnection: true);

    expect(controller.enabled.value, isTrue);
    // The next sync retries instead of believing the service is up.
    startAccepted = true;
    await controller.syncForConnections(hasGatewayConnection: true);
    expect(calls, ['start', 'start']);
  });

  test('a missing platform channel is not an error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final controller = build();

    await controller.syncForConnections(hasGatewayConnection: true);
    await controller.setEnabled(false);

    expect(controller.enabled.value, isFalse);
  });
}
