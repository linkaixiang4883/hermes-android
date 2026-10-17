import '../models/connection.dart';
import 'desktop_gateway_client.dart';

/// Application-scoped owner of the gateway connections.
///
/// Every [SavedConnection] gets exactly one [DesktopGatewayClient], held here
/// for as long as the app lives. Screens borrow that instance (they attach
/// their listeners and detach them again on dispose), so a turn keeps
/// streaming — and its replay watermarks, socket and session bindings keep
/// existing — while the user is somewhere else in the app. Whoever *borrows* a
/// client must never close it; only this registry does, and only when the
/// whole app is disposed or the connection itself is dropped.
///
/// Without a registry a screen still builds a private client, which it owns and
/// closes: that fallback keeps every existing constructor path (tests, and any
/// entry point that was not handed a registry) behaving exactly as before.
class GatewayClientRegistry {
  final Map<String, DesktopGatewayClient> _clients = {};
  bool _closed = false;

  /// The shared client for [connection], built on first use.
  ///
  /// The connection id is the identity: two [SavedConnection] values describing
  /// the same saved connection share one socket, which is what keeps the
  /// chat screen and the draft/notification owner on a single connection.
  DesktopGatewayClient clientFor(SavedConnection connection) {
    if (_closed) throw StateError('GatewayClientRegistry is closed.');
    return _clients.putIfAbsent(
      connection.id,
      () => DesktopGatewayClient.fromConnection(connection),
    );
  }

  /// The client retained for [connectionId], or null when none was built.
  ///
  /// Does not create one: a caller that only wants to observe (or detach from)
  /// an existing connection must not bring a socket up as a side effect.
  DesktopGatewayClient? existingFor(String connectionId) =>
      _clients[connectionId];

  /// Drops one connection, closing the client every borrower was sharing.
  void closeConnection(String connectionId) {
    _clients.remove(connectionId)?.close();
  }

  /// Closes every retained client. The app calls this on its way out; borrows
  /// that are still attached are detached by their own owners first.
  void close() {
    _closed = true;
    for (final client in List.of(_clients.values)) {
      client.close();
    }
    _clients.clear();
  }
}
