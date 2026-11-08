/// Formats a cron job's next-run timestamp without converting time zones.
///
/// The dashboard returns ISO-8601 strings such as
/// `2026-11-09T09:00:00+11:00`. The wall-clock portion and its explicit
/// offset are meaningful to the scheduler; converting the value to the
/// phone's local zone would hide which zone the job actually runs in.
///
/// A timestamp with no offset is still shown, but its zone is reported as
/// unknown rather than guessed from the phone.
class CronNextRun {
  const CronNextRun({required this.wallClock, this.zoneLabel});

  /// `yyyy-MM-dd HH:mm` exactly as expressed by the server.
  final String wallClock;

  /// `UTC+11:00`, `UTC`, etc. Null when the payload had no zone.
  final String? zoneLabel;
}

final RegExp _isoNextRun = RegExp(
  r'^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2})(?::\d{2}(?:\.\d+)?)?\s*(Z|[+-]\d{2}:?\d{2})?$',
);

/// Parses [raw] without applying the device's local timezone.
CronNextRun? parseCronNextRun(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;

  final match = _isoNextRun.firstMatch(value);
  if (match == null) {
    // Keep an unexpected but non-empty value visible instead of dropping the
    // next-run row entirely. It has no verified zone.
    return CronNextRun(wallClock: value);
  }

  final zone = match.group(3);
  String? zoneLabel;
  if (zone != null) {
    if (zone == 'Z') {
      zoneLabel = 'UTC';
    } else {
      final sign = zone[0];
      final digits = zone.replaceAll(':', '');
      zoneLabel = 'UTC$sign${digits.substring(1, 3)}:${digits.substring(3, 5)}';
    }
  }

  return CronNextRun(
    wallClock: '${match.group(1)} ${match.group(2)}',
    zoneLabel: zoneLabel,
  );
}

/// Human-readable schedule text from a dashboard cron job record.
///
/// Mirrors the fields `CronScreen` already understands: an explicit
/// `schedule_display`, then the schedule string, then useful map keys.
String cronScheduleDisplay(Map<String, dynamic> job) {
  final display = job['schedule_display'];
  if (display is String && display.trim().isNotEmpty) return display.trim();

  final schedule = job['schedule'];
  if (schedule is String && schedule.trim().isNotEmpty) return schedule.trim();
  if (schedule is Map) {
    for (final key in const ['display', 'expression', 'run_at', 'value']) {
      final value = schedule[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    final kind = schedule['kind'];
    if (kind is String && kind.trim().isNotEmpty) return kind.trim();
  }
  return '';
}
