// Phase 2C, widget half: the app owns the invalidation, not the screens.
//
// `ConnectionManager` reports a connection whose cached gateway client must go
// (edited identity, or deleted) and the app answers by closing it in the
// registry it owns. These tests pin that wiring where a unit test cannot see
// it: through the real Home screen and through the real app widget.
//
// No gateway is involved. The clients are built (never dialled) and the app's
// own HTTP is not used, so what is asserted is ownership: after a deletion
// driven from Home's card menu, and after an edit applied while the app is
// running, the registry no longer hands out the client built from the previous
// definition.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_client_registry.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/inert_turn_application_session.dart';
import 'support/l10n_test_utils.dart';

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

Future<ConnectionManager> _buildManager() async {
  final prefs = await SharedPreferences.getInstance();
  return ConnectionManager.create(
    prefs,
    credentialStore: _MemoryCredentialStore(),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('deleting a connection from Home drops the shared client', (
    tester,
  ) async {
    final l10n = await loadTestL10n();
    final manager = await _buildManager();
    await manager.saveConnection('Home', '192.168.1.50', 8642, 'key');
    final registry = GatewayClientRegistry();
    addTearDown(registry.close);
    manager.onConnectionClientInvalidated = registry.closeConnection;

    final connection = manager.getConnections().single;
    // A borrower that is still mounted on the connection, the way a chat is.
    final client = registry.clientFor(connection);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          connManager: manager,
          turnApplicationController: GatewayTurnApplicationController(
            sessionFactory: (_) => InertTurnApplicationSession(),
          ),
          gatewayRegistry: registry,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.delete));
    await tester.pumpAndSettle();

    expect(manager.getConnections(), isEmpty);
    expect(
      client.isClosed,
      isTrue,
      reason:
          'deleting a connection must not leave its socket reconnecting to a '
          'host the user removed',
    );
    expect(registry.existingFor(connection.id), isNull);
  });

  testWidgets('the running app invalidates an edit on the registry it owns', (
    tester,
  ) async {
    final manager = await _buildManager();
    await manager.saveConnection('Home', '192.168.1.50', 8642, 'key');

    await tester.pumpWidget(HermesApp(connManager: manager));
    await tester.pump();
    await tester.pump();

    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    final registry = home.gatewayRegistry;
    expect(registry, isNotNull);

    final connection = manager.getConnections().single;
    final client = registry!.clientFor(connection);
    expect(registry.existingFor(connection.id), same(client));

    // The edit the Home dialog performs, applied while the app is up.
    await manager.updateConnection(
      connection.id,
      connection.label,
      connection.host,
      connection.port,
      connection.apiKey,
      dashboardPort: 30433,
    );
    await tester.pump();

    expect(
      client.isClosed,
      isTrue,
      reason:
          'the app has to hand its registry to the connection store, or a '
          'saved edit would only take effect after a restart',
    );
    expect(registry.existingFor(connection.id), isNull);
  });
}
