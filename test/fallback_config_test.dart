import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/fallback_config.dart';

void main() {
  test('parses primary and legacy fallback entries without losing metadata', () {
    final config = FallbackConfig.fromConfig({
      'fallback_providers': [
        {'provider': 'nous', 'model': 'hermes-5', 'base_url': 'https://x'},
        {'provider': 'openai', 'model': 'gpt-5'},
      ],
      'fallback_model': {'provider': 'legacy', 'model': 'old'},
    });

    expect(config.entries, hasLength(2));
    expect(config.entries.first.provider, 'nous');
    expect(config.entries.first.model, 'hermes-5');
    expect(config.entries.first.hasMetadata, isTrue);
    expect(config.legacyEntries.single.provider, 'legacy');
  });

  test('confirms an ordered readback and preserves legacy absence', () {
    final before = FallbackConfig.fromConfig({
      'fallback_providers': [
        {'provider': 'a', 'model': '1'},
      ],
    });
    final expected = [FallbackEntry({'provider': 'a', 'model': '1'})];
    final after = FallbackConfig.fromConfig({
      'fallback_providers': [
        {'provider': 'a', 'model': '1'},
      ],
    });
    expect(after.confirms(expected, before), isTrue);

    final reordered = FallbackConfig.fromConfig({
      'fallback_providers': [
        {'provider': 'b', 'model': '2'},
        {'provider': 'a', 'model': '1'},
      ],
    });
    expect(reordered.confirms(expected, before), isFalse);
  });

  test('does not treat a missing primary key as clearing a persisted chain', () {
    final before = FallbackConfig.fromConfig({
      'fallback_providers': [
        {'provider': 'a', 'model': '1'},
      ],
    });
    final missing = FallbackConfig.fromConfig({});
    expect(missing.confirms(const [], before), isFalse);
  });

  test('rejects malformed and incomplete entries', () {
    expect(
      () => FallbackConfig.fromConfig({'fallback_providers': 'bad'}),
      throwsFormatException,
    );
    expect(
      () => FallbackConfig.fromConfig({
        'fallback_providers': [
          {'provider': 'a'},
        ],
      }),
      throwsFormatException,
    );
  });
}
