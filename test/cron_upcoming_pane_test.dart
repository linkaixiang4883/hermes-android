import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/utils/cron_schedule.dart';
import 'package:hermes_android/core/widgets/cron_upcoming_pane.dart';
import 'package:hermes_android/core/widgets/crons_pane.dart';
import 'package:hermes_android/core/widgets/hermes_shell.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

const _fixtureKey = 'fixture';

SavedConnection _connection({bool dashboard = true}) => SavedConnection(
  id: 'cron-test',
  label: 'Cron test',
  host: 'host',
  port: 9119,
  apiKey: _fixtureKey,
  desktopGatewayUrl: dashboard ? 'https://host' : null,
);

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: HermesPaneVisibility(active: true, child: child),
  ),
);

void main() {
  group('cron schedule formatting', () {
    test('preserves explicit offset and wall-clock time', () {
      final run = parseCronNextRun('2026-11-09T09:00:00+11:00');
      expect(run, isNotNull);
      expect(run!.wallClock, '2026-11-09 09:00');
      expect(run.zoneLabel, 'UTC+11:00');
    });

    test('recognises Z without converting to local time', () {
      final run = parseCronNextRun('2026-11-09T09:00:00Z');
      expect(run!.wallClock, '2026-11-09 09:00');
      expect(run.zoneLabel, 'UTC');
    });

    test('reports an unknown zone instead of guessing', () {
      final run = parseCronNextRun('2026-11-09T09:00:00');
      expect(run!.wallClock, '2026-11-09 09:00');
      expect(run.zoneLabel, isNull);
    });

    test('reads display, string and map schedules', () {
      expect(
        cronScheduleDisplay({'schedule_display': 'Every day at 09:00'}),
        'Every day at 09:00',
      );
      expect(cronScheduleDisplay({'schedule': 'every 2h'}), 'every 2h');
      expect(
        cronScheduleDisplay({
          'schedule': {'kind': 'cron', 'expression': '0 9 * * *'},
        }),
        '0 9 * * *',
      );
    });
  });

  testWidgets('renders upcoming jobs with status, zone and delivery target', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CronUpcomingPane(
          connection: _connection(),
          loadJobs: () async => [
            {
              'id': 'job-1',
              'name': 'Daily digest',
              'enabled': true,
              'schedule_display': 'Every day at 09:00',
              'next_run_at': '2026-11-09T09:00:00+11:00',
              'prompt': 'Summarize the day',
              'deliver': 'telegram',
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Daily digest'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Schedule: Every day at 09:00'), findsOneWidget);
    expect(
      find.text('Next: 2026-11-09 09:00 (UTC+11:00)'),
      findsOneWidget,
    );
    expect(find.text('Delivers to: telegram'), findsOneWidget);
  });

  testWidgets('paused and no-next-run jobs stay visible', (tester) async {
    await tester.pumpWidget(
      _host(
        CronUpcomingPane(
          connection: _connection(),
          loadJobs: () async => [
            {
              'id': 'job-2',
              'name': 'Paused job',
              'enabled': false,
              'schedule': 'every 1h',
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Paused job'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('No next run scheduled'), findsOneWidget);
  });

  testWidgets('empty schedule is distinct from unavailable dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CronUpcomingPane(
          connection: _connection(),
          loadJobs: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No scheduled jobs.'), findsOneWidget);
  });

  testWidgets('API-only connection explains the dashboard requirement', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(CronUpcomingPane(connection: _connection(dashboard: false))),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Scheduled jobs need a Dashboard connection.'),
      findsOneWidget,
    );
  });

  testWidgets('Crons pane opens Upcoming first and switches to History', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CronsPane(upcoming: const Text('UPCOMING'), history: const Text('HISTORY')),
      ),
    );
    await tester.pumpAndSettle();

    final pane = tester.state<CronsPaneState>(find.byType(CronsPane));
    expect(pane.view, CronsView.upcoming);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(kCronsUpcomingChipKey))
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(kCronsHistoryChipKey));
    await tester.pumpAndSettle();
    expect(pane.view, CronsView.history);
    expect(
      tester.widget<ChoiceChip>(find.byKey(kCronsHistoryChipKey)).selected,
      isTrue,
    );
  });
}
