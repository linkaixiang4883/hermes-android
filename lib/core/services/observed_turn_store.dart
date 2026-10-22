import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ws_client.dart' show StreamEvent;

/// One chat's most recent observed turn state.
@immutable
class ObservedTurn {
  final String gatewaySessionId;
  final String? mobileSessionId;
  final String? title;
  final String state; // running | completed | failed
  final String? summary;
  final DateTime updatedAt;

  const ObservedTurn({
    required this.gatewaySessionId,
    required this.mobileSessionId,
    required this.title,
    required this.state,
    required this.summary,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'gateway_session_id': gatewaySessionId,
    'mobile_session_id': mobileSessionId,
    'title': title,
    'state': state,
    'summary': summary,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  static ObservedTurn? fromJson(Map<String, dynamic> json) {
    final id = (json['gateway_session_id'] ?? '').toString();
    if (id.isEmpty) return null;
    final state = (json['state'] ?? '').toString();
    if (state != 'running' && state != 'completed' && state != 'failed') {
      return null;
    }
    return ObservedTurn(
      gatewaySessionId: id,
      mobileSessionId: (json['mobile_session_id'] as String?)?.trim(),
      title: (json['title'] as String?)?.trim(),
      state: state,
      summary: (json['summary'] as String?)?.trim(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updated_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// A bounded, persisted timeline built from the gateway's own fan-out.
///
/// The turn-recovery journal only exists on gateways that advertise
/// `turn_recovery`; on a stock gateway the Activity screen had no data at all.
/// This store listens to the frames every gateway sends (`message.delta`,
/// terminal frames) and keeps one row per chat, so Activity can be honest with
/// or without the journal.
class ObservedTurnStore {
  ObservedTurnStore({this.maxEntries = 100, SharedPreferences? prefs})
    // ignore: prefer_initializing_formals — public param, private field.
    : _prefs = prefs;

  static const String prefsKey = 'observed_turns_v1';

  final int maxEntries;
  SharedPreferences? _prefs;
  final Map<String, ObservedTurn> _entries = {};
  final List<ObservedTurn> _ordered = [];

  List<ObservedTurn> get entries => List.unmodifiable(_ordered);

  ObservedTurn? forSession(String gatewaySessionId) =>
      _entries[gatewaySessionId];

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      for (final item in list.whereType<Map>()) {
        final turn = ObservedTurn.fromJson(Map<String, dynamic>.from(item));
        if (turn != null) _upsert(turn, persist: false);
      }
    } catch (_) {
      // A corrupt cache degrades to an empty timeline; it must not break the
      // screen that asked for it.
    }
  }

  /// Folds one bridged frame into the timeline.
  void observe(StreamEvent event, String? mobileSessionId, {String? title}) {
    final gatewaySessionId = event.data['session_id']?.toString() ?? '';
    if (gatewaySessionId.isEmpty) return;
    final type = event.type;
    String? state;
    if (type == 'message.delta' ||
        type == 'message.interim' ||
        type.startsWith('tool.')) {
      state = 'running';
    } else if (type == 'message.complete' || type == 'turn.end') {
      state = event.data['error'] != null ? 'failed' : 'completed';
    } else if (type == 'turn.error' || type == 'error') {
      state = 'failed';
    }
    if (state == null) return;
    final raw =
        (event.data['rendered'] ??
                event.data['text'] ??
                event.data['message'] ??
                '')
            .toString();
    final summary = state == 'running'
        ? null
        : raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    _upsert(
      ObservedTurn(
        gatewaySessionId: gatewaySessionId,
        mobileSessionId: mobileSessionId,
        title: title ?? _entries[gatewaySessionId]?.title,
        state: state,
        summary: summary,
        updatedAt: DateTime.now(),
      ),
      persist: true,
    );
  }

  void _upsert(ObservedTurn turn, {required bool persist}) {
    _entries[turn.gatewaySessionId] = turn;
    _ordered.removeWhere(
      (item) => item.gatewaySessionId == turn.gatewaySessionId,
    );
    _ordered.insert(0, turn);
    while (_ordered.length > maxEntries) {
      final dropped = _ordered.removeLast();
      _entries.remove(dropped.gatewaySessionId);
    }
    if (persist) unawaited(_persist());
  }

  Future<void> _persist() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      prefsKey,
      jsonEncode([for (final turn in _ordered) turn.toJson()]),
    );
  }
}
