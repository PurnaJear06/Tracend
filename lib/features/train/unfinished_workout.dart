/// A workout the athlete logged sets in and never finished. The server closes
/// a session left open since an earlier day (`private.abandon_stale_workouts`)
/// and offers it back for 7 days, because finishing it for the athlete would
/// write a workout they did not confirm. Only the athlete's Save puts it in
/// their history, and Discard keeps it out for good.
library;

/// The workout the server offers back (`get_my_unfinished_workout_v1`).
class UnfinishedWorkout {
  const UnfinishedWorkout({
    required this.sessionId,
    required this.plannedWorkoutId,
    required this.name,
    required this.localDate,
    required this.loggedSets,
    required this.totalSets,
  });

  /// Reads the payload's `workout`; null when it is not one this build
  /// understands, so a malformed answer never shows a card.
  static UnfinishedWorkout? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final sessionId = raw['session_id'];
    final plannedWorkoutId = raw['planned_workout_id'];
    final name = raw['name'];
    final localDate = raw['local_date'];
    final logged = raw['logged_sets'];
    final total = raw['total_sets'];
    if (sessionId is! String ||
        plannedWorkoutId is! String ||
        name is! String ||
        localDate is! String ||
        logged is! num ||
        total is! num) {
      return null;
    }
    final date = DateTime.tryParse(localDate);
    if (date == null) return null;
    return UnfinishedWorkout(
      sessionId: sessionId,
      plannedWorkoutId: plannedWorkoutId,
      name: name,
      localDate: DateTime(date.year, date.month, date.day),
      loggedSets: logged.toInt(),
      totalSets: total.toInt(),
    );
  }

  final String sessionId;
  final String plannedWorkoutId;
  final String name;

  /// The day it was logged on, as a date with no time.
  final DateTime localDate;
  final int loggedSets;
  final int totalSets;

  /// Sets the plan had that were never logged.
  int get unloggedSets => totalSets > loggedSets ? totalSets - loggedSets : 0;
}

abstract interface class UnfinishedWorkoutRepository {
  /// The newest workout offered back, or null.
  Future<UnfinishedWorkout?> loadUnfinishedWorkout();

  /// Completes [workout] on its own day with the athlete's own
  /// [sessionEffort], a whole number from 1 to 10. A phone's copy of its
  /// unsent draft goes with it.
  Future<void> saveUnfinishedWorkout(
    UnfinishedWorkout workout, {
    required int sessionEffort,
  });

  /// Keeps [workout] out of the athlete's history for good. A phone's copy of
  /// its unsent draft goes with it.
  Future<void> discardUnfinishedWorkout(UnfinishedWorkout workout);
}
