import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session_context.dart';

void main() {
  group('SessionContext.fromBreakdown', () {
    test('parses full fields', () {
      final ctx = SessionContext.fromBreakdown({
        'context_used': 12000,
        'context_max': 200000,
        'context_percent': 6.0,
        'model': 'test-model',
      });
      expect(ctx, isNotNull);
      expect(ctx!.used, 12000);
      expect(ctx.max, 200000);
      expect(ctx.percent, 6.0);
      expect(ctx.model, 'test-model');
    });

    test('accepts double numbers via num conversion', () {
      final ctx = SessionContext.fromBreakdown({
        'context_used': 12000.0,
        'context_max': 200000.0,
        'context_percent': 6.5,
        'model': 'test-model',
      });
      expect(ctx, isNotNull);
      expect(ctx!.used, 12000);
      expect(ctx.max, 200000);
      expect(ctx.percent, 6.5);
    });

    test('all-zero returns null', () {
      expect(
        SessionContext.fromBreakdown({
          'context_used': 0,
          'context_max': 0,
          'context_percent': 0,
          'model': 'test-model',
        }),
        isNull,
      );
    });

    test('missing max returns null', () {
      expect(
        SessionContext.fromBreakdown({
          'context_used': 12000,
          'context_percent': 6.0,
          'model': 'test-model',
        }),
        isNull,
      );
    });

    test('missing model defaults to empty', () {
      final ctx = SessionContext.fromBreakdown({
        'context_used': 500,
        'context_max': 100000,
        'context_percent': 0.5,
      });
      expect(ctx, isNotNull);
      expect(ctx!.model, '');
    });

    test('zero max with nonzero used returns null (fail-closed)', () {
      expect(
        SessionContext.fromBreakdown({
          'context_used': 12000,
          'context_max': 0,
          'context_percent': 0,
          'model': 'test-model',
        }),
        isNull,
      );
    });

    test('missing percent derives from used/max', () {
      final ctx = SessionContext.fromBreakdown({
        'context_used': 10000,
        'context_max': 200000,
        'model': 'test-model',
      });
      expect(ctx, isNotNull);
      expect(ctx!.percent, closeTo(5.0, 1e-9));
    });

    test('non-string model coerces via toString', () {
      final ctx = SessionContext.fromBreakdown({
        'context_used': 500,
        'context_max': 100000,
        'context_percent': 0.5,
        'model': 123,
      });
      expect(ctx, isNotNull);
      expect(ctx!.model, '123');
    });

    test('string numbers fall back without throwing', () {
      // A string max is unusable data, not zero.
      expect(
        SessionContext.fromBreakdown({
          'context_used': 12000,
          'context_max': '200000',
          'context_percent': 6.0,
          'model': 'test-model',
        }),
        isNull,
      );
      // A string used falls back to 0 while a numeric percent still holds.
      final ctx = SessionContext.fromBreakdown({
        'context_used': '12000',
        'context_max': 200000,
        'context_percent': 6.0,
        'model': 'test-model',
      });
      expect(ctx, isNotNull);
      expect(ctx!.used, 0);
      expect(ctx.percent, 6.0);
    });

    test('negative used returns null', () {
      expect(
        SessionContext.fromBreakdown({
          'context_used': -100,
          'context_max': 200000,
          'context_percent': 5.0,
          'model': 'test-model',
        }),
        isNull,
      );
    });

    test('negative percent falls back to derived used/max', () {
      final ctx = SessionContext.fromBreakdown({
        'context_used': 10000,
        'context_max': 200000,
        'context_percent': -3.0,
        'model': 'test-model',
      });
      expect(ctx, isNotNull);
      expect(ctx!.percent, closeTo(5.0, 1e-9));
    });

    test('NaN percent falls back to derived used/max', () {
      final ctx = SessionContext.fromBreakdown({
        'context_used': 10000,
        'context_max': 200000,
        'context_percent': double.nan,
        'model': 'test-model',
      });
      expect(ctx, isNotNull);
      expect(ctx!.percent, closeTo(5.0, 1e-9));
    });

    test('infinite percent falls back to derived used/max', () {
      final ctx = SessionContext.fromBreakdown({
        'context_used': 10000,
        'context_max': 200000,
        'context_percent': double.infinity,
        'model': 'test-model',
      });
      expect(ctx, isNotNull);
      expect(ctx!.percent, closeTo(5.0, 1e-9));
    });
  });
}
