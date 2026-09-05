/// Session-level context window usage parsed from the Gateway breakdown.
///
/// Breakdown shape (server `tui_gateway/methods_session.py`):
/// `{context_used, context_max, context_percent, model, categories?, estimated_total?}`
///
/// Numbers may arrive as `int` or `double`, so all numeric reads go
/// through `(x as num?)` conversion.
class SessionContext {
  final int used;
  final int max;
  final double percent;
  final String model;

  const SessionContext({
    required this.used,
    required this.max,
    required this.percent,
    required this.model,
  });

  /// Returns `null` when the breakdown carries no usable data:
  /// all-zero (`used == 0 && max == 0 && percent == 0`) or missing `max`.
  static SessionContext? fromBreakdown(Map<String, dynamic> json) {
    final used = (json['context_used'] as num?)?.toInt() ?? 0;
    final maxNum = json['context_max'] as num?;
    if (maxNum == null) return null;
    final max = maxNum.toInt();
    final percent = (json['context_percent'] as num?)?.toDouble() ?? 0;
    if (used == 0 && max == 0 && percent == 0) return null;
    final model = json['model'] as String? ?? '';
    return SessionContext(
      used: used,
      max: max,
      percent: percent,
      model: model,
    );
  }
}
