/// The in-progress workout as the logging screen edits it, and the plain
/// readings of it that the screen shows (suggested starting values, last
/// time, best set). Every number traces to a set the athlete logged, the
/// exercise history or the approved plan; nothing is estimated.
library;

import 'package:tracend/features/train/exercise_history.dart';
import 'package:tracend/features/train/workout_logic.dart';
import 'package:tracend/features/train/workout_repository.dart';

/// A load for display: `60`, `62.5`, `61.25`. Never more than two decimals,
/// which is what the server stores.
String formatKg(num kg) {
  final rounded = (kg * 100).round() / 100;
  return rounded % 1 == 0 ? '${rounded.toInt()}' : '$rounded';
}

String _text(Object? value) => switch (value) {
  null => '',
  num() => formatKg(value),
  String() => value.trim(),
  _ => '',
};

/// One set in the workout draft. Load, reps and effort are kept as the text
/// the athlete entered; the server parses them on sync.
class WorkoutSetDraft {
  WorkoutSetDraft({
    this.load = '',
    this.reps = '',
    this.rpe = '',
    this.completed = false,
  });

  factory WorkoutSetDraft.fromMap(Map<String, dynamic> map) => WorkoutSetDraft(
    load: _text(map['load_kg']),
    reps: _text(map['repetitions']),
    rpe: _text(map['rpe']),
    completed: map['completed'] == true,
  );

  String load;
  String reps;

  /// The set's effort (RPE), a whole number from 1 to 10, or blank.
  String rpe;
  bool completed;

  /// The athlete changed the load on this screen. An emptied load then stays
  /// empty (no added weight) instead of showing a suggestion again.
  bool loadEdited = false;

  num? get loadKg => num.tryParse(load);
  int? get repetitions => num.tryParse(reps)?.toInt();
  int? get rpeValue => num.tryParse(rpe)?.round();

  LoggedSet get logged =>
      LoggedSet(completed: completed, loadKg: loadKg, repetitions: repetitions);

  Map<String, dynamic> toMap() => {
    'load_kg': load,
    'repetitions': reps,
    'rpe': rpe,
    'completed': completed,
  };
}

/// One planned exercise and the sets logged against it.
class ExerciseDraft {
  ExerciseDraft(this.exercise)
    : sets = [for (var i = 0; i < exercise.setCount; i++) WorkoutSetDraft()];

  final PlannedExercise exercise;
  final List<WorkoutSetDraft> sets;

  /// `unknown`, `performed` or `skipped`, as the sync RPC accepts.
  String status = 'unknown';
  bool pain = false;

  bool get skipped => status == 'skipped';

  int get completedCount => sets.where((set) => set.completed).length;

  /// The first set not yet done, or null when every set is done.
  int? get currentSetIndex {
    final index = sets.indexWhere((set) => !set.completed);
    return index < 0 ? null : index;
  }

  /// The logged load is machine help, not weight lifted.
  bool get assisted =>
      isAssistedExercise(slug: exercise.exerciseSlug, name: exercise.name);

  List<LoggedSet> get logged => [for (final set in sets) set.logged];

  LoggedExercise get loggedExercise =>
      LoggedExercise(sets: logged, assisted: assisted);

  /// The sets that are new bests against [history] (see
  /// [newBestSetIndexes]). Empty when the history is unknown.
  Set<int> newBests(ExerciseHistory? history) =>
      newBestSetIndexes(history: history, sets: logged);

  /// Reads the exercise from a saved draft or a server session.
  void restore(Map<String, dynamic> map) {
    status = map['status'] as String? ?? 'unknown';
    pain = map['pain_flag'] == true;
    final rows = map['sets'] as List? ?? const [];
    for (var i = 0; i < rows.length && i < sets.length; i++) {
      final row = rows[i];
      if (row is Map) {
        sets[i] = WorkoutSetDraft.fromMap(Map<String, dynamic>.from(row));
      }
    }
  }
}

/// Where the starting kg and reps of a set came from.
enum SetSuggestionSource {
  /// The athlete entered both on this set.
  entered,

  /// The set done before it in this workout.
  earlierSet,

  /// The same set in the last session with this exercise.
  lastTime,

  /// The approved plan's starting load and lowest rep target.
  plan,
}

/// The kg and reps a set starts from before the athlete confirms it.
class SetSuggestion {
  const SetSuggestion({
    required this.load,
    required this.reps,
    required this.source,
  });

  final String load;
  final String reps;
  final SetSuggestionSource source;
}

/// The set of the last session that matches set [index] by number, else
/// that session's last set; null without one.
HistorySet? lastTimeSet(ExerciseHistory? history, int index) {
  final sets = history?.lastSession?.sets ?? const <HistorySet>[];
  if (sets.isEmpty) return null;
  for (final set in sets) {
    if (set.setNumber == index + 1) return set;
  }
  return sets.last;
}

/// The starting values for set [index] of [draft]: what the athlete entered,
/// else the set done before it in this workout, else last time, else the
/// plan. The athlete confirms them by finishing the set.
SetSuggestion suggestSet(
  ExerciseDraft draft,
  int index,
  ExerciseHistory? history,
) {
  final set = draft.sets[index];
  WorkoutSetDraft? earlier;
  for (var i = index - 1; i >= 0; i--) {
    if (draft.sets[i].completed) {
      earlier = draft.sets[i];
      break;
    }
  }
  final last = lastTimeSet(history, index);
  final String load;
  final String reps;
  final SetSuggestionSource source;
  if (earlier != null) {
    (load, reps, source) = (
      earlier.load,
      earlier.reps,
      SetSuggestionSource.earlierSet,
    );
  } else if (last != null && last.repetitions != null) {
    (load, reps, source) = (
      _text(last.loadKg),
      '${last.repetitions}',
      SetSuggestionSource.lastTime,
    );
  } else {
    (load, reps, source) = (
      _text(draft.exercise.targetLoadKg),
      draft.exercise.repMin > 0 ? '${draft.exercise.repMin}' : '',
      SetSuggestionSource.plan,
    );
  }
  final ownLoad = set.load.isNotEmpty || set.loadEdited;
  final ownReps = set.reps.isNotEmpty;
  return SetSuggestion(
    load: ownLoad ? set.load : load,
    reps: ownReps ? set.reps : reps,
    source: ownLoad && ownReps ? SetSuggestionSource.entered : source,
  );
}

/// "60 kg × 8", "8 reps", or "20 kg help × 8" for an assisted exercise.
String describeSet({
  required num? loadKg,
  required int? repetitions,
  bool assisted = false,
}) {
  final reps = repetitions;
  final load = loadKg;
  if (reps == null) {
    return load == null ? '' : '${formatKg(load)} kg';
  }
  if (assisted && load != null) {
    return load == 0
        ? 'Unassisted × $reps'
        : '${formatKg(load)} kg help × $reps';
  }
  if (load != null && load > 0) return '${formatKg(load)} kg × $reps';
  return reps == 1 ? '1 rep' : '$reps reps';
}

/// The best set in the history, as it reads on the strip; null without one.
String? describeBest(ExerciseBestSet? best) {
  if (best == null || best.repetitions == null) return null;
  return describeSet(
    loadKg: best.kind == ExerciseHistoryKind.reps ? null : best.loadKg,
    repetitions: best.repetitions,
    assisted: best.kind == ExerciseHistoryKind.assistance,
  );
}
