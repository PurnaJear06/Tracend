import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Metabolic Target readout (Stitch `today.html` nutrition module).
///
/// Binding contract (plan §4.1): headline = target kcal, progress bar =
/// consumed/target, protein line = consumed protein + remaining protein.
/// Consumed comes from `brief.nutrition` (`get_my_daily_nutrition`); targets
/// come from the active `nutrition_target_sets` row.
///
/// State table:
/// - full: target headline + consumed bar + protein remaining
/// - no targets: consumed only, honest "No target set" note (no fabricated bar)
/// - no consumed: targets only, empty bar (cold start)
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

  /// Opens the Nutrition tab to log a meal. Null hides the LOG button (no
  /// no-op affordance when the shell doesn't wire tab switching).
  final VoidCallback? onLog;

  double get _consumedCalories =>
      ((consumed?['calories'] as num?) ?? 0).toDouble();
  double get _consumedProtein =>
      ((consumed?['protein_g'] as num?) ?? 0).toDouble();

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final targets = this.targets;

    if (targets == null) {
      return PremiumGradientCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MetabolicTag(),
            const SizedBox(height: TracendSpacing.sm),
            Text(
              '${_consumedCalories.round()} kcal logged',
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

    final calorieFraction = targets.calories <= 0
        ? 0.0
        : (_consumedCalories / targets.calories).clamp(0.0, 1.0);
    final proteinRemaining = (targets.protein - _consumedProtein).clamp(
      0.0,
      targets.protein,
    );

    return PremiumGradientCard(
      glow: true,
      glowColor: colors.accentAmber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MetabolicTag(),
                    const SizedBox(height: TracendSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            targets.calories.round().toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontFamily: TracendFonts.monoFamily,
                                  fontSize: 30,
                                  letterSpacing: -0.6,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ),
                        const SizedBox(width: TracendSpacing.xxs),
                        Text(
                          'kcal',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontFamily: TracendFonts.monoFamily,
                                fontSize: 13,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onLog != null) _LogButton(onLog: onLog!),
            ],
          ),
          const SizedBox(height: TracendSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 5,
              child: Stack(
                children: [
                  Container(color: colors.borderSubtle.withValues(alpha: 0.4)),
                  FractionallySizedBox(
                    widthFactor: calorieFraction,
                    child: Container(color: colors.accentAmber),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: TracendSpacing.sm),
          Row(
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.accentAmber,
                      ),
                    ),
                    const SizedBox(width: TracendSpacing.xxs),
                    Flexible(
                      child: Text(
                        '${_consumedProtein.round()}g PRO',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontFamily: TracendFonts.monoFamily,
                              fontSize: 11,
                              color: colors.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: TracendSpacing.xs),
              Flexible(
                child: Text(
                  '${proteinRemaining.round()}g REMAINING',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontFamily: TracendFonts.monoFamily,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetabolicTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(CupertinoIcons.flame_fill, size: 13, color: colors.accentAmber),
        const SizedBox(width: TracendSpacing.xxs),
        Flexible(
          child: Text(
            'METABOLIC TARGET',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TracendTheme.labelCaps(context, color: colors.accentAmber),
          ),
        ),
      ],
    );
  }
}

class _LogButton extends StatelessWidget {
  const _LogButton({required this.onLog});
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onLog,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: TracendSpacing.sm),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(color: colors.borderHairline),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            'LOG',
            style: TracendTheme.labelCaps(context, color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}
