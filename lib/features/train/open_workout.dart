/// Workouts left open on this phone: a draft with a set done and no finish
/// waiting, whatever day it is logged under. Train and Today offer them back
/// with a Resume card, a day that holds one says "In progress", and the Live
/// Activity reopens the newest. The lookup reads only this phone's drafts, so
/// it works with no connection.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The local draft field with the day the session is logged under
/// (`YYYY-MM-DD`). A draft saved before it was kept has none, and its day is
/// then the day it began.
const sessionDateDraftKey = 'session_local_date';

/// The local draft field with the workout's name, so a Resume card can name
/// it without the plan.
const workoutNameDraftKey = 'workout_name';

/// What the athlete is told when a workout they reopen was filed on its own
/// day by the send of waiting workouts meanwhile: it is answered on Today.
const workoutFiledMessage =
    'This workout was sent to Tracend. Save or discard it on Today.';

/// The day [draft] stored as its session's, or null for a draft saved before
/// the date was kept.
DateTime? draftSessionDate(Map<String, dynamic> draft) {
  final raw = draft[sessionDateDraftKey];
  if (raw is! String) return null;
  final day = DateTime.tryParse(raw);
  return day == null ? null : DateTime(day.year, day.month, day.day);
}

/// One workout left open on this phone.
@immutable
class OpenWorkout {
  const OpenWorkout({
    required this.workoutId,
    required this.name,
    required this.date,
    required this.doneSets,
    required this.lastActivity,
    this.sessionId,
    this.identityJson,
  });

  /// The planned workout the draft is kept under.
  final String workoutId;

  /// The workout's name as the draft saved it; empty for a draft saved before
  /// the name was kept.
  final String name;

  /// The day the session is logged under: the stored session date, else the
  /// day the workout began.
  final DateTime date;

  /// The sets marked done.
  final int doneSets;

  /// When the last set was done, else when the workout began: newest first
  /// orders by it.
  final DateTime lastActivity;

  final String? sessionId;

  /// Who the workout is in a plan copied with new ids, as the draft stored it
  /// (`WorkoutIdentity.toJson`); null for a draft that kept none.
  final Object? identityJson;

  /// Whether this is the draft of [workoutId] logged under [day].
  bool isOn(String workoutId, DateTime day) =>
      this.workoutId == workoutId &&
      date.year == day.year &&
      date.month == day.month &&
      date.day == day.day;

  /// [name], or what [fallback] names for a draft that kept none.
  String nameOr(String? fallback) =>
      name.trim().isNotEmpty ? name : (fallback ?? 'Your workout');

  /// Reads the saved draft of [workoutId]. Null when it cannot be read, has
  /// no set done, or has no day to be logged under.
  static OpenWorkout? fromDraft(String workoutId, String saved) {
    final Map<String, dynamic> draft;
    try {
      final decoded = jsonDecode(saved);
      if (decoded is! Map) return null;
      draft = Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
    var done = 0;
    DateTime? lastDone;
    final exercises = draft['exercises'];
    if (exercises is List) {
      for (final exercise in exercises) {
        final sets = exercise is Map ? exercise['sets'] : null;
        if (sets is! List) continue;
        for (final set in sets) {
          if (set is! Map || set['completed'] != true) continue;
          done++;
          final at = DateTime.tryParse('${set['completed_at'] ?? ''}');
          if (at != null && (lastDone == null || at.isAfter(lastDone))) {
            lastDone = at;
          }
        }
      }
    }
    if (done == 0) return null;
    final started = DateTime.tryParse('${draft['actual_started_at'] ?? ''}');
    final startedLocal = started?.toLocal();
    final date =
        draftSessionDate(draft) ??
        (startedLocal == null
            ? null
            : DateTime(
                startedLocal.year,
                startedLocal.month,
                startedLocal.day,
              ));
    final last = lastDone ?? started;
    if (date == null || last == null) return null;
    final name = draft[workoutNameDraftKey];
    final session = draft['session_id'];
    return OpenWorkout(
      workoutId: workoutId,
      name: name is String ? name : '',
      date: date,
      doneSets: done,
      lastActivity: last.toUtc(),
      sessionId: session is String ? session : null,
      identityJson: draft['workout_identity'],
    );
  }
}

/// The open workouts among [drafts] (saved draft by planned workout id),
/// newest first: by the last set done, then by day, then by id, so the same
/// drafts always give the same order. A workout in [finished] has a finish
/// waiting to be sent and is not open.
List<OpenWorkout> openWorkoutsFrom(
  Map<String, String> drafts, {
  Set<String> finished = const {},
}) {
  final open = [
    for (final entry in drafts.entries)
      if (!finished.contains(entry.key))
        ?OpenWorkout.fromDraft(entry.key, entry.value),
  ];
  open.sort((a, b) {
    final byActivity = b.lastActivity.compareTo(a.lastActivity);
    if (byActivity != 0) return byActivity;
    final byDay = b.date.compareTo(a.date);
    if (byDay != 0) return byDay;
    return a.workoutId.compareTo(b.workoutId);
  });
  return open;
}

/// A repository that can list this phone's open workouts.
abstract interface class OpenWorkoutRepository {
  /// The signed-in athlete's open workouts, newest first; empty when nobody
  /// is signed in.
  Future<List<OpenWorkout>> loadOpenWorkouts();
}

/// Asks Train to reopen one open workout: Today's Resume card switches to
/// Train and leaves the workout here for it to take.
class ResumeRequests extends ChangeNotifier {
  OpenWorkout? _pending;

  /// Leaves [workout] for Train and tells it.
  void request(OpenWorkout workout) {
    _pending = workout;
    notifyListeners();
  }

  /// The workout asked for, once; null when none waits.
  OpenWorkout? take() {
    final pending = _pending;
    _pending = null;
    return pending;
  }
}
