import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';

/// One planned exercise of today's workout, with the brief's own row for the
/// fields only some readers need (rep range, load).
typedef TodayPlannedExercise = ({
  int order,
  String name,
  int sets,
  Map<String, dynamic> row,
});

/// Where today's session stands, read once from the brief for every surface
/// that shows it (the session card and the widgets' snapshot).
class TodaySessionProgress {
  const TodaySessionProgress._({
    required this.state,
    required this.exercises,
    required this.total,
    required this.logged,
    required Map<int, int> completedSets,
  }) : _completedSets = completedSets;

  /// `rest` (no workout), `planned`, `in_progress` or `completed`.
  final String state;

  /// Every planned exercise, in the plan's order. Sets are capped at 12.
  final List<TodayPlannedExercise> exercises;

  /// Prescribed sets across all exercises.
  final int total;

  /// Logged sets, each exercise capped at its prescribed sets.
  final int logged;

  final Map<int, int> _completedSets;

  /// Sets logged for [exercise], never more than it prescribes.
  int doneFor(TodayPlannedExercise exercise) =>
      (_completedSets[exercise.order] ?? 0).clamp(0, exercise.sets);

  /// [adjustment] is today's same-day adjustment: once the athlete accepted a
  /// lighter session, each exercise counts the sets it was cut to. It is used
  /// only for the workout it is about, on the day it is for.
  factory TodaySessionProgress.of(
    DailyBrief brief, {
    DayAdjustment? adjustment,
  }) {
    final workout = brief.workout;
    final cut =
        adjustment != null &&
            adjustment.easesSession &&
            adjustment.localDate == brief.localDate &&
            workout != null &&
            adjustment.plannedWorkoutId == workout['id']
        ? {
            for (final change in adjustment.appliedChanges)
              change.exerciseOrder: change.setsTo,
          }
        : const <int, int>{};
    final exercises = <TodayPlannedExercise>[
      for (final item in (workout?['exercises'] as List? ?? const []))
        if (item is Map)
          (
            order: (item['order'] as num?)?.toInt() ?? 0,
            name: item['name'] as String? ?? 'Exercise',
            sets:
                (cut[(item['order'] as num?)?.toInt() ?? 0] ??
                        (item['set_count'] as num?)?.toInt() ??
                        0)
                    .clamp(0, 12),
            row: Map<String, dynamic>.from(item),
          ),
    ];
    final session = brief.todaySession;
    final completed = session?.completedSets ?? const <int, int>{};
    return TodaySessionProgress._(
      state: workout == null
          ? 'rest'
          : session == null
          ? 'planned'
          : session.completed
          ? 'completed'
          : 'in_progress',
      exercises: exercises,
      total: exercises.fold(0, (sum, e) => sum + e.sets),
      logged: exercises.fold(
        0,
        (sum, e) => sum + (completed[e.order] ?? 0).clamp(0, e.sets),
      ),
      completedSets: completed,
    );
  }
}
