import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Daily targets grid (plan §5.2, Stitch `nutrition.html` instrument rows).
///
/// Binding contract:
/// - targets = active `nutrition_target_sets` row ([NutritionTargets])
/// - consumed = confirmed totals from `get_my_daily_nutrition`
///   ([NutritionSummary])
/// - solid cells only (no nested glass); mono values; `X / Yg` readable text
///
/// State table:
/// - full: consumed/target per macro + progress bars + remaining
/// - no targets: consumed only, honest "No active target set" note
/// - no consumed: targets only, empty bars (cold start)
class TargetsGrid extends StatelessWidget {
  const TargetsGrid({required this.summary, required this.targets, super.key});

  final NutritionSummary? summary;
  final NutritionTargets? targets;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final targets = this.targets;

    if (targets == null) {
      return PremiumGradientCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TargetsTag(),
            const SizedBox(height: TracendSpacing.sm),
            Text(
              '${_round(summary?.calories)} kcal logged',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFamily: TracendFonts.monoFamily,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              'No active nutrition target is set.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    final calories = summary?.calories ?? 0;
    final protein = summary?.protein ?? 0;
    final carbohydrate = summary?.carbohydrate ?? 0;
    final fat = summary?.fat ?? 0;
    final proteinRemaining = (targets.protein - protein).clamp(
      0.0,
      targets.protein,
    );

    return PremiumGradientCard(
      glow: true,
      glowColor: colors.accentAmber,
      padding: const EdgeInsets.all(TracendSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: TracendSpacing.xxs,
              bottom: TracendSpacing.sm,
            ),
            child: _TargetsTag(),
          ),
          _WideCell(
            label: 'ENERGY INTAKE',
            labelColor: colors.textSecondary,
            consumed: _round(calories),
            target: '/ ${_round(targets.calories)} kcal',
            trailing: _percent(calories, targets.calories),
            fraction: _fraction(calories, targets.calories),
            barColor: colors.textPrimary,
            semanticsLabel:
                'Energy ${_round(calories)} of ${_round(targets.calories)} kilocalories',
          ),
          const SizedBox(height: TracendSpacing.xxs),
          _WideCell(
            label: 'PROTEIN',
            labelColor: colors.actionPrimary,
            consumed: _round(protein),
            target: '/ ${_round(targets.protein)}g',
            trailing: '${_round(proteinRemaining)}g left',
            fraction: _fraction(protein, targets.protein),
            barColor: colors.actionPrimary,
            highlighted: true,
            semanticsLabel:
                'Protein ${_round(protein)} of ${_round(targets.protein)} grams, '
                '${_round(proteinRemaining)} grams remaining',
          ),
          const SizedBox(height: TracendSpacing.xxs),
          Row(
            children: [
              Expanded(
                child: _HalfCell(
                  label: 'CARBS',
                  labelColor: colors.stateStable,
                  consumed: _round(carbohydrate),
                  target: '/ ${_round(targets.carbohydrate)}g',
                  fraction: _fraction(carbohydrate, targets.carbohydrate),
                  barColor: colors.stateStable,
                  semanticsLabel:
                      'Carbohydrate ${_round(carbohydrate)} of '
                      '${_round(targets.carbohydrate)} grams',
                ),
              ),
              const SizedBox(width: TracendSpacing.xxs),
              Expanded(
                child: _HalfCell(
                  label: 'FATS',
                  labelColor: colors.accentAmber,
                  consumed: _round(fat),
                  target: '/ ${_round(targets.fat)}g',
                  fraction: _fraction(fat, targets.fat),
                  barColor: colors.accentAmber,
                  semanticsLabel:
                      'Fat ${_round(fat)} of ${_round(targets.fat)} grams',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _round(num? value) => (value ?? 0).round().toString();

  static double _fraction(num consumed, num target) =>
      target <= 0 ? 0 : (consumed / target).clamp(0.0, 1.0);

  static String _percent(num consumed, num target) => target <= 0
      ? '--'
      : '${((consumed / target) * 100).clamp(0, 999).round()}%';
}

class _TargetsTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(CupertinoIcons.scope, size: 13, color: colors.accentAmber),
        const SizedBox(width: TracendSpacing.xxs),
        Flexible(
          child: Text(
            'DAILY TARGETS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontSize: 10,
              letterSpacing: 1.4,
              color: colors.accentAmber,
            ),
          ),
        ),
      ],
    );
  }
}

class _WideCell extends StatelessWidget {
  const _WideCell({
    required this.label,
    required this.labelColor,
    required this.consumed,
    required this.target,
    required this.trailing,
    required this.fraction,
    required this.barColor,
    required this.semanticsLabel,
    this.highlighted = false,
  });

  final String label;
  final Color labelColor;
  final String consumed;
  final String target;
  final String trailing;
  final double fraction;
  final Color barColor;
  final String semanticsLabel;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Semantics(
      label: semanticsLabel,
      child: Container(
        padding: const EdgeInsets.all(TracendSpacing.sm),
        decoration: BoxDecoration(
          color: highlighted
              ? colors.actionPrimary.withValues(alpha: 0.06)
              : colors.surfaceRaised,
          border: Border.all(color: colors.borderHairline),
          borderRadius: BorderRadius.circular(TracendRadii.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontSize: 10,
                              letterSpacing: 1.2,
                              color: labelColor,
                            ),
                      ),
                      const SizedBox(height: TracendSpacing.xxs),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              consumed,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontFamily: TracendFonts.monoFamily,
                                    fontSize: 26,
                                    letterSpacing: -0.5,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ),
                          const SizedBox(width: TracendSpacing.xxs),
                          Flexible(
                            child: Text(
                              target,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    fontFamily: TracendFonts.monoFamily,
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  trailing,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontFamily: TracendFonts.monoFamily,
                    fontSize: 12,
                    color: highlighted
                        ? colors.actionPrimary
                        : colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: TracendSpacing.sm),
            _TargetBar(fraction: fraction, color: barColor),
          ],
        ),
      ),
    );
  }
}

class _HalfCell extends StatelessWidget {
  const _HalfCell({
    required this.label,
    required this.labelColor,
    required this.consumed,
    required this.target,
    required this.fraction,
    required this.barColor,
    required this.semanticsLabel,
  });

  final String label;
  final Color labelColor;
  final String consumed;
  final String target;
  final double fraction;
  final Color barColor;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Semantics(
      label: semanticsLabel,
      child: Container(
        padding: const EdgeInsets.all(TracendSpacing.sm),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          border: Border.all(color: colors.borderHairline),
          borderRadius: BorderRadius.circular(TracendRadii.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontSize: 10,
                letterSpacing: 1.2,
                color: labelColor,
              ),
            ),
            const SizedBox(height: TracendSpacing.xxs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    consumed,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFamily: TracendFonts.monoFamily,
                      fontSize: 20,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: TracendSpacing.xxs),
                Flexible(
                  child: Text(
                    target,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontFamily: TracendFonts.monoFamily,
                      fontSize: 10,
                      color: colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TracendSpacing.sm),
            _TargetBar(fraction: fraction, color: barColor),
          ],
        ),
      ),
    );
  }
}

class _TargetBar extends StatelessWidget {
  const _TargetBar({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: SizedBox(
      height: 4,
      child: Stack(
        children: [
          Container(
            color: context.tracendColors.borderSubtle.withValues(alpha: 0.4),
          ),
          FractionallySizedBox(
            widthFactor: fraction,
            child: Container(color: color),
          ),
        ],
      ),
    ),
  );
}
