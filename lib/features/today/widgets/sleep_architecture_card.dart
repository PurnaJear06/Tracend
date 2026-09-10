import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/shared/widgets/micro_motion.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Full-width sleep quality readout, sibling to `RecoveryReadoutCard`:
/// card tag + band chip, tabular mono score with a count-up, reflowing
/// sub-score rows (label + value on one line, 0-100 bar beneath — no fixed
/// columns, so accessibility text scales reflow instead of crowding), and a
/// debt/surplus pill. Baseline values are not repeated here — the recovery
/// readout's driver rows already carry them one card up.
///
/// State table:
/// - full: score + band chip + sub-score rows + debt pill
/// - score null: 'No data' + honest empty copy
/// - cold_start / low confidence: 'Building baseline' caption under the score
/// - debt pill: positive = debt, negative = surplus, 0 = target met
class SleepArchitectureCard extends StatelessWidget {
  const SleepArchitectureCard({required this.computed, super.key});

  final ComputedMetrics computed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final scores = computed.scores;
    final quality = scores.sleepQuality;
    final hasData = quality != null;
    final lowConfidence =
        computed.dataConfidence == 'cold_start' ||
        computed.dataConfidence == 'low';

    return PremiumGradientCard(
      glow: hasData,
      glowColor: colors.actionPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _CardTag(label: 'SLEEP ARCHITECTURE'),
              const Spacer(),
              if (hasData)
                _BandChip(
                  label: _bandLabel(quality),
                  color: _bandColor(colors, quality),
                ),
            ],
          ),
          const SizedBox(height: TracendSpacing.sm),
          Semantics(
            label: hasData
                ? 'Sleep quality $quality out of 100'
                : 'Sleep quality unavailable',
            excludeSemantics: true,
            child: hasData
                ? MicroMotionCountUp(
                    value: quality,
                    builder: (context, value) =>
                        Text('$value / 100', style: _scoreStyle(context)),
                  )
                : Text('No data', style: _scoreStyle(context)),
          ),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            !hasData
                ? 'No sleep recorded for today yet.'
                : lowConfidence
                ? 'Building baseline'
                : 'Derived from tonight\'s duration, efficiency, restorative stages, and 7-day consistency.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          if (scores.sleepBreakdown != null) ...[
            const SizedBox(height: TracendSpacing.md),
            _SleepSubScores(breakdown: scores.sleepBreakdown!),
          ],
          if (scores.sleepDebtMinutes != null) ...[
            const SizedBox(height: TracendSpacing.sm),
            _SleepDebt(debtMinutes: scores.sleepDebtMinutes!),
          ],
        ],
      ),
    );
  }

  TextStyle _scoreStyle(BuildContext context) =>
      Theme.of(context).textTheme.displaySmall!.copyWith(
        fontFamily: TracendFonts.monoFamily,
        fontSize: 36,
        height: 1.0,
        letterSpacing: -1,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  String _bandLabel(int quality) {
    if (quality >= 80) return 'Restorative';
    if (quality >= 60) return 'Adequate';
    if (quality >= 40) return 'Light';
    return 'Disrupted';
  }

  Color _bandColor(TracendColors colors, int quality) {
    if (quality >= 80) return colors.stateStable;
    if (quality >= 60) return colors.accentAmber;
    return colors.stateAttention;
  }
}

class _CardTag extends StatelessWidget {
  const _CardTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = context.tracendColors.actionPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bedtime_rounded, size: 13, color: color),
        const SizedBox(width: TracendSpacing.xxs),
        Text(label, style: TracendTheme.labelCaps(context, color: color)),
      ],
    );
  }
}

class _BandChip extends StatelessWidget {
  const _BandChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TracendSpacing.xs + 2,
        vertical: TracendSpacing.xxs,
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontSize: 11, color: color),
      ),
    ),
  );
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _SubScoreRow(label: items[i].$1, score: items[i].$2),
          if (i < items.length - 1) const SizedBox(height: TracendSpacing.sm),
        ],
      ],
    );
  }
}

/// One sub-score: label and rounded value on the first line, 0-100 bar
/// beneath. No fixed-width columns — at accessibility text scales the label
/// wraps and the value stays reachable.
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

    return Semantics(
      label: '$label ${score.round()} of 100',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
              ),
              const Spacer(),
              Text(
                score.round().toString(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontFamily: TracendFonts.monoFamily,
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 6,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(color: colors.borderSubtle.withValues(alpha: 0.3)),
                  AnimatedFractionallySizedBox(
                    duration: TracendMotion.standard,
                    curve: TracendMotion.curve,
                    widthFactor: pct,
                    alignment: Alignment.centerLeft,
                    child: Container(color: barColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SleepDebt extends StatelessWidget {
  const _SleepDebt({required this.debtMinutes});

  final int debtMinutes;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    // SQL convention (daily_computed_metrics): sleep_debt_minutes =
    // 480 - round(avg_7d_sleep_minutes), so a POSITIVE value is debt (avg
    // sleep under the 8-hour target) and a negative value is surplus.
    final hasDebt = debtMinutes > 0;
    final hours = debtMinutes.abs() ~/ 60;
    final mins = debtMinutes.abs() % 60;
    final label = hasDebt
        ? 'Sleep debt: ${hours}h ${mins}m'
        : debtMinutes < 0
        ? 'Sleep surplus: ${hours}h ${mins}m'
        : 'Sleep target met';
    final icon = debtMinutes > 0
        ? Icons.trending_down_rounded
        : debtMinutes < 0
        ? Icons.trending_up_rounded
        : Icons.trending_flat_rounded;
    final color = debtMinutes > 0 ? colors.stateAttention : colors.stateStable;

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TracendSpacing.xs + 2,
            vertical: TracendSpacing.xxs,
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
                ).textTheme.labelMedium?.copyWith(fontSize: 11, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
