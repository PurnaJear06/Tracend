import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/evidence_trend_chart.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// Which way the weight should move for a goal: -1 down, 1 up, 0 neither.
int goalWeightDirection(String? goal) => switch (goal) {
  'fat_loss' => -1,
  'muscle_gain' => 1,
  _ => 0,
};

/// Plain-language read of the 28-day fit's R². The middle band starts at the
/// chart's [lowConfidenceR2Threshold], so the words and the dashed line agree.
String trendSteadinessLabel(double r2) {
  if (r2 >= 0.6) return 'Steady trend';
  if (r2 >= lowConfidenceR2Threshold) return 'Some day-to-day variation';
  return 'Too noisy to call yet';
}

/// The Progress hero: latest weigh-in, change across the selected period,
/// the weekly rate, and the chart, in one card.
///
/// Binding contract:
/// - weight and change come only from confirmed [BodyMeasurement]s; the
///   change needs two weigh-ins inside the period
/// - the weekly rate is the server's OLS slope
///   (`ComputedMetrics.scores.weightTrend28d`, else `weightTrend7d`) × 7;
///   nothing is fitted on the device
/// - the chart keeps [EvidenceTrendChart]'s raw-dot and overlay rules
/// - the change chip takes the lime signal only when it moves toward the
///   active goal (`fat_loss` down, `muscle_gain` up); the arrow and the
///   spoken label carry the same meaning, so color is never the only signal
class WeightHeroCard extends StatelessWidget {
  const WeightHeroCard({
    required this.measurements,
    required this.periodMeasurements,
    required this.onRecord,
    this.computed,
    this.goal,
    this.fallbackWeightKg,
    this.now,
    super.key,
  });

  /// Every confirmed weigh-in, oldest first.
  final List<BodyMeasurement> measurements;

  /// The weigh-ins inside the selected period, oldest first.
  final List<BodyMeasurement> periodMeasurements;
  final VoidCallback onRecord;
  final ComputedMetrics? computed;
  final String? goal;

  /// Server summary weight, shown only when no weigh-in list is available.
  final double? fallbackWeightKg;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    final latest = measurements.isEmpty ? null : measurements.last;
    final weight = latest?.weightKg ?? fallbackWeightKg;

    if (weight == null) {
      return PremiumGradientCard(
        padding: const EdgeInsets.all(TracendSpacing.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(onInfo: () => _showExplainer(context)),
            const SizedBox(height: TracendSpacing.xs),
            Text('Add your first weigh-in', style: theme.headlineMedium),
            const SizedBox(height: TracendSpacing.xs),
            Text(
              'Your first weigh-in is your starting point. Two or more show '
              'which way you are heading.',
              style: theme.bodyMedium,
            ),
            const SizedBox(height: TracendSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('record-measurement'),
                onPressed: onRecord,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.plus, size: 18),
                    SizedBox(width: TracendSpacing.xs),
                    Flexible(
                      child: Text(
                        'Record measurement',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final scores = computed?.scores;
    final slope = scores?.weightTrend28d ?? scores?.weightTrend7d;
    final r2 = scores?.weightTrend28d == null ? null : scores?.weightTrendR2;
    final period = periodMeasurements;
    final change = period.length >= 2
        ? period.last.weightKg - period.first.weightKg
        : null;

    return PremiumGradientCard(
      padding: const EdgeInsets.all(TracendSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(onInfo: () => _showExplainer(context)),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: weight.toStringAsFixed(1),
                  style: TracendTheme.numeric(
                    colors,
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                  ).copyWith(height: 1.05, letterSpacing: -0.8),
                ),
                TextSpan(
                  text: ' kg',
                  style: TracendTheme.numeric(
                    colors,
                    fontSize: 20,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (latest != null) ...[
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              'Last weigh-in · ${friendlyDate(latest.date, now: now)}',
              style: theme.bodyMedium,
            ),
          ],
          if (change != null || slope != null) ...[
            const SizedBox(height: TracendSpacing.md),
            Wrap(
              spacing: TracendSpacing.xs,
              runSpacing: TracendSpacing.xs,
              children: [
                if (change != null)
                  _ChangeChip(
                    change: change,
                    since: shortDate(period.first.date, now: now),
                    goalDirection: goalWeightDirection(goal),
                  ),
                if (slope != null)
                  _FactChip(
                    label: kgPerWeek(slope),
                    icon: CupertinoIcons.speedometer,
                  ),
                if (r2 != null)
                  _FactChip(
                    label: trendSteadinessLabel(r2),
                    icon: CupertinoIcons.waveform_path,
                  ),
              ],
            ),
          ],
          if (period.length >= 2) ...[
            const SizedBox(height: TracendSpacing.md),
            EvidenceTrendChart(
              values: period
                  .map((item) => DatedTrendValue(item.date, item.weightKg))
                  .toList(),
              unit: 'kg',
              trendSlope7d: scores?.weightTrend7d,
              trendSlope28d: scores?.weightTrend28d,
              trendR2: scores?.weightTrendR2,
              semanticLabel:
                  'Weight trend from ${period.first.weightKg.toStringAsFixed(1)} '
                  'to ${period.last.weightKg.toStringAsFixed(1)} kilograms '
                  'across ${period.length} weigh-ins.',
            ),
          ] else ...[
            const SizedBox(height: TracendSpacing.sm),
            Text(
              period.isEmpty
                  ? 'No weigh-ins in this period. Pick a longer period or '
                        'record one today.'
                  : 'Record one more weigh-in to see your trend.',
              style: theme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  void _showExplainer(BuildContext context) => showTracendSheet<void>(
    context,
    title: 'How this is calculated',
    builder: (context) => const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Each dot is a weigh-in you recorded, shown exactly as entered. '
          'The lines and the weekly rate are calculated from your '
          'weigh-ins. Nothing here is estimated by AI.',
        ),
        SizedBox(height: TracendSpacing.sm),
        Text(
          'A dashed line means your weight has moved around too much from '
          'day to day to trust the longer-term direction yet.',
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.onInfo});
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          'Weight',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: context.tracendColors.textSecondary,
          ),
        ),
      ),
      IconButton(
        onPressed: onInfo,
        tooltip: 'How this is calculated',
        icon: Icon(
          CupertinoIcons.info_circle,
          size: 18,
          color: context.tracendColors.textSecondary,
        ),
      ),
    ],
  );
}

class _ChangeChip extends StatelessWidget {
  const _ChangeChip({
    required this.change,
    required this.since,
    required this.goalDirection,
  });

  final double change;
  final String since;
  final int goalDirection;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final rounded = double.parse(change.toStringAsFixed(1));
    final direction = rounded.sign.toInt();
    final towardGoal = direction != 0 && direction == goalDirection;
    final color = towardGoal ? colors.accentSignalInk : colors.textPrimary;
    final arrow = switch (direction) {
      -1 => CupertinoIcons.arrow_down_right,
      1 => CupertinoIcons.arrow_up_right,
      _ => CupertinoIcons.arrow_right,
    };
    final amount = '${rounded.abs().toStringAsFixed(1)} kg';
    final text = direction == 0
        ? 'No change since $since'
        : '$amount since $since';
    final spoken = switch (direction) {
      -1 => 'Down $amount since $since',
      1 => 'Up $amount since $since',
      _ => 'No change since $since',
    };
    return Semantics(
      label: towardGoal ? '$spoken, toward your goal' : spoken,
      excludeSemantics: true,
      child: _ChipShell(
        fill: towardGoal ? colors.accentSignalTint : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(arrow, size: 14, color: color),
            const SizedBox(width: TracendSpacing.xxs),
            Flexible(
              child: Text(
                text,
                style: TracendTheme.numeric(colors, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return _ChipShell(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.textSecondary),
          const SizedBox(width: TracendSpacing.xxs),
          Flexible(child: Text(label, style: TracendTheme.numeric(colors))),
        ],
      ),
    );
  }
}

/// A pill for one fact about the trend; [fill] defaults to `surfaceRaised`.
class _ChipShell extends StatelessWidget {
  const _ChipShell({required this.child, this.fill});
  final Color? fill;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: fill ?? context.tracendColors.surfaceRaised,
      borderRadius: BorderRadius.circular(TracendRadii.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TracendSpacing.sm,
        vertical: TracendSpacing.xs,
      ),
      child: child,
    ),
  );
}
