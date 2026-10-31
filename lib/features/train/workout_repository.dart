import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/breadcrumbs.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/train/exercise_history.dart';
import 'package:tracend/features/train/muscle_groups.dart';
import 'package:tracend/features/train/offline_safety_notes.dart';
import 'package:tracend/features/train/training_hub_cache.dart';
import 'package:tracend/features/train/unfinished_workout.dart';
import 'package:tracend/features/train/workout_logic.dart';
import 'package:tracend/shared/app_lifecycle.dart';
import 'package:tracend/shared/diagnostics.dart';

/// What the next session's target does with last time's result.
enum NextTargetAction {
  addLoad('add_load'),
  addReps('add_reps'),
  hold('hold'),
  lower('lower');

  const NextTargetAction(this.key);
  final String key;

  static NextTargetAction? fromKey(Object? key) {
    for (final action in values) {
      if (action.key == key) return action;
    }
    return null;
  }
}

/// The next-session target for one exercise, worked out by the server from
/// the sets the athlete logged (hub 1.7 `next_targets`): weight, reps and
/// reps in reserve. It never comes from heart rate. An exercise with no
/// logged sets has none, and the plan's prescription stands.
class NextTarget {
  const NextTarget({
    required this.action,
    required this.reason,
    required this.reps,
    required this.sets,
    this.loadKg,
    this.lowConfidence = false,
  });

  final NextTargetAction action;

  /// The server's reason code, for example `top_of_range`.
  final String reason;

  /// Null for an exercise logged without a load.
  final num? loadKg;
  final int reps;
  final int sets;

  /// True when reps in reserve were not logged for every working set.
  final bool lowConfidence;

  /// Null when [raw] is not a target this build understands.
  static NextTarget? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final action = NextTargetAction.fromKey(raw['action']);
    final reason = raw['reason'];
    final reps = raw['reps'];
    final sets = raw['sets'];
    final load = raw['load_kg'];
    if (action == null ||
        reason is! String ||
        reps is! num ||
        sets is! num ||
        (load != null && load is! num)) {
      return null;
    }
    return NextTarget(
      action: action,
      reason: reason,
      loadKg: load as num?,
      reps: reps.toInt(),
      sets: sets.toInt(),
      lowConfidence: raw['confidence'] == 'low',
    );
  }
}

class PlannedExercise {
  const PlannedExercise({
    required this.order,
    required this.name,
    required this.setCount,
    required this.repMin,
    required this.repMax,
    required this.targetRpe,
    this.restSeconds = 90,
    this.notes = '',
    this.targetLoadKg,
    this.exerciseSlug,
    this.primaryMuscles = const [],
    this.nextTarget,
    this.plannedSetCount,
    this.loadHeld = false,
    this.leftOut = false,
    this.rangeNoteCodes = const [],
    this.swappedFrom,
  });
  final int order;
  final String name;
  final int setCount;
  final int repMin;
  final int repMax;
  final num targetRpe;
  final int restSeconds;
  final String notes;

  /// The starting load Tracend set from a reported top set; null when none.
  final num? targetLoadKg;

  /// The catalog slug (hub 1.6); null for exercises not linked to the
  /// catalog and for every exercise in a 1.5 payload.
  final String? exerciseSlug;

  /// The primary muscles (hub 1.6): the catalog entry's for a linked
  /// exercise, otherwise those of Tracend's reviewed exercise list for this
  /// name. Empty when the name is on neither: nothing is inferred.
  final List<MuscleGroup> primaryMuscles;

  /// The next-session target from the sets logged (hub 1.7); null without
  /// logged sets and in every payload older than 1.7.
  final NextTarget? nextTarget;

  /// The plan's set count when today's accepted adjustment made the session
  /// lighter ([setCount] is then the lighter one); null otherwise.
  final int? plannedSetCount;

  /// Today's accepted adjustment holds last time's load and reps here, and
  /// [nextTarget] is that held target.
  final bool loadHeld;

  /// Today's accepted adjustment leaves this exercise out for a sore joint:
  /// it has no sets today and is never logged.
  final bool leftOut;

  /// The pain-free range cues (`range_note_code`s) that apply to this
  /// exercise today, in the order the server gave them.
  final List<String> rangeNoteCodes;

  /// The exercise the plan has here when today's accepted adjustment swapped
  /// it for a gentler one ([name] and [exerciseSlug] are then the swap's);
  /// null when it was not swapped.
  final PlannedExercise? swappedFrom;

  PlannedExercise _copy({
    String? name,
    int? setCount,
    num? targetRpe,
    Object? targetLoadKg = _keep,
    Object? exerciseSlug = _keep,
    Object? nextTarget = _keep,
    int? plannedSetCount,
    bool? loadHeld,
    bool? leftOut,
    List<String>? rangeNoteCodes,
    PlannedExercise? swappedFrom,
  }) => PlannedExercise(
    order: order,
    name: name ?? this.name,
    setCount: setCount ?? this.setCount,
    repMin: repMin,
    repMax: repMax,
    targetRpe: targetRpe ?? this.targetRpe,
    restSeconds: restSeconds,
    notes: notes,
    targetLoadKg: identical(targetLoadKg, _keep)
        ? this.targetLoadKg
        : targetLoadKg as num?,
    exerciseSlug: identical(exerciseSlug, _keep)
        ? this.exerciseSlug
        : exerciseSlug as String?,
    primaryMuscles: primaryMuscles,
    nextTarget: identical(nextTarget, _keep)
        ? this.nextTarget
        : nextTarget as NextTarget?,
    plannedSetCount: plannedSetCount ?? this.plannedSetCount,
    loadHeld: loadHeld ?? this.loadHeld,
    leftOut: leftOut ?? this.leftOut,
    rangeNoteCodes: rangeNoteCodes ?? this.rangeNoteCodes,
    swappedFrom: swappedFrom ?? this.swappedFrom,
  );

  static const Object _keep = Object();

  /// This exercise as an accepted same-day adjustment leaves it: [setCount]
  /// sets, a lower effort when [targetRpe] is given, and, with [hold], last
  /// time's load and reps as the target. The plan itself is not changed.
  PlannedExercise eased({
    required int setCount,
    num? targetRpe,
    num? heldLoadKg,
    int? heldReps,
    bool hold = false,
  }) => _copy(
    setCount: setCount,
    targetRpe: targetRpe,
    nextTarget: hold
        ? NextTarget(
            action: NextTargetAction.hold,
            reason: 'day_adjustment',
            loadKg: heldLoadKg ?? nextTarget?.loadKg,
            reps: heldReps ?? nextTarget?.reps ?? repMin,
            sets: setCount,
          )
        : nextTarget,
    plannedSetCount: setCount < this.setCount ? this.setCount : plannedSetCount,
    loadHeld: hold || loadHeld,
  );

  /// This exercise swapped for the gentler [name] (catalog [slug]) the
  /// accepted adjustment chose. The swap keeps the sets, reps and effort and
  /// carries no starting load: the athlete picks it.
  PlannedExercise swappedTo({required String name, String? slug}) => _copy(
    name: name,
    exerciseSlug: slug,
    targetLoadKg: null,
    nextTarget: null,
    loadHeld: false,
    swappedFrom: swappedFrom ?? this,
  );

  /// The plan's exercise this one was swapped from, or itself.
  PlannedExercise get asPlanned => swappedFrom ?? this;

  /// This exercise left out today for a sore joint: no sets, never logged.
  PlannedExercise leftOutToday() => _copy(
    setCount: 0,
    plannedSetCount: plannedSetCount ?? setCount,
    leftOut: true,
  );

  /// This exercise with the pain-free range cues [codes] that apply today.
  PlannedExercise withRangeNotes(List<String> codes) =>
      _copy(rangeNoteCodes: List.unmodifiable(codes));

  /// The key `get_my_exercise_history` knows this exercise by: its catalog
  /// slug, or its name when it has none.
  String get historyKey {
    final slug = exerciseSlug?.trim() ?? '';
    return slug.isEmpty ? name.trim() : slug;
  }
}

class PlannedWorkout {
  const PlannedWorkout({
    required this.id,
    required this.name,
    required this.objective,
    required this.estimatedMinutes,
    required this.exercises,
    this.order,
    this.weekday,
    this.warmUp = '',
    this.cooldownCardio = '',
  });

  /// A workout known only by its id, for the calls that read nothing else
  /// (`start_workout`, the session read).
  const PlannedWorkout.byId(this.id)
    : name = '',
      objective = '',
      estimatedMinutes = 0,
      exercises = const [],
      order = null,
      weekday = null,
      warmUp = '',
      cooldownCardio = '';

  final String id;
  final String name;
  final String objective;
  final int estimatedMinutes;
  final List<PlannedExercise> exercises;

  /// The workout's place in the plan (`workout_order`); null where the source
  /// does not say.
  final int? order;
  final int? weekday;
  final String warmUp;
  final String cooldownCardio;

  /// Who this workout is when its id changes: the plan is copied with new ids
  /// (a deload or a block ending), keeping each workout's place and its
  /// exercises. Null when [order] is unknown.
  WorkoutIdentity? get identity => order == null
      ? null
      : WorkoutIdentity(
          order: order!,
          exercises: {
            for (final exercise in exercises)
              exercise.order: exercise.asPlanned.name,
          },
        );

  /// This workout with [exercises] in place of its own.
  PlannedWorkout withExercises(List<PlannedExercise> exercises) =>
      PlannedWorkout(
        id: id,
        name: name,
        objective: objective,
        estimatedMinutes: estimatedMinutes,
        exercises: exercises,
        order: order,
        weekday: weekday,
        warmUp: warmUp,
        cooldownCardio: cooldownCardio,
      );

  /// Parses a workout from `get_my_training_hub` or the daily brief's
  /// `today_workout`, which share one shape. [nextTargets] holds the hub's
  /// 1.7 targets by planned exercise id.
  factory PlannedWorkout.fromHubJson(
    Map<String, dynamic> row, {
    Map<String, NextTarget> nextTargets = const {},
  }) => PlannedWorkout(
    id: row['id'] as String,
    name: row['name'] as String,
    objective: row['objective'] as String,
    order: (row['order'] as num?)?.toInt(),
    weekday: (row['weekday'] as num?)?.toInt(),
    estimatedMinutes: (row['estimated_minutes'] as num).toInt(),
    warmUp: row['warm_up'] as String? ?? '',
    cooldownCardio: row['cooldown_cardio'] as String? ?? '',
    exercises: (row['exercises'] as List? ?? const []).map((item) {
      final exercise = Map<String, dynamic>.from(item as Map);
      return PlannedExercise(
        order: (exercise['order'] as num).toInt(),
        name: exercise['name'] as String,
        setCount: (exercise['set_count'] as num).toInt(),
        repMin: (exercise['rep_min'] as num).toInt(),
        repMax: (exercise['rep_max'] as num).toInt(),
        targetRpe: exercise['target_rpe'] as num? ?? 8,
        restSeconds: (exercise['rest_seconds'] as num? ?? 90).toInt(),
        notes: exercise['notes'] as String? ?? '',
        targetLoadKg: exercise['target_load_kg'] as num?,
        exerciseSlug: exercise['exercise_slug'] as String?,
        primaryMuscles: _muscleGroups(exercise['primary_muscles']),
        nextTarget: nextTargets[exercise['id']],
      );
    }).toList(),
  );

  static List<MuscleGroup> _muscleGroups(Object? raw) {
    if (raw is! List) return const [];
    final groups = <MuscleGroup>[];
    for (final key in raw) {
      final group = MuscleGroup.fromKey(key);
      if (group != null && !groups.contains(group)) groups.add(group);
    }
    return groups;
  }

  static const fixture = PlannedWorkout(
    id: 'fixture-push',
    name: 'Push day',
    estimatedMinutes: 60,
    objective: 'Build pressing strength without adding unnecessary fatigue.',
    exercises: [
      PlannedExercise(
        order: 1,
        name: 'Incline dumbbell press',
        setCount: 3,
        repMin: 8,
        repMax: 10,
        targetRpe: 8,
      ),
      PlannedExercise(
        order: 2,
        name: 'Machine chest press',
        setCount: 3,
        repMin: 10,
        repMax: 12,
        targetRpe: 8,
      ),
      PlannedExercise(
        order: 3,
        name: 'Cable lateral raise',
        setCount: 3,
        repMin: 12,
        repMax: 15,
        targetRpe: 9,
      ),
      PlannedExercise(
        order: 4,
        name: 'Rope pressdown',
        setCount: 3,
        repMin: 10,
        repMax: 12,
        targetRpe: 8,
      ),
    ],
  );
}

/// Who a planned workout is when its id is not: a plan copy keeps each
/// workout's place in the plan (`workout_order`) and its exercises by
/// `exercise_order` and name, and gives everything new ids.
@immutable
class WorkoutIdentity {
  const WorkoutIdentity({required this.order, required this.exercises});

  final int order;

  /// The plan's exercise name by exercise order.
  final Map<int, String> exercises;

  static String _normalized(String name) => name.trim().toLowerCase();

  /// [workout] is this workout in another copy of the plan.
  bool matches(PlannedWorkout workout) {
    if (workout.order != order ||
        workout.exercises.length != exercises.length) {
      return false;
    }
    for (final exercise in workout.exercises) {
      final name = exercises[exercise.order];
      if (name == null ||
          _normalized(name) != _normalized(exercise.asPlanned.name)) {
        return false;
      }
    }
    return true;
  }

  Map<String, Object> toJson() => {
    'order': order,
    'exercises': {
      for (final entry in exercises.entries) '${entry.key}': entry.value,
    },
  };

  /// Null when [raw] is not what [toJson] wrote.
  static WorkoutIdentity? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final order = raw['order'];
    final exercises = raw['exercises'];
    if (order is! int || exercises is! Map) return null;
    final byOrder = <int, String>{};
    for (final entry in exercises.entries) {
      final key = int.tryParse('${entry.key}');
      final name = entry.value;
      if (key == null || name is! String) return null;
      byOrder[key] = name;
    }
    return WorkoutIdentity(order: order, exercises: byOrder);
  }
}

/// Where a completed session's completion came from (hub 1.6).
enum CompletionSource {
  manual,
  healthkit;

  static CompletionSource? fromKey(Object? key) => switch (key) {
    'manual' => manual,
    'healthkit' => healthkit,
    _ => null,
  };
}

/// Where a completed session's effort rating came from (hub 1.6).
enum EffortSource {
  /// The athlete rated the workout.
  athlete,

  /// The app's fixed 8 from builds before `complete_workout_v2`.
  legacyDefault,

  /// The fixed 5 written when Apple Health completed the workout.
  healthkitDefault;

  static EffortSource? fromKey(Object? key) => switch (key) {
    'athlete' => athlete,
    'legacy_default' => legacyDefault,
    'healthkit_default' => healthkitDefault,
    _ => null,
  };
}

class TrainingSessionSummary {
  const TrainingSessionSummary({
    required this.name,
    required this.date,
    this.durationSeconds,
    this.workoutId,
    this.id,
    this.effort,
    this.completionSource,
    this.effortSource,
  });
  final String name;
  final DateTime date;
  final int? durationSeconds;

  /// Planned workout id from the hub (`recent_sessions[].workout_id`).
  /// Null on older payloads; the session row is then display-only.
  final String? workoutId;

  /// The session id (`recent_sessions[].id`).
  final String? id;

  /// The whole-workout effort, 0–10; read with [effortSource].
  final num? effort;

  /// Null in a 1.5 payload and for sessions with no audit evidence.
  final CompletionSource? completionSource;

  /// Null in a 1.5 payload.
  final EffortSource? effortSource;
}

class ExerciseProgression {
  const ExerciseProgression({
    required this.exercise,
    required this.sessions,
    this.bestLoadKg,
    this.bestRepetitions,
    this.latestDate,
  });
  final String exercise;
  final int sessions;
  final num? bestLoadKg;
  final int? bestRepetitions;

  /// The latest completed session with this exercise; null when absent.
  final DateTime? latestDate;
}

/// The approved plan's header from `active_plan`.
class ActivePlanSummary {
  const ActivePlanSummary({
    required this.title,
    this.blockWeeks,
    this.sessionsPerWeek,
    this.effectiveDate,
    this.approvedOn,
    this.progressionRule,
  });
  final String title;
  final int? blockWeeks;
  final int? sessionsPerWeek;

  /// The local day the plan took effect (hub 1.6); null in a 1.5 payload.
  final DateTime? effectiveDate;

  /// The local day the athlete approved the plan (hub 1.6).
  final DateTime? approvedOn;

  /// The plan's progression rule; null for older plans, which hide it.
  final String? progressionRule;
}

/// One day's intensity class (ALGORITHMS §4 "Day Level").
enum DayLoadLevel {
  rest,
  easy,
  moderate,
  hard;

  static DayLoadLevel? fromKey(Object? key) => switch (key) {
    'rest' => rest,
    'easy' => easy,
    'moderate' => moderate,
    'hard' => hard,
    _ => null,
  };
}

/// One local day of `daily_load` (hub 1.6).
class DailyLoadDay {
  const DailyLoadDay({
    required this.date,
    required this.recorded,
    required this.strain,
    required this.minutes,
    required this.sessions,
    required this.effortReported,
    this.level,
    this.personalReference = false,
  });
  final DateTime date;

  /// At least one completed session that day.
  final bool recorded;
  final double strain;
  final int minutes;
  final int sessions;

  /// Every session that day carries an athlete-reported effort.
  final bool effortReported;

  /// Null for a trained day whose effort was a default: "Calibrating".
  final DayLoadLevel? level;

  /// The class came from the athlete's own percentiles, not the fixed
  /// cut-offs.
  final bool personalReference;
}

/// The hub's `computed` block: the deterministic load numbers for today.
class HubLoadMetrics {
  const HubLoadMetrics({this.acwr, this.trainingMonotony, this.todayStrain});
  final double? acwr;
  final double? trainingMonotony;
  final double? todayStrain;
}

class HealthkitCompletionCandidate {
  const HealthkitCompletionCandidate({
    required this.plannedWorkoutId,
    required this.plannedWorkoutName,
    required this.workoutCount,
    required this.workoutMinutes,
    required this.localDate,
  });
  final String plannedWorkoutId;
  final String plannedWorkoutName;
  final int workoutCount;
  final int workoutMinutes;
  final DateTime localDate;
}

class TrainingHubData {
  const TrainingHubData({
    required this.planTitle,
    required this.workouts,
    required this.recentSessions,
    required this.completedSessions,
    required this.plannedSessions,
    required this.progression,
    this.completedDays = const {},
    this.plan,
    this.localToday,
    this.todayWorkout,
    this.dailyLoad = const [],
    this.load,
    this.cachedAt,
  });

  /// The hub this phone saved at [CachedTrainingHub.savedAt], for a launch
  /// or a load with no connection. The day is [now]'s: the plan's weekdays
  /// still say which workout is today's, but the load numbers, today's
  /// workout and the next-session targets the server worked out (a lighter
  /// week changes their loads by the day) belong to the day the copy was
  /// saved, so when that is another day they are left out rather than shown
  /// for today.
  factory TrainingHubData.fromCache(CachedTrainingHub cached, DateTime now) {
    final json = Map<String, dynamic>.of(cached.hub);
    final today = localDayKey(now);
    if (json['local_today'] != today) {
      json
        ..['local_today'] = today
        ..remove('daily_load')
        ..remove('computed')
        ..remove('today_workout')
        ..remove('next_targets');
    }
    return TrainingHubData.fromHubJson(json, cachedAt: cached.savedAt);
  }

  /// Parses `get_my_training_hub`. A cached 1.5 payload parses too: every
  /// 1.6 and 1.7 field is optional and reads as absent.
  factory TrainingHubData.fromHubJson(
    Map<String, dynamic> value, {
    DateTime? cachedAt,
  }) {
    final targets = _nextTargets(value['next_targets']);
    final active = _map(value['active_plan']);
    final adherence = _map(value['adherence']);
    final computed = _map(value['computed']);
    final todayWorkout = value['today_workout'];
    return TrainingHubData(
      planTitle: active['title'] as String? ?? 'Approved plan',
      plan: active.isEmpty
          ? null
          : ActivePlanSummary(
              title: active['title'] as String? ?? 'Approved plan',
              blockWeeks: (active['block_weeks'] as num?)?.toInt(),
              sessionsPerWeek: (active['sessions_per_week'] as num?)?.toInt(),
              effectiveDate: _date(active['effective_date']),
              approvedOn: _date(active['approved_on']),
              progressionRule: _text(active['progression_rule']),
            ),
      localToday: _date(value['local_today']),
      workouts: (value['workouts'] as List? ?? const [])
          .map(
            (item) =>
                PlannedWorkout.fromHubJson(_map(item), nextTargets: targets),
          )
          .toList(),
      todayWorkout: todayWorkout is Map
          ? PlannedWorkout.fromHubJson(_map(todayWorkout), nextTargets: targets)
          : null,
      recentSessions: (value['recent_sessions'] as List? ?? const []).map((
        item,
      ) {
        final row = _map(item);
        return TrainingSessionSummary(
          name: row['name'] as String,
          date: DateTime.parse(row['local_date'] as String),
          durationSeconds: (row['duration_seconds'] as num?)?.toInt(),
          workoutId: row['workout_id'] as String?,
          id: row['id'] as String?,
          effort: row['effort'] as num?,
          completionSource: CompletionSource.fromKey(row['completion_source']),
          effortSource: EffortSource.fromKey(row['effort_source']),
        );
      }).toList(),
      completedSessions: (adherence['completed_sessions'] as num? ?? 0).toInt(),
      plannedSessions: (adherence['planned_sessions'] as num? ?? 0).toInt(),
      progression: (value['progression'] as List? ?? const []).map((item) {
        final row = _map(item);
        return ExerciseProgression(
          exercise: row['exercise'] as String,
          sessions: (row['sessions'] as num).toInt(),
          bestLoadKg: row['best_load_kg'] as num?,
          bestRepetitions: (row['best_repetitions'] as num?)?.toInt(),
          latestDate: _date(row['latest_date']),
        );
      }).toList(),
      completedDays: (value['completed_day_set'] as List? ?? const [])
          .map((d) => DateTime.parse(d as String))
          .toSet(),
      dailyLoad: (value['daily_load'] as List? ?? const []).map((item) {
        final row = _map(item);
        final recorded = row['recorded'] as bool? ?? false;
        return DailyLoadDay(
          date: DateTime.parse(row['local_date'] as String),
          recorded: recorded,
          strain: (row['strain'] as num? ?? 0).toDouble(),
          minutes: (row['minutes'] as num? ?? 0).toInt(),
          sessions: (row['sessions'] as num? ?? 0).toInt(),
          effortReported: row['effort_reported'] as bool? ?? false,
          level: recorded
              ? DayLoadLevel.fromKey(row['level'])
              : DayLoadLevel.rest,
          personalReference: row['reference'] == 'personal',
        );
      }).toList(),
      load: computed.isEmpty
          ? null
          : HubLoadMetrics(
              acwr: (computed['acwr'] as num?)?.toDouble(),
              trainingMonotony: (computed['training_monotony'] as num?)
                  ?.toDouble(),
              todayStrain: (computed['today_strain'] as num?)?.toDouble(),
            ),
      cachedAt: cachedAt,
    );
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  /// The 1.7 targets by planned exercise id; a target this build cannot read
  /// is left out, so that exercise keeps the plan's prescription.
  static Map<String, NextTarget> _nextTargets(Object? raw) {
    final targets = <String, NextTarget>{};
    if (raw is! List) return targets;
    for (final item in raw) {
      final id = item is Map ? item['planned_exercise_id'] : null;
      final target = NextTarget.fromJson(item);
      if (id is String && target != null) targets[id] = target;
    }
    return targets;
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  final String planTitle;
  final List<PlannedWorkout> workouts;
  final List<TrainingSessionSummary> recentSessions;
  final int completedSessions;
  final int plannedSessions;
  final List<ExerciseProgression> progression;
  final Set<DateTime> completedDays;

  /// The plan header; null when the hub has no active plan.
  final ActivePlanSummary? plan;

  /// The athlete's local date on the server (hub 1.6).
  final DateTime? localToday;

  /// Today's planned workout from the hub, when one is scheduled.
  final PlannedWorkout? todayWorkout;

  /// The 28 local days ending on [localToday] (hub 1.6); empty in 1.5.
  final List<DailyLoadDay> dailyLoad;

  /// The hub's computed load numbers for today; null when absent.
  final HubLoadMetrics? load;

  /// When this phone saved the hub it shows, when the server could not be
  /// reached and this is the last copy; null for a hub just loaded.
  final DateTime? cachedAt;

  bool isDayCompleted(DateTime date) => completedDays.any(
    (d) => d.year == date.year && d.month == date.month && d.day == date.day,
  );

  PlannedWorkout? workoutForWeekday(int weekday) {
    for (final workout in workouts) {
      if (workout.weekday == weekday) return workout;
    }
    final hasAssignedWeekdays = workouts.any(
      (workout) => workout.weekday != null,
    );
    if (!hasAssignedWeekdays) return workouts.isEmpty ? null : workouts.first;
    return null;
  }
}

abstract interface class TrainingHubRepository {
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28});
}

/// A repository that keeps the last hub that loaded on the phone.
abstract interface class SavedTrainingHubRepository {
  /// That copy, marked with [TrainingHubData.cachedAt]; null when there is
  /// none for the signed-in athlete.
  Future<TrainingHubData?> loadSavedTrainingHub();
}

/// A repository that can find a workout again after the plan was copied with
/// new ids (a lighter week starting or a temporary block ending).
abstract interface class WorkoutPlanRemapper {
  /// The athlete signed in now, or null.
  String? get signedInUserId;

  /// The workout of the current plan that [identity] names, with the phone's
  /// draft and saved finish of the workout [staleId] moved to it. Null when
  /// the current plan has no such workout (or [identity] is unknown), or when
  /// [ownerId], the athlete the draft belongs to, is no longer the one signed
  /// in: the draft then stays where it is. Throws when the plan cannot be
  /// read.
  Future<PlannedWorkout?> moveToCurrentPlan(
    String staleId,
    WorkoutIdentity? identity, {
    required String? ownerId,
  });
}

/// A repository that can say when the workouts it is sending have gone out.
abstract interface class WorkoutSendInFlight {
  /// Completes once the send of waiting workouts running now for the
  /// signed-in athlete (if any) is over. Never throws.
  Future<void> sendInFlight();
}

/// A repository that keeps the athlete's last sore-area notes beside the
/// saved plan.
abstract interface class SavedSafetyNotesRepository {
  /// Keeps what [adjustment] says about sore areas for [userId], and only
  /// while [userId] is the athlete signed in: an answer that arrives after
  /// another athlete signed in is dropped.
  Future<void> saveSafetyNotes(
    DayAdjustment adjustment, {
    required String userId,
  });

  /// The notes kept for the signed-in athlete, or null.
  Future<OfflineSafetyNotes?> loadSavedSafetyNotes();
}

class WorkoutRepairCandidate {
  const WorkoutRepairCandidate({
    required this.sessionId,
    required this.localDate,
    required this.workoutName,
    required this.recordedDurationSeconds,
    required this.healthkitDurationSeconds,
    required this.recommendedStartedAt,
    required this.recommendedEndedAt,
    this.blankDuplicateSessionId,
  });
  final String sessionId;
  final DateTime localDate;
  final String workoutName;
  final int recordedDurationSeconds;
  final int healthkitDurationSeconds;
  final DateTime recommendedStartedAt;
  final DateTime recommendedEndedAt;
  final String? blankDuplicateSessionId;
}

abstract interface class WorkoutRepairRepository {
  Future<List<WorkoutRepairCandidate>> loadRepairCandidates();
  Future<void> confirmRepair(WorkoutRepairCandidate candidate);
}

class WorkoutReconciliation {
  const WorkoutReconciliation({
    required this.id,
    required this.status,
    required this.confidence,
    required this.durationDifferenceSeconds,
    required this.activityType,
    required this.healthDurationSeconds,
    required this.workoutName,
    required this.localDate,
  });
  final String id;
  final String status;
  final double confidence;
  final int durationDifferenceSeconds;
  final String activityType;
  final int healthDurationSeconds;
  final String workoutName;
  final DateTime localDate;
}

abstract interface class WorkoutReconciliationRepository {
  Future<List<WorkoutReconciliation>> loadReconciliations();
  Future<void> respondToReconciliation(String id, {required bool accept});
}

abstract interface class HealthkitCandidateRepository {
  Future<HealthkitCompletionCandidate?> getHealthkitCandidate(DateTime date);
}

abstract interface class WorkoutRepository {
  Future<PlannedWorkout> loadTodayWorkout();
  Future<String?> loadDraft(String workoutId);
  Future<Map<String, dynamic>?> loadSession(
    PlannedWorkout workout, {
    DateTime? localDate,
  });
  Future<void> saveDraft(String workoutId, String json);
  Future<void> clearDraft(String workoutId);
  Future<String> start(
    PlannedWorkout workout,
    String idempotencyKey, {
    DateTime? localDate,
  });
  Future<void> sync(String sessionId, int revision, Map<String, dynamic> draft);

  /// Finishes the workout with the athlete's own [sessionEffort], a whole
  /// number from 1 to 10 (`complete_workout_v2`, energy null). The request
  /// is saved on the device before the call, so when the call fails it can
  /// be sent again from [loadPendingFinish]; a repeat after the server
  /// already finished it returns `replayed`. Clears the draft on success.
  Future<WorkoutCompletion> completeWithEffort(
    String sessionId,
    int revision,
    int durationSeconds,
    Map<String, dynamic> draft, {
    required int sessionEffort,
  });

  /// Keeps the athlete's finish for [workoutId] on the phone, so it can be
  /// sent from [loadPendingFinish] once the workout and its sets can be.
  Future<void> savePendingFinish(String workoutId, PendingWorkoutFinish finish);

  /// The finish request saved for [workoutId] that has not reached the
  /// server yet, or null.
  Future<PendingWorkoutFinish?> loadPendingFinish(String workoutId);

  /// Discards an in-progress workout (`abandon_workout`) and its draft.
  /// Offline, the discard waits on the device and is sent before the next
  /// session load; the server answers a repeat with `replayed`.
  Future<WorkoutDiscard> abandon(String sessionId, {required String workoutId});

  /// Last time, best set and recent top sets for each key
  /// ([PlannedExercise.historyKey]). Falls back to this device's last copy
  /// when the server cannot be reached.
  Future<ExerciseHistoryResult> loadExerciseHistory(
    List<String> keys, {
    int sessions = 8,
  });
}

/// The answer to finishing a workout.
class WorkoutCompletion {
  const WorkoutCompletion({
    required this.replayed,
    this.completedSets,
    this.totalSets,
  });

  factory WorkoutCompletion.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return WorkoutCompletion(
      replayed: map['replayed'] == true,
      completedSets: (map['completed_sets'] as num?)?.toInt(),
      totalSets: (map['total_sets'] as num?)?.toInt(),
    );
  }

  /// The server had already finished this workout; nothing changed.
  final bool replayed;

  /// Null on a replay, which reports no counts.
  final int? completedSets;
  final int? totalSets;
}

/// A finish the athlete confirmed that has not reached the server.
class PendingWorkoutFinish {
  PendingWorkoutFinish({
    required this.sessionEffort,
    required this.durationSeconds,
  }) {
    RangeError.checkValueInInterval(sessionEffort, 1, 10, 'sessionEffort');
  }

  static PendingWorkoutFinish? fromJson(Object? json) {
    if (json is! Map) return null;
    final effort = json['session_effort'];
    final duration = json['duration_seconds'];
    if (effort is! int || effort < 1 || effort > 10 || duration is! int) {
      return null;
    }
    return PendingWorkoutFinish(
      sessionEffort: effort,
      durationSeconds: duration,
    );
  }

  final int sessionEffort;
  final int durationSeconds;

  Map<String, Object> toJson() => {
    'session_effort': sessionEffort,
    'duration_seconds': durationSeconds,
  };
}

/// The answer to discarding a workout.
class WorkoutDiscard {
  const WorkoutDiscard({this.replayed = false, this.queued = false});

  /// The server had already discarded it.
  final bool replayed;

  /// Offline: the discard is saved and sent before the next session load.
  final bool queued;
}

/// The workout never reached the server (its id is still `pending-`), so it
/// cannot be finished there yet. The finish request stays on the device.
class WorkoutSessionPendingException implements Exception {
  const WorkoutSessionPendingException();

  @override
  String toString() => 'The workout has not reached the server yet.';
}

String newIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class SupabaseWorkoutRepository
    implements
        WorkoutRepository,
        TrainingHubRepository,
        SavedTrainingHubRepository,
        SavedSafetyNotesRepository,
        WorkoutPlanRemapper,
        WorkoutSendInFlight,
        WorkoutRepairRepository,
        WorkoutReconciliationRepository,
        HealthkitCandidateRepository,
        UnfinishedWorkoutRepository {
  /// With [loggerOpen] the repository leaves the sending of waiting workouts
  /// to the open logger, which sends its own workout itself.
  SupabaseWorkoutRepository(
    this._client,
    this._preferences, {
    DateTime Function()? clock,
    bool Function()? loggerOpen,
  }) : _clock = clock ?? DateTime.now,
       _loggerOpen = loggerOpen,
       _hubCache = TrainingHubCache(_preferences);
  final SupabaseClient _client;
  final SharedPreferencesAsync _preferences;
  final DateTime Function() _clock;
  final bool Function()? _loggerOpen;
  final TrainingHubCache _hubCache;
  String get _userId => _client.auth.currentUser!.id;
  String _draftKey(String workoutId) =>
      '${WorkoutLocalKeys.draftPrefix(_userId)}$workoutId';
  String _finishKey(String workoutId) =>
      '${WorkoutLocalKeys.finishPrefix(_userId)}$workoutId';
  String get _discardKey => WorkoutLocalKeys.discards(_userId);
  String get _historyKey => WorkoutLocalKeys.exerciseHistory(_userId);

  /// The window the offline copy is kept for; a hub for another window (the
  /// Progress tab's) is never saved or served from it.
  static const _cachedHubDays = 28;

  /// How long a hub request may take before the saved copy is used.
  static const _hubWait = Duration(seconds: 10);

  /// The hub from the server. When the server cannot be reached, this
  /// phone's last copy for this athlete answers instead, marked with
  /// [TrainingHubData.cachedAt]; with no copy the failure is rethrown. A hub
  /// that loads also sends the workouts that waited for a connection.
  @override
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28}) async {
    final userId = _client.auth.currentUser?.id;
    final Map<String, dynamic> hub;
    try {
      hub = await _fetchHub(periodDays);
    } catch (error) {
      if (userId == null || periodDays != _cachedHubDays) rethrow;
      final cached = await _hubCache.load(userId);
      if (cached == null) rethrow;
      logNonCritical(error, 'training hub from device');
      return TrainingHubData.fromCache(cached, _clock());
    }
    if (userId != null) {
      if (periodDays == _cachedHubDays) await _saveHub(userId, hub);
      unawaited(sendWaiting());
    }
    return TrainingHubData.fromHubJson(hub);
  }

  Future<Map<String, dynamic>> _fetchHub(int periodDays) async =>
      Map<String, dynamic>.from(
        await _client
                .rpc('get_my_training_hub', params: {'period_days': periodDays})
                .timeout(_hubWait)
            as Map,
      );

  /// Keeps [hub] as [userId]'s copy, unless [userId] is no longer signed in:
  /// a load still in flight when the athlete signed out must not write their
  /// plan back after it was cleared.
  Future<void> _saveHub(String userId, Map<String, dynamic> hub) async {
    if (_client.auth.currentUser?.id != userId) return;
    await _hubCache.save(userId, hub, _clock());
    if (_client.auth.currentUser?.id != userId) await _hubCache.clear(userId);
  }

  @override
  Future<TrainingHubData?> loadSavedTrainingHub() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final cached = await _hubCache.load(userId);
    return cached == null ? null : TrainingHubData.fromCache(cached, _clock());
  }

  @override
  Future<void> saveSafetyNotes(
    DayAdjustment adjustment, {
    required String userId,
  }) async {
    if (_client.auth.currentUser?.id != userId) return;
    await _hubCache.saveSafety(userId, OfflineSafetyNotes.from(adjustment));
    if (_client.auth.currentUser?.id != userId) await _hubCache.clear(userId);
  }

  @override
  Future<OfflineSafetyNotes?> loadSavedSafetyNotes() async {
    final userId = _client.auth.currentUser?.id;
    return userId == null ? null : _hubCache.loadSafety(userId);
  }

  // A workout the plan no longer knows by its id ---------------------------

  @override
  String? get signedInUserId => _client.auth.currentUser?.id;

  @override
  Future<PlannedWorkout?> moveToCurrentPlan(
    String staleId,
    WorkoutIdentity? identity, {
    required String? ownerId,
  }) async {
    if (identity == null || ownerId == null) return null;
    final hub = await _fetchHub(_cachedHubDays);
    // The draft is ownerId's: if another athlete signed in while the plan was
    // read, that plan is not where it goes.
    if (_client.auth.currentUser?.id != ownerId) return null;
    await _saveHub(ownerId, hub);
    PlannedWorkout? current;
    for (final workout in TrainingHubData.fromHubJson(hub).workouts) {
      if (workout.id != staleId && identity.matches(workout)) {
        current = workout;
        break;
      }
    }
    if (current == null || !await _moveDraft(staleId, current.id)) return null;
    AppBreadcrumbs.workout('Workout moved to the current plan');
    return current;
  }

  /// Moves the phone's draft and saved finish of workout [from] to workout
  /// [to]. False when [to] already holds a different draft: both stay.
  Future<bool> _moveDraft(String from, String to) async {
    final draft = await _preferences.getString(_draftKey(from));
    if (draft == null) return true;
    final existing = await _preferences.getString(_draftKey(to));
    if (existing != null) {
      final same = _sameSession(draft, existing);
      if (same) await clearDraft(from);
      return same;
    }
    final moved = decodeDraft(draft)..['workout_id'] = to;
    await _preferences.setString(_draftKey(to), jsonEncode(moved));
    final finish = await _preferences.getString(_finishKey(from));
    if (finish != null) {
      await _preferences.setString(_finishKey(to), finish);
    }
    await clearDraft(from);
    return true;
  }

  static bool _sameSession(String a, String b) {
    try {
      final key = decodeDraft(a)['idempotency_key'];
      return key != null && key == decodeDraft(b)['idempotency_key'];
    } catch (_) {
      return false;
    }
  }

  // Workouts that waited for a connection ----------------------------------

  /// The sends running now, by athlete: the gate and the Train tab each have
  /// a repository, and both ask after a reconnect.
  static final Map<String, Future<void>> _sending = {};

  /// Forgets sends that never finished (a test that ended inside one).
  @visibleForTesting
  static void forgetSending() => _sending.clear();

  @override
  Future<void> sendInFlight() {
    final userId = _client.auth.currentUser?.id;
    return userId == null
        ? Future<void>.value()
        : _sending[userId] ?? Future<void>.value();
  }

  /// Sends every workout of this athlete that is finished, or was left on an
  /// earlier day, and has not reached the server: its start, its sets and its
  /// finish, one workout at a time, under the keys it was saved with. A repeat
  /// is harmless (the server answers `replayed`). Does nothing while a logger
  /// is open (it sends its own workout) and never touches another athlete's
  /// keys. Never throws; what cannot be sent stays on the phone.
  Future<void> sendWaiting() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return Future<void>.value();
    return _sending[userId] ??= _sendAllWaiting(userId).whenComplete(() {
      _sending.remove(userId);
    });
  }

  Future<void> _sendAllWaiting(String userId) async {
    try {
      final prefix = WorkoutLocalKeys.draftPrefix(userId);
      final ids = [
        for (final key in await _preferences.getKeys())
          if (key.startsWith(prefix)) key.substring(prefix.length),
      ];
      for (final id in ids) {
        if (_client.auth.currentUser?.id != userId) return;
        if (_loggerOpen?.call() ?? false) return;
        await _sendWaitingWorkout(id);
      }
    } catch (e) {
      logNonCritical(e, 'waiting workouts not sent');
    }
  }

  Future<void> _sendWaitingWorkout(String workoutId) async {
    final saved = await loadDraft(workoutId);
    if (saved == null) return;
    final Map<String, dynamic> draft;
    try {
      draft = decodeDraft(saved);
    } catch (error) {
      logNonCritical(error, 'workout draft not read');
      return;
    }
    // A workout of today that is not finished belongs to its logger.
    final finished = await loadPendingFinish(workoutId) != null;
    if (!finished && !(draftHasDoneSet(draft) && _leftOnEarlierDay(draft))) {
      return;
    }
    final result = await sendLeftOverDraft(
      this,
      PlannedWorkout.byId(workoutId),
      draft,
    );
    if (result.settled) await clearDraft(result.workoutId);
  }

  bool _leftOnEarlierDay(Map<String, dynamic> draft) {
    final started = DateTime.tryParse('${draft['actual_started_at'] ?? ''}');
    if (started == null) return false;
    final now = _clock();
    return workoutLeftOnEarlierDay(
      startedAt: started,
      now: now,
      sessionDate: now,
      maxSeconds: maxWorkoutSeconds,
    );
  }

  HealthkitCompletionCandidate _parseHealthkitCandidate(
    Map<String, dynamic> row,
  ) => HealthkitCompletionCandidate(
    plannedWorkoutId: row['planned_workout_id'] as String,
    plannedWorkoutName: row['planned_workout_name'] as String,
    workoutCount: (row['workout_count'] as num).toInt(),
    workoutMinutes: (row['workout_minutes'] as num).toInt(),
    localDate: DateTime.parse(row['local_date'] as String),
  );

  @override
  Future<List<WorkoutRepairCandidate>> loadRepairCandidates() async {
    final value = await _client.rpc('get_my_workout_repair_candidates');
    return (value as List? ?? const []).map((item) {
      final row = Map<String, dynamic>.from(item as Map);
      return WorkoutRepairCandidate(
        sessionId: row['session_id'] as String,
        localDate: DateTime.parse(row['local_date'] as String),
        workoutName: row['workout_name'] as String,
        recordedDurationSeconds: (row['recorded_duration_seconds'] as num? ?? 0)
            .toInt(),
        healthkitDurationSeconds: (row['healthkit_duration_seconds'] as num)
            .toInt(),
        recommendedStartedAt: DateTime.parse(
          row['recommended_started_at'] as String,
        ),
        recommendedEndedAt: DateTime.parse(
          row['recommended_ended_at'] as String,
        ),
        blankDuplicateSessionId: row['blank_duplicate_session_id'] as String?,
      );
    }).toList();
  }

  @override
  Future<void> confirmRepair(WorkoutRepairCandidate candidate) async {
    await _client.rpc(
      'correct_completed_workout',
      params: {
        'p_session_id': candidate.sessionId,
        'p_actual_started_at': candidate.recommendedStartedAt
            .toUtc()
            .toIso8601String(),
        'p_actual_ended_at': candidate.recommendedEndedAt
            .toUtc()
            .toIso8601String(),
        'p_reason':
            'Owner confirmed Apple Health workout duration and recovered incomplete Tracend logging.',
        'p_abandon_duplicate_session_id': candidate.blankDuplicateSessionId,
      },
    );
  }

  @override
  Future<List<WorkoutReconciliation>> loadReconciliations() async {
    final value = await _client.rpc('get_my_workout_reconciliation_candidates');
    return (value as List? ?? const []).map((item) {
      final row = Map<String, dynamic>.from(item as Map);
      return WorkoutReconciliation(
        id: row['id'] as String,
        status: row['status'] as String,
        confidence: (row['confidence'] as num).toDouble(),
        durationDifferenceSeconds: (row['duration_difference_seconds'] as num)
            .toInt(),
        activityType: row['activity_type'] as String,
        healthDurationSeconds: (row['health_duration_seconds'] as num).toInt(),
        workoutName: row['workout_name'] as String,
        localDate: DateTime.parse(row['local_date'] as String),
      );
    }).toList();
  }

  @override
  Future<void> respondToReconciliation(
    String id, {
    required bool accept,
  }) async {
    await _client.rpc(
      'respond_workout_reconciliation',
      params: {'p_reconciliation_id': id, 'p_accept': accept},
    );
  }

  @override
  Future<UnfinishedWorkout?> loadUnfinishedWorkout() async {
    // A discard queued offline goes first: the server then records it as the
    // athlete's answer, and one that is still waiting hides its session.
    final waiting = await _replayDiscards();
    final value = await _client.rpc('get_my_unfinished_workout_v1');
    if (value is! Map) return null;
    final workout = UnfinishedWorkout.fromJson(value['workout']);
    if (workout != null && waiting.contains(workout.sessionId)) return null;
    return workout;
  }

  @override
  Future<void> saveUnfinishedWorkout(
    UnfinishedWorkout workout, {
    required int sessionEffort,
  }) async {
    RangeError.checkValueInInterval(sessionEffort, 1, 10, 'sessionEffort');
    // Sets and times that never reached the server go first: the draft is
    // removed after the answer, so it must not hold anything the server lacks.
    // When they cannot be sent nothing is answered and nothing is removed. A
    // session that already refuses them (55000) was settled by an earlier try
    // whose answer was lost; the answer below then replays or says it is gone.
    try {
      await _sendDraftOf(workout);
    } on PostgrestException catch (e) {
      if (e.code != '55000') rethrow;
    }
    await _answer(workout, {
      'p_session_id': workout.sessionId,
      'p_action': 'save',
      'p_session_effort': sessionEffort,
    });
    AppBreadcrumbs.workout('Unfinished workout saved');
    await _dropDraftOf(workout);
  }

  @override
  Future<void> discardUnfinishedWorkout(UnfinishedWorkout workout) async {
    await _answer(workout, {
      'p_session_id': workout.sessionId,
      'p_action': 'discard',
    });
    AppBreadcrumbs.workout('Unfinished workout discarded');
    await _dropDraftOf(workout);
  }

  /// `resolve_unfinished_workout_v1`. Answers that say the workout can no
  /// longer be answered become [UnfinishedWorkoutGone]: P0002 (past its seven
  /// days, or not an unfinished workout any more), 55000 (it was discarded; the
  /// phone's draft of it goes, since it can never be sent) and, for a discard,
  /// 22023 (it was finished meanwhile).
  Future<void> _answer(
    UnfinishedWorkout workout,
    Map<String, Object> params,
  ) async {
    try {
      await _client.rpc('resolve_unfinished_workout_v1', params: params);
    } on PostgrestException catch (e) {
      final gone =
          e.code == 'P0002' ||
          e.code == '55000' ||
          (params['p_action'] == 'discard' && e.code == '22023');
      if (!gone) rethrow;
      if (e.code == '55000') await _dropDraftOf(workout);
      throw const UnfinishedWorkoutGone();
    }
  }

  /// Sends the phone's draft of [workout] (its sets and times) to its
  /// session, which takes them while it is closed as stale. Nothing is sent
  /// without a readable draft of that very session; a failed send throws.
  Future<void> _sendDraftOf(UnfinishedWorkout workout) async {
    final saved = await loadDraft(workout.plannedWorkoutId);
    if (saved == null) return;
    final Map<String, dynamic> draft;
    try {
      draft = decodeDraft(saved);
    } catch (error) {
      logNonCritical(error, 'workout draft not read');
      return;
    }
    if (draft['session_id'] != workout.sessionId) return;
    await syncDraft(
      this,
      workout.sessionId,
      (draft['revision'] as num?)?.toInt() ?? 0,
      serverDraftPayload(draft, workout.sessionId),
      readRows: () async {
        final value = await _client.rpc(
          'get_my_workout_session',
          params: {
            'p_planned_workout_id': workout.plannedWorkoutId,
            'p_local_date': workout.localDate.toIso8601String().substring(
              0,
              10,
            ),
          },
        );
        return value is Map && value['session_id'] == workout.sessionId
            ? value['exercises']
            : null;
      },
    );
  }

  /// This phone's draft and saved finish of an answered workout. Only the
  /// draft that belongs to that session goes: opening the planned workout
  /// again must not find it and send its sets into a session the server no
  /// longer takes them for, and a draft of a newer session of the same
  /// workout stays.
  Future<void> _dropDraftOf(UnfinishedWorkout workout) async {
    try {
      final saved = await loadDraft(workout.plannedWorkoutId);
      if (saved == null) return;
      if (decodeDraft(saved)['session_id'] != workout.sessionId) return;
      await clearDraft(workout.plannedWorkoutId);
    } catch (error) {
      logNonCritical(error, 'workout draft not removed');
    }
  }

  @override
  Future<PlannedWorkout> loadTodayWorkout() async {
    final weekday = DateTime.now().weekday;
    final rows = await _client
        .from('planned_workouts')
        .select(
          'id,name,objective,estimated_minutes,preferred_weekday,'
          'training_plan_versions!inner(status),'
          'planned_exercises(exercise_order,display_name_snapshot,set_count,rep_min,rep_max,target_rpe,rest_seconds,notes,target_load_kg,exercise_slug)',
        )
        .eq('training_plan_versions.status', 'active')
        .eq('preferred_weekday', weekday)
        .order('workout_order', ascending: true)
        .limit(1);
    if (rows.isEmpty) {
      throw const FormatException('No approved workout is assigned today.');
    }
    final row = rows.first;
    final exercises =
        (row['planned_exercises'] as List).cast<Map<String, dynamic>>()..sort(
          (a, b) => (a['exercise_order'] as int).compareTo(
            b['exercise_order'] as int,
          ),
        );
    return PlannedWorkout(
      id: row['id'] as String,
      name: row['name'] as String,
      objective: row['objective'] as String,
      estimatedMinutes: row['estimated_minutes'] as int,
      exercises: exercises
          .map(
            (e) => PlannedExercise(
              order: e['exercise_order'] as int,
              name: e['display_name_snapshot'] as String,
              setCount: e['set_count'] as int,
              repMin: e['rep_min'] as int,
              repMax: e['rep_max'] as int,
              targetRpe: e['target_rpe'] as num,
              restSeconds: e['rest_seconds'] as int? ?? 90,
              notes: e['notes'] as String? ?? '',
              targetLoadKg: e['target_load_kg'] as num?,
              exerciseSlug: e['exercise_slug'] as String?,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<String?> loadDraft(String workoutId) =>
      _preferences.getString(_draftKey(workoutId));
  @override
  Future<Map<String, dynamic>?> loadSession(
    PlannedWorkout workout, {
    DateTime? localDate,
  }) async {
    final date = localDate ?? DateTime.now();
    final waiting = await _replayDiscards();
    final value = await _client.rpc(
      'get_my_workout_session',
      params: {
        'p_planned_workout_id': workout.id,
        'p_local_date': date.toIso8601String().substring(0, 10),
      },
    );
    if (value is! Map) return null;
    // A workout discarded offline is gone for the athlete even while the
    // server still holds it in progress.
    if (waiting.contains(value['session_id'])) return null;
    return Map<String, dynamic>.from(value);
  }

  @override
  Future<void> saveDraft(String workoutId, String json) =>
      _preferences.setString(_draftKey(workoutId), json);
  @override
  Future<void> clearDraft(String workoutId) => _preferences.clear(
    allowList: {_draftKey(workoutId), _finishKey(workoutId)},
  );
  @override
  Future<String> start(
    PlannedWorkout workout,
    String idempotencyKey, {
    DateTime? localDate,
  }) async {
    final date = localDate ?? DateTime.now();
    final sessionId =
        await _client.rpc(
              'start_workout',
              params: {
                'p_planned_workout_id': workout.id,
                'p_local_date': date.toIso8601String().substring(0, 10),
                'p_timezone': DateTime.now().timeZoneName,
                'p_idempotency_key': idempotencyKey,
              },
            )
            as String;
    AppBreadcrumbs.workout('Workout started');
    return sessionId;
  }

  @override
  Future<void> sync(
    String sessionId,
    int revision,
    Map<String, dynamic> draft,
  ) async {
    await _client.rpc(
      'sync_workout_draft',
      params: {
        'session_id': sessionId,
        'client_revision': revision,
        'draft': draft,
      },
    );
  }

  @override
  Future<WorkoutCompletion> completeWithEffort(
    String sessionId,
    int revision,
    int durationSeconds,
    Map<String, dynamic> draft, {
    required int sessionEffort,
  }) async {
    final finish = PendingWorkoutFinish(
      sessionEffort: sessionEffort,
      durationSeconds: durationSeconds,
    );
    final workoutId = draft['workout_id'] as String?;
    if (workoutId != null) await savePendingFinish(workoutId, finish);
    if (sessionId.startsWith('pending-')) {
      throw const WorkoutSessionPendingException();
    }
    final completion = WorkoutCompletion.fromJson(
      await _client.rpc(
        'complete_workout_v2',
        params: {
          'session_id': sessionId,
          'client_revision': revision,
          'duration_seconds': durationSeconds,
          'session_effort': sessionEffort,
          'notes': draft['notes'] ?? '',
          'session_energy': null,
        },
      ),
    );
    if (workoutId != null) await clearDraft(workoutId);
    AppBreadcrumbs.workout(
      'Workout finished',
      data: {'effort_source': 'athlete', 'replayed': completion.replayed},
    );
    return completion;
  }

  @override
  Future<void> savePendingFinish(
    String workoutId,
    PendingWorkoutFinish finish,
  ) => _preferences.setString(
    _finishKey(workoutId),
    jsonEncode(finish.toJson()),
  );

  @override
  Future<PendingWorkoutFinish?> loadPendingFinish(String workoutId) async {
    final stored = await _preferences.getString(_finishKey(workoutId));
    if (stored == null) return null;
    try {
      return PendingWorkoutFinish.fromJson(jsonDecode(stored));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<WorkoutDiscard> abandon(
    String sessionId, {
    required String workoutId,
  }) async {
    await clearDraft(workoutId);
    if (sessionId.startsWith('pending-')) {
      // The server never created it, so there is nothing to discard there.
      AppBreadcrumbs.workout('Workout discarded', data: {'local_only': true});
      return const WorkoutDiscard();
    }
    try {
      final discard = await _sendDiscard(sessionId);
      AppBreadcrumbs.workout(
        'Workout discarded',
        data: {'replayed': discard.replayed},
      );
      return discard;
    } on PostgrestException catch (e) {
      if (_isDiscardRefusal(e)) rethrow;
      logNonCritical(e, 'discard waits for the server');
      return _queueDiscard(sessionId);
    } catch (e) {
      logNonCritical(e, 'discard waits for a connection');
      return _queueDiscard(sessionId);
    }
  }

  /// `abandon_workout` refuses a finished session (22023) and one that is
  /// not the athlete's (P0002). Those answers are final; any other server
  /// error is treated like a lost connection, so the discard is kept.
  static bool _isDiscardRefusal(PostgrestException e) =>
      e.code == '22023' || e.code == 'P0002';

  Future<WorkoutDiscard> _queueDiscard(String sessionId) async {
    final waiting = await _waitingDiscards();
    await _preferences.setStringList(_discardKey, [
      ...waiting.where((id) => id != sessionId),
      sessionId,
    ]);
    AppBreadcrumbs.workout('Workout discarded', data: {'queued': true});
    return const WorkoutDiscard(queued: true);
  }

  Future<WorkoutDiscard> _sendDiscard(String sessionId) async {
    final value = await _client.rpc(
      'abandon_workout',
      params: {'p_session_id': sessionId},
    );
    return WorkoutDiscard(replayed: value is Map && value['replayed'] == true);
  }

  Future<List<String>> _waitingDiscards() async =>
      await _preferences.getStringList(_discardKey) ?? const [];

  /// Sends discards saved offline. A final refusal (already finished, not
  /// found) settles it too; a connection failure or any other server error
  /// keeps it. Returns the ids still waiting.
  Future<Set<String>> _replayDiscards() async {
    final waiting = await _waitingDiscards();
    if (waiting.isEmpty) return const {};
    final kept = <String>[];
    for (final id in waiting) {
      try {
        await _sendDiscard(id);
      } on PostgrestException catch (e) {
        if (_isDiscardRefusal(e)) {
          logNonCritical(e, 'saved discard refused');
        } else {
          logNonCritical(e, 'saved discard still waiting');
          kept.add(id);
        }
      } catch (e) {
        logNonCritical(e, 'saved discard still waiting');
        kept.add(id);
      }
    }
    if (kept.isEmpty) {
      await _preferences.remove(_discardKey);
    } else {
      await _preferences.setStringList(_discardKey, kept);
    }
    if (kept.length < waiting.length) {
      AppBreadcrumbs.workout(
        'Saved discards sent',
        data: {'still_waiting': kept.isNotEmpty},
      );
    }
    return kept.toSet();
  }

  /// The RPC accepts at most this many keys per call.
  static const _historyKeysPerCall = 20;

  /// Exercises kept in the offline copy of the history.
  static const _historyCacheSize = 200;

  @override
  Future<ExerciseHistoryResult> loadExerciseHistory(
    List<String> keys, {
    int sessions = 8,
  }) async {
    final requested = exerciseHistoryKeys(keys);
    if (requested.isEmpty) {
      return const ExerciseHistoryResult(exercises: {});
    }
    final rows = <String, Map<String, dynamic>>{};
    try {
      for (var i = 0; i < requested.length; i += _historyKeysPerCall) {
        final value = await _client.rpc(
          'get_my_exercise_history',
          params: {
            'p_keys': requested.skip(i).take(_historyKeysPerCall).toList(),
            'p_sessions': sessions,
          },
        );
        final exercises = value is Map ? value['exercises'] : null;
        for (final row in exercises is List ? exercises : const []) {
          if (row is Map && row['key'] is String) {
            rows[row['key'] as String] = Map<String, dynamic>.from(row);
          }
        }
      }
    } catch (e) {
      logNonCritical(e, 'exercise history from device');
      final cached = await _cachedHistory();
      return ExerciseHistoryResult.fromJson({
        'exercises': [
          for (final key in requested)
            if (cached[key] != null) cached[key],
        ],
      }, fromCache: true);
    }
    await _saveHistory(rows);
    return ExerciseHistoryResult.fromJson({'exercises': rows.values.toList()});
  }

  Future<Map<String, Object?>> _cachedHistory() async {
    final stored = await _preferences.getString(_historyKey);
    if (stored == null) return const {};
    try {
      final decoded = jsonDecode(stored);
      return decoded is Map ? Map<String, Object?>.from(decoded) : const {};
    } on FormatException {
      return const {};
    }
  }

  /// Merges fresh answers into the offline copy, newest last, dropping the
  /// longest-unrequested exercises beyond [_historyCacheSize].
  Future<void> _saveHistory(Map<String, Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    try {
      final cache = Map<String, Object?>.of(await _cachedHistory())
        ..removeWhere((key, _) => rows.containsKey(key))
        ..addAll(rows);
      final overflow = cache.length - _historyCacheSize;
      if (overflow > 0) {
        cache.keys.take(overflow).toList().forEach(cache.remove);
      }
      await _preferences.setString(_historyKey, jsonEncode(cache));
    } catch (e) {
      logNonCritical(e, 'exercise history not saved');
    }
  }

  Future<void> autoCompleteFromHealthKit(
    String plannedWorkoutId,
    String localDate,
  ) async {
    await _client.rpc(
      'healthkit_auto_complete_workout',
      params: {
        'p_planned_workout_id': plannedWorkoutId,
        'p_local_date': localDate,
      },
    );
  }

  @override
  Future<HealthkitCompletionCandidate?> getHealthkitCandidate(
    DateTime date,
  ) async {
    final value = await _client.rpc(
      'get_healthkit_completion_candidate',
      params: {'p_local_date': date.toIso8601String().substring(0, 10)},
    );
    if (value == null || value is! Map || (value).isEmpty) return null;
    return _parseHealthkitCandidate(Map<String, dynamic>.from(value));
  }
}

class FixtureWorkoutRepository
    implements WorkoutRepository, TrainingHubRepository {
  String? _draft;
  @override
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28}) async =>
      const TrainingHubData(
        planTitle: 'Approved training plan',
        workouts: [PlannedWorkout.fixture],
        recentSessions: [],
        completedSessions: 0,
        plannedSessions: 4,
        progression: [],
      );
  @override
  Future<PlannedWorkout> loadTodayWorkout() async => PlannedWorkout.fixture;
  @override
  Future<String?> loadDraft(String workoutId) async => _draft;
  @override
  Future<Map<String, dynamic>?> loadSession(
    PlannedWorkout workout, {
    DateTime? localDate,
  }) async => null;
  @override
  Future<void> saveDraft(String workoutId, String json) async => _draft = json;
  @override
  Future<void> clearDraft(String workoutId) async => _draft = null;
  @override
  Future<String> start(
    PlannedWorkout workout,
    String idempotencyKey, {
    DateTime? localDate,
  }) async => 'local-$idempotencyKey';
  @override
  Future<void> sync(
    String sessionId,
    int revision,
    Map<String, dynamic> draft,
  ) async {}
  @override
  Future<WorkoutCompletion> completeWithEffort(
    String sessionId,
    int revision,
    int durationSeconds,
    Map<String, dynamic> draft, {
    required int sessionEffort,
  }) async {
    RangeError.checkValueInInterval(sessionEffort, 1, 10, 'sessionEffort');
    await clearDraft(draft['workout_id'] as String? ?? 'fixture');
    return const WorkoutCompletion(replayed: false);
  }

  @override
  Future<void> savePendingFinish(
    String workoutId,
    PendingWorkoutFinish finish,
  ) async {}

  @override
  Future<PendingWorkoutFinish?> loadPendingFinish(String workoutId) async =>
      null;

  @override
  Future<WorkoutDiscard> abandon(
    String sessionId, {
    required String workoutId,
  }) async {
    await clearDraft(workoutId);
    return const WorkoutDiscard();
  }

  /// Fixture mode has no past workouts: every exercise is a first log.
  @override
  Future<ExerciseHistoryResult> loadExerciseHistory(
    List<String> keys, {
    int sessions = 8,
  }) async => ExerciseHistoryResult(
    exercises: {
      for (final key in exerciseHistoryKeys(keys))
        key: ExerciseHistory(key: key),
    },
  );
}

/// The keys `get_my_exercise_history` accepts: trimmed, 1 to 120
/// characters, each once, in the order given.
List<String> exerciseHistoryKeys(Iterable<String> keys) => {
  for (final key in keys)
    if (key.trim().isNotEmpty && key.trim().length <= 120) key.trim(),
}.toList();

/// This device's workout storage for one athlete, so account deletion can
/// remove all of it.
abstract final class WorkoutLocalKeys {
  static String draftPrefix(String userId) => 'workout_draft_${userId}_';
  static String finishPrefix(String userId) => 'workout_finish_${userId}_';
  static String discards(String userId) => 'workout_discards_$userId';
  static String exerciseHistory(String userId) => 'exercise_history_$userId';

  static bool owns(String userId, String key) =>
      key.startsWith(draftPrefix(userId)) ||
      key.startsWith(finishPrefix(userId)) ||
      key == discards(userId) ||
      key == exerciseHistory(userId) ||
      key == TrainingHubCache.keyFor(userId) ||
      key == TrainingHubCache.safetyKeyFor(userId);
}

Map<String, dynamic> decodeDraft(String value) =>
    Map<String, dynamic>.from(jsonDecode(value) as Map);

/// [draft] has a set marked done.
bool draftHasDoneSet(Map<String, dynamic> draft) {
  final exercises = draft['exercises'];
  if (exercises is! List) return false;
  return exercises.any(
    (exercise) =>
        exercise is Map &&
        exercise['sets'] is List &&
        (exercise['sets'] as List).any(
          (set) => set is Map && set['completed'] == true,
        ),
  );
}

/// What [sendLeftOverDraft] did: [settled] when nothing is left on this phone
/// that the server lacks, and the id of the planned workout the draft ended
/// up under ([PlannedWorkout.id] unless the plan was copied meanwhile).
typedef LeftOverResult = ({bool settled, String workoutId});

/// Sends what the phone's [draft] of [workout] holds that the server may not
/// have: its sets, and its finish when one was saved. [LeftOverResult.settled]
/// is true when nothing is left on this phone that the server lacks, so the
/// draft may go: no set was done and no finish waits, or everything reached
/// the server. False keeps the draft (offline, or a draft whose session was
/// never created and has no finish to send). A session that no longer takes
/// sets or a finish (55000: it was saved or discarded already, say by an
/// earlier try whose answer was lost) is settled: nothing of the draft can
/// reach it, so it goes and never opens as a workout.
///
/// A start the server answers with "planned workout not found" (P0002) means
/// the plan was copied with new ids since the draft was made: the workout is
/// found again in the current plan by its place and exercises, the draft moves
/// to it, and the start is made again under the same key. With no such
/// workout the draft stays.
Future<LeftOverResult> sendLeftOverDraft(
  WorkoutRepository repository,
  PlannedWorkout workout,
  Map<String, dynamic> draft,
) async {
  // Whose draft this is: the athlete signed in now. A start that hangs while
  // another athlete signs in must not move or send this draft under theirs.
  final owner = repository is WorkoutPlanRemapper
      ? (repository as WorkoutPlanRemapper).signedInUserId
      : null;
  var current = workout;
  var data = draft;
  try {
    final finish = await repository.loadPendingFinish(current.id);
    if (finish == null && !draftHasDoneSet(data)) {
      return (settled: true, workoutId: current.id);
    }
    var id = data['session_id'] as String?;
    final started = DateTime.tryParse('${data['actual_started_at'] ?? ''}');
    if (id == null || id.startsWith('pending-')) {
      final key = data['idempotency_key'] as String?;
      if (finish == null || key == null || started == null) {
        return (settled: false, workoutId: current.id);
      }
      try {
        id = await repository.start(current, key, localDate: started.toLocal());
      } on PostgrestException catch (e) {
        final moved = e.code == 'P0002' && repository is WorkoutPlanRemapper
            ? await (repository as WorkoutPlanRemapper).moveToCurrentPlan(
                current.id,
                WorkoutIdentity.fromJson(data['workout_identity']) ??
                    current.identity,
                ownerId: owner,
              )
            : null;
        if (moved == null) rethrow;
        if ((repository as WorkoutPlanRemapper).signedInUserId != owner) {
          return (settled: false, workoutId: current.id);
        }
        current = moved;
        data = {...data, 'workout_id': moved.id};
        id = await repository.start(current, key, localDate: started.toLocal());
      }
    }
    final revision = (data['revision'] as num?)?.toInt() ?? 0;
    final sessionId = id;
    final sent = await syncDraft(
      repository,
      sessionId,
      revision,
      serverDraftPayload(data, sessionId),
      readRows: () async {
        // The session of the day the draft was made on, not today's.
        final session = await repository.loadSession(
          current,
          localDate: started?.toLocal(),
        );
        return session != null && session['session_id'] == sessionId
            ? session['exercises']
            : null;
      },
    );
    if (finish != null) {
      await repository.completeWithEffort(
        sessionId,
        revision,
        finish.durationSeconds,
        sent,
        sessionEffort: finish.sessionEffort,
      );
    }
    AppBreadcrumbs.workout(
      'Earlier workout sent',
      data: {'finished': finish != null},
    );
    return (settled: true, workoutId: current.id);
  } on PostgrestException catch (e) {
    if (e.code == '55000') {
      logNonCritical(e, 'earlier workout already settled');
      return (settled: true, workoutId: current.id);
    }
    logNonCritical(e, 'earlier workout kept on the phone');
    return (settled: false, workoutId: current.id);
  } catch (e) {
    logNonCritical(e, 'earlier workout kept on the phone');
    return (settled: false, workoutId: current.id);
  }
}

/// The keys of a saved draft that the server reads; the rest only this phone
/// needs.
const _serverDraftKeys = [
  'workout_id',
  'session_id',
  'idempotency_key',
  'revision',
  'exercises',
  'notes',
];

/// The five set keys the server may refuse when this phone's times are off.
const _timingKeys = [
  'started_at',
  'completed_at',
  'rest_before_seconds',
  'rir',
  'timing_source',
];

/// What the server reads of [draft], for session [sessionId].
Map<String, dynamic> serverDraftPayload(
  Map<String, dynamic> draft,
  String sessionId,
) => {
  for (final key in _serverDraftKeys)
    if (draft.containsKey(key)) key: draft[key],
  'session_id': sessionId,
};

/// Reads the exercises of a session as `get_my_workout_session` gives them
/// (each with its `order` and `sets` rows), or null when they cannot be read:
/// offline, or a session the stale-workout rule closed, which that read no
/// longer returns.
typedef SessionRowsReader = Future<Object?> Function();

/// Sends [payload] with `sync_workout_draft` and returns what was sent.
///
/// The server decides how many set rows an exercise has (`start_workout`
/// applies the athlete's accepted same-day answer: fewer sets, or none for an
/// exercise left out for a joint), and it refuses a set number it does not
/// have. A saved draft that never read those rows (`rows_aligned: false`)
/// can hold sets the server never made, so the rows are read first through
/// [readRows] and the payload is made to fit them by [alignPayloadToRows].
/// A set with something on it is never dropped; it stays in the draft and the
/// server's refusal is the athlete's to see. When the server refuses the set
/// times (22023, a phone clock that is off) the sets are sent again without
/// them.
Future<Map<String, dynamic>> syncDraft(
  WorkoutRepository repository,
  String sessionId,
  int revision,
  Map<String, dynamic> payload, {
  SessionRowsReader? readRows,
}) async {
  Object? rows;
  try {
    rows = await readRows?.call();
  } on Object catch (error) {
    logNonCritical(error, 'session rows not read');
  }
  final fitted = alignPayloadToRows(payload, rows);
  try {
    await repository.sync(sessionId, revision, fitted);
    return fitted;
  } on PostgrestException catch (e) {
    if (e.code != '22023') rethrow;
    final untimed = _withoutTiming(fitted);
    await repository.sync(sessionId, revision, untimed);
    return untimed;
  }
}

/// A set of a draft payload with nothing on it: not done, and no load, reps or
/// effort entered.
bool _blankSet(Object? set) {
  if (set is! Map) return false;
  bool empty(Object? value) => value == null || '$value'.trim().isEmpty;
  return set['completed'] != true &&
      empty(set['load_kg']) &&
      empty(set['repetitions']) &&
      empty(set['rpe']);
}

/// [payload] with each exercise's sets made to fit the rows the server holds
/// for it: trailing blank sets beyond the row count go (they say nothing the
/// server lacks). With [rows] unreadable (null), every trailing blank set
/// goes, which is safe for the same reason: the server's rows are never
/// fewer than the sets that have something on them, or it would already have
/// refused them. A set with entries is never dropped.
Map<String, dynamic> alignPayloadToRows(
  Map<String, dynamic> payload,
  Object? rows,
) {
  final exercises = payload['exercises'];
  if (exercises is! List) return payload;
  final counts = <int, int>{
    if (rows is List)
      for (final row in rows)
        if (row is Map && row['order'] is num && row['sets'] is List)
          (row['order'] as num).toInt(): (row['sets'] as List).length,
  };
  return {
    ...payload,
    'exercises': [
      for (final exercise in exercises)
        if (exercise is Map && exercise['sets'] is List)
          {
            ...Map<String, dynamic>.from(exercise),
            'sets': _fitSets(
              List<Object?>.of(exercise['sets'] as List),
              counts[(exercise['order'] as num?)?.toInt()],
            ),
          }
        else
          exercise,
    ],
  };
}

List<Object?> _fitSets(List<Object?> sets, int? rowCount) {
  while (sets.isNotEmpty &&
      _blankSet(sets.last) &&
      (rowCount == null || sets.length > rowCount)) {
    sets.removeLast();
  }
  return sets;
}

Map<String, dynamic> _withoutTiming(Map<String, dynamic> payload) => {
  ...payload,
  'exercises': [
    for (final exercise in payload['exercises'] as List)
      {
        ...(exercise as Map<String, dynamic>),
        'sets': [
          for (final set in exercise['sets'] as List)
            {
              for (final entry in (set as Map<String, dynamic>).entries)
                if (!_timingKeys.contains(entry.key)) entry.key: entry.value,
            },
        ],
      },
  ],
};
