import 'package:flutter/foundation.dart';
import 'package:tracend/features/train/workout_repository.dart';

/// What today's session can be eased by (decision D6, Contract 5).
enum DayAdjustmentKind {
  holdLoad('hold_load'),
  reduceSets('reduce_sets'),
  swapToEasyCardio('swap_to_easy_cardio');

  const DayAdjustmentKind(this.wire);
  final String wire;

  static DayAdjustmentKind? fromWire(Object? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

/// Where the answer to today's adjustment stands. `none` means the rules ask
/// for nothing; `proposed` waits for the athlete.
enum DayAdjustmentStatus {
  none,
  proposed,
  accepted,
  declined;

  static DayAdjustmentStatus? fromWire(Object? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

/// Which way the day reads: from the check-in first, then sleep and recovery.
enum DayBand {
  green,
  amber,
  red,
  unknown;

  static DayBand? fromWire(Object? value) {
    for (final band in values) {
      if (band.name == value) return band;
    }
    return null;
  }
}

/// One exercise of today's session as the adjustment changes it.
@immutable
class DayAdjustmentChange {
  const DayAdjustmentChange({
    required this.exerciseOrder,
    required this.name,
    required this.setsFrom,
    required this.setsTo,
    this.loadNote,
    this.loadKgFrom,
    this.loadKgTo,
    this.repsFrom,
    this.repsTo,
    this.rpeTo,
  });

  final int exerciseOrder;
  final String name;
  final int setsFrom;
  final int setsTo;

  /// "Keep last time's 60 kg"; null when the load is unchanged.
  final String? loadNote;
  final num? loadKgFrom;
  final num? loadKgTo;
  final int? repsFrom;
  final int? repsTo;
  final num? rpeTo;

  static DayAdjustmentChange? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final order = raw['exercise_order'];
    final name = raw['name'];
    final from = raw['sets_from'];
    final to = raw['sets_to'];
    if (order is! num || name is! String || from is! num || to is! num) {
      return null;
    }
    num? number(String key) => raw[key] is num ? raw[key] as num : null;
    return DayAdjustmentChange(
      exerciseOrder: order.toInt(),
      name: name,
      setsFrom: from.toInt(),
      setsTo: to.toInt(),
      loadNote: raw['load_note'] as String?,
      loadKgFrom: number('load_kg_from'),
      loadKgTo: number('load_kg_to'),
      repsFrom: number('reps_from')?.toInt(),
      repsTo: number('reps_to')?.toInt(),
      rpeTo: number('rpe_to'),
    );
  }
}

/// The easy-cardio dose of a swap day.
@immutable
class DayAdjustmentCardio {
  const DayAdjustmentCardio({
    required this.minutesMin,
    required this.minutesMax,
  });

  final int minutesMin;
  final int minutesMax;

  static DayAdjustmentCardio? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final low = raw['minutes_min'];
    final high = raw['minutes_max'];
    if (low is! num || high is! num) return null;
    return DayAdjustmentCardio(
      minutesMin: low.toInt(),
      minutesMax: high.toInt(),
    );
  }
}

/// One kind the athlete may choose today, with what it would change.
@immutable
class DayAdjustmentOption {
  const DayAdjustmentOption({
    required this.kind,
    required this.explanation,
    required this.setsTotalTo,
    required this.changes,
    this.cardio,
  });

  final DayAdjustmentKind kind;
  final String explanation;
  final int setsTotalTo;
  final List<DayAdjustmentChange> changes;
  final DayAdjustmentCardio? cardio;

  static DayAdjustmentOption? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kind = DayAdjustmentKind.fromWire(raw['kind']);
    final explanation = raw['explanation'];
    final total = raw['sets_total_to'];
    if (kind == null || explanation is! String || total is! num) return null;
    return DayAdjustmentOption(
      kind: kind,
      explanation: explanation,
      setsTotalTo: total.toInt(),
      changes: _changes(raw['changes']),
      cardio: DayAdjustmentCardio.tryParse(raw['cardio']),
    );
  }
}

/// The values behind the band that are not the check-in: what the recovery
/// score and last night's sleep say. Any may be null; none is invented.
@immutable
class DaySignals {
  const DaySignals({
    this.recoveryScore,
    this.recoveryConfidence,
    this.recoveryMode,
    this.recoveryLow = false,
    this.sleepMinutes,
  });

  final int? recoveryScore;
  final String? recoveryConfidence;
  final String? recoveryMode;
  final bool recoveryLow;
  final int? sleepMinutes;

  static DaySignals parse(Object? raw) {
    if (raw is! Map) return const DaySignals();
    return DaySignals(
      recoveryScore: (raw['recovery_score'] as num?)?.toInt(),
      recoveryConfidence: raw['recovery_confidence'] as String?,
      recoveryMode: raw['recovery_mode'] as String?,
      recoveryLow: raw['recovery_low'] == true,
      sleepMinutes: (raw['sleep_minutes'] as num?)?.toInt(),
    );
  }
}

/// An earlier answer today that the rules no longer stand behind: `reason` is
/// `check_in` (a different check-in) or `new_data` (sleep or scores that
/// arrived after the answer).
@immutable
class PreviousDayAnswer {
  const PreviousDayAnswer({
    required this.kind,
    required this.status,
    required this.reason,
  });

  final DayAdjustmentKind? kind;
  final DayAdjustmentStatus? status;
  final String? reason;

  static PreviousDayAnswer? tryParse(Object? raw) {
    if (raw is! Map) return null;
    return PreviousDayAnswer(
      kind: DayAdjustmentKind.fromWire(raw['kind']),
      status: DayAdjustmentStatus.fromWire(raw['status']),
      reason: raw['reason'] as String?,
    );
  }
}

List<DayAdjustmentChange> _changes(Object? raw) => [
  for (final item in raw is List ? raw : const [])
    ?DayAdjustmentChange.tryParse(item),
];

/// Today's same-day readiness adjustment (`get_my_day_adjustment_v1`, 1.x).
/// An overlay for one day: it never changes the plan.
@immutable
class DayAdjustment {
  const DayAdjustment({
    required this.localDate,
    required this.band,
    required this.triggers,
    required this.kind,
    required this.changes,
    required this.explanation,
    required this.status,
    required this.available,
    required this.unavailableReason,
    required this.safetyRoute,
    required this.confidence,
    required this.missing,
    required this.cardio,
    required this.plannedWorkoutId,
    required this.workoutName,
    required this.setsTotalFrom,
    required this.setsTotalTo,
    required this.previousAnswer,
    required this.answeredAt,
    required this.origin,
    required this.options,
    required this.signals,
  });

  /// "2026-10-24": the day the server answered for.
  final String localDate;
  final DayBand band;
  final List<String> triggers;

  /// What the answer or the proposal is; null when the rules ask for nothing.
  final DayAdjustmentKind? kind;
  final List<DayAdjustmentChange> changes;
  final String explanation;
  final DayAdjustmentStatus status;
  final bool available;

  /// Why today cannot be adjusted: `no_plan`, `rest_day`, `session_started`,
  /// `session_done`, `coach_adjusted`, or a reason this build does not know.
  final String? unavailableReason;

  /// Set on a day the athlete is sent to a professional instead (`pain_referral`
  /// today). A route this build does not know is still a route.
  final String? safetyRoute;
  final String? confidence;
  final List<String> missing;
  final DayAdjustmentCardio? cardio;
  final String? plannedWorkoutId;
  final String? workoutName;
  final int setsTotalFrom;
  final int setsTotalTo;
  final PreviousDayAnswer? previousAnswer;
  final DateTime? answeredAt;

  /// `proposed` (the kind the rules computed) or `chosen` (the athlete's own
  /// pick); null before an answer.
  final String? origin;
  final List<DayAdjustmentOption> options;
  final DaySignals signals;

  /// Null when [raw] is not an object this build can read: another major
  /// version, or a missing key. Nothing is shown or applied from it.
  static DayAdjustment? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final version = raw['schema_version'];
    if (version is! String || !version.startsWith('1.')) return null;
    final date = raw['local_date'];
    final band = DayBand.fromWire(raw['band']);
    final status = DayAdjustmentStatus.fromWire(raw['status']);
    final explanation = raw['explanation'];
    final from = raw['sets_total_from'];
    final to = raw['sets_total_to'];
    final kindWire = raw['kind'];
    final kind = DayAdjustmentKind.fromWire(kindWire);
    if (date is! String ||
        DateTime.tryParse(date) == null ||
        band == null ||
        status == null ||
        explanation is! String ||
        from is! num ||
        to is! num ||
        raw['available'] is! bool ||
        (kindWire != 'none' && kind == null)) {
      return null;
    }
    List<String> strings(Object? list) => [
      for (final item in list is List ? list : const [])
        if (item is String) item,
    ];
    return DayAdjustment(
      localDate: date,
      band: band,
      triggers: strings(raw['triggers']),
      kind: kind,
      changes: _changes(raw['changes']),
      explanation: explanation,
      status: status,
      available: raw['available'] as bool,
      unavailableReason: raw['unavailable_reason'] as String?,
      safetyRoute: raw['safety_route'] as String?,
      confidence: raw['confidence'] as String?,
      missing: strings(raw['missing']),
      cardio: DayAdjustmentCardio.tryParse(raw['cardio']),
      plannedWorkoutId: raw['planned_workout_id'] as String?,
      workoutName: raw['workout_name'] as String?,
      setsTotalFrom: from.toInt(),
      setsTotalTo: to.toInt(),
      previousAnswer: PreviousDayAnswer.tryParse(raw['previous_answer']),
      answeredAt: DateTime.tryParse('${raw['answered_at'] ?? ''}'),
      origin: raw['origin'] as String?,
      options: [
        for (final item
            in raw['options'] is List ? raw['options'] as List : const [])
          ?DayAdjustmentOption.tryParse(item),
      ],
      signals: DaySignals.parse(raw['signals']),
    );
  }

  bool get hasSafetyRoute => safetyRoute != null;

  bool get isAnswered =>
      status == DayAdjustmentStatus.accepted ||
      status == DayAdjustmentStatus.declined;

  bool get isAccepted => status == DayAdjustmentStatus.accepted;

  /// The session has started or is done: an answer can no longer be changed.
  bool get sessionBegun =>
      unavailableReason == 'session_started' ||
      unavailableReason == 'session_done';

  /// The kind of the accepted answer standing for today: set only for an
  /// answer the rules still back, whose stored changes this payload carries.
  /// Null on a day with a safety route.
  ///
  /// An earlier accepted answer that no longer stands is not here: the server
  /// keeps it in force and `start_workout` applies it, but `previous_answer`
  /// carries no changes, so the app says it in words only and shows no sets
  /// or weights for it. The logger follows the rows the server made.
  DayAdjustmentKind? get appliedKind =>
      hasSafetyRoute || !isAccepted ? null : kind;

  /// What the standing accepted answer changes; empty otherwise.
  List<DayAdjustmentChange> get appliedChanges =>
      appliedKind == null ? const [] : changes;

  /// An accepted answer made today's strength session lighter (an easy-cardio
  /// answer leaves the plan's sets as they are).
  bool get easesSession =>
      appliedChanges.isNotEmpty &&
      (appliedKind == DayAdjustmentKind.holdLoad ||
          appliedKind == DayAdjustmentKind.reduceSets);

  /// The option for [wanted], when the server offers it today.
  DayAdjustmentOption? optionFor(DayAdjustmentKind wanted) {
    for (final option in options) {
      if (option.kind == wanted) return option;
    }
    return null;
  }

  /// [workout] as today's accepted answer leaves it: fewer sets and the last
  /// loads held. Anything else is returned as it is, including a workout this
  /// answer is not about.
  ///
  /// With [sets] false the set counts stay the plan's and only the held loads
  /// and effort apply: that is what the logger gets. How many sets a started
  /// workout has is the server's to say (`start_workout` reads the accepted
  /// answer itself), and the logger follows the rows the server holds, never
  /// this phone's copy of the answer.
  PlannedWorkout applyTo(PlannedWorkout workout, {bool sets = true}) {
    if (!easesSession || workout.id != plannedWorkoutId) return workout;
    final byOrder = {
      for (final change in appliedChanges) change.exerciseOrder: change,
    };
    return workout.withExercises([
      for (final exercise in workout.exercises)
        if (byOrder[exercise.order] case final change?)
          exercise.eased(
            setCount: sets ? change.setsTo : exercise.setCount,
            targetRpe: change.rpeTo,
            heldLoadKg: change.loadKgTo,
            heldReps: change.repsTo,
            hold: change.loadKgTo != null || change.repsTo != null,
          )
        else
          exercise,
    ]);
  }
}
