/// One category from the gateway's context breakdown.
class ContextUsageCategory {
  const ContextUsageCategory({
    required this.id,
    required this.label,
    required this.tokens,
    this.color,
  });

  final String id;
  final String label;
  final int tokens;

  /// Server-supplied `#RRGGBB` swatch, when present.
  final String? color;

  static ContextUsageCategory? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final label =
        (raw['label'] ?? raw['name'] ?? raw['category'] ?? '').toString().trim();
    final tokensRaw = raw['tokens'] ?? raw['count'] ?? raw['size'];
    final tokens = tokensRaw is num ? tokensRaw.round() : null;
    if (label.isEmpty || tokens == null || tokens < 0) return null;
    return ContextUsageCategory(
      id: (raw['id'] ?? label).toString(),
      label: label,
      tokens: tokens,
      color: raw['color']?.toString().trim().isEmpty == false
          ? raw['color'].toString().trim()
          : null,
    );
  }
}

/// Session-level context window usage parsed from the Gateway breakdown.
///
/// Breakdown shape (server `tui_gateway/methods_session.py`):
/// `{context_used, context_max, context_percent, model, categories?, estimated_total?}`
///
/// Numbers may arrive as `int` or `double` (never strings), so all numeric
/// reads use `is num` guards and fall back when the type is unexpected.
class SessionContext {
  final int used;
  final int max;
  final double percent;
  final String model;

  /// Per-category token split; empty before the live agent builds.
  final List<ContextUsageCategory> categories;

  /// Server-side estimated total, when the live agent exposes it.
  final int estimatedTotal;

  /// Whether [used] is an estimate rather than a measured count.
  final bool estimated;

  const SessionContext({
    required this.used,
    required this.max,
    required this.percent,
    required this.model,
    this.categories = const [],
    this.estimatedTotal = 0,
    this.estimated = false,
  });

  /// Returns `null` when the breakdown carries no usable data:
  /// missing/non-numeric `max`, non-positive `max` (fail-closed),
  /// negative `used`, or zero usage with zero percent.
  static SessionContext? fromBreakdown(Map<String, dynamic> json) {
    final usedRaw = json['context_used'];
    final used =
        usedRaw is num && usedRaw.isFinite ? usedRaw.toInt() : 0;
    if (used < 0) return null;
    final maxRaw = json['context_max'];
    if (maxRaw is! num || !maxRaw.isFinite) return null;
    final max = maxRaw.toInt();
    // Fail closed: a non-positive window cannot host any usage, so a
    // `max: 0` breakdown with `used > 0` is corrupt data, not 0%.
    if (max <= 0) return null;
    final percentRaw = json['context_percent'];
    // A missing percent is derived from used/max; the dialog rounds it,
    // so float dust here never reaches the UI.
    // A non-finite (NaN/Infinity) or negative percent is corrupt data:
    // guard before any round() (NaN.round() throws) and fall back to
    // the derived value (0 when max is unusable, unreachable here).
    final double percent;
    if (percentRaw is num &&
        percentRaw.isFinite &&
        percentRaw.toDouble() >= 0) {
      percent = percentRaw.toDouble();
    } else {
      percent = max > 0 ? used / max * 100 : 0;
    }
    if (used == 0 && percent == 0) return null;
    final model = json['model']?.toString() ?? '';
    final rawCategories = json['categories'];
    final categories = rawCategories is List
        ? rawCategories
              .map(ContextUsageCategory.fromJson)
              .whereType<ContextUsageCategory>()
              .toList(growable: false)
        : const <ContextUsageCategory>[];
    final estimatedTotalRaw = json['estimated_total'];
    return SessionContext(
      used: used,
      max: max,
      percent: percent,
      model: model,
      categories: categories,
      estimatedTotal: estimatedTotalRaw is num
          ? estimatedTotalRaw.toInt()
          : 0,
      estimated: json['context_estimated'] == true,
    );
  }
}
