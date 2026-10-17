// Phase 3 review fix: the three places that ask the gateway for a CURRENT
// live-turn snapshot must really ask for one.
//
// `ensureSession` without `refresh` returns early on an already-mapped
// session, so a screen that forgot the flag would rebuild the running turn
// from the snapshot taken when the socket came up — i.e. from nothing, for a
// turn that started while the user was elsewhere. The flag itself has no other
// observable (the socket in these tests is unreachable on purpose), so the
// wiring is pinned through `ChatScreen.testDesktopEnsureSessionHook`, which
// records the flag of every `_ensureDesktopSession()` call.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

/// The mobile-side chat id this screen shows.
const _sessionId = 'wiring-session';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('entering the chat refreshes; an app resume refreshes again', (
    tester,
  ) async {
    final calls = <bool>[];
    await _pumpChat(tester, ensureCalls: calls.add);

    expect(
      calls,
      [true],
      reason:
          'entering the chat must re-attach with refresh: a plain ensure '
          'reuses the stored snapshot, which can predate the running turn',
    );

    _background(tester);
    await tester.pump();
    _foreground(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      calls,
      [true, true],
      reason:
          'a turn that started — or finished — while the app was away is only '
          'visible through a fresh resume',
    );
  });

  testWidgets('a resume with a reattach pending refreshes too', (tester) async {
    final connectionHook = TestDesktopConnectionHook();
    final calls = <bool>[];
    final history = _WiringHttpClient();
    final submission = Completer<void>();
    await _pumpChat(
      tester,
      ensureCalls: calls.add,
      connectionHook: connectionHook,
      history: history,
      remoteSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            onSent();
            return submission.future;
          },
    );
    expect(calls, [true]);

    // A turn this screen submitted itself is in flight when the socket drops,
    // so the resync stays pending until a reattach lands.
    connectionHook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Long running task');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    connectionHook.handler?.call(DesktopConnectionState.reconnecting);
    await tester.pump();

    _background(tester);
    await tester.pump();
    _foreground(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      calls.where((refresh) => refresh),
      hasLength(2),
      reason:
          'the reattach-pending resume refreshes as well: it is the same '
          'foreground transition, and the snapshot is just as stale',
    );

    // Let the retry loop settle, then drop the tree so its timers go with it.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

/// Walks the lifecycle chain the framework accepts: a bare
/// `resumed → paused` jump (or `paused → resumed`) trips the transition assert
/// in the tree's [AppLifecycleListener].
void _background(WidgetTester tester) {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void _foreground(WidgetTester tester) {
  for (final state in const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required void Function(bool refresh) ensureCalls,
  TestDesktopConnectionHook? connectionHook,
  _WiringHttpClient? history,
  TestRemotePromptSubmit? remoteSubmit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: _connection(),
        session: _session(),
        testApiClient: ApiClient(
          baseUrl: 'http://wiring.fixture',
          apiKey: 'wiring-fixture-key',
          httpClient: history ?? _WiringHttpClient(),
        ),
        testDesktopEnsureSessionHook: ensureCalls,
        testDesktopConnectionHook: connectionHook,
        testRemotePromptSubmit: remoteSubmit,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// The desktop-gateway URL is unreachable on purpose: what is asserted is the
/// flag each call site passes into `_ensureDesktopSession`, and a failed
/// attach is exactly the state a test can hold the wiring in.
SavedConnection _connection() => SavedConnection(
  id: 'conn-wiring',
  label: 'Wiring fixture',
  host: 'wiring.fixture',
  port: 8642,
  apiKey: 'wiring-fixture-key',
  desktopGatewayUrl: 'https://gateway.invalid:8642',
);

Session _session() => const Session(
  id: _sessionId,
  title: 'Wiring fixture chat',
  model: 'fixture-model',
  source: 'test',
  messageCount: 0,
  isActive: true,
  preview: '',
  startedAt: 1,
);

/// Answers the bounded transcript request and nothing else.
class _WiringHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'data': const []}))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'error': 'unexpected request'}))),
      404,
      headers: {'content-type': 'application/json'},
    );
  }
}
