import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/utils/message_time.dart';

void main() {
  test(
    'parses epoch seconds and milliseconds without shifting the instant',
    () {
      final seconds = messageTimestamp({'timestamp': 1794075136.911});
      final milliseconds = messageTimestamp({'timestamp': 1794075136911});

      expect(seconds, isNotNull);
      expect(milliseconds, isNotNull);
      expect(seconds!.millisecondsSinceEpoch, 1794075136911);
      expect(milliseconds!.millisecondsSinceEpoch, 1794075136911);
    },
  );

  test('falls back to created_at when timestamp is absent', () {
    final parsed = messageTimestamp({'created_at': '1794075136.5'});
    expect(parsed?.millisecondsSinceEpoch, 1794075136500);
  });

  test('returns null for missing or malformed timestamps', () {
    expect(messageTimestamp(const {}), isNull);
    expect(messageTimestamp({'timestamp': 'not-a-time'}), isNull);
    expect(messageTimestamp({'timestamp': 0}), isNull);
    expect(messageTimestamp({'timestamp': -1}), isNull);
  });
}
