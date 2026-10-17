// Phase 2C: the shared gateway client must not outlive the connection
// definition it was built from.
//
// Phase 2B-ii gave every connection one application-scoped
// `DesktopGatewayClient`, keyed by connection id and alive for as long as the
// app. That cache only knew how to be emptied on app shutdown, so a saved edit
// kept handing the old client back — old host, old port, old dashboard
// credentials, old profile — until a restart, and a deleted connection left its
// socket reconnecting to a host the user had removed.
//
// These tests pin the invalidation at the store, because the store is what
// knows a mutation landed: `ConnectionManager` notifies through
// `onConnectionClientInvalidated`, and the app wires that to its
// `GatewayClientRegistry` (the end-to-end wiring through the app widget is in
// home_connection_client_invalidation_test.dart).
//
// Pinned here:
//   * every mutation path that can change an identity field drops the client
//     (`updateConnection`, `updateDashboardAuth`, and the `gatewayProfile`
//     variant of the edit dialog), and the next borrow builds a client from the
//     *current* definition
//   * a rename, a REST api-key update and a REST path-prefix change do not:
//     a live socket is not torn down by an edit the client cannot see
//   * deleting a connection always drops its client
//   * a mutation that failed (fail-closed credential store) drops nothing
//   * a restore that removes a connection drops its client, while an untouched
//     sibling keeps its socket
//   * a store with no owner wired commits exactly as before

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_client_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryCredentialStore implements CredentialStore {
  final Map<String, String> values = <String, String>{};
  final Map<String, String> _cache = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
    _cache.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    final value = values[key];
    if (value == null) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    return value;
  }

  @override
  String? readCached(String key) => _cache[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

/// A working store that can be switched to failing, so one mutation runs into
/// the fail-closed credential path after an earlier one already succeeded.
class _SwitchableCredentialStore extends _MemoryCredentialStore {
  bool failWrites = false;

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) {
      throw StateError('secure store unavailable');
    }
    await super.write(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GatewayClientRegistry registry;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    registry = GatewayClientRegistry();
  });

  tearDown(() {
    registry.close();
  });

  /// A manager wired the way `main.dart` wires it: the store reports the
  /// connections whose cached client must go, the registry closes them.
  Future<ConnectionManager> buildManager({CredentialStore? store}) async {
    final prefs = await SharedPreferences.getInstance();
    final manager = await ConnectionManager.create(
      prefs,
      credentialStore: store ?? _MemoryCredentialStore(),
    );
    manager.onConnectionClientInvalidated = registry.closeConnection;
    return manager;
  }

  group('editing a saved connection', () {
    test('drops the client, and the next borrow rebuilds it', () async {
      final manager = await buildManager();
      await manager.saveConnection('Home', '192.168.1.50', 8642, 'key');
      final original = manager.getConnections().single;
      final client = registry.clientFor(original);
      expect(
        client.gatewayBaseUrl,
        DesktopGatewayClient.normalizedGatewayBaseUrl(original),
      );

      // The dashboard port is part of the origin every client is built from.
      await manager.updateConnection(
        original.id,
        original.label,
        original.host,
        original.port,
        original.apiKey,
        dashboardPort: 30433,
      );

      final edited = manager.getConnections().single;
      expect(
        gatewayClientIdentityChanged(original, edited),
        isTrue,
        reason: 'the fixture has to be an identity edit',
      );
      expect(
        client.isClosed,
        isTrue,
        reason: 'the client built for the old definition is released',
      );
      expect(registry.existingFor(original.id), isNull);

      final replacement = registry.clientFor(edited);
      expect(identical(replacement, client), isFalse);
      expect(
        replacement.gatewayBaseUrl,
        DesktopGatewayClient.normalizedGatewayBaseUrl(edited),
      );
      expect(
        replacement.gatewayBaseUrl,
        isNot(client.gatewayBaseUrl),
        reason: 'the replacement must dial the edited endpoint',
      );
    });

    test('drops the client when the host moves', () async {
      final manager = await buildManager();
      await manager.saveConnection('Home', '192.168.1.50', 8642, 'key');
      final original = manager.getConnections().single;
      final client = registry.clientFor(original);

      await manager.updateConnection(
        original.id,
        original.label,
        '192.168.1.99',
        original.port,
        original.apiKey,
      );

      expect(client.isClosed, isTrue);
      expect(registry.existingFor(original.id), isNull);
    });

    test('drops the client when the gateway profile changes', () async {
      final manager = await buildManager();
      await manager.saveConnection('Home', '192.168.1.50', 8642, 'key');
      final original = manager.getConnections().single;
      final client = registry.clientFor(original);

      await manager.updateConnection(
        original.id,
        original.label,
        original.host,
        original.port,
        original.apiKey,
        gatewayProfile: 'sol',
      );

      expect(client.isClosed, isTrue);
      expect(registry.existingFor(original.id), isNull);
      expect(manager.getConnections().single.gatewayProfile, 'sol');
    });

    test('drops the client when the dashboard credentials change', () async {
      final manager = await buildManager();
      await manager.saveConnection('Home', '192.168.1.50', 8642, 'key');
      final original = manager.getConnections().single;
      final client = registry.clientFor(original);

      await manager.updateDashboardAuth(
        original.id,
        dashboardPort: 30433,
        username: 'misha',
        password: 'secret',
      );

      expect(client.isClosed, isTrue);
      expect(registry.existingFor(original.id), isNull);
    });

    test('a rename keeps the live client', () async {
      final manager = await buildManager();
      await manager.saveConnection('Home', '192.168.1.50', 8642, 'key');
      final original = manager.getConnections().single;
      final client = registry.clientFor(original);

      await manager.updateConnection(
        original.id,
        'Study gateway',
        original.host,
        original.port,
        original.apiKey,
      );

      expect(manager.getConnections().single.label, 'Study gateway');
      expect(
        registry.existingFor(original.id),
        same(client),
        reason:
            'a display-name edit must not cut a socket the connection still '
            'needs',
      );
      expect(client.isClosed, isFalse);
    });

    test('a REST-only edit keeps the live client', () async {
      final manager = await buildManager();
      await manager.saveConnection(
        'Home',
        '192.168.1.50',
        8642,
        'key',
        gatewayPrefix: '/old-gateway',
      );
      final original = manager.getConnections().single;
      final client = registry.clientFor(original);

      // The API key authenticates the REST surface per request; the WebSocket
      // transport logs in with a dashboard ticket instead.
      await manager.updateApiKey(original.id, 'new-key');
      expect(registry.existingFor(original.id), same(client));
      expect(client.isClosed, isFalse);

      // So does the gateway path prefix.
      await manager.updateConnection(
        original.id,
        original.label,
        original.host,
        original.port,
        'new-key',
        gatewayPrefix: '/gateway',
      );
      expect(manager.getConnections().single.gatewayPrefix, '/gateway');
      expect(registry.existingFor(original.id), same(client));
      expect(client.isClosed, isFalse);
    });
  });

  group('deleting a saved connection', () {
    test('drops its client even though nothing else changed', () async {
      final manager = await buildManager();
      await manager.saveConnection('Home', '192.168.1.50', 8642, 'key');
      final original = manager.getConnections().single;
      final client = registry.clientFor(original);

      await manager.deleteConnection(original.id);

      expect(manager.getConnections(), isEmpty);
      expect(
        client.isClosed,
        isTrue,
        reason:
            'a deleted connection must not leave a socket reconnecting to a '
            'host the user removed',
      );
      expect(registry.existingFor(original.id), isNull);
    });
  });

  group('a mutation that failed', () {
    test('drops nothing: the client of a still-valid connection stays', () async {
      final store = _SwitchableCredentialStore();
      final manager = await buildManager(store: store);
      await manager.saveConnection('Home', '192.168.1.50', 8642, 'key');
      final original = manager.getConnections().single;
      final client = registry.clientFor(original);

      store.failWrites = true;

      await expectLater(
        manager.updateConnection(
          original.id,
          original.label,
          original.host,
          original.port,
          original.apiKey,
          dashboardPort: 30433,
        ),
        throwsA(isA<CredentialStorageException>()),
      );

      expect(
        manager.getConnections().single.dashboardPortOverride,
        isNull,
        reason: 'the failed edit did not land',
      );
      expect(
        registry.existingFor(original.id),
        same(client),
        reason: 'a fail-closed save must not tear down a client that still '
            'matches the stored connection',
      );
      expect(client.isClosed, isFalse);
    });
  });

  group('a config restore', () {
    test('drops the client of a connection the import removed', () async {
      final manager = await buildManager();
      await manager.saveConnection('Home', '192.168.1.50', 8642, 'key');
      await manager.saveConnection('Study', '192.168.1.60', 8642, 'key');
      final connections = manager.getConnections();
      final home = connections.firstWhere((c) => c.label == 'Home');
      final study = connections.firstWhere((c) => c.label == 'Study');
      final homeClient = registry.clientFor(home);
      final studyClient = registry.clientFor(study);

      await manager.importConnections([study], replaceExisting: true);

      expect(registry.existingFor(home.id), isNull);
      expect(homeClient.isClosed, isTrue);
      expect(
        registry.existingFor(study.id),
        same(studyClient),
        reason: 'a connection the restore did not touch keeps its socket',
      );
      expect(studyClient.isClosed, isFalse);
    });
  });

  group('a store with no owner wired', () {
    test('commits exactly as before', () async {
      final prefs = await SharedPreferences.getInstance();
      final manager = await ConnectionManager.create(
        prefs,
        credentialStore: _MemoryCredentialStore(),
      );
      await manager.saveConnection('Home', '192.168.1.50', 8642, 'key');
      final original = manager.getConnections().single;
      final client = registry.clientFor(original);

      await manager.updateConnection(
        original.id,
        original.label,
        original.host,
        original.port,
        original.apiKey,
        dashboardPort: 30433,
      );
      await manager.deleteConnection(original.id);

      expect(manager.getConnections(), isEmpty);
      expect(
        registry.existingFor(original.id),
        same(client),
        reason: 'nothing was wired, so there was nobody to invalidate',
      );
    });
  });
}
