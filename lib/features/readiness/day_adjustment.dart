import 'package:flutter/foundation.dart';
import 'package:tracend/features/train/workout_repository.dart';

/// What today's session can be eased by (decision D6, Contract 5).
enum DayAdjustmentKind {
  holdLoad('hold_load'),
  reduceSets('reduce_sets'),
  swapToEasyCardio('swap_to_easy_cardio'),

  /// Only the joint changes (a swap, a pain-free range or an exercise left
  /// out), on a day the readiness rules ask for nothing (schema 1.1).
  jointAdjust('joint_adjust');

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

/// What a joint does to one exercise of today's session (schema 1.1).
enum JointAction {
  /// A gentler exercise takes its place.
  swap,

  /// It stays, in a range that stays pain-free, with the load held.
  limit,

  /// It is left out today.
  drop;

  static JointAction? fromWire(Object? value) {
    for (final action in values) {
      if (action.name == value) return action;
    }
    return null;
  }
}

/// The joints the pain check asks about. `other` has no joint rules.
enum PainArea {
  knee,
  back,
  shoulder,
  other;

  static PainArea? fromWire(Object? value) {
    for (final area in values) {
      if (area.name == value) return area;
    }
    return null;
  }
}

/// Where a sore area stands (schema 1.1 `joint_states[].state`).
enum JointStateKind {
  /// A red flag or a pain of 7 or more routed out; held until a clinician
  /// has cleared it.
  held,

  /// Pain of 4 to 6: the area is eased for a week.
  limited,

  /// Pain of 1 to 3: the area is watched for a week.
  watch;

  static JointStateKind? fromWire(Object? value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

/// One area that is held, limited or on watch today.
@immutable
class JointState {
  const JointState({
    required this.area,
    required this.state,
    required this.severity,
    required this.persistent,
    this.since,
    this.holdOutcome,
  });

  final PainArea area;
  final JointStateKind state;
  final int severity;

  /// The area has been limited or held for two weeks or more.
  final bool persistent;

  /// "2026-10-24": the day the hold began, or the day of the newest report.
  final String? since;

  /// For a held area, the strictest outcome behind the hold: `urgent`,
  /// `clinician_today` or `clinician`. Null otherwise.
  final String? holdOutcome;

  /// A hold the day keeps only as a reminder (see a doctor or physio, not
  /// today): the server gives no safety route for it on later days.
  bool get isReminderHold =>
      state == JointStateKind.held && holdOutcome == 'clinician';

  /// Null for a state this build does not know; it is not shown or acted on.
  static JointState? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final area = PainArea.fromWire(raw['area']);
    final state = JointStateKind.fromWire(raw['state']);
    final severity = raw['severity'];
    if (area == null || state == null || severity is! num) return null;
    return JointState(
      area: area,
      state: state,
      severity: severity.toInt(),
      persistent: raw['persistent'] == true,
      since: raw['since'] as String?,
      holdOutcome: raw['hold_outcome'] as String?,
    );
  }
}

/// A gentler exercise for one joint (`joint_options`).
@immutable
class JointSwap {
  const JointSwap({required this.slug, required this.name});
  final String slug;
  final String name;

  static JointSwap? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final slug = raw['slug'];
    final name = raw['name'];
    if (slug is! String || name is! String) return null;
    return JointSwap(slug: slug, name: name);
  }
}

/// The gentlest swap for each joint on one exercise of today's session, so the
/// in-workout pain check can offer one at once, even offline.
@immutable
class ExerciseJointOptions {
  const ExerciseJointOptions({
    required this.exerciseOrder,
    required this.name,
    required this.options,
  });

  final int exerciseOrder;
  final String name;

  /// By joint: knee, back, shoulder. A joint with no gentler exercise is absent.
  final Map<PainArea, JointSwap> options;

  static ExerciseJointOptions? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final order = raw['exercise_order'];
    final name = raw['name'];
    if (order is! num || name is! String) return null;
    final byJoint = raw['joint_options'];
    return ExerciseJointOptions(
      exerciseOrder: order.toInt(),
      name: name,
      options: {
        if (byJoint is Map)
          for (final area in const [
            PainArea.knee,
            PainArea.back,
            PainArea.shoulder,
          ])
            area: ?JointSwap.tryParse(byJoint[area.name]),
      },
    );
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
    this.jointAction,
    this.joint,
    this.swapToSlug,
    this.swapToName,
    this.rangeNoteCodes = const [],
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

  /// What a sore joint does to this exercise; null when no joint touches it
  /// (or the server named an action this build does not know).
  final JointAction? jointAction;

  /// The joint behind [jointAction].
  final PainArea? joint;

  /// For a swap, the gentler exercise: its catalog slug and name.
  final String? swapToSlug;
  final String? swapToName;

  /// For a limit, the pain-free range cues, in the order the server gave them.
  final List<String> rangeNoteCodes;

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
    var action = JointAction.fromWire(raw['joint_action']);
    // A swap without its replacement cannot be shown or applied.
    if (action == JointAction.swap &&
        (raw['swap_to_name'] is! String || raw['swap_to_slug'] is! String)) {
      action = null;
    }
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
      jointAction: action,
      joint: PainArea.fromWire(raw['joint']),
      swapToSlug: action == JointAction.swap
          ? raw['swap_to_slug'] as String?
          : null,
      swapToName: action == JointAction.swap
          ? raw['swap_to_name'] as String?
          : null,
      rangeNoteCodes: action == JointAction.limit ? _codes(raw) : const [],
    );
  }

  /// The range cues of a limit: `range_note_codes`, else the single
  /// `range_note_code`.
  static List<String> _codes(Map raw) {
    final many = raw['range_note_codes'];
    if (many is List) {
      return [
        for (final code in many)
          if (code is String) code,
      ];
    }
    final one = raw['range_note_code'];
    return one is String ? [one] : const [];
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
    required this.unsupportedKind,
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
    this.jointStates = const [],
    this.exerciseJointOptions = const [],
  });

  /// "2026-10-24": the day the server answered for.
  final String localDate;
  final DayBand band;
  final List<String> triggers;

  /// What the answer or the proposal is; null when the rules ask for nothing
  /// or ask for a kind this build does not know ([unsupportedKind]).
  final DayAdjustmentKind? kind;

  /// The server named a kind this build cannot apply (a later 1.x payload).
  /// Nothing is proposed or applied for it; the band, the explanation and any
  /// safety route are still shown.
  final bool unsupportedKind;
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

  /// The areas that are held, limited or on watch today (schema 1.1); empty
  /// for a 1.0 payload.
  final List<JointState> jointStates;

  /// The gentlest swap per joint for each exercise of today's session
  /// (schema 1.1), for the in-workout pain check.
  final List<ExerciseJointOptions> exerciseJointOptions;

  /// Null when [raw] is not an object this build can read: another major
  /// version, or a missing key. Nothing is shown or applied from it. A later
  /// 1.x payload still reads: unknown keys are ignored, an option of an
  /// unknown kind is skipped, and an unknown top-level kind is kept as
  /// [unsupportedKind] so that a safety route is never lost with it.
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
        kindWire is! String) {
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
      unsupportedKind: kindWire != 'none' && kind == null,
      changes: kind == null ? const [] : _changes(raw['changes']),
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
      jointStates: [
        for (final item
            in raw['joint_states'] is List
                ? raw['joint_states'] as List
                : const [])
          ?JointState.tryParse(item),
      ],
      exerciseJointOptions: [
        for (final item
            in raw['exercise_joint_options'] is List
                ? raw['exercise_joint_options'] as List
                : const [])
          ?ExerciseJointOptions.tryParse(item),
      ],
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

  /// The standing accepted answer changes an exercise for a sore joint.
  bool get hasJointChanges =>
      appliedChanges.any((change) => change.jointAction != null);

  /// The joint today's session loads on the exercise at [order], when it can
  /// be told without guessing: the joint a change of the standing answer is
  /// for, else the only joint with a gentler exercise on offer. Null when it
  /// cannot be told (the athlete chooses).
  PainArea? likelyJoint(int order) {
    for (final change in appliedChanges) {
      if (change.exerciseOrder == order && change.joint != null) {
        return change.joint;
      }
    }
    final options = jointOptionsFor(order)?.options;
    return options != null && options.length == 1 ? options.keys.first : null;
  }

  /// The gentler exercises on offer for the exercise at [order].
  ExerciseJointOptions? jointOptionsFor(int order) {
    for (final item in exerciseJointOptions) {
      if (item.exerciseOrder == order) return item;
    }
    return null;
  }

  /// The option for [wanted], when the server offers it today.
  DayAdjustmentOption? optionFor(DayAdjustmentKind wanted) {
    for (final option in options) {
      if (option.kind == wanted) return option;
    }
    return null;
  }

  /// [workout] as today's accepted answer leaves it: fewer sets and the last
  /// loads held, a gentler exercise where a joint asked for one, a pain-free
  /// range noted, an exercise left out. Anything else is returned as it is,
  /// including a workout this answer is not about.
  ///
  /// With [sets] false the set counts stay the plan's and only the held loads
  /// and effort apply: that is what the logger gets. How many sets a started
  /// workout has is the server's to say (`start_workout` reads the accepted
  /// answer itself), and the logger follows the rows the server holds, never
  /// this phone's copy of the answer. An exercise left out for a joint is the
  /// one exception: it shows as left out in either, so that it is never
  /// offered for logging while the rows are still unread.
  PlannedWorkout applyTo(PlannedWorkout workout, {bool sets = true}) {
    if (appliedChanges.isEmpty || workout.id != plannedWorkoutId) {
      return workout;
    }
    final byOrder = {
      for (final change in appliedChanges) change.exerciseOrder: change,
    };
    final eases = easesSession || appliedKind == DayAdjustmentKind.jointAdjust;
    return workout.withExercises([
      for (final exercise in workout.exercises)
        if (byOrder[exercise.order] case final change?)
          _applyChange(exercise, change, eases: eases, sets: sets)
        else
          exercise,
    ]);
  }

  PlannedExercise _applyChange(
    PlannedExercise exercise,
    DayAdjustmentChange change, {
    required bool eases,
    required bool sets,
  }) {
    var result = exercise;
    final dropped = change.jointAction == JointAction.drop;
    if (eases && !dropped) {
      result = result.eased(
        setCount: sets ? change.setsTo : exercise.setCount,
        targetRpe: change.rpeTo,
        heldLoadKg: change.loadKgTo,
        heldReps: change.repsTo,
        hold: change.loadKgTo != null || change.repsTo != null,
      );
    }
    switch (change.jointAction) {
      case JointAction.swap:
        result = result.swappedTo(
          name: change.swapToName!,
          slug: change.swapToSlug,
        );
      case JointAction.limit:
        result = result.withRangeNotes(change.rangeNoteCodes);
      case JointAction.drop:
        result = result.leftOutToday();
      case null:
        break;
    }
    return result;
  }
}
