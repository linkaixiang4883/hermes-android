import 'package:http/http.dart' as http;

import 'connection_manager.dart';
import 'dashboard_rest_client.dart';
import 'desktop_gateway_client.dart';

/// Whether this connection's REST traffic belongs on the dashboard origin.
///
/// New connections are dashboard-only, but existing legacy connections keep
/// their API-key transport until they are migrated. This predicate selects the
/// dashboard branch only when the connection actually carries dashboard
/// details; a bare API-key connection still uses the isolated legacy adapter.
bool usesDashboardRest(SavedConnection connection) {
  return connection.desktopGatewayUrl?.trim().isNotEmpty == true ||
      connection.dashboardProxied ||
      (connection.dashboardUsername?.trim().isNotEmpty == true &&
          connection.dashboardPassword?.trim().isNotEmpty == true);
}

/// Builds the REST client for [connection].
///
/// The dashboard branch deliberately reuses [dashboard] when a caller already
/// holds one (the app-wide [GatewayClientRegistry] / [DesktopGatewayClient]
/// owns the single-flight login). Building a fresh [DashboardClient] per screen
/// would trigger one password login per navigation and risk the dashboard's
/// login rate limit.
DashboardClient buildConnectionDashboard(
  SavedConnection connection, {
  http.Client? httpClient,
}) {
  final baseUri = Uri.parse(
    DesktopGatewayClient.normalizedGatewayBaseUrl(connection),
  );
  final pathPrefix = baseUri.path == '/' ? '' : baseUri.path;
  return DashboardClient(
    host: baseUri.host,
    port: baseUri.port,
    useHttps: baseUri.scheme == 'https',
    pathPrefix: pathPrefix,
    proxied: connection.dashboardProxied,
    username: connection.dashboardUsername,
    password: connection.dashboardPassword,
    gatewayProfile: connection.gatewayProfile,
    httpClient: httpClient,
  );
}

HermesRestClient buildConnectionRestClient(
  SavedConnection connection, {
  DashboardClient? dashboard,
  http.Client? httpClient,
}) {
  if (!usesDashboardRest(connection)) {
    return ApiClient(
      baseUrl: connection.baseUrl,
      apiKey: connection.apiKey,
      pathPrefix: connection.gatewayPrefix ?? '',
      httpClient: httpClient,
    );
  }

  final client =
      dashboard ?? buildConnectionDashboard(connection, httpClient: httpClient);
  return DashboardRestClient(
    client,
    gatewayProfile: connection.gatewayProfile,
    ownsDashboard: dashboard == null,
  );
}
