import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/exercise_history.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

String _normalized(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// The `get_my_exercise_history` key for each lift in [hub]'s progression:
/// the catalog slug of the plan exercise with the same name, otherwise the
/// name itself (the key the server uses for exercises without a slug).
Map<String, String> liftHistoryKeys(TrainingHubData hub) {
  final planned = <String, String>{
    for (final workout in hub.workouts)
      for (final exercise in workout.exercises)
        _normalized(exercise.name): exercise.historyKey,
  };
  return {
    for (final lift in hub.progression)
      lift.exercise:
          planned[_normalized(lift.exercise)] ?? lift.exercise.trim(),
  };
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The lifts whose latest workout set their all-time best set.
///
/// A lift counts only when its history has a best set dated the same day as
/// its last completed session, that session is the one the hub reports as
/// the lift's latest, and there was an earlier session to beat. Ties go to
/// the earliest date on the server, so repeating a record is never a new
/// best. Unknown history is never a new best.
Set<String> liftNewBests(
  TrainingHubData hub,
  Map<String, String> keys,
  ExerciseHistoryResult history,
) => {
  for (final lift in hub.progression)
    if (_setNewBest(lift, history[keys[lift.exercise] ?? lift.exercise]))
      lift.exercise,
};

bool _setNewBest(ExerciseProgression lift, ExerciseHistory? history) {
  final bestOn = history?.bestSet?.localDate;
  final lastOn = history?.lastSession?.localDate;
  final latest = lift.latestDate;
  if (history == null || bestOn == null || lastOn == null || latest == null) {
    return false;
  }
  return history.topSets.length >= 2 &&
      _sameDay(bestOn, lastOn) &&
      _sameDay(lastOn, latest);
}

/// Strength section: workout consistency for the selected period and the
/// best confirmed value per lift from `get_my_training_hub`. Planned loads
/// are never shown as progress.
class TrainingEvidenceSection extends StatelessWidget {
  const TrainingEvidenceSection({
    required this.training,
    required this.periodDays,
    this.newBests = const {},
    super.key,
  });

  final TrainingHubData? training;
  final int periodDays;

  /// Lifts whose latest workout set an all-time best ([liftNewBests]).
  final Set<String> newBests;

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
        Semantics(
          container: true,
          label:
              '${hub.completedSessions} of ${hub.plannedSessions} planned '
              'workouts done in the last ${periodLabel(periodDays)}',
          excludeSemantics: true,
          child: PremiumGradientCard(
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
                            style: TracendTheme.numeric(
                              colors,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text: ' of ${hub.plannedSessions} workouts',
                            style: theme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Last ${periodLabel(periodDays)}',
                      style: theme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: TracendSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(TracendRadii.pill),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: colors.surfaceRaised),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: fraction,
                          child: ColoredBox(color: colors.actionPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: TracendSpacing.xs),
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
                    _LiftTile(
                      item: hub.progression[i],
                      newBest: newBests.contains(hub.progression[i].exercise),
                    ),
                    if (i < hub.progression.length - 1)
                      const SizedBox(width: TracendSpacing.xs),
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
  const _LiftTile({required this.item, required this.newBest});
  final ExerciseProgression item;
  final bool newBest;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    final best = item.bestLoadKg == null
        ? '${item.bestRepetitions ?? '—'} reps'
        : '${item.bestLoadKg} kg';
    final workouts = 'Best · ${item.sessions} workouts';
    return Semantics(
      container: true,
      label:
          '${item.exercise}, best $best across ${item.sessions} workouts'
          '${newBest ? ', new best in your last workout' : ''}',
      excludeSemantics: true,
      child: SizedBox(
        width: 160,
        child: PremiumGradientCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (newBest) ...[
                const _NewBestChip(),
                const SizedBox(height: TracendSpacing.xs),
              ],
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
                style: TracendTheme.numeric(
                  colors,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(workouts, style: theme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lime marks a new best: the signal for "now", never a judgement.
class _NewBestChip extends StatelessWidget {
  const _NewBestChip();

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accentSignal,
        borderRadius: BorderRadius.circular(TracendRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.star_fill,
              size: 12,
              color: colors.onAccentSignal,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'New best',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onAccentSignal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
