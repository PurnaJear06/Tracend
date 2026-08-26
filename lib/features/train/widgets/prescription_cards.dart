import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Prescription card: the planned exercises with real set/rep/RPE/rest data
/// from `planned_exercises`. Hairline dividers, no boxes-in-boxes.
class PrescriptionCard extends StatelessWidget {
  const PrescriptionCard({required this.workout, super.key});

  final PlannedWorkout workout;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return PremiumGradientCard(
      padding: const EdgeInsets.symmetric(
        horizontal: TracendSpacing.md,
        vertical: TracendSpacing.sm,
      ),
      child: Column(
        children: [
          for (var index = 0; index < workout.exercises.length; index++) ...[
            _ExerciseRow(exercise: workout.exercises[index]),
            if (index < workout.exercises.length - 1)
              Divider(height: TracendSpacing.lg, color: colors.borderHairline),
          ],
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise});
  final PlannedExercise exercise;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Semantics(
      label:
          '${exercise.name}, ${exercise.setCount} sets of '
          '${exercise.repMin} to ${exercise.repMax} reps at RPE '
          '${exercise.targetRpe}, rest ${exercise.restSeconds} seconds',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${exercise.order}'.padLeft(2, '0'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontFamily: TracendFonts.monoFamily,
                  fontSize: 11,
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: TracendSpacing.xxs),
                  Wrap(
                    spacing: TracendSpacing.md,
                    runSpacing: TracendSpacing.xxs,
                    children: [
                      _ExerciseStat(
                        text:
                            '${exercise.setCount} × ${exercise.repMin}–${exercise.repMax}',
                      ),
                      _ExerciseStat(text: 'RPE ${exercise.targetRpe}'),
                      _ExerciseStat(text: '${exercise.restSeconds}s rest'),
                    ],
                  ),
                  if (exercise.notes.isNotEmpty) ...[
                    const SizedBox(height: TracendSpacing.xxs),
                    Text(
                      exercise.notes,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseStat extends StatelessWidget {
  const _ExerciseStat({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      fontFamily: TracendFonts.monoFamily,
      fontSize: 11,
      color: context.tracendColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

/// Warm-up and cooldown guidance card (real plan fields).
class WarmUpCard extends StatelessWidget {
  const WarmUpCard({required this.workout, super.key});

  final PlannedWorkout workout;

  @override
  Widget build(BuildContext context) => PremiumGradientCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (workout.warmUp.isNotEmpty) ...[
          Text('Warm-up', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: TracendSpacing.xxs),
          Text(workout.warmUp),
        ],
        if (workout.cooldownCardio.isNotEmpty) ...[
          if (workout.warmUp.isNotEmpty)
            const SizedBox(height: TracendSpacing.sm),
          Text(
            'Cooldown / cardio',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: TracendSpacing.xxs),
          Text(workout.cooldownCardio),
        ],
      ],
    ),
  );
}

/// Adherence readout: real completed/planned session counts from the hub.
class AdherenceCard extends StatelessWidget {
  const AdherenceCard({
    required this.completedSessions,
    required this.plannedSessions,
    super.key,
  });

  final int completedSessions;
  final int plannedSessions;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final ratio = plannedSessions == 0
        ? 0.0
        : (completedSessions / plannedSessions).clamp(0, 1).toDouble();
    return PremiumGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$completedSessions',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: TracendFonts.monoFamily,
                  fontSize: 26,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: TracendSpacing.xxs),
              Text(
                'of $plannedSessions planned sessions',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 5,
              child: Stack(
                children: [
                  Container(color: colors.borderSubtle.withValues(alpha: 0.4)),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(color: colors.stateStable),
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

/// Progression readout: real best load/reps from comparable completed
/// sessions. Display-only — the values are facts, not navigation, so the
/// rows carry no chevron or tap target (no dead affordance).
class ProgressionCard extends StatelessWidget {
  const ProgressionCard({required this.progression, super.key});

  final List<ExerciseProgression> progression;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    if (progression.isEmpty) {
      return PremiumGradientCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No progression yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: TracendSpacing.xxs),
            const Text(
              'Progression appears after at least two completed sessions contain comparable logged sets. Planned values are never charted.',
            ),
          ],
        ),
      );
    }
    return PremiumGradientCard(
      padding: const EdgeInsets.symmetric(
        horizontal: TracendSpacing.md,
        vertical: TracendSpacing.sm,
      ),
      child: Column(
        children: [
          for (var index = 0; index < progression.length; index++) ...[
            _ProgressionRow(item: progression[index]),
            if (index < progression.length - 1)
              Divider(height: TracendSpacing.lg, color: colors.borderHairline),
          ],
        ],
      ),
    );
  }
}

class _ProgressionRow extends StatelessWidget {
  const _ProgressionRow({required this.item});
  final ExerciseProgression item;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.exercise,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: TracendSpacing.xxs),
                Text(
                  '${item.sessions} comparable sessions',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            item.bestLoadKg == null
                ? '${item.bestRepetitions ?? '—'} reps'
                : '${item.bestLoadKg} kg',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontFamily: TracendFonts.monoFamily,
              color: colors.stateStable,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Recent sessions list. Rows with a resolvable planned workout open the
/// workout detail for that session date; rows without one are display-only
/// (no dead chevron).
class RecentSessionsCard extends StatelessWidget {
  const RecentSessionsCard({
    required this.sessions,
    required this.workoutForId,
    required this.repository,
    super.key,
  });

  final List<TrainingSessionSummary> sessions;
  final PlannedWorkout? Function(String workoutId) workoutForId;
  final WorkoutRepository repository;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return PremiumGradientCard(
      padding: const EdgeInsets.symmetric(
        horizontal: TracendSpacing.md,
        vertical: TracendSpacing.sm,
      ),
      child: Column(
        children: [
          for (var index = 0; index < sessions.length; index++) ...[
            _RecentSessionRow(
              session: sessions[index],
              workout: sessions[index].workoutId == null
                  ? null
                  : workoutForId(sessions[index].workoutId!),
              repository: repository,
            ),
            if (index < sessions.length - 1)
              Divider(height: TracendSpacing.lg, color: colors.borderHairline),
          ],
        ],
      ),
    );
  }
}

class _RecentSessionRow extends StatelessWidget {
  const _RecentSessionRow({
    required this.session,
    required this.workout,
    required this.repository,
  });

  final TrainingSessionSummary session;
  final PlannedWorkout? workout;
  final WorkoutRepository repository;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final dateLabel =
        '${session.date.day}/${session.date.month}/${session.date.year}';
    final duration = session.durationSeconds == null
        ? null
        : '${(session.durationSeconds! / 60).round()} min';
    final openable = workout != null;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.check_mark_circled_solid,
            size: 18,
            color: colors.stateStable,
          ),
          const SizedBox(width: TracendSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: TracendSpacing.xxs),
                Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontFamily: TracendFonts.monoFamily,
                    fontSize: 11,
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (duration != null)
            Text(
              duration,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontFamily: TracendFonts.monoFamily,
                fontSize: 11,
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          if (openable) ...[
            const SizedBox(width: TracendSpacing.xs),
            Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: colors.textSecondary,
            ),
          ],
        ],
      ),
    );
    if (!openable) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push<void>(
          CupertinoPageRoute(
            builder: (_) => WorkoutDetailScreen(
              repository: repository,
              workout: workout,
              sessionDate: session.date,
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(TracendRadii.control),
        child: content,
      ),
    );
  }
}
