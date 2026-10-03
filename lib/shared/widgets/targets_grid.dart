import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Daily targets grid: confirmed intake against the active targets.
///
/// Binding contract:
/// - targets = active `nutrition_target_sets` row ([NutritionTargets])
/// - consumed = confirmed totals from `get_my_daily_nutrition`
///   ([NutritionSummary])
/// - flat cells on `surfaceRaised`; numbers in the numeric family with
///   tabular figures; `X / Yg` readable text
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
      final summary = this.summary;
      return PremiumGradientCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TargetsTag(),
            const SizedBox(height: TracendSpacing.sm),
            Text(
              summary == null
                  ? 'No confirmed meals yet'
                  : '${summary.calories.round()} kcal logged',
              style: TracendTheme.numeric(
                colors,
                fontSize: 22,
                fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.all(TracendSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(
              left: TracendSpacing.xxs,
              top: TracendSpacing.xxs,
              bottom: TracendSpacing.sm,
            ),
            child: _TargetsTag(),
          ),
          _WideCell(
            label: 'Calories',
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
            label: 'Protein',
            swatch: colors.actionPrimary,
            consumed: _round(protein),
            target: '/ ${_round(targets.protein)}g',
            trailing: '${_round(proteinRemaining)}g left',
            fraction: _fraction(protein, targets.protein),
            barColor: colors.actionPrimary,
            semanticsLabel:
                'Protein ${_round(protein)} of ${_round(targets.protein)} grams, '
                '${_round(proteinRemaining)} grams remaining',
          ),
          const SizedBox(height: TracendSpacing.xxs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _HalfCell(
                  label: 'Carbs',
                  swatch: colors.stateStable,
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
                  label: 'Fat',
                  swatch: colors.accentAmber,
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

/// The honesty label: totals count confirmed meals only.
class _TargetsTag extends StatelessWidget {
  const _TargetsTag();

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          CupertinoIcons.checkmark_seal,
          size: 14,
          color: colors.textSecondary,
        ),
        const SizedBox(width: TracendSpacing.xxs),
        Flexible(
          child: Text(
            'From confirmed meals',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// A macro's name with the small colour key it shares with the meal split
/// bars, so the colour is never the only label.
class _CellLabel extends StatelessWidget {
  const _CellLabel({required this.label, this.color});

  final String label;

  /// The macro's key colour; calories, the total, has none.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (color != null) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _WideCell extends StatelessWidget {
  const _WideCell({
    required this.label,
    this.swatch,
    required this.consumed,
    required this.target,
    required this.trailing,
    required this.fraction,
    required this.barColor,
    required this.semanticsLabel,
  });

  final String label;
  final Color? swatch;
  final String consumed;
  final String target;
  final String trailing;
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
          borderRadius: BorderRadius.circular(TracendRadii.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _CellLabel(label: label, color: swatch),
                ),
                const SizedBox(width: TracendSpacing.xs),
                Expanded(
                  flex: 2,
                  child: Text(
                    trailing,
                    textAlign: TextAlign.end,
                    style: TracendTheme.numeric(colors, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TracendSpacing.xxs),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: TracendSpacing.xxs,
              children: [
                Text(
                  consumed,
                  style: TracendTheme.numeric(
                    colors,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ).copyWith(height: 1.1),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(target, style: TracendTheme.dataUtility(colors)),
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
    required this.swatch,
    required this.consumed,
    required this.target,
    required this.fraction,
    required this.barColor,
    required this.semanticsLabel,
  });

  final String label;
  final Color swatch;
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
          borderRadius: BorderRadius.circular(TracendRadii.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CellLabel(label: label, color: swatch),
            const SizedBox(height: TracendSpacing.xxs),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: TracendSpacing.xxs,
              children: [
                Text(
                  consumed,
                  style: TracendTheme.numeric(
                    colors,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ).copyWith(height: 1.1),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(target, style: TracendTheme.dataUtility(colors)),
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
    borderRadius: BorderRadius.circular(TracendRadii.pill),
    child: SizedBox(
      height: 4,
      child: Stack(
        children: [
          Container(color: context.tracendColors.borderSubtle),
          FractionallySizedBox(
            widthFactor: fraction,
            child: Container(color: color),
          ),
        ],
      ),
    ),
  );
}
