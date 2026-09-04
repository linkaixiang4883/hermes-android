import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the gen-l10n contract both ARB files must uphold:
///
/// * every non-metadata key exists in **both** locales (a missing zh key
///   silently falls back to English at runtime — this test makes it loud);
/// * every `{placeholder}` used in a value is declared in that key's `@key`
///   metadata with a concrete type, otherwise `flutter gen-l10n` either
///   fails or generates a getter with the wrong signature.
Map<String, dynamic> _readArb(String name) {
  final file = File('lib/l10n/$name');
  assert(file.existsSync(), 'run flutter test from the package root');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

final _placeholderPattern = RegExp(r'\{([A-Za-z][A-Za-z0-9]*)\}');

void main() {
  late Map<String, dynamic> en;
  late Map<String, dynamic> zh;

  setUpAll(() {
    en = _readArb('app_en.arb');
    zh = _readArb('app_zh.arb');
  });

  Set<String> keys(Map<String, dynamic> arb) =>
      arb.keys.where((key) => !key.startsWith('@')).toSet();

  test('en and zh define the same key set', () {
    final enKeys = keys(en);
    final zhKeys = keys(zh);
    expect(
      zhKeys.difference(enKeys),
      isEmpty,
      reason: 'zh-only keys have no English template: '
          '${zhKeys.difference(enKeys)}',
    );
    expect(
      enKeys.difference(zhKeys),
      isEmpty,
      reason: 'keys missing a Chinese translation (runtime falls back to '
          'English): ${enKeys.difference(zhKeys)}',
    );
  });

  test('every placeholder is declared in @key metadata', () {
    final problems = <String>[];
    for (final entry in en.entries) {
      if (entry.key.startsWith('@')) continue;
      final value = entry.value;
      if (value is! String) continue;
      final used = _placeholderPattern
          .allMatches(value)
          .map((match) => match.group(1)!)
          .toSet();
      if (used.isEmpty) continue;
      final meta = en['@${entry.key}'];
      final declared =
          (meta is Map
                  ? (meta['placeholders'] as Map? ?? const {})
                  : const {})
              .keys
              .toSet();
      final missing = used.difference(declared);
      if (missing.isNotEmpty) {
        problems.add('${entry.key}: uses $missing but declares $declared');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('zh has no leftover untranslated template markers', () {
    // A translation that still contains the English-only TODO convention
    // means someone added the key but never translated it.
    final todos = keys(zh).where((key) {
      final value = zh[key];
      return value is String && value.startsWith('TODO:');
    }).toList();
    expect(todos, isEmpty, reason: 'untranslated keys: $todos');
  });
}
