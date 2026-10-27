import 'package:http/http.dart' as http;

import 'connection_manager.dart';
import 'dashboard_rest_client.dart';
import 'desktop_gateway_client.dart';

/// Whether this connection's REST traffic belongs on the dashboard origin.
///
/// This mirrors the predicate the chat screen uses to enable the desktop
/// gateway: a saved dashboard URL, dashboard credentials, or a proxied
/// dashboard all imply the 9119 transport. A bare API-key connection keeps the
/// legacy 8642 REST path.
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

  final client = dashboard ??
      buildConnectionDashboard(connection, httpClient: httpClient);
  return DashboardRestClient(
    client,
    gatewayProfile: connection.gatewayProfile,
    ownsDashboard: dashboard == null,
  );
}
