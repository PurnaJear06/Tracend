import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  });
  final int order;
  final String name;
  final int setCount;
  final int repMin;
  final int repMax;
  final num targetRpe;
  final int restSeconds;
  final String notes;
}

class PlannedWorkout {
  const PlannedWorkout({
    required this.id,
    required this.name,
    required this.objective,
    required this.estimatedMinutes,
    required this.exercises,
    this.weekday,
    this.warmUp = '',
    this.cooldownCardio = '',
  });
  final String id;
  final String name;
  final String objective;
  final int estimatedMinutes;
  final List<PlannedExercise> exercises;
  final int? weekday;
  final String warmUp;
  final String cooldownCardio;

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

class TrainingSessionSummary {
  const TrainingSessionSummary({
    required this.name,
    required this.date,
    this.durationSeconds,
  });
  final String name;
  final DateTime date;
  final int? durationSeconds;
}

class ExerciseProgression {
  const ExerciseProgression({
    required this.exercise,
    required this.sessions,
    this.bestLoadKg,
    this.bestRepetitions,
  });
  final String exercise;
  final int sessions;
  final num? bestLoadKg;
  final int? bestRepetitions;
}

class TrainingHubData {
  const TrainingHubData({
    required this.planTitle,
    required this.workouts,
    required this.recentSessions,
    required this.completedSessions,
    required this.plannedSessions,
    required this.progression,
  });
  final String planTitle;
  final List<PlannedWorkout> workouts;
  final List<TrainingSessionSummary> recentSessions;
  final int completedSessions;
  final int plannedSessions;
  final List<ExerciseProgression> progression;

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

abstract interface class WorkoutRepository {
  Future<PlannedWorkout> loadTodayWorkout();
  Future<String?> loadDraft();
  Future<void> saveDraft(String json);
  Future<void> clearDraft();
  Future<String> start(PlannedWorkout workout, String idempotencyKey);
  Future<void> sync(String sessionId, int revision, Map<String, dynamic> draft);
  Future<void> complete(
    String sessionId,
    int revision,
    int durationSeconds,
    Map<String, dynamic> draft,
  );
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
    implements WorkoutRepository, TrainingHubRepository {
  SupabaseWorkoutRepository(this._client, this._preferences);
  final SupabaseClient _client;
  final SharedPreferencesAsync _preferences;
  String get _draftKey => 'workout_draft_${_client.auth.currentUser!.id}';

  @override
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28}) async {
    final value = Map<String, dynamic>.from(
      await _client.rpc(
            'get_my_training_hub',
            params: {'period_days': periodDays},
          )
          as Map,
    );
    final active = value['active_plan'] is Map
        ? Map<String, dynamic>.from(value['active_plan'] as Map)
        : const <String, dynamic>{};
    final workouts = (value['workouts'] as List? ?? const [])
        .map((item) => _workoutFromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final adherence = value['adherence'] is Map
        ? Map<String, dynamic>.from(value['adherence'] as Map)
        : const <String, dynamic>{};
    return TrainingHubData(
      planTitle: active['title'] as String? ?? 'Approved plan',
      workouts: workouts,
      recentSessions: (value['recent_sessions'] as List? ?? const []).map((
        item,
      ) {
        final row = Map<String, dynamic>.from(item as Map);
        return TrainingSessionSummary(
          name: row['name'] as String,
          date: DateTime.parse(row['local_date'] as String),
          durationSeconds: (row['duration_seconds'] as num?)?.toInt(),
        );
      }).toList(),
      completedSessions: (adherence['completed_sessions'] as num? ?? 0).toInt(),
      plannedSessions: (adherence['planned_sessions'] as num? ?? 0).toInt(),
      progression: (value['progression'] as List? ?? const []).map((item) {
        final row = Map<String, dynamic>.from(item as Map);
        return ExerciseProgression(
          exercise: row['exercise'] as String,
          sessions: (row['sessions'] as num).toInt(),
          bestLoadKg: row['best_load_kg'] as num?,
          bestRepetitions: (row['best_repetitions'] as num?)?.toInt(),
        );
      }).toList(),
    );
  }

  PlannedWorkout _workoutFromJson(Map<String, dynamic> row) => PlannedWorkout(
    id: row['id'] as String,
    name: row['name'] as String,
    objective: row['objective'] as String,
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
      );
    }).toList(),
  );

  @override
  Future<PlannedWorkout> loadTodayWorkout() async {
    final weekday = DateTime.now().weekday;
    final rows = await _client
        .from('planned_workouts')
        .select(
          'id,name,objective,estimated_minutes,preferred_weekday,'
          'training_plan_versions!inner(status),'
          'planned_exercises(exercise_order,display_name_snapshot,set_count,rep_min,rep_max,target_rpe,rest_seconds,notes)',
        )
        .eq('training_plan_versions.status', 'active')
        .eq('preferred_weekday', weekday)
        .order('workout_order')
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
            ),
          )
          .toList(),
    );
  }

  @override
  Future<String?> loadDraft() => _preferences.getString(_draftKey);
  @override
  Future<void> saveDraft(String json) =>
      _preferences.setString(_draftKey, json);
  @override
  Future<void> clearDraft() => _preferences.remove(_draftKey);
  @override
  Future<String> start(PlannedWorkout workout, String idempotencyKey) async =>
      await _client.rpc(
            'start_workout',
            params: {
              'p_planned_workout_id': workout.id,
              'p_local_date': DateTime.now().toIso8601String().substring(0, 10),
              'p_timezone': DateTime.now().timeZoneName,
              'p_idempotency_key': idempotencyKey,
            },
          )
          as String;
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
  Future<void> complete(
    String sessionId,
    int revision,
    int durationSeconds,
    Map<String, dynamic> draft,
  ) async {
    await _client.rpc(
      'complete_workout',
      params: {
        'session_id': sessionId,
        'client_revision': revision,
        'duration_seconds': durationSeconds,
        'session_energy': 3,
        'session_effort': 8,
        'notes': draft['notes'] ?? '',
      },
    );
    await clearDraft();
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
  Future<String?> loadDraft() async => _draft;
  @override
  Future<void> saveDraft(String json) async => _draft = json;
  @override
  Future<void> clearDraft() async => _draft = null;
  @override
  Future<String> start(PlannedWorkout workout, String idempotencyKey) async =>
      'local-$idempotencyKey';
  @override
  Future<void> sync(
    String sessionId,
    int revision,
    Map<String, dynamic> draft,
  ) async {}
  @override
  Future<void> complete(
    String sessionId,
    int revision,
    int durationSeconds,
    Map<String, dynamic> draft,
  ) => clearDraft();
}

Map<String, dynamic> decodeDraft(String value) =>
    Map<String, dynamic>.from(jsonDecode(value) as Map);
