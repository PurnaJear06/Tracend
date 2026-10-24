import 'package:flutter/material.dart';
import 'package:tracend/features/train/widgets/train_parts.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';

/// The selected day's exercises as one grouped list. Every row opens the
/// exercise sheet: today's target, last time, your best and the plan's tip.
class ExerciseListCard extends StatelessWidget {
  const ExerciseListCard({
    required this.workout,
    required this.onExerciseTap,
    super.key,
  });

  final PlannedWorkout workout;
  final ValueChanged<PlannedExercise> onExerciseTap;

  @override
  Widget build(BuildContext context) => TracendGroupedList(
    children: [
      for (var i = 0; i < workout.exercises.length; i++)
        TracendListRow(
          key: ValueKey('exercise-row-${workout.exercises[i].order}'),
          leading: ExerciseIndexTile(number: i + 1),
          title: workout.exercises[i].name,
          subtitle: exerciseLine(workout.exercises[i]),
          trailing: _wasSets(workout.exercises[i]),
          semanticLabel:
              '${workout.exercises[i].name}, '
              '${exerciseSpeech(workout.exercises[i])}. Opens details.',
          onTap: () => onExerciseTap(workout.exercises[i]),
        ),
    ],
  );
}

/// The plan's own set count, struck through, beside an exercise today's
/// accepted adjustment cut. VoiceOver reads the cut in [exerciseSpeech].
Widget? _wasSets(PlannedExercise exercise) {
  final planned = exercise.plannedSetCount;
  if (planned == null) return null;
  return ExcludeSemantics(
    child: Builder(
      builder: (context) => Text(
        '$planned',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          decoration: TextDecoration.lineThrough,
          color: Theme.of(
            context,
          ).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
        ),
      ),
    ),
  );
}

/// The exercise line in words VoiceOver reads naturally.
String exerciseSpeech(PlannedExercise exercise) {
  final planned = exercise.plannedSetCount;
  final sets =
      '${exercise.setCount} sets of ${repRange(exercise)} reps'
      '${planned == null ? '' : ', down from $planned sets'}';
  final next = exercise.nextTarget;
  if (next != null) {
    final load = next.loadKg;
    final String target;
    if (load == null) {
      target = '${next.reps} reps';
    } else if (isAssistedPlanned(exercise)) {
      target = load == 0
          ? 'unassisted for ${next.reps} reps'
          : '${formatKg(load)} kilograms of help for ${next.reps} reps';
    } else {
      target = '${formatKg(load)} kilograms for ${next.reps} reps';
    }
    return exercise.loadHeld
        ? '$sets, held at $target today'
        : '$sets, next target $target';
  }
  final load = exercise.targetLoadKg;
  return load == null ? sets : '$sets at ${formatKg(load)} kilograms';
}
