import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/train/exercise_history.dart';
import 'package:tracend/features/train/muscle_groups.dart';
import 'package:tracend/features/train/workout_repository.dart';

/// Train screen fixtures: the prototype's week, Friday 2 October 2026.
final trainToday = DateTime(2026, 10, 2);

DateTime trainNow() => DateTime(2026, 10, 2, 9);

PlannedExercise _ex(
  int order,
  String name,
  int sets,
  int min,
  int max, {
  num? kg,
  List<MuscleGroup> muscles = const [],
  bool linked = true,
  String notes = '',
}) => PlannedExercise(
  order: order,
  name: name,
  setCount: sets,
  repMin: min,
  repMax: max,
  targetRpe: 8,
  restSeconds: sets == 3 ? 120 : 75,
  targetLoadKg: kg,
  notes: notes,
  exerciseSlug: linked ? name.toLowerCase().replaceAll(' ', '-') : null,
  primaryMuscles: linked ? muscles : const [],
);

final upperA = PlannedWorkout(
  id: 'w-upper-a',
  name: 'Upper body A',
  objective: 'Build pressing and pulling strength with steady volume.',
  estimatedMinutes: 48,
  weekday: 5,
  warmUp: '5 minutes easy rowing, then two light sets of bench press.',
  cooldownCardio: '10 minutes easy walking.',
  exercises: [
    _ex(
      1,
      'Bench press',
      3,
      6,
      8,
      kg: 72.5,
      muscles: const [MuscleGroup.chest, MuscleGroup.triceps],
      notes: 'If all three sets reach 8 reps, add 2.5 kg next time.',
    ),
    _ex(
      2,
      'Barbell row',
      3,
      8,
      10,
      kg: 62.5,
      muscles: const [MuscleGroup.back, MuscleGroup.biceps],
    ),
    _ex(
      3,
      'Overhead press',
      3,
      8,
      8,
      kg: 40,
      muscles: const [MuscleGroup.shoulders, MuscleGroup.triceps],
    ),
    _ex(
      4,
      'Lat pulldown',
      3,
      10,
      12,
      kg: 55,
      muscles: const [MuscleGroup.back, MuscleGroup.biceps],
    ),
    _ex(5, 'Cable fly', 2, 12, 12, kg: 12, linked: false),
    _ex(
      6,
      'Triceps pushdown',
      2,
      12,
      12,
      kg: 25,
      muscles: const [MuscleGroup.triceps],
    ),
  ],
);

final upperB = PlannedWorkout(
  id: 'w-upper-b',
  name: 'Upper body B',
  objective: 'Volume for the upper body.',
  estimatedMinutes: 46,
  weekday: 2,
  exercises: [
    _ex(
      1,
      'Incline bench press',
      3,
      8,
      8,
      kg: 50,
      muscles: const [MuscleGroup.chest],
    ),
    _ex(2, 'Pull-up', 3, 6, 6, muscles: const [MuscleGroup.back]),
  ],
);

final lowerA = PlannedWorkout(
  id: 'w-lower-a',
  name: 'Lower body A',
  objective: 'Squat strength.',
  estimatedMinutes: 52,
  weekday: 3,
  exercises: [
    _ex(
      1,
      'Back squat',
      3,
      5,
      5,
      kg: 90,
      muscles: const [MuscleGroup.quads, MuscleGroup.glutes],
    ),
    _ex(
      2,
      'Romanian deadlift',
      3,
      8,
      8,
      kg: 80,
      muscles: const [MuscleGroup.hamstrings, MuscleGroup.glutes],
    ),
  ],
);

final lowerB = PlannedWorkout(
  id: 'w-lower-b',
  name: 'Lower body B',
  objective: 'Hinge strength.',
  estimatedMinutes: 50,
  weekday: 7,
  exercises: [
    _ex(
      1,
      'Deadlift',
      3,
      5,
      5,
      kg: 110,
      muscles: const [MuscleGroup.glutes, MuscleGroup.hamstrings],
    ),
  ],
);

/// 28 days ending today; Tuesday and Wednesday this week are done.
List<DailyLoadDay> trainLoad({bool calibrating = false, bool fresh = false}) {
  final trained = <int, (int, double)>{
    if (!fresh) ...{
      27: (45, 30),
      25: (50, 35),
      22: (48, 30),
      20: (52, 38),
      18: (46, 28),
      15: (50, 33),
      13: (48, 30),
      11: (52, 36),
      8: (46, 28),
      6: (48, 28.8),
      5: (50, 40),
    },
    3: (46, 32.2),
    2: (52, 41.6),
  };
  return [
    for (var back = 27; back >= 0; back--)
      () {
        final date = trainToday.subtract(Duration(days: back));
        final day = trained[back];
        final defaulted = calibrating && back >= 5 && day != null;
        return DailyLoadDay(
          date: date,
          recorded: day != null,
          strain: day?.$2 ?? 0,
          minutes: day?.$1 ?? 0,
          sessions: day == null ? 0 : 1,
          effortReported: day != null && !defaulted,
          level: day == null
              ? DayLoadLevel.rest
              : defaulted
              ? null
              : day.$2 <= 30
              ? DayLoadLevel.easy
              : day.$2 <= 40
              ? DayLoadLevel.moderate
              : DayLoadLevel.hard,
        );
      }(),
  ];
}

TrainingHubData trainHub({
  bool calibrating = false,
  bool fresh = false,
  List<TrainingSessionSummary>? sessions,
  Set<DateTime>? completed,
  bool withPlan = true,
  List<PlannedWorkout>? workouts,
}) => TrainingHubData(
  planTitle: 'Strength foundation',
  plan: withPlan
      ? ActivePlanSummary(
          title: 'Strength foundation',
          blockWeeks: 6,
          sessionsPerWeek: 4,
          effectiveDate: DateTime(2026, 9, 16),
          approvedOn: DateTime(2026, 9, 15),
          progressionRule:
              'When every set reaches the top of its rep range, add the '
              'smallest weight step next time.',
        )
      : null,
  localToday: trainToday,
  workouts: workouts ?? [upperA, upperB, lowerA, lowerB],
  recentSessions:
      sessions ??
      [
        TrainingSessionSummary(
          name: 'Lower body A',
          date: DateTime(2026, 9, 30),
          durationSeconds: 3120,
          workoutId: lowerA.id,
          completionSource: CompletionSource.manual,
          effortSource: EffortSource.athlete,
        ),
        TrainingSessionSummary(
          name: 'Upper body B',
          date: DateTime(2026, 9, 29),
          durationSeconds: 2760,
          workoutId: upperB.id,
          completionSource: CompletionSource.healthkit,
          effortSource: EffortSource.healthkitDefault,
        ),
      ],
  completedSessions: 2,
  plannedSessions: 4,
  progression: const [],
  completedDays: completed ?? {DateTime(2026, 9, 29), DateTime(2026, 9, 30)},
  dailyLoad: trainLoad(calibrating: calibrating, fresh: fresh),
  load: fresh
      ? const HubLoadMetrics(acwr: 1.4)
      : const HubLoadMetrics(acwr: 1.07, trainingMonotony: 1.6),
);

/// A hub repository with controllable history and session answers.
class TrainFixtureRepository extends FixtureWorkoutRepository
    implements HealthkitCandidateRepository {
  TrainFixtureRepository({
    TrainingHubData? hub,
    this.history,
    this.historyError,
    this.session,
    this.candidate,
    this.hubError,
  }) : hub = hub ?? trainHub();

  TrainingHubData hub;
  ExerciseHistoryResult? history;
  Object? historyError;
  Map<String, dynamic>? session;
  HealthkitCompletionCandidate? candidate;
  Object? hubError;
  int hubLoads = 0;
  final List<List<String>> historyRequests = [];

  @override
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28}) async {
    hubLoads++;
    if (hubError != null) throw hubError!;
    return hub;
  }

  @override
  Future<ExerciseHistoryResult> loadExerciseHistory(
    List<String> keys, {
    int sessions = 8,
  }) async {
    historyRequests.add(keys);
    if (historyError != null) throw historyError!;
    return history ?? benchHistory();
  }

  @override
  Future<Map<String, dynamic>?> loadSession(
    PlannedWorkout workout, {
    DateTime? localDate,
  }) async => session;

  @override
  Future<HealthkitCompletionCandidate?> getHealthkitCandidate(
    DateTime date,
  ) async =>
      candidate != null &&
          candidate!.localDate.year == date.year &&
          candidate!.localDate.month == date.month &&
          candidate!.localDate.day == date.day
      ? candidate
      : null;
}

ExerciseHistoryResult benchHistory({bool fromCache = false}) =>
    ExerciseHistoryResult.fromJson({
      'exercises': [
        {
          'key': 'bench-press',
          'kind': 'load',
          'last_session': {
            'local_date': '2026-09-25',
            'sets': [
              {'set_number': 1, 'load_kg': 70, 'repetitions': 8},
              {'set_number': 2, 'load_kg': 70, 'repetitions': 8},
              {'set_number': 3, 'load_kg': 70, 'repetitions': 7},
            ],
          },
          'best_set': {
            'kind': 'load',
            'load_kg': 72.5,
            'repetitions': 6,
            'local_date': '2026-09-18',
          },
          'top_sets': [
            {'local_date': '2026-09-25', 'load_kg': 70, 'repetitions': 8},
            {'local_date': '2026-09-18', 'load_kg': 72.5, 'repetitions': 6},
            {'local_date': '2026-09-11', 'load_kg': 67.5, 'repetitions': 8},
            {'local_date': '2026-09-04', 'load_kg': 65, 'repetitions': 8},
          ],
        },
      ],
    }, fromCache: fromCache);

ComputedMetrics trainComputed({int? recovery = 84}) => ComputedMetrics(
  scores: ComputedScores(recovery: recovery, acwr: 1.07),
  baselines: const ComputedBaselines(
    hrv: BaselineMetric(ewma: 4.0, spread: 0.2, nObs: 30, confidence: 'high'),
    restingHr: BaselineMetric(
      ewma: 55,
      spread: 3,
      nObs: 30,
      confidence: 'high',
    ),
    sleepMinutes: BaselineMetric(
      ewma: 420,
      spread: 30,
      nObs: 30,
      confidence: 'high',
    ),
  ),
  dataConfidence: 'high',
  todayRaw: const TodayRaw(hrvMs: 58, restingHrBpm: 54, sleepMinutes: 462),
);

class TrainBriefRepository implements DailyBriefRepository {
  TrainBriefRepository({this.computed, this.health = true, this.error});

  final ComputedMetrics? computed;
  final bool health;
  final Object? error;

  @override
  Future<DailyBrief> load(DateTime date) async {
    if (error != null) throw error!;
    return DailyBrief(
      localDate: '2026-10-02',
      computed: computed,
      health: health ? const {'local_date': '2026-10-02'} : null,
    );
  }
}

class TrainCoachRepository extends FixtureCoachRepository {
  const TrainCoachRepository();

  @override
  Future<CoachDecision?> loadLatest() async => CoachDecision(
    id: 'decision-1',
    localDate: '2026-10-02',
    trainingAction: 'Proceed',
    trainingSummary: 'Train as planned.',
    nutritionAction: 'Keep',
    nutritionSummary: 'Keep intake.',
    finalDecision: 'Train as planned.',
    reason: 'Evidence supports the plan.',
    confidence: 'high',
    evidence: const [],
    missingData: const [],
    riskFlags: const [],
    createdAt: DateTime(2026, 10, 2),
  );
}
