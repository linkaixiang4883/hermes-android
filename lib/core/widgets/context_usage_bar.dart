import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/session_context.dart';
import '../theme/hermes_theme.dart';

/// Slim context-window gauge shown above the composer.
///
/// The numbers come from `session.context_breakdown`. Tapping opens a compact
/// category sheet; a breakdown with no live agent renders nothing so a fresh
/// screen never shows a misleading empty gauge.
class ContextUsageBar extends StatelessWidget {
  const ContextUsageBar({required this.usage, super.key});

  final SessionContext usage;

  static String _compact(int tokens) {
    if (tokens >= 1000000) {
      final millions = tokens / 1000000;
      return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}M';
    }
    if (tokens >= 1000) {
      final thousands = tokens / 1000;
      return '${thousands.toStringAsFixed(thousands >= 10 ? 0 : 1)}k';
    }
    return '$tokens';
  }

  bool get _hasData => usage.max > 0 && usage.used > 0;

  double get _fraction =>
      usage.max <= 0 ? 0 : (usage.used / usage.max).clamp(0.0, 1.0).toDouble();

  String get _usedText => '${usage.estimated ? '~' : ''}${_compact(usage.used)}';

  @override
  Widget build(BuildContext context) {
    if (!_hasData) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final percent = (usage.percent.isFinite ? usage.percent : 0).round();
    final tint = percent >= 90
        ? scheme.error
        : percent >= 75
        ? scheme.tertiary
        : scheme.primary;

    return Semantics(
      label: context.l10n.usage_title,
      value: context.l10n.usage_bar_summary(
        _usedText,
        _compact(usage.max),
        percent,
      ),
      button: true,
      excludeSemantics: true,
      child: InkWell(
        key: const Key('context-usage-bar'),
        borderRadius: BorderRadius.circular(HermesRadius.sm),
        onTap: () => _showBreakdown(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.donut_small_outlined,
                    size: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: HermesSpacing.xs),
                  Text(
                    context.l10n.context_usage_percent(percent),
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    context.l10n.context_usage_tokens(
                      _usedText,
                      _compact(usage.max),
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HermesSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _fraction,
                  minHeight: 3,
                  backgroundColor: scheme.outlineVariant,
                  valueColor: AlwaysStoppedAnimation<Color>(tint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBreakdown(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            HermesSpacing.xl,
            0,
            HermesSpacing.xl,
            HermesSpacing.lg,
          ),
          child: Column(
            key: const Key('context-usage-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.context_usage_title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: HermesSpacing.xs),
              Text(
                l10n.usage_bar_summary(
                  _usedText,
                  _compact(usage.max),
                  (usage.percent.isFinite ? usage.percent : 0).round(),
                ),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              if (usage.model.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  l10n.usage_model_name(usage.model),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (usage.estimated) ...[
                const SizedBox(height: 2),
                Text(
                  l10n.context_usage_estimated,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (usage.categories.isEmpty) ...[
                const SizedBox(height: HermesSpacing.md),
                Text(
                  l10n.context_usage_no_breakdown,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                const SizedBox(height: HermesSpacing.md),
                for (final category in usage.categories)
                  Padding(
                    key: ValueKey('context-usage-category-${category.id}'),
                    padding: const EdgeInsets.symmetric(
                      vertical: HermesSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _categoryColor(scheme, category.color),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: HermesSpacing.sm),
                        Expanded(
                          child: Text(
                            category.label,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          _compact(category.tokens),
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Color _categoryColor(ColorScheme scheme, String? raw) {
    final value = raw?.replaceFirst('#', '') ?? '';
    if (value.length == 6) {
      final parsed = int.tryParse(value, radix: 16);
      if (parsed != null) return Color(0xFF000000 | parsed);
    }
    return scheme.primary;
  }
}
