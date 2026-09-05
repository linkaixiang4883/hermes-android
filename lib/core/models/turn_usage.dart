/// Per-turn token usage parsed from the stream triple.
///
/// Expects an outer event map holding a `usage` sub map with
/// `prompt_tokens` / `completion_tokens` / `total_tokens`.
/// A bare usage map (without the `usage` wrapper) is also accepted.
class TurnUsage {
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;

  const TurnUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
  });

  /// Returns `null` when there is no `usage` map or `total_tokens` is absent.
  static TurnUsage? fromJson(Map<String, dynamic> json) {
    final raw = json['usage'];
    final Map<String, dynamic> usage;
    if (raw is Map<String, dynamic>) {
      usage = raw;
    } else if (raw is Map) {
      usage = Map<String, dynamic>.from(raw);
    } else if (json.containsKey('prompt_tokens') ||
        json.containsKey('completion_tokens') ||
        json.containsKey('total_tokens')) {
      usage = json;
    } else {
      return null;
    }
    final totalRaw = usage['total_tokens'];
    final total = totalRaw is num ? totalRaw.toInt() : null;
    if (total == null) return null;
    final inputRaw = usage['prompt_tokens'];
    final outputRaw = usage['completion_tokens'];
    return TurnUsage(
      inputTokens: inputRaw is num ? inputRaw.toInt() : 0,
      outputTokens: outputRaw is num ? outputRaw.toInt() : 0,
      totalTokens: total,
    );
  }

  /// Compact display: >=1M -> `x.xM`, >=1k -> `x.xk`, else raw number.
  static String formatCompact(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return '$value';
  }
}
