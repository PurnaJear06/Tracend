/// Calculations on the sets logged in one workout, done on the device
/// (ALGORITHMS §4 "Workout logging"). The server returns no volume.
library;

import 'package:tracend/features/train/exercise_history.dart';

/// One set as the athlete logged it.
class LoggedSet {
  const LoggedSet({required this.completed, this.loadKg, this.repetitions});

  /// Reads a set from the workout draft, where kg and reps are the text the
  /// athlete typed. Text the server would not accept reads as not logged.
  factory LoggedSet.fromDraft(Map<String, dynamic> row) => LoggedSet(
    completed: row['completed'] == true,
    loadKg: _parseNum(row['load_kg']),
    repetitions: _parseNum(row['repetitions'])?.toInt(),
  );

  static num? _parseNum(Object? value) => switch (value) {
    num() => value,
    String() => num.tryParse(value.trim()),
    _ => null,
  };

  final bool completed;
  final num? loadKg;
  final int? repetitions;
}

/// The sets of one exercise in this workout.
class LoggedExercise {
  const LoggedExercise({required this.sets, this.assisted = false});

  final List<LoggedSet> sets;

  /// The logged load is machine help, not weight lifted.
  final bool assisted;
}

/// The server's rule for an assisted exercise: a catalog slug starting
/// `assisted-`, or, without a slug, a name starting with the word "assisted".
bool isAssistedExercise({String? slug, required String name}) {
  if (slug != null && slug.trim().isNotEmpty) {
    return slug.trim().startsWith('assisted-');
  }
  return name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .startsWith('assisted ');
}

/// Whether [set] can be ranked under [kind], as the server ranks history:
/// reps above zero, a load above zero for `load`, a logged assistance
/// (0 is unassisted) for `assistance`.
bool _rankable(ExerciseHistoryKind kind, num? loadKg, int? repetitions) {
  if (repetitions == null || repetitions <= 0) return false;
  return switch (kind) {
    ExerciseHistoryKind.load => loadKg != null && loadKg > 0,
    ExerciseHistoryKind.reps => true,
    ExerciseHistoryKind.assistance => loadKg != null && loadKg >= 0,
  };
}

/// True when (load, reps) is strictly stronger than (otherLoad, otherReps).
bool _beats(
  ExerciseHistoryKind kind,
  num load,
  int reps,
  num? otherLoad,
  int? otherReps,
) {
  final previousReps = otherReps ?? 0;
  switch (kind) {
    case ExerciseHistoryKind.load:
      final previous = otherLoad ?? 0;
      return load > previous || (load == previous && reps > previousReps);
    case ExerciseHistoryKind.reps:
      return reps > previousReps;
    case ExerciseHistoryKind.assistance:
      if (otherLoad == null) return true;
      return load < otherLoad || (load == otherLoad && reps > previousReps);
  }
}

/// The indexes of [sets] that are new bests.
///
/// A completed set is a new best only when it beats both the historical
/// best set and every completed set before it in this exercise, by the
/// history's kind. So repeating a record never announces it twice, and
/// un-ticking a set changes the answer on the next call. Unknown history and
/// a first log have no best to beat, so they never produce one.
Set<int> newBestSetIndexes({
  required ExerciseHistory? history,
  required List<LoggedSet> sets,
}) {
  final best = history?.bestSet;
  if (best == null) return const {};
  final kind = best.kind;
  final result = <int>{};
  num? strongestLoad = best.loadKg;
  int? strongestReps = best.repetitions;
  for (var i = 0; i < sets.length; i++) {
    final set = sets[i];
    if (!set.completed || !_rankable(kind, set.loadKg, set.repetitions)) {
      continue;
    }
    final load = set.loadKg ?? 0;
    final reps = set.repetitions!;
    if (_beats(kind, load, reps, strongestLoad, strongestReps)) {
      result.add(i);
      strongestLoad = set.loadKg;
      strongestReps = reps;
    }
  }
  return result;
}

/// "Weight lifted": load × reps summed over completed sets with a logged
/// load above zero, exactly as entered (a dumbbell load is not doubled).
/// Bodyweight sets and assisted exercises add nothing. Rounded to 0.1 kg.
num weightLiftedKg(Iterable<LoggedExercise> exercises) {
  var total = 0.0;
  for (final exercise in exercises) {
    if (exercise.assisted) continue;
    for (final set in exercise.sets) {
      final load = set.loadKg;
      final reps = set.repetitions;
      if (!set.completed || load == null || load <= 0) continue;
      if (reps == null || reps <= 0) continue;
      total += load * reps;
    }
  }
  return (total * 10).round() / 10;
}
