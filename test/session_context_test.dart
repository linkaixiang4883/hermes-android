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
  });
}
