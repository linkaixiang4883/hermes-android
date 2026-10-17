// Phase 3 review fixes, widget half: entering a chat hydrates the transcript
// over REST while the shared connection re-attaches the session over WS, so
// the resume snapshot that rebuilt the running turn and the bounded history
// page travel on different channels and either can land last.
//
// The history response is authoritative for the COMMITTED rows only — it knows
// nothing about the turn being followed — so landing last must not erase the
// reconstructed bubbles and leave the user with a status bar and no reply.
// Both orderings are pinned here, together with the two guards inside
// `_enterFollowMode`: a locally pending reply owns its bubbles, and a repeated
// snapshot updates the projection row instead of appending another one.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_live_turn.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

/// The mobile-side chat id this screen shows.
const _sessionId = 'race-session';

/// The copy the follow state shows while the turn is still running.
const _followingCopy = 'Running · auto-syncing';

/// The snapshot a `session.resume` answers with for a running turn.
const _runningTurn = LiveTurnProjection(
  running: true,
  status: 'running',
  user: 'hi',
  assistant: 'partial',
  streaming: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a history response landing AFTER the projection keeps it', (
    tester,
  ) async {
    final hook = TestDesktopLiveTurnHook();
    final history = _RaceHistoryHttpClient()
      ..rows = const [
        {'id': 1, 'role': 'user', 'content': 'hi'},
      ];
    await _pumpChat(tester, hook: hook, history: history);

    // The entry resume answers while the history fetch is still in flight.
    // (The transcript is not built yet — the screen shows its loading state
    // until the page lands — so the projection's own paint is asserted below.)
    hook.handler?.call(_sessionId, _runningTurn);
    await tester.pump();

    // The page lands late: it carries the committed user row and nothing else.
    history.release();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text(_followingCopy),
      findsOneWidget,
      reason: 'the follow is still live: the gateway has not reported the end',
    );
    expect(
      find.text('partial'),
      findsOneWidget,
      reason:
          'the committed page must not erase the reply this screen is '
          'following — the status bar would be left pointing at nothing',
    );
    expect(
      find.text('hi'),
      findsOneWidget,
      reason:
          'the prompt is deduped against the rows that just arrived: the '
          'transcript must not paint it twice',
    );
  });

  testWidgets('a projection delivered AFTER the history response keeps it', (
    tester,
  ) async {
    final hook = TestDesktopLiveTurnHook();
    final history = _RaceHistoryHttpClient();
    await _pumpChat(tester, hook: hook, history: history);

    // Control ordering for the same race: the fetch resolves first.
    history.release();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    hook.handler?.call(_sessionId, _runningTurn);
    await tester.pump();

    expect(find.text(_followingCopy), findsOneWidget);
    expect(find.text('partial'), findsOneWidget);
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('a 404 history response does not blank the followed turn', (
    tester,
  ) async {
    final hook = TestDesktopLiveTurnHook();
    final history = _RaceHistoryHttpClient()..status = 404;
    await _pumpChat(tester, hook: hook, history: history);

    hook.handler?.call(_sessionId, _runningTurn);
    await tester.pump();

    history.release();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(_followingCopy), findsOneWidget);
    expect(
      find.text('partial'),
      findsOneWidget,
      reason:
          'a 404 empties the committed rows, not the followed turn: the '
          'running reply is still the only bubble the user can see',
    );
  });

  testWidgets('a locally pending reply is not repainted by the snapshot', (
    tester,
  ) async {
    final hook = TestDesktopLiveTurnHook();
    final history = _RaceHistoryHttpClient()..gated = false;
    final connectionHook = TestDesktopConnectionHook();
    final submission = Completer<void>();
    await _pumpChat(
      tester,
      hook: hook,
      history: history,
      connectionHook: connectionHook,
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

    // A turn this screen submitted itself: its optimistic bubbles are in
    // `_messages` and the assistant row is still pending.
    connectionHook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Local prompt');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Local prompt'), findsOneWidget);

    // The resume now also reports a running turn for the same chat.
    hook.handler?.call(_sessionId, _runningTurn);
    await tester.pump();

    expect(
      find.text('Local prompt'),
      findsOneWidget,
      reason: 'the submit that started the turn keeps ownership of its bubbles',
    );
    expect(
      find.text('partial'),
      findsNothing,
      reason: 'the snapshot must not paint a second assistant bubble',
    );
    expect(
      find.text('hi'),
      findsNothing,
      reason: 'the snapshot must not insert its prompt beside the local one',
    );
    expect(
      find.text(_followingCopy),
      findsOneWidget,
      reason: 'the follow state itself is still recorded for the exit path',
    );

    submission.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('an updated snapshot repaints the projection row in place', (
    tester,
  ) async {
    final hook = TestDesktopLiveTurnHook();
    final history = _RaceHistoryHttpClient()..gated = false;
    await _pumpChat(tester, hook: hook, history: history);

    hook.handler?.call(_sessionId, _runningTurn);
    await tester.pump();
    expect(find.text('partial'), findsOneWidget);

    hook.handler?.call(
      _sessionId,
      const LiveTurnProjection(
        running: true,
        status: 'running',
        user: 'hi',
        assistant: 'partial two',
        streaming: true,
      ),
    );
    await tester.pump();

    expect(find.text('partial two'), findsOneWidget);
    expect(
      find.text('partial'),
      findsNothing,
      reason: 'the projection row is replaced, never appended beside',
    );
    expect(
      find.text('hi'),
      findsOneWidget,
      reason: 'the prompt is not appended twice by the update',
    );
    expect(find.text(_followingCopy), findsOneWidget);
  });
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required TestDesktopLiveTurnHook hook,
  required _RaceHistoryHttpClient history,
  TestDesktopConnectionHook? connectionHook,
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
          baseUrl: 'http://race.fixture',
          apiKey: 'race-fixture-key',
          httpClient: history,
        ),
        testDesktopLiveTurnHook: hook,
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
/// screen's own handling of a projection and of the history page that races
/// it, not a live transport.
SavedConnection _connection() => SavedConnection(
  id: 'conn-race',
  label: 'Race fixture',
  host: 'race.fixture',
  port: 8642,
  apiKey: 'race-fixture-key',
  desktopGatewayUrl: 'https://gateway.invalid:8642',
);

Session _session() => const Session(
  id: _sessionId,
  title: 'Race fixture chat',
  model: 'fixture-model',
  source: 'test',
  messageCount: 0,
  isActive: true,
  preview: '',
  startedAt: 1,
);

/// Serves the stored transcript, optionally holding the answer back until
/// [release] so two orderings of the same race can be driven deterministically.
class _RaceHistoryHttpClient extends http.BaseClient {
  /// Whether `/messages` waits for [release] before answering.
  bool gated = true;

  /// Status the next `/messages` answers with.
  int status = 200;

  /// The committed rows the gateway holds for this chat.
  List<Map<String, dynamic>> rows = const [];

  final _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      if (gated) await _gate.future;
      final body = status == 200
          ? jsonEncode({'data': rows})
          : jsonEncode({'error': 'not found'});
      return http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        status,
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
