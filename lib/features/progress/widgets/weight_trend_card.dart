import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/shared/widgets/evidence_trend_chart.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Weight direction card: measured dots + optional computed regression
/// overlays (plan §6.1).
///
/// Binding contract:
/// - dots = confirmed [BodyMeasurement] weigh-ins (the honesty statement)
/// - overlays = `ComputedMetrics.scores.weightTrend7d/28d` (OLS slopes,
///   kg/day, ALGORITHMS.md §5), anchored to real measurements by
///   [deriveTrendOverlay] — never invented intercepts, never extrapolated
/// - R² = `weightTrendR2` (28-day window only) gates only the 28-day line
/// - overlay windows end at the latest confirmed weigh-in, which may trail
///   the server's brief target date; the centroid anchor uses the displayed
///   body-measurement dots, while the server fit may also merge HealthKit
///   summary weights (see [deriveTrendOverlay] for both disclosures)
class WeightTrendCard extends StatelessWidget {
  const WeightTrendCard({required this.measurements, this.computed, super.key});

  final List<BodyMeasurement> measurements;
  final ComputedMetrics? computed;

  @override
  Widget build(BuildContext context) {
    final first = measurements.first.weightKg;
    final last = measurements.last.weightKg;
    final change = last - first;
    final scores = computed?.scores;
    return PremiumGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weight direction',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            '${measurements.length} actual weigh-ins · no smoothing',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: TracendSpacing.sm),
          Row(
            children: [
              _TrendFact(
                label: 'Started',
                value: '${first.toStringAsFixed(1)} kg',
              ),
              _TrendFact(label: 'Now', value: '${last.toStringAsFixed(1)} kg'),
              _TrendFact(
                label: 'Change',
                value:
                    '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)} kg',
              ),
            ],
          ),
          const SizedBox(height: 16),
          EvidenceTrendChart(
            values: measurements
                .map((item) => DatedTrendValue(item.date, item.weightKg))
                .toList(),
            unit: 'kg',
            trendSlope7d: scores?.weightTrend7d,
            trendSlope28d: scores?.weightTrend28d,
            trendR2: scores?.weightTrendR2,
            semanticLabel:
                'Weight trend from ${first.toStringAsFixed(1)} to ${last.toStringAsFixed(1)} kilograms across ${measurements.length} confirmed days.',
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            'Each dot is an actual confirmed weigh-in. Tap a history row below to verify its date and source.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TrendFact extends StatelessWidget {
  const _TrendFact({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: TracendSpacing.xxs),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}
