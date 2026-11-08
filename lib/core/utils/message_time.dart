import 'package:flutter/material.dart';

/// Reads a per-message timestamp from the gateway's history row.
///
/// Hermes stores `timestamp` as epoch seconds (float). Some projections may
/// expose it as `created_at`, and a few fixtures use milliseconds; accept both
/// without inventing a time when the field is absent or malformed.
DateTime? messageTimestamp(Map<String, dynamic> message) {
  final raw = message['timestamp'] ?? message['created_at'];
  double? value;
  if (raw is num) {
    value = raw.toDouble();
  } else if (raw is String) {
    value = double.tryParse(raw.trim());
  }
  if (value == null || !value.isFinite || value <= 0) return null;
  // Epoch milliseconds are three orders of magnitude larger than seconds.
  if (value > 100000000000) value /= 1000;
  return DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
}

/// Formats a message clock in the device's locale and 12/24-hour preference.
String formatMessageClock(BuildContext context, DateTime timestamp) {
  final localizations = MaterialLocalizations.of(context);
  return localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(timestamp),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}
