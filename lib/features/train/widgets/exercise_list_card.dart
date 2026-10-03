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
          semanticLabel:
              '${workout.exercises[i].name}, '
              '${exerciseSpeech(workout.exercises[i])}. Opens details.',
          onTap: () => onExerciseTap(workout.exercises[i]),
        ),
    ],
  );
}

/// The exercise line in words VoiceOver reads naturally.
String exerciseSpeech(PlannedExercise exercise) {
  final sets = '${exercise.setCount} sets of ${repRange(exercise)} reps';
  final load = exercise.targetLoadKg;
  return load == null ? sets : '$sets at ${formatKg(load)} kilograms';
}
