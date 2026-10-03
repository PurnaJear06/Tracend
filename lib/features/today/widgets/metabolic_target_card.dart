import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Today's food against the active targets, under the "Food" section label.
///
/// Binding: eaten comes from `brief.nutrition` (`get_my_daily_nutrition`,
/// confirmed meals only); targets come from the active
/// `nutrition_target_sets` row.
///
/// State table:
/// - targets: "1,240 of 2,300 kcal eaten", a progress bar, "Protein 120 g"
///   and the protein left in grams
/// - no targets: what was eaten, with an honest "no target" note and no bar
/// - "Log a meal" opens Nutrition; left out when not wired
class MetabolicTargetCard extends StatelessWidget {
  const MetabolicTargetCard({
    required this.consumed,
    required this.targets,
    required this.onLog,
    super.key,
  });

  /// `brief.nutrition` map (calories, protein_g, ...). May be null.
  final Map<String, dynamic>? consumed;

  /// Active nutrition targets. Null when no target set is active.
  final NutritionTargets? targets;

  /// Opens the Nutrition tab to log a meal.
  final VoidCallback? onLog;

  double get _calories => ((consumed?['calories'] as num?) ?? 0).toDouble();
  double get _protein => ((consumed?['protein_g'] as num?) ?? 0).toDouble();

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final targets = this.targets;
    final eaten = groupedThousands(_calories.round());
    final numberStyle = textTheme.headlineSmall?.copyWith(
      fontFamily: TracendFonts.numericFamily,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final secondary = textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
    );

    final List<Widget> body;
    if (targets == null) {
      body = [
        Text('$eaten kcal eaten', style: numberStyle),
        const SizedBox(height: TracendSpacing.xxs),
        Text('No nutrition target is set yet.', style: secondary),
      ];
    } else {
      final target = groupedThousands(targets.calories.round());
      final fraction = targets.calories <= 0
          ? 0.0
          : (_calories / targets.calories).clamp(0.0, 1.0);
      final proteinLeft = (targets.protein - _protein).clamp(
        0.0,
        targets.protein,
      );
      body = [
        Semantics(
          label: '$eaten of $target kilocalories eaten',
          excludeSemantics: true,
          child: Text('$eaten of $target kcal eaten', style: numberStyle),
        ),
        const SizedBox(height: TracendSpacing.sm),
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(TracendRadii.pill),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: colors.surfaceRaised),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.actionPrimary,
                        borderRadius: BorderRadius.circular(TracendRadii.pill),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: TracendSpacing.sm),
        Wrap(
          spacing: TracendSpacing.md,
          runSpacing: TracendSpacing.xxs,
          children: [
            Text(
              'Protein ${_protein.round()} g',
              style: TracendTheme.numeric(colors, fontSize: 15),
            ),
            Text(
              proteinLeft <= 0
                  ? 'Protein target reached'
                  : '${proteinLeft.round()} g left',
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ];
    }

    final onLog = this.onLog;
    return PremiumGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...body,
          if (onLog != null) ...[
            const SizedBox(height: TracendSpacing.md),
            OutlinedButton.icon(
              onPressed: onLog,
              icon: const Icon(CupertinoIcons.plus, size: 18),
              label: const Text('Log a meal'),
            ),
          ],
        ],
      ),
    );
  }
}

/// "1,240" for 1240. Whole numbers only; the sign is kept.
String groupedThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
