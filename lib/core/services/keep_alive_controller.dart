import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the "keep the connection alive in the background" switch and drives
/// the Android foreground service behind it.
///
/// Android freezes cached processes and Doze drops their network, so the
/// gateway WebSocket that carries approvals and turn completions dies as soon
/// as the user switches away from the app. A foreground service is the
/// platform's supported way to stay scheduled: it keeps this process (and the
/// socket the Flutter engine owns) running, at the cost of an ongoing
/// notification and some battery. The switch exists because that cost is the
/// user's call — it is on by default, and turning it off stops the service.
///
/// The controller never creates the socket itself; [syncForConnections] only
/// mirrors whether one exists. Every platform call is best effort: a missing
/// plugin (iOS, desktop, tests) or a refused start must leave the app working.
class KeepAliveController {
  KeepAliveController._({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// The app-wide instance: the settings switch and the workspace must agree
  /// on one value and one service.
  static final KeepAliveController shared = KeepAliveController._();

  /// Builds an instance bound to [channel] so tests can observe the platform
  /// calls without an Android device.
  @visibleForTesting
  factory KeepAliveController.withChannel(MethodChannel channel) =>
      KeepAliveController._(channel: channel);

  static const channelName = 'com.hermesagent.hermes_android/keep_alive';

  /// Per-device preference key; absent means on.
  static const storageKey = 'keep_alive_enabled';

  final MethodChannel _channel;

  /// The live value the settings switch renders.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  Future<void>? _loaded;
  bool _hasConnection = false;
  bool _running = false;

  /// Reads the persisted switch into [enabled]. Idempotent: the first
  /// [syncForConnections] or [setEnabled] loads it too, so a caller that only
  /// attaches a connection never has to remember to load first.
  Future<void> load() => _ensureLoaded();

  Future<void> _ensureLoaded() => _loaded ??= _readPrefs();

  Future<void> _readPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(storageKey) ?? true;
    } catch (_) {
      // An unreadable store keeps the default (on) instead of blocking.
    }
  }

  /// Persists [value] and applies it: turning the switch off stops the service
  /// right away, turning it on starts it only when there is a socket to keep.
  Future<void> setEnabled(bool value) async {
    await _ensureLoaded();
    enabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(storageKey, value);
    } catch (_) {
      // Persistence is best effort: the switch already moved this session.
    }
    if (!value) {
      await _stop();
    } else if (_hasConnection) {
      await _start();
    }
  }

  /// Mirrors whether the app currently holds a gateway connection.
  ///
  /// A connection that exists while the switch is on keeps the service up; no
  /// connection (or the switch off) tears it down, because a foreground
  /// service with nothing to keep alive is only a notification and a battery
  /// cost.
  Future<void> syncForConnections({required bool hasGatewayConnection}) async {
    await _ensureLoaded();
    _hasConnection = hasGatewayConnection;
    if (hasGatewayConnection && enabled.value) {
      await _start();
    } else {
      await _stop();
    }
  }

  Future<bool> _start() async {
    if (_running) return true;
    final started = await _invoke('start');
    _running = started;
    return started;
  }

  Future<void> _stop() async {
    _running = false;
    // Always tell the platform: a service restarted sticky by Android outlives
    // this instance's bookkeeping, and stopService is harmless when idle.
    await _invoke('stop');
  }

  Future<bool> _invoke(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      // iOS, desktop and plain `flutter test` have no foreground service.
      return false;
    } on PlatformException catch (error) {
      debugPrint('KeepAliveController.$method failed: ${error.code}');
      return false;
    }
  }
}
