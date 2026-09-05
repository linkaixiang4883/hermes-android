import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/turn_usage.dart';

void main() {
  group('TurnUsage.fromJson', () {
    test('parses usage sub map', () {
      final usage = TurnUsage.fromJson({
        'usage': {
          'prompt_tokens': 1500,
          'completion_tokens': 800,
          'total_tokens': 2300,
        },
      });
      expect(usage, isNotNull);
      expect(usage!.inputTokens, 1500);
      expect(usage.outputTokens, 800);
      expect(usage.totalTokens, 2300);
    });

    test('missing total returns null', () {
      expect(
        TurnUsage.fromJson({
          'usage': {
            'prompt_tokens': 1500,
            'completion_tokens': 800,
          },
        }),
        isNull,
      );
    });

    test('missing usage map returns null', () {
      expect(TurnUsage.fromJson({}), isNull);
    });
  });

  group('TurnUsage.formatCompact', () {
    test('formats millions', () {
      expect(TurnUsage.formatCompact(1500000), '1.5M');
    });

    test('formats thousands', () {
      expect(TurnUsage.formatCompact(2300), '2.3k');
    });

    test('keeps small numbers raw', () {
      expect(TurnUsage.formatCompact(999), '999');
      expect(TurnUsage.formatCompact(0), '0');
    });
  });
}
