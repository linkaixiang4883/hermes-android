// Phase 3 of the mobile live-follow plan: the `inflight` snapshot a
// `session.resume` answer carries is the authoritative projection of the turn
// that is still running, and it is what a reconnecting client rebuilds its
// bubbles from (the gateway's own contract comment says exactly that).
//
// These are the pure parse rules — no socket, no widget:
//   * what makes a payload a live turn (running, streaming, or partial text),
//   * which payloads carry nothing to rebuild (null),
//   * when a retained failure must be surfaced instead of the partial being
//     rendered as a healthy reply.
//
// The retained-failure case matters: the gateway keeps a failed turn's
// snapshot replayable for a client that missed the terminal frame, so a
// projection built from it must be able to say "this turn failed" without
// losing the partial text the user already saw.

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/gateway_live_turn.dart';

void main() {
  group('LiveTurnProjection.fromResume', () {
    test('a running turn with partial text carries every projected field', () {
      final projection = LiveTurnProjection.fromResume({
        'session_id': 'gw-runtime-1',
        'running': true,
        'status': 'running',
        'inflight': {
          'user': 'hi',
          'assistant': 'partial text',
          'streaming': true,
        },
      });

      expect(projection, isNotNull);
      expect(projection!.running, isTrue);
      expect(projection.status, 'running');
      expect(projection.user, 'hi');
      expect(projection.assistant, 'partial text');
      expect(projection.streaming, isTrue);
      expect(projection.error, isEmpty);
      expect(projection.failed, isFalse);
      expect(projection.isLive, isTrue);
    });

    test('an empty payload projects no turn at all', () {
      expect(LiveTurnProjection.fromResume(const {}), isNull);
    });

    test('an idle resume without an inflight snapshot projects no turn', () {
      expect(
        LiveTurnProjection.fromResume(const {
          'session_id': 'gw-runtime-1',
          'running': false,
          'status': 'idle',
        }),
        isNull,
      );
    });

    test('an inflight whose every field is empty projects no turn', () {
      expect(
        LiveTurnProjection.fromResume(const {
          'inflight': {'user': '', 'assistant': '', 'streaming': false},
        }),
        isNull,
      );
    });

    test('a retained error surfaces as a failure, not a healthy partial', () {
      final projection = LiveTurnProjection.fromResume(const {
        'inflight': {
          'user': 'hi',
          'assistant': 'half a reply',
          'error': 'boom',
        },
      });

      expect(projection, isNotNull);
      expect(projection!.failed, isTrue);
      expect(projection.error, 'boom');
      expect(projection.assistant, 'half a reply');
    });

    test('every terminal status is a failure', () {
      for (final status in const [
        'error',
        'failed',
        'interrupted',
        'cancelled',
        'canceled',
      ]) {
        final projection = LiveTurnProjection.fromResume({
          'inflight': {'user': 'hi', 'assistant': 'partial', 'status': status},
        });

        expect(projection, isNotNull, reason: 'status $status');
        expect(projection!.failed, isTrue, reason: 'status $status');
        expect(projection.status, status);
      }
    });

    test('a terminal status is a failure even without a snapshot', () {
      final projection = LiveTurnProjection.fromResume(const {
        'session_id': 'gw-runtime-1',
        'running': false,
        'status': 'interrupted',
      });

      expect(projection, isNotNull);
      expect(projection!.failed, isTrue);
      expect(projection.isLive, isFalse);
    });

    test('running alone is live before the first delta arrives', () {
      final projection = LiveTurnProjection.fromResume(const {
        'running': true,
        'inflight': <String, dynamic>{},
      });

      expect(projection, isNotNull);
      expect(projection!.isLive, isTrue);
      expect(projection.assistant, isEmpty);
      expect(projection.user, isEmpty);
      expect(projection.streaming, isFalse);
    });

    test('partial text without a running flag is still a live turn', () {
      final projection = LiveTurnProjection.fromResume(const {
        'running': false,
        'inflight': {'assistant': 'partial text'},
      });

      expect(projection, isNotNull);
      expect(projection!.isLive, isTrue);
    });
  });
}
