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

/// Who recorded a set's times (`timing_source`).
enum SetTimingSource {
  app,
  watch;

  static SetTimingSource? parse(Object? value) => switch (value) {
    'app' => app,
    'watch' => watch,
    _ => null,
  };
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

int? _whole(Object? value, int max) =>
    value is num && value == value.roundToDouble() && value >= 0 && value <= max
    ? value.toInt()
    : null;

/// One set in the workout draft. Load, reps and effort are kept as the text
/// the athlete entered; the server parses them on sync.
class WorkoutSetDraft {
  WorkoutSetDraft({
    this.load = '',
    this.reps = '',
    this.rpe = '',
    this.completed = false,
    DateTime? startedAt,
    DateTime? completedAt,
    int? restBeforeSeconds,
    int? rir,
    SetTimingSource? timingSource,
  }) : _startedAt = startedAt,
       _completedAt = completedAt,
       _restBeforeSeconds = restBeforeSeconds,
       _rir = rir,
       _timingSource = timingSource;

  /// A set read from a saved draft or a server session. It knows only the
  /// Contract 2 keys [map] holds with a readable value; a draft saved by an
  /// older build holds none, and its set leaves the server's values alone.
  factory WorkoutSetDraft.fromMap(Map<String, dynamic> map) {
    final set = WorkoutSetDraft(
      load: _text(map['load_kg']),
      reps: _text(map['repetitions']),
      rpe: _text(map['rpe']),
      completed: map['completed'] == true,
      startedAt: _time(map['started_at']),
      completedAt: _time(map['completed_at']),
      restBeforeSeconds: _whole(map['rest_before_seconds'], 3600),
      rir: _whole(map['rir'], maxRir),
      timingSource: SetTimingSource.parse(map['timing_source']),
    );
    final read = {
      _startedKey: set.startedAt,
      _completedKey: set.completedAt,
      _restKey: set.restBeforeSeconds,
      _rirKey: set.rir,
      _sourceKey: set.timingSource,
    };
    set._known.retainWhere(
      (key) => map.containsKey(key) && (map[key] == null || read[key] != null),
    );
    return set;
  }

  /// The highest reps in reserve stored; it means "5 or more".
  static const maxRir = 5;

  static const _startedKey = 'started_at';
  static const _completedKey = 'completed_at';
  static const _restKey = 'rest_before_seconds';
  static const _rirKey = 'rir';
  static const _sourceKey = 'timing_source';

  /// The Contract 2 keys this set holds the truth for, so [toMap] sends
  /// them, null included. A new set knows all five; a set read from a map
  /// knows the ones the map held, and learns each one the athlete's
  /// logging sets (tick, undo, reps left, a re-measured rest).
  final Set<String> _known = {
    _startedKey,
    _completedKey,
    _restKey,
    _rirKey,
    _sourceKey,
  };

  String load;
  String reps;

  /// The set's effort (RPE), a whole number from 1 to 10, or blank. The app
  /// now asks for [rir] and writes the RPE the same answer meant before
  /// (10 − reps left); older sets may have only this.
  String rpe;
  bool completed;

  /// When the set began and when it was ticked (Contract 2).
  DateTime? get startedAt => _startedAt;
  DateTime? _startedAt;
  set startedAt(DateTime? value) {
    _startedAt = value;
    _known.add(_startedKey);
  }

  DateTime? get completedAt => _completedAt;
  DateTime? _completedAt;
  set completedAt(DateTime? value) {
    _completedAt = value;
    _known.add(_completedKey);
  }

  /// The rest actually taken before this set, in seconds.
  int? get restBeforeSeconds => _restBeforeSeconds;
  int? _restBeforeSeconds;
  set restBeforeSeconds(int? value) {
    _restBeforeSeconds = value;
    _known.add(_restKey);
  }

  /// Reps in reserve, 0 to [maxRir]. Set it with [setRir].
  int? get rir => _rir;
  int? _rir;

  SetTimingSource? get timingSource => _timingSource;
  SetTimingSource? _timingSource;
  set timingSource(SetTimingSource? value) {
    _timingSource = value;
    _known.add(_sourceKey);
  }

  /// The reps left as the set reads: [rir], else what an older set's RPE
  /// meant (10 − RPE, 5 or more below RPE 5). Shown only; nothing derived
  /// is sent.
  int? get shownRir {
    final reserve = rir;
    if (reserve != null) return reserve;
    final effort = num.tryParse(rpe);
    return effort == null ? null : (10 - effort).round().clamp(0, maxRir);
  }

  /// Nothing was entered or done on this set.
  bool get isUntouched =>
      !completed && load.isEmpty && reps.isEmpty && rpe.isEmpty && !loadEdited;

  /// The athlete changed the load on this screen. An emptied load then stays
  /// empty (no added weight) instead of showing a suggestion again.
  bool loadEdited = false;

  num? get loadKg => num.tryParse(load);
  int? get repetitions => num.tryParse(reps)?.toInt();

  /// Sets or clears the reps left, with the matching RPE.
  void setRir(int? value) {
    _rir = value;
    _known.add(_rirKey);
    rpe = value == null ? '' : '${10 - value}';
  }

  LoggedSet get logged =>
      LoggedSet(completed: completed, loadKg: loadKg, repetitions: repetitions);

  /// The set as the draft holds it. Only the Contract 2 keys this set knows
  /// are included (a missing key keeps the server's value; a null clears
  /// it). A time before [notBefore] is left out too, so the server keeps
  /// what it has: it refuses times from before the session it holds began
  /// (a workout started offline), and one refused time would hold back the
  /// whole draft. Without [timing] the five Contract 2 keys (times, rest,
  /// reps left, source) are all left out: the server refused this phone's
  /// times, and the reps left still reach it as the matching RPE.
  Map<String, dynamic> toMap({DateTime? notBefore, bool timing = true}) {
    bool sendable(DateTime? time) =>
        notBefore == null || time == null || !time.isBefore(notBefore);
    return {
      'load_kg': load,
      'repetitions': reps,
      'rpe': rpe,
      'completed': completed,
      if (timing) ..._timingMap(sendable),
    };
  }

  Map<String, dynamic> _timingMap(bool Function(DateTime?) sendable) {
    final start = startedAt;
    final end = completedAt;
    bool knows(String key) => _known.contains(key);
    return {
      if (sendable(start)) ...{
        if (knows(_startedKey)) _startedKey: start?.toUtc().toIso8601String(),
        if (knows(_restKey)) _restKey: restBeforeSeconds,
      },
      if (sendable(end) && knows(_completedKey))
        _completedKey: end?.toUtc().toIso8601String(),
      if (knows(_rirKey)) _rirKey: rir,
      if (knows(_sourceKey)) _sourceKey: timingSource?.name,
    };
  }
}

/// One planned exercise and the sets logged against it.
class ExerciseDraft {
  ExerciseDraft(this.exercise)
    : sets = [for (var i = 0; i < exercise.setCount; i++) WorkoutSetDraft()];

  /// The exercise the athlete is logging. It is the plan's, unless the
  /// server's row says it was swapped for a gentler one for a sore joint (the
  /// row's `performed_name` is then the swap's), or the athlete swapped it
  /// during the workout.
  PlannedExercise exercise;
  final List<WorkoutSetDraft> sets;

  /// `unknown`, `performed` or `skipped`, as the sync RPC accepts.
  String status = 'unknown';
  bool pain = false;

  /// The server's id for this exercise's performance, once its row has been
  /// read; a pain report can name it.
  String? performanceId;

  /// The athlete swapped this exercise during the workout and the server has
  /// not confirmed it yet: a server row that still says "prescribed" must not
  /// undo it.
  bool swapPending = false;

  /// The exercise was left out today for a sore joint: the server made no
  /// set rows for it, so nothing is logged against it and nothing is sent.
  bool get leftOut => sets.isEmpty;

  /// A set has something on it: it is never dropped or relabelled.
  bool get hasEntries => sets.any((set) => !set.isUntouched);

  /// The swap this exercise is logged as, when it is one: the keys the sync
  /// RPC reads to record a substituted performance (reason `pain`).
  Map<String, Object> get swapFields => exercise.swappedFrom == null
      ? const {}
      : {
          'performance_kind': 'substituted',
          'performed_name': exercise.name,
          'substitution_reason': 'pain',
        };

  /// Swaps this exercise for [name] (catalog [slug]) during the workout. The
  /// swap carries no starting load. Only before any set has an entry.
  bool swapForPain({required String name, String? slug}) {
    if (hasEntries) return false;
    exercise = exercise.swappedTo(name: name, slug: slug);
    swapPending = true;
    return true;
  }

  /// Takes the exercise's identity from a server row: `performance_kind` and
  /// `performed_name`. A substituted row shows and logs the swap's name; a
  /// prescribed one shows the plan's. A swap the athlete made that the server
  /// has not confirmed yet ([swapPending]) is kept over a row that does not
  /// say it.
  ///
  /// Returns true for a conflict: the row names the exercise differently
  /// while sets with entries are already logged against this name. Nothing is
  /// renamed then (entries are never relabelled or dropped); the sync needs
  /// attention instead.
  bool takeIdentity(Map<dynamic, dynamic> row) {
    final id = row['performance_id'];
    if (id is String) performanceId = id;
    final kind = row['performance_kind'];
    final name = row['performed_name'];
    if (kind == 'substituted' && name is String && name.trim().isNotEmpty) {
      if (exercise.name == name) {
        swapPending = false;
        return false;
      }
      if (swapPending) return false;
      if (hasEntries) return true;
      final slug = row['exercise_slug'];
      exercise = exercise.asPlanned.swappedTo(
        name: name,
        slug: slug is String ? slug : null,
      );
      return false;
    }
    if (kind == 'prescribed' && exercise.swappedFrom != null && !swapPending) {
      if (hasEntries) return true;
      exercise = exercise.asPlanned;
    }
    return false;
  }

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

  /// Gives the exercise [count] sets, the number of set rows the server holds
  /// for it. The server's `start_workout` decides that number (it applies the
  /// athlete's accepted same-day answer), so the phone follows it: untouched
  /// sets at the end go, missing ones are added. A set that already has
  /// something on it is never dropped.
  void alignTo(int count) {
    while (sets.length > count && sets.last.isUntouched) {
      sets.removeLast();
    }
    while (sets.length < count) {
      sets.add(WorkoutSetDraft());
    }
  }

  /// Reads the exercise from a saved draft or a server session.
  void restore(Map<String, dynamic> map) {
    status = map['status'] as String? ?? 'unknown';
    pain = map['pain_flag'] == true;
    swapPending = false;
    takeIdentity(map);
    // A swap that was made on this phone and not confirmed yet stays pending
    // until a server row says it.
    swapPending = map['swap_pending'] == true && exercise.swappedFrom != null;
    // A list of no rows is an exercise left out today: it has no sets.
    final rows = map['sets'];
    if (rows is! List) return;
    alignTo(rows.length);
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

  /// The next-session target worked out from the sets logged last time.
  nextTarget,

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
/// else the set done before it in this workout, else the next target worked
/// out from last time's sets, else last time, else the plan. The athlete confirms them by finishing the set.
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
  } else if (draft.exercise.nextTarget != null) {
    final target = draft.exercise.nextTarget!;
    (load, reps, source) = (
      _text(target.loadKg),
      '${target.reps}',
      SetSuggestionSource.nextTarget,
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
