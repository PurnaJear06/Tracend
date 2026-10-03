/// Typed reading of `get_my_exercise_history` 1.0. Every field is optional on
/// the way in: a missing or mistyped value reads as unknown, never as zero.
library;

/// How sets of an exercise are ranked (ALGORITHMS §4, DATA_MODEL).
enum ExerciseHistoryKind {
  /// Heavier wins, then more reps.
  load,

  /// Bodyweight: more reps wins.
  reps,

  /// Machine help: less assistance wins, 0 is unassisted, then more reps.
  assistance;

  static ExerciseHistoryKind? parse(Object? value) => switch (value) {
    'load' => load,
    'reps' => reps,
    'assistance' => assistance,
    _ => null,
  };
}

num? _num(Object? value) => value is num ? value : null;
int? _int(Object? value) => value is num ? value.toInt() : null;
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;
List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map) Map<String, dynamic>.from(item),
      ]
    : const [];

/// One set of the last session.
class HistorySet {
  const HistorySet({this.setNumber, this.loadKg, this.repetitions, this.rpe});

  factory HistorySet.fromJson(Map<String, dynamic> json) => HistorySet(
    setNumber: _int(json['set_number']),
    loadKg: _num(json['load_kg']),
    repetitions: _int(json['repetitions']),
    rpe: _num(json['rpe']),
  );

  final int? setNumber;
  final num? loadKg;
  final int? repetitions;
  final num? rpe;
}

/// The most recent completed session with this exercise.
class ExerciseLastSession {
  const ExerciseLastSession({
    this.sessionId,
    this.localDate,
    this.sets = const [],
  });

  factory ExerciseLastSession.fromJson(Map<String, dynamic> json) =>
      ExerciseLastSession(
        sessionId: json['session_id'] as String?,
        localDate: _date(json['local_date']),
        sets: [for (final set in _maps(json['sets'])) HistorySet.fromJson(set)],
      );

  final String? sessionId;
  final DateTime? localDate;
  final List<HistorySet> sets;
}

/// The strongest set ever logged, by the kind's rule.
class ExerciseBestSet {
  const ExerciseBestSet({
    required this.kind,
    this.loadKg,
    this.repetitions,
    this.localDate,
  });

  /// Null when the kind is unreadable: an unrankable best is no best.
  static ExerciseBestSet? fromJson(
    Map<String, dynamic> json,
    ExerciseHistoryKind? fallbackKind,
  ) {
    final kind = ExerciseHistoryKind.parse(json['kind']) ?? fallbackKind;
    if (kind == null) return null;
    return ExerciseBestSet(
      kind: kind,
      loadKg: _num(json['load_kg']),
      repetitions: _int(json['repetitions']),
      localDate: _date(json['local_date']),
    );
  }

  final ExerciseHistoryKind kind;
  final num? loadKg;
  final int? repetitions;
  final DateTime? localDate;
}

/// The best set of one completed session.
class ExerciseTopSet {
  const ExerciseTopSet({this.localDate, this.loadKg, this.repetitions});

  factory ExerciseTopSet.fromJson(Map<String, dynamic> json) => ExerciseTopSet(
    localDate: _date(json['local_date']),
    loadKg: _num(json['load_kg']),
    repetitions: _int(json['repetitions']),
  );

  final DateTime? localDate;
  final num? loadKg;
  final int? repetitions;
}

/// History for one requested key (a catalog slug or an exercise name).
class ExerciseHistory {
  const ExerciseHistory({
    required this.key,
    this.kind,
    this.lastSession,
    this.bestSet,
    this.topSets = const [],
  });

  /// Null without a string key: the entry cannot be matched to an exercise.
  static ExerciseHistory? fromJson(Map<String, dynamic> json) {
    final key = json['key'];
    if (key is! String || key.isEmpty) return null;
    final kind = ExerciseHistoryKind.parse(json['kind']);
    final last = _map(json['last_session']);
    final best = _map(json['best_set']);
    return ExerciseHistory(
      key: key,
      kind: kind,
      lastSession: last == null ? null : ExerciseLastSession.fromJson(last),
      bestSet: best == null ? null : ExerciseBestSet.fromJson(best, kind),
      topSets: [
        for (final top in _maps(json['top_sets'])) ExerciseTopSet.fromJson(top),
      ],
    );
  }

  final String key;
  final ExerciseHistoryKind? kind;
  final ExerciseLastSession? lastSession;
  final ExerciseBestSet? bestSet;

  /// The best set of each recent session, newest first.
  final List<ExerciseTopSet> topSets;

  /// Never logged before: the logging screen says "First log".
  bool get isFirstLog => lastSession == null && bestSet == null;
}

/// A `get_my_exercise_history` answer, from the server or this device's copy.
class ExerciseHistoryResult {
  const ExerciseHistoryResult({
    required this.exercises,
    this.fromCache = false,
  });

  /// Parses a response body; entries that cannot be read are left out.
  factory ExerciseHistoryResult.fromJson(
    Object? json, {
    bool fromCache = false,
  }) {
    final exercises = <String, ExerciseHistory>{};
    for (final row in _maps(_map(json)?['exercises'])) {
      final history = ExerciseHistory.fromJson(row);
      if (history != null) exercises[history.key] = history;
    }
    return ExerciseHistoryResult(exercises: exercises, fromCache: fromCache);
  }

  final Map<String, ExerciseHistory> exercises;

  /// True when the server could not be reached and this is the saved copy.
  final bool fromCache;

  /// Null when the key's history is unknown (offline with no saved copy):
  /// neither "First log" nor a new best can be said then.
  ExerciseHistory? operator [](String key) => exercises[key.trim()];
}
