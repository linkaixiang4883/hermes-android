// ignore_for_file: prefer_initializing_formals

/// Raw fallback fields from the Dashboard config.
///
/// Deliberately keeps only the fallback keys. The full config may hold
/// credentials or unrelated provider settings; never retain or log it.
class FallbackConfig {
  const FallbackConfig._({
    required this.entries,
    required this.legacyEntries,
    required bool legacyPresent,
    required Object? legacy,
    required Object? primary,
  }) : _legacyPresent = legacyPresent,
       _legacy = legacy,
       _primary = primary;

  factory FallbackConfig.fromConfig(Map<String, dynamic> config) {
    return FallbackConfig._(
      entries: _entries(config['fallback_providers']),
      legacyEntries: _entries(config['fallback_model']),
      legacyPresent: config.containsKey('fallback_model'),
      legacy: _freeze(config['fallback_model']),
      primary: _freeze(config['fallback_providers']),
    );
  }

  final List<FallbackEntry> entries;
  final List<FallbackEntry> legacyEntries;

  final bool _legacyPresent;
  final Object? _legacy;
  final Object? _primary;

  /// Confirms that a read-back matches the intended primary chain while
  /// preserving any legacy fallback value exactly as it was.
  bool confirms(List<FallbackEntry> expected, FallbackConfig before) {
    final expectedJson = expected.map((entry) => entry.toJson()).toList();
    return (_equal(_primary, expectedJson) ||
            (_primary == null &&
                before._primary == null &&
                expected.isEmpty)) &&
        _legacyPresent == before._legacyPresent &&
        _equal(_legacy, before._legacy);
  }

  static List<FallbackEntry> _entries(Object? value) {
    if (value == null) return const [];
    final List candidates;
    if (value is Map<String, dynamic>) {
      candidates = [value];
    } else if (value is List) {
      candidates = value;
    } else {
      throw const FormatException('Invalid fallback configuration');
    }
    return List.unmodifiable(
      candidates.map((row) {
        if (row is! Map) {
          throw const FormatException('Invalid fallback configuration');
        }
        final entry = FallbackEntry(Map<String, dynamic>.from(row));
        if (!entry.complete) {
          throw const FormatException('Incomplete fallback configuration');
        }
        return entry;
      }),
    );
  }
}

/// One fallback route. Opaque metadata (endpoints, credentials, routing hints)
/// is preserved byte-for-byte for entries that already exist.
class FallbackEntry {
  FallbackEntry(Map<String, dynamic> data)
    : _data = _freeze(data) as Map<String, dynamic> {
    if (data['provider'] is! String || data['model'] is! String) {
      throw const FormatException('Invalid fallback selection');
    }
  }
  factory FallbackEntry.blank() => FallbackEntry({
        'provider': '',
        'model': '',
      });

  final Map<String, dynamic> _data;

  String get provider => _data['provider'] as String;
  String get model => _data['model'] as String;
  bool get complete => provider.trim().isNotEmpty && model.trim().isNotEmpty;

  /// Unknown fields may carry routing semantics. Never reuse them for a
  /// different provider/model pair.
  bool get hasMetadata =>
      _data.keys.any((key) => key != 'provider' && key != 'model');

  FallbackEntry select(String provider, String model) => FallbackEntry({
        ..._data,
        'provider': provider,
        'model': model,
      });

  Map<String, dynamic> toJson() => _data;
}

Object? _freeze(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map(
        (key, item) => MapEntry(key.toString(), _freeze(item)),
      ),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  throw const FormatException('Invalid fallback metadata');
}

bool _equal(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _equal(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (index) => index)
            .every((index) => _equal(a[index], b[index]));
  }
  return a.runtimeType == b.runtimeType && a == b;
}
