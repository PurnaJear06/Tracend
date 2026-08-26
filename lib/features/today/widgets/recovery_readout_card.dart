import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/shared/widgets/micro_motion.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Full-width recovery readout (Chunk 6). Replaces the centered
/// `RecoveryRing` and the cramped recovery tile of the old readiness strip:
/// one wide card with the tabular score, a band chip, and five driver rows
/// with z-score bars.
///
/// State table:
/// - full: score + band chip + driver rows (bar fill clamps z to ±2,
///   semantics announce the true z-score)
/// - score null: '--' + honest empty copy; driver rows only with a breakdown
/// - driver missing: row reports 'No data' — a missing component is never
///   rendered as an at-baseline '+0.0'
/// - cold_start / low confidence: 'Building baseline' caption under the score
class RecoveryReadoutCard extends StatelessWidget {
  const RecoveryReadoutCard({required this.computed, super.key});

  final ComputedMetrics computed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final score = computed.scores.recovery;
    final breakdown = computed.scores.recoveryBreakdown;
    final confidence = computed.dataConfidence;
    final lowConfidence = confidence == 'cold_start' || confidence == 'low';

    return PremiumGradientCard(
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _CardTag(label: 'RECOVERY'),
              const Spacer(),
              if (score != null)
                _BandChip(
                  label: _bandLabel(score),
                  color: _bandColor(colors, score),
                ),
            ],
          ),
          const SizedBox(height: TracendSpacing.sm),
          Semantics(
            label: score != null
                ? 'Recovery score $score out of 100'
                : 'Recovery score unavailable',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (score != null)
                  MicroMotionCountUp(
                    value: score,
                    builder: (context, value) =>
                        Text('$value', style: _scoreStyle(context)),
                  )
                else
                  Text('--', style: _scoreStyle(context)),
                const SizedBox(width: TracendSpacing.xxs),
                Text(
                  '/ 100',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontFamily: TracendFonts.monoFamily,
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            score == null
                ? 'Not enough data for a recovery score. Sync Apple Health and check in to build your baseline.'
                : lowConfidence
                ? 'Building baseline'
                : 'Derived from HRV, resting HR, sleep, respiratory rate, and prior strain.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          if (breakdown != null) ...[
            const SizedBox(height: TracendSpacing.md),
            _DriverRows(breakdown: breakdown),
          ],
        ],
      ),
    );
  }

  TextStyle _scoreStyle(BuildContext context) =>
      Theme.of(context).textTheme.displaySmall!.copyWith(
        fontFamily: TracendFonts.monoFamily,
        fontSize: 44,
        height: 1.0,
        letterSpacing: -1.5,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  String _bandLabel(int score) {
    if (score >= 80) return 'Excellent';
    if (score >= 65) return 'Good';
    if (score >= 50) return 'Moderate';
    if (score >= 35) return 'Low';
    return 'Poor';
  }

  Color _bandColor(TracendColors colors, int score) {
    if (score >= 65) return colors.stateStable;
    if (score >= 50) return colors.accentAmber;
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
        Icon(CupertinoIcons.heart_fill, size: 13, color: color),
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

class _DriverRows extends StatelessWidget {
  const _DriverRows({required this.breakdown});

  final RecoveryBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final missing = breakdown.missingComponents.toSet();
    final drivers = [
      ('HRV', 'hrv_sdnn', breakdown.hrvZ, colors.actionPrimary),
      ('RHR', 'resting_hr', breakdown.rhrZ, colors.stateStable),
      (
        'Sleep',
        'sleep_minutes',
        breakdown.sleepZ,
        colors.actionPrimary.withValues(alpha: 0.55),
      ),
      ('Resp', 'resp_rate', breakdown.respRateZ, colors.accentAmber),
      ('Strain', 'prev_strain', breakdown.prevStrainZ, colors.stateAttention),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recovery drivers',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: TracendSpacing.xs),
        for (var i = 0; i < drivers.length; i++) ...[
          if (i > 0) const SizedBox(height: TracendSpacing.xs + 2),
          _DriverRow(
            label: drivers[i].$1,
            zScore: drivers[i].$3,
            color: drivers[i].$4,
            missing: missing.contains(drivers[i].$2),
          ),
        ],
      ],
    );
  }
}

/// One recovery-driver row: label, horizontal z-score bar, signed z value.
/// The bar fill clamps the z-score to ±2 for layout; the semantics label and
/// the trailing value report the true (unclamped) z-score — the announced
/// value is the data, never the display clamp. The hairline notch marks the
/// baseline (z = 0).
///
/// When [missing] is true the component did not contribute to the score
/// (value or baseline unavailable). The row reports 'No data' instead of an
/// at-baseline '+0.0', which would falsely imply a measured, neutral reading.
class _DriverRow extends StatelessWidget {
  const _DriverRow({
    required this.label,
    required this.zScore,
    required this.color,
    this.missing = false,
  });

  final String label;
  final double zScore;
  final Color color;
  final bool missing;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final filled = (zScore.clamp(-2.0, 2.0) + 2.0) / 4.0;
    final zText = missing
        ? 'No data'
        : '${zScore >= 0 ? '+' : ''}${zScore.toStringAsFixed(1)}';

    return Semantics(
      label: missing
          ? '$label driver, no data'
          : '$label driver, z-score $zText',
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontSize: 11,
                letterSpacing: 0.6,
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      color: colors.borderSubtle.withValues(alpha: 0.35),
                    ),
                    if (!missing) ...[
                      Positioned.fill(
                        child: Align(
                          child: Container(
                            width: 1,
                            color: colors.borderHairline,
                          ),
                        ),
                      ),
                      AnimatedFractionallySizedBox(
                        duration: TracendMotion.standard,
                        curve: TracendMotion.curve,
                        widthFactor: filled,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: TracendSpacing.xs),
          SizedBox(
            width: 52,
            child: Text(
              zText,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontFamily: TracendFonts.monoFamily,
                fontSize: 11,
                color: missing
                    ? colors.textSecondary
                    : zScore >= 0
                    ? colors.stateStable
                    : colors.stateAttention,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
