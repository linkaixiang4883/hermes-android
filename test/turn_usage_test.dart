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

    test('parses a bare usage map without the wrapper', () {
      final usage = TurnUsage.fromJson({
        'prompt_tokens': 120,
        'completion_tokens': 45,
        'total_tokens': 165,
      });
      expect(usage, isNotNull);
      expect(usage!.inputTokens, 120);
      expect(usage.outputTokens, 45);
      expect(usage.totalTokens, 165);
    });

    test('string token values fall back without throwing', () {
      // A string total is unusable data.
      expect(
        TurnUsage.fromJson({
          'usage': {
            'prompt_tokens': '1500',
            'completion_tokens': '800',
            'total_tokens': '2300',
          },
        }),
        isNull,
      );
      // A string input falls back to 0 while numeric siblings still hold.
      final usage = TurnUsage.fromJson({
        'usage': {
          'prompt_tokens': '1500',
          'completion_tokens': 800,
          'total_tokens': 2300,
        },
      });
      expect(usage, isNotNull);
      expect(usage!.inputTokens, 0);
      expect(usage.outputTokens, 800);
      expect(usage.totalTokens, 2300);
      // A non-map usage payload carries no triple.
      expect(TurnUsage.fromJson({'usage': 'nope'}), isNull);
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
