/// The Crons destination: **Upcoming** schedules beside run **History**.
///
/// The destination used to be history-only, so a job scheduled for next week
/// stayed invisible until it first fired. Upcoming reads the cron manager's
/// own job definitions; History keeps the existing cron-run conversation
/// browser. Both views stay mounted so history state survives a switch.
library;

import 'package:flutter/material.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

import '../theme/hermes_theme.dart';
import 'hermes_shell.dart';

enum CronsView { upcoming, history }

const Key kCronsUpcomingChipKey = Key('crons-view-upcoming');
const Key kCronsHistoryChipKey = Key('crons-view-history');

class CronsPane extends StatefulWidget {
  const CronsPane({
    required this.upcoming,
    required this.history,
    this.initialView = CronsView.upcoming,
    this.onViewChanged,
    super.key,
  });

  final Widget upcoming;
  final Widget history;
  final CronsView initialView;
  final ValueChanged<CronsView>? onViewChanged;

  @override
  State<CronsPane> createState() => CronsPaneState();
}

class CronsPaneState extends State<CronsPane> {
  late CronsView _view = widget.initialView;

  CronsView get view => _view;

  void select(CronsView view) {
    if (_view == view) return;
    setState(() => _view = view);
    widget.onViewChanged?.call(view);
  }

  String _label(CronsView view) => switch (view) {
    CronsView.upcoming => context.l10n.crons_upcoming,
    CronsView.history => context.l10n.crons_history,
  };

  Key _key(CronsView view) => switch (view) {
    CronsView.upcoming => kCronsUpcomingChipKey,
    CronsView.history => kCronsHistoryChipKey,
  };

  @override
  Widget build(BuildContext context) {
    final destinationVisible = HermesPaneVisibility.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HermesSpacing.lg,
            HermesSpacing.md,
            HermesSpacing.lg,
            0,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final view in CronsView.values)
                  Padding(
                    padding: const EdgeInsets.only(right: HermesSpacing.sm),
                    child: ChoiceChip(
                      key: _key(view),
                      label: Text(_label(view)),
                      selected: _view == view,
                      onSelected: (_) => select(view),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _view.index,
            sizing: StackFit.expand,
            children: [
              HermesPaneVisibility(
                active: destinationVisible && _view == CronsView.upcoming,
                child: widget.upcoming,
              ),
              HermesPaneVisibility(
                active: destinationVisible && _view == CronsView.history,
                child: widget.history,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
