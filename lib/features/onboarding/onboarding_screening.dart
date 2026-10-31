/// The result of the pre-plan health check (Contract 8 of the coaching platform). The server
/// works it out from the four answers; the app only shows what it returns.
enum ScreeningOutcome {
  /// Nothing to hold the plan back.
  cleared('cleared'),

  /// The plan stays at moderate effort until a professional clears the athlete.
  moderateUntilCleared('moderate_until_cleared'),

  /// No plan is built until a health professional has cleared the athlete.
  seeProfessional('see_professional');

  const ScreeningOutcome(this.wire);

  final String wire;

  /// Null for a value this build does not know.
  static ScreeningOutcome? fromWire(Object? value) {
    for (final outcome in values) {
      if (outcome.wire == value) return outcome;
    }
    return null;
  }
}

/// The four answers, in the keys the draft and `record_screening_v1` read.
class ScreeningAnswers {
  const ScreeningAnswers({
    required this.exercisesRegularly,
    required this.knownCondition,
    required this.symptoms,
    required this.clearedByProfessional,
  });

  final bool exercisesRegularly;

  /// A known heart, metabolic or kidney condition.
  final bool knownCondition;

  /// A current sign or symptom.
  final bool symptoms;

  /// False when the question was not asked.
  final bool clearedByProfessional;

  Map<String, dynamic> toJson() => {
    'exercises_regularly': exercisesRegularly,
    'known_disease': knownCondition,
    'symptoms': symptoms,
    'cleared_by_professional': clearedByProfessional,
  };

  @override
  bool operator ==(Object other) =>
      other is ScreeningAnswers &&
      other.exercisesRegularly == exercisesRegularly &&
      other.knownCondition == knownCondition &&
      other.symptoms == symptoms &&
      other.clearedByProfessional == clearedByProfessional;

  @override
  int get hashCode => Object.hash(
    exercisesRegularly,
    knownCondition,
    symptoms,
    clearedByProfessional,
  );

  /// The clearance question is asked only with a known condition and no
  /// current symptom; with a symptom the outcome is already settled.
  static bool asksClearance({bool? knownCondition, bool? symptoms}) =>
      knownCondition == true && symptoms == false;

  /// The answers once every question shown has been answered; null before.
  static ScreeningAnswers? fromChoices({
    bool? exercisesRegularly,
    bool? knownCondition,
    bool? symptoms,
    bool? clearedByProfessional,
  }) {
    if (exercisesRegularly == null ||
        knownCondition == null ||
        symptoms == null) {
      return null;
    }
    final asked = asksClearance(
      knownCondition: knownCondition,
      symptoms: symptoms,
    );
    if (asked && clearedByProfessional == null) return null;
    return ScreeningAnswers(
      exercisesRegularly: exercisesRegularly,
      knownCondition: knownCondition,
      symptoms: symptoms,
      clearedByProfessional: asked && clearedByProfessional == true,
    );
  }

  /// The answers saved in a draft, or null when the draft has none (an older
  /// build) or they are incomplete.
  static ScreeningAnswers? fromJson(Object? json) {
    if (json is! Map) return null;
    final exercises = json['exercises_regularly'];
    final condition = json['known_disease'];
    final symptoms = json['symptoms'];
    final cleared = json['cleared_by_professional'] ?? false;
    if (exercises is! bool ||
        condition is! bool ||
        symptoms is! bool ||
        cleared is! bool) {
      return null;
    }
    return ScreeningAnswers(
      exercisesRegularly: exercises,
      knownCondition: condition,
      symptoms: symptoms,
      clearedByProfessional: cleared,
    );
  }
}

/// What `record_screening_v1` answers.
class ScreeningRecord {
  const ScreeningRecord({required this.outcome, required this.screenedAt});

  final ScreeningOutcome outcome;
  final DateTime screenedAt;

  /// Throws a [FormatException] for an answer this build cannot read.
  factory ScreeningRecord.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('The screening answer is not an object.');
    }
    final outcome = ScreeningOutcome.fromWire(json['outcome']);
    final screenedAt = DateTime.tryParse('${json['screened_at']}');
    if (outcome == null || screenedAt == null) {
      throw const FormatException('The screening answer is not readable.');
    }
    return ScreeningRecord(outcome: outcome, screenedAt: screenedAt);
  }
}

/// What `get_my_screening_v1` answers: the athlete's current screening on the
/// server, which may be newer than the draft (the athlete went back and
/// answered again).
class StoredScreening {
  const StoredScreening({required this.outcome, required this.answers});

  final ScreeningOutcome outcome;

  /// Null when the athlete was never screened.
  final ScreeningAnswers? answers;

  /// Throws a [FormatException] for an answer this build cannot read.
  factory StoredScreening.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('The screening answer is not an object.');
    }
    final outcome = ScreeningOutcome.fromWire(json['outcome']);
    if (outcome == null) {
      throw const FormatException('The screening answer is not readable.');
    }
    return StoredScreening(
      outcome: outcome,
      answers: json['screened'] == true
          ? ScreeningAnswers.fromJson(json)
          : null,
    );
  }
}
