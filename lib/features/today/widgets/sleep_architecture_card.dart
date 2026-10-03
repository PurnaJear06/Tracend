import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/shared/widgets/micro_motion.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// Last night's sleep quality on Today, under the "Sleep" section label:
/// the score with a count-up and a band chip, four reflowing sub-score rows
/// (label and value on one line, a 0–100 bar beneath, no fixed columns) and
/// the sleep debt or surplus. Baselines are not repeated here; the recovery
/// drivers already carry them.
///
/// State table:
/// - full: score + band chip + sub-score rows + debt chip
/// - score null: "Not enough data yet" with honest copy
/// - cold_start / low confidence: "Building baseline" under the score
/// - debt: positive = debt, negative = surplus, 0 = target met
class SleepArchitectureCard extends StatelessWidget {
  const SleepArchitectureCard({required this.computed, super.key});

  final ComputedMetrics computed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final scores = computed.scores;
    final quality = scores.sleepQuality;
    final lowConfidence =
        computed.dataConfidence == 'cold_start' ||
        computed.dataConfidence == 'low';

    return PremiumGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: TracendSpacing.xs,
              runSpacing: TracendSpacing.xs,
              children: [
                Text(
                  'Sleep quality',
                  style: textTheme.titleSmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                if (quality != null) _band(quality),
              ],
            ),
          ),
          const SizedBox(height: TracendSpacing.xxs),
          Semantics(
            label: quality != null
                ? 'Sleep quality $quality out of 100'
                : 'Sleep quality: not enough data yet',
            excludeSemantics: true,
            child: quality != null
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        MicroMotionCountUp(
                          value: quality,
                          builder: (context, value) =>
                              Text('$value', style: _scoreStyle(context)),
                        ),
                        const SizedBox(width: TracendSpacing.xxs),
                        Text(
                          '/ 100',
                          style: textTheme.titleMedium?.copyWith(
                            fontFamily: TracendFonts.numericFamily,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Text('Not enough data yet', style: textTheme.titleMedium),
          ),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            quality == null
                ? 'No sleep is recorded for last night yet.'
                : lowConfidence
                ? 'Building baseline'
                : 'From last night\'s duration, efficiency and restorative '
                      'stages, and your 7-day consistency.',
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          if (scores.sleepBreakdown != null) ...[
            const SizedBox(height: TracendSpacing.md),
            _SleepSubScores(breakdown: scores.sleepBreakdown!),
          ],
          if (scores.sleepDebtMinutes != null) ...[
            const SizedBox(height: TracendSpacing.md),
            _SleepDebt(debtMinutes: scores.sleepDebtMinutes!),
          ],
        ],
      ),
    );
  }

  TextStyle? _scoreStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .displayMedium
      ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  Widget _band(int quality) {
    final (label, tone, icon) = quality >= 80
        ? ('Restorative', StatusTone.good, CupertinoIcons.checkmark_circle_fill)
        : quality >= 60
        ? ('Adequate', StatusTone.caution, CupertinoIcons.minus_circle_fill)
        : quality >= 40
        ? ('Light', StatusTone.low, CupertinoIcons.exclamationmark_circle_fill)
        : (
            'Disrupted',
            StatusTone.low,
            CupertinoIcons.exclamationmark_circle_fill,
          );
    return Semantics(
      label: 'Sleep band: $label',
      excludeSemantics: true,
      child: StatusChip(label: label, icon: icon, tone: tone),
    );
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

/// One sub-score: label and rounded value on the first line, a 0–100 bar
/// beneath. No fixed-width columns, so at accessibility text sizes the label
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
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(width: TracendSpacing.xs),
              Text(
                score.round().toString(),
                style: TracendTheme.numeric(colors, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(TracendRadii.pill),
            child: SizedBox(
              height: 6,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(color: colors.surfaceRaised),
                  AnimatedFractionallySizedBox(
                    duration: TracendMotionScope.movement(
                      context,
                      TracendMotion.standard,
                    ),
                    curve: TracendMotion.curve,
                    widthFactor: pct,
                    alignment: Alignment.centerLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(TracendRadii.pill),
                      ),
                      child: const SizedBox.expand(),
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
}

class _SleepDebt extends StatelessWidget {
  const _SleepDebt({required this.debtMinutes});

  final int debtMinutes;

  @override
  Widget build(BuildContext context) {
    // SQL convention (daily_computed_metrics): sleep_debt_minutes =
    // 480 - round(avg_7d_sleep_minutes), so a POSITIVE value is debt (average
    // sleep under the 8-hour target) and a negative value is surplus.
    final amount = _formatMinutes(debtMinutes.abs());
    final (label, tone, icon) = debtMinutes > 0
        ? (
            'Sleep debt: $amount',
            StatusTone.caution,
            CupertinoIcons.arrow_down_right,
          )
        : debtMinutes < 0
        ? (
            'Sleep surplus: $amount',
            StatusTone.good,
            CupertinoIcons.arrow_up_right,
          )
        : ('Sleep target met', StatusTone.good, CupertinoIcons.checkmark_alt);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: StatusChip(label: label, icon: icon, tone: tone),
    );
  }

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '$rest min';
    return rest == 0 ? '$hours h' : '$hours h $rest min';
  }
}
