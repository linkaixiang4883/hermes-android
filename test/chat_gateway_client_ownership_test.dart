// Phase 2B-ii, widget half: a chat screen borrows its connection instead of
// owning it.
//
// The socket is application-scoped (`GatewayClientRegistry`); a route only
// attaches and detaches listeners. These tests pin the handoff from the UI
// side, with no live gateway: the desktop-gateway URL is unreachable and the
// test binding answers every HTTP request with 400, so what is asserted is
// ownership itself — which instance the screen bound, and whether it survived
// the screen.
//
// The socket-level half (a borrowed socket stays open and keeps delivering,
// the owner still tears it down) lives in gateway_client_registry_test.dart,
// because real local WS traffic cannot share a suite with
// TestWidgetsFlutterBinding.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_client_registry.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/models/projects_tree_overview.dart';
import 'package:hermes_android/core/widgets/chat_context_header.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/inert_turn_application_session.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a chat screen borrows the shared client and leaves it open', (
    tester,
  ) async {
    final registry = GatewayClientRegistry();
    addTearDown(registry.close);
    final connection = _connection(desktopGatewayUrl: 'https://host:8642');

    // A consumer that already holds the connection, the way the session list
    // or the draft controller does.
    final shared = registry.clientFor(connection);
    final witness = <DesktopConnectionState>[];
    final witnessToken = shared.addConnectionListener(witness.add);

    final bound = <DesktopGatewayClient>[];
    await _pumpChat(
      tester,
      connection: connection,
      gatewayRegistry: registry,
      onGatewayBound: bound.add,
    );

    expect(bound, hasLength(1));
    final client = bound.single;
    expect(
      identical(client, registry.existingFor(connection.id)),
      isTrue,
      reason:
          'the screen must borrow the registry instance: a client of its own '
          'would be a second socket for one connection',
    );
    expect(
      client.connectionListenerCount,
      2,
      reason: 'the screen registers beside the existing listener, not over it',
    );

    await _dispose(tester);

    expect(
      client.isClosed,
      isFalse,
      reason:
          'leaving a chat must not close the shared connection — the turn '
          'keeps streaming on it, and the next visit re-attaches to it',
    );
    expect(registry.existingFor(connection.id), same(client));
    expect(
      client.connectionListenerCount,
      1,
      reason: 'the disposed screen detaches exactly its own listener',
    );

    // The survivor is the witness, and the borrowed connection is still live:
    // a transition still reaches it after the screen is gone. Had dispose left
    // the screen's own listener attached, nothing would land here.
    unawaited(
      client.ensureSession('mob-witness').then<void>((_) {}, onError: (_) {}),
    );
    await tester.pump();
    expect(
      witness,
      contains(DesktopConnectionState.connecting),
      reason: 'the shared client keeps dispatching to its remaining listeners',
    );

    client.removeConnectionListener(witnessToken);
    expect(client.connectionListenerCount, 0);
  });

  testWidgets(
    'a borrowed client that is already connected seeds the header as connected',
    (tester) async {
      final registry = GatewayClientRegistry();
      addTearDown(registry.close);
      final connection = _connection(desktopGatewayUrl: 'https://host:8642');

      // The session list / draft owner opened this connection earlier, so the
      // screen borrows a live instance and will never see its
      // connecting -> connected transition: there is none left to see.
      final shared = registry.clientFor(connection);
      shared.debugSetConnectionState(DesktopConnectionState.connected);

      // A draft session keeps _ensureDesktopSession from opening a socket of
      // its own, and the injected project loader keeps the header's sticky
      // lookup off the gateway — otherwise the refresh path below would open
      // one and dispatch `connecting` over the seeded state. What is asserted
      // is the header's first paint, seeded from the borrowed client.
      await _pumpChat(
        tester,
        connection: connection,
        gatewayRegistry: registry,
        session: _draftSession(),
        projectOverviewLoader: () async => ProjectsTreeOverview.empty,
      );

      final header = tester.widget<ChatContextHeader>(
        find.byType(ChatContextHeader),
      );
      expect(
        header.connectionStatus,
        ChatConnectionStatus.connected,
        reason:
            'a borrowed client that is already up must not read as offline '
            'just because this screen missed the transition',
      );
    },
  );

  testWidgets('a chat screen without a registry still closes its own client', (
    tester,
  ) async {
    final connection = _connection(desktopGatewayUrl: 'https://host:8642');
    final bound = <DesktopGatewayClient>[];
    await _pumpChat(
      tester,
      connection: connection,
      onGatewayBound: bound.add,
    );

    final client = bound.single;
    expect(client.connectionListenerCount, 1);
    expect(client.isClosed, isFalse);

    await _dispose(tester);

    expect(
      client.isClosed,
      isTrue,
      reason:
          'the no-registry fallback keeps the route-local contract: a client '
          'the screen built is a client the screen closes',
    );
    expect(client.connectionListenerCount, 0);
  });

  testWidgets('the workspace shell inherits the gateway registry', (
    tester,
  ) async {
    final controller = GatewayTurnApplicationController(
      sessionFactory: (_) => InertTurnApplicationSession(),
    );
    addTearDown(controller.close);
    final registry = GatewayClientRegistry();
    addTearDown(registry.close);
    final connection = _connection();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SessionListScreen(
          connection: connection,
          turnApplicationController: controller,
          gatewayRegistry: registry,
        ),
      ),
    );
    await tester.pump();

    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    scaffold.openDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('open-workspace')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final workspace = tester.widget<WorkspaceScreen>(
      find.byType(WorkspaceScreen),
    );
    expect(
      workspace.gatewayRegistry,
      same(registry),
      reason:
          'Home opens chats itself; without the registry they would each build '
          'a private socket against the same connection',
    );
  });

  testWidgets('the default chat route carries the gateway registry', (
    tester,
  ) async {
    final registry = GatewayClientRegistry();
    addTearDown(registry.close);

    final screen = buildWorkspaceChatScreen(
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      session: _session(),
      gatewayRegistry: registry,
    );

    expect(screen, isA<ChatScreen>());
    expect((screen as ChatScreen).gatewayRegistry, same(registry));
  });
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required SavedConnection connection,
  GatewayClientRegistry? gatewayRegistry,
  ValueChanged<DesktopGatewayClient>? onGatewayBound,
  Session? session,
  TestProjectOverviewLoader? projectOverviewLoader,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: connection,
        session: session ?? _session(),
        gatewayRegistry: gatewayRegistry,
        testProjectOverviewLoader: projectOverviewLoader,
        testDesktopGatewayObserver: onGatewayBound,
        testApiClient: ApiClient(
          baseUrl: 'http://fixture.example',
          apiKey: 'fixture-key',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Replaces the tree so the chat screen's [State.dispose] runs.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SizedBox.shrink(),
    ),
  );
  await tester.pump();
}

SavedConnection _connection({
  String? desktopGatewayUrl,
  String id = 'conn-ownership',
}) => SavedConnection(
  id: id,
  label: 'Ownership fixture',
  host: 'fixture.example',
  port: 8642,
  apiKey: 'fixture-key',
  desktopGatewayUrl: desktopGatewayUrl,
);

Session _session() => Session(
  id: 'mob-ownership',
  title: 'Ownership fixture chat',
  model: 'fixture-model',
  source: 'test',
  messageCount: 0,
  isActive: true,
  preview: '',
  startedAt: 1,
);

/// A draft chat: opening it binds the borrowed client but never opens a
/// socket of its own, so a test-seeded connection state stands untouched.
Session _draftSession() => Session(
  id: 'mob-ownership-draft',
  title: 'Ownership fixture draft',
  model: 'fixture-model',
  source: 'test',
  messageCount: 0,
  isActive: true,
  preview: '',
  startedAt: 1,
  isLocalDraft: true,
);
