import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Strength section: workout consistency for the selected period and the
/// best confirmed value per lift from `get_my_training_hub`. Planned loads
/// are never shown as progress.
class TrainingEvidenceSection extends StatelessWidget {
  const TrainingEvidenceSection({
    required this.training,
    required this.periodDays,
    super.key,
  });

  final TrainingHubData? training;
  final int periodDays;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    final hub = training;
    if (hub == null) {
      return PremiumGradientCard(
        child: Text(
          'Workout data is unavailable right now. Your weigh-ins and photos '
          'still work.',
          style: theme.bodyMedium,
        ),
      );
    }
    final fraction = hub.plannedSessions == 0
        ? 0.0
        : (hub.completedSessions / hub.plannedSessions).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PremiumGradientCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: TracendSpacing.sm,
                runSpacing: TracendSpacing.xxs,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${hub.completedSessions}',
                          style: theme.headlineMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        TextSpan(
                          text: ' of ${hub.plannedSessions} workouts',
                          style: theme.titleMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Last ${periodLabel(periodDays)}',
                    style: theme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: TracendSpacing.sm),
              Semantics(
                label:
                    '${hub.completedSessions} of ${hub.plannedSessions} '
                    'planned workouts done',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    color: colors.actionPrimary,
                    backgroundColor: colors.surfaceRaised,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: TracendSpacing.sm),
        if (hub.progression.isEmpty)
          PremiumGradientCard(
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.chart_bar_alt_fill,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: TracendSpacing.sm),
                Expanded(
                  child: Text(
                    'Lift progress shows up after you repeat an exercise in '
                    'two workouts.',
                    style: theme.bodyMedium,
                  ),
                ),
              ],
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < hub.progression.length; i++) ...[
                    _LiftTile(item: hub.progression[i]),
                    if (i < hub.progression.length - 1)
                      const SizedBox(width: TracendSpacing.sm),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _LiftTile extends StatelessWidget {
  const _LiftTile({required this.item});
  final ExerciseProgression item;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    final best = item.bestLoadKg == null
        ? '${item.bestRepetitions ?? '—'} reps'
        : '${item.bestLoadKg} kg';
    return SizedBox(
      width: 156,
      child: PremiumGradientCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.exercise,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.titleSmall,
            ),
            const Spacer(),
            const SizedBox(height: TracendSpacing.sm),
            Text(
              best,
              style: theme.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              'Best · ${item.sessions} workouts',
              style: TracendTheme.labelCaps(
                context,
                color: colors.textSecondary,
              ).copyWith(letterSpacing: 0.2),
            ),
          ],
        ),
      ),
    );
  }
}
