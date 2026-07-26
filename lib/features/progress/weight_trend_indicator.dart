import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class WeightTrendIndicator extends StatelessWidget {
  const WeightTrendIndicator({required this.computed, super.key});

  final ComputedMetrics computed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final trend7 = computed.scores.weightTrend7d;
    final trend28 = computed.scores.weightTrend28d;
    final r2 = computed.scores.weightTrendR2;

    return TracendCard(
      raised: true,
      padding: const EdgeInsets.all(TracendSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2A45C).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(TracendRadii.control),
                ),
                child: const Icon(Icons.trending_down_rounded, size: 20, color: Color(0xFFE2A45C)),
              ),
              const SizedBox(width: TracendSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WEIGHT TREND',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFFE2A45C),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: TracendSpacing.xxs),
                  Text(
                    trend7 != null
                        ? '${_format(trend7)} kg/day'
                        : 'No data',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: trend7 != null ? colors.textPrimary : colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (trend7 != null || trend28 != null) ...[
            const SizedBox(height: TracendSpacing.md),
            Row(
              children: [
                _TrendChip(
                  label: '7-day',
                  value: trend7,
                  r2: null,
                ),
                const SizedBox(width: TracendSpacing.sm),
                if (trend28 != null)
                  _TrendChip(
                    label: '28-day',
                    value: trend28,
                    r2: r2,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _format(double value) {
    if (value == 0) return '0.0';
    if (value > 0) return '+${value.toStringAsFixed(1)}';
    return value.toStringAsFixed(2);
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.label, required this.value, this.r2});

  final String label;
  final double? value;
  final double? r2;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    if (value == null) return const SizedBox.shrink();

    final isLosing = value! < 0;
    final color = isLosing ? colors.stateStable : colors.stateAttention;
    final arrow = isLosing ? '\u2193' : '\u2191';
    final trendValue = value!.abs();

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(TracendSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(TracendRadii.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: TracendSpacing.xxs),
            Row(
              children: [
                Text(
                  '$arrow ${trendValue.toStringAsFixed(2)} kg/day',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (r2 != null) ...[
                  const SizedBox(width: TracendSpacing.xxs),
                  Text(
                    'R\u00B2 ${r2?.toStringAsFixed(2) ?? '--'}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
