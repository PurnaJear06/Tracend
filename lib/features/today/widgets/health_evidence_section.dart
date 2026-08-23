import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/shared/widgets/evidence_trend_chart.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Apple Health evidence section (restyled into PremiumGradientCard context).
/// Kept from Phase 4 — real data, honest missing-state copy.
class HealthEvidenceSection extends StatelessWidget {
  const HealthEvidenceSection({required this.history, super.key});

  final HealthHistory history;

  @override
  Widget build(BuildContext context) {
    final latest = history.latest;
    if (latest == null) {
      return const TracendCard(
        child: Text(
          'No Apple Health summaries are stored yet. Refresh after granting access, or continue with the daily check-in.',
        ),
      );
    }
    final sleep = history.days
        .where((day) => day.sleepMinutes != null)
        .toList();
    final steps = history.days.where((day) => day.steps != null).toList();
    return Column(
      children: [
        PremiumGradientCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Latest stored day · ${_shortDate(latest.date)}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: TracendSpacing.md),
              Text(
                'What matters today',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: TracendSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _SignalMetric(
                      label: 'Steps',
                      value: latest.steps?.toString() ?? '—',
                    ),
                  ),
                  const SizedBox(width: TracendSpacing.xs),
                  Expanded(
                    child: _SignalMetric(
                      label: 'Sleep',
                      value: latest.sleepMinutes == null
                          ? '—'
                          : _duration(latest.sleepMinutes!),
                    ),
                  ),
                  const SizedBox(width: TracendSpacing.xs),
                  Expanded(
                    child: _SignalMetric(
                      label: 'Training',
                      value: latest.workoutMinutes == null
                          ? '—'
                          : '${latest.workoutMinutes}m',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TracendSpacing.sm),
              Text(
                latest.sleepMinutes == null
                    ? 'Activity is available. Recovery guidance relies more on your check-in because sleep was not found.'
                    : 'Activity and sleep are available to your Coach for today’s recovery context.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Material(
                color: Colors.transparent,
                child: ExpansionTile(
                  key: const PageStorageKey('today-more-health'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('More health details'),
                  children: [
                    _HealthDetail(
                      label: 'Active energy',
                      value: latest.activeEnergyKcal == null
                          ? 'Not found'
                          : '${latest.activeEnergyKcal!.round()} kcal',
                    ),
                    _HealthDetail(
                      label: 'Resting heart rate',
                      value: latest.restingHeartRateBpm == null
                          ? 'Not found'
                          : '${latest.restingHeartRateBpm!.round()} bpm',
                    ),
                    _HealthDetail(
                      label: 'HRV (SDNN)',
                      value: latest.hrvSdnnMs == null
                          ? 'Not found'
                          : '${latest.hrvSdnnMs!.round()} ms',
                    ),
                    _HealthDetail(
                      label: 'Weight',
                      value: latest.weightKg == null
                          ? 'Not found'
                          : '${latest.weightKg!.toStringAsFixed(1)} kg',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (sleep.length >= 2) ...[
          const SizedBox(height: TracendSpacing.sm),
          _HealthTrend(
            title: 'Sleep duration',
            points: sleep
                .map((day) => DatedTrendValue(day.date, day.sleepMinutes! / 60))
                .toList(),
            unit: 'hours',
          ),
        ],
        if (steps.length >= 2) ...[
          const SizedBox(height: TracendSpacing.sm),
          _HealthTrend(
            title: 'Daily steps',
            points: steps
                .map((day) => DatedTrendValue(day.date, day.steps!.toDouble()))
                .toList(),
            unit: 'steps',
          ),
        ],
        if (sleep.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: TracendSpacing.sm),
            child: TracendCard(
              child: Text(
                'Sleep has no stored samples. Confirm Apple Health contains sleep records and that Tracend has Sleep read access; an empty query cannot tell us which one is missing.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
      ],
    );
  }

  static String _duration(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';
  static String _shortDate(DateTime date) => '${date.day}/${date.month}';
}

class _SignalMetric extends StatelessWidget {
  const _SignalMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.tracendColors.surfaceRaised,
      borderRadius: BorderRadius.circular(TracendRadii.control),
    ),
    child: Padding(
      padding: const EdgeInsets.all(TracendSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontFamily: TracendFonts.monoFamily,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ),
  );
}

class _HealthDetail extends StatelessWidget {
  const _HealthDetail({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: TracendSpacing.xs),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontFamily: TracendFonts.monoFamily,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _HealthTrend extends StatelessWidget {
  const _HealthTrend({
    required this.title,
    required this.points,
    required this.unit,
  });
  final String title;
  final List<DatedTrendValue> points;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final latest = points.last.value;
    final average =
        points.fold<double>(0, (sum, item) => sum + item.value) / points.length;
    final difference = latest - average;
    return TracendCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            '${_format(latest)} $unit today · ${difference >= 0 ? '+' : ''}${_format(difference)} vs average',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: TracendSpacing.sm),
          EvidenceTrendChart(
            values: points,
            unit: unit,
            average: average,
            compact: true,
            semanticLabel:
                '$title from ${_date(points.first.date)} to ${_date(points.last.date)}. Latest ${_format(latest)} $unit. Average ${_format(average)}.',
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            'Dots are recorded days. Gaps follow the real calendar; the thin line marks your recorded average.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _format(double value) =>
      value >= 100 ? value.round().toString() : value.toStringAsFixed(1);
  String _date(DateTime date) => '${date.day}/${date.month}';
}
