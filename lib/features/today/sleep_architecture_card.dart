import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'computed_metrics.dart';

class SleepArchitectureCard extends StatelessWidget {
  const SleepArchitectureCard({required this.computed, super.key});

  final ComputedMetrics computed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final scores = computed.scores;
    final baselines = computed.baselines;
    final hasData = scores.sleepQuality != null;

    return PremiumGradientCard(
      glow: hasData,
      glowColor: colors.actionPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SleepHeader(quality: scores.sleepQuality, hasData: hasData),
          if (scores.sleepBreakdown != null) ...[
            const SizedBox(height: TracendSpacing.md),
            _SleepSubScores(breakdown: scores.sleepBreakdown!),
          ],
          if (scores.sleepDebtMinutes != null) ...[
            const SizedBox(height: TracendSpacing.md),
            _SleepDebt(debtMinutes: scores.sleepDebtMinutes!),
          ],
          if (baselines.hrv != null || baselines.restingHr != null) ...[
            const SizedBox(height: TracendSpacing.md),
            Divider(height: 1, color: colors.borderSubtle),
            const SizedBox(height: TracendSpacing.md),
            _BaselineFooter(hrv: baselines.hrv, restingHr: baselines.restingHr),
          ],
        ],
      ),
    );
  }
}

class _SleepHeader extends StatelessWidget {
  const _SleepHeader({required this.quality, required this.hasData});

  final int? quality;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.actionPrimary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(TracendRadii.control),
          ),
          child: Icon(
            Icons.bedtime_rounded,
            size: 20,
            color: colors.actionPrimary,
          ),
        ),
        const SizedBox(width: TracendSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SLEEP ARCHITECTURE',
              style: TracendTheme.labelCaps(
                context,
                color: colors.actionPrimary,
              ),
            ),
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              hasData ? '$quality / 100' : 'No data',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: hasData
                    ? _qualityColor(colors, quality!)
                    : colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const Spacer(),
        if (hasData)
          Text(
            _label(quality!),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: _qualityColor(colors, quality!),
            ),
          ),
      ],
    );
  }

  Color _qualityColor(TracendColors colors, int q) {
    if (q >= 80) return colors.stateStable;
    if (q >= 60) return colors.accentAmber;
    return colors.stateAttention;
  }

  String _label(int q) {
    if (q >= 80) return 'Restorative';
    if (q >= 60) return 'Adequate';
    if (q >= 40) return 'Light';
    return 'Disrupted';
  }
}

class _SleepSubScores extends StatelessWidget {
  const _SleepSubScores({required this.breakdown});

  final SleepBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Duration', breakdown.durationScore),
      ('Efficiency', breakdown.efficiencyScore),
      ('Restorative', breakdown.restorativeScore),
      ('Consistency', breakdown.consistencyScore),
    ];

    return Column(
      children: [
        for (final item in items) ...[
          _SubScoreRow(label: item.$1, score: item.$2),
          if (item != items.last) SizedBox(height: TracendSpacing.sm),
        ],
      ],
    );
  }
}

class _SubScoreRow extends StatelessWidget {
  const _SubScoreRow({required this.label, required this.score});

  final String label;
  final double score;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final pct = score.clamp(0, 100) / 100.0;
    final barColor = pct >= 0.8
        ? colors.stateStable
        : pct >= 0.6
        ? colors.accentAmber
        : colors.stateAttention;

    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(width: TracendSpacing.xs),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 6,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: pct),
                duration: TracendMotion.standard,
                curve: TracendMotion.curve,
                builder: (context, value, _) {
                  return Stack(
                    children: [
                      Container(
                        color: colors.borderSubtle.withValues(alpha: 0.3),
                      ),
                      FractionallySizedBox(
                        widthFactor: value,
                        child: Container(color: barColor),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: TracendSpacing.xs),
        SizedBox(
          width: 36,
          child: Text(
            score.round().toString(),
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _SleepDebt extends StatelessWidget {
  const _SleepDebt({required this.debtMinutes});

  final int debtMinutes;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final hasDebt = debtMinutes < 0;
    final hours = debtMinutes.abs() ~/ 60;
    final mins = debtMinutes.abs() % 60;
    final label = hasDebt
        ? 'Sleep debt: ${hours}h ${mins}m'
        : 'Sleep surplus: ${hours}h ${mins}m';
    final icon = hasDebt
        ? Icons.trending_down_rounded
        : Icons.trending_up_rounded;
    final color = hasDebt ? colors.stateAttention : colors.stateStable;

    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(TracendRadii.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TracendSpacing.sm,
          vertical: TracendSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: TracendSpacing.xxs),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _BaselineFooter extends StatelessWidget {
  const _BaselineFooter({required this.hrv, required this.restingHr});

  final BaselineMetric? hrv;
  final BaselineMetric? restingHr;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (hrv != null) ...[
          Expanded(
            child: _BaselineMetric(label: 'HRV BASELINE', metric: hrv!),
          ),
          const SizedBox(width: TracendSpacing.sm),
        ],
        if (restingHr != null)
          Expanded(
            child: _BaselineMetric(label: 'RESTING HR', metric: restingHr!),
          ),
      ],
    );
  }
}

class _BaselineMetric extends StatelessWidget {
  const _BaselineMetric({required this.label, required this.metric});

  final String label;
  final BaselineMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final isLow =
        metric.confidence == 'low' || metric.confidence == 'cold_start';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TracendTheme.labelCaps(context, color: colors.textSecondary),
        ),
        const SizedBox(height: TracendSpacing.xxs),
        Row(
          children: [
            Text(
              metric.ewma.toStringAsFixed(1),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (isLow) ...[
              const SizedBox(width: TracendSpacing.xxs),
              Text(
                '· ${metric.nObs}d',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
