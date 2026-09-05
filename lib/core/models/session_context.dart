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

  const SessionContext({
    required this.used,
    required this.max,
    required this.percent,
    required this.model,
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
    return SessionContext(
      used: used,
      max: max,
      percent: percent,
      model: model,
    );
  }
}
