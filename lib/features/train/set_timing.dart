/// When each set began and ended, and the rest actually taken before it
/// (coaching platform Contract 2). Every time is a wall-clock moment, never
/// a count of timer ticks, so a phone in a pocket records the same times as
/// one on the bench: a rest that ran out while the app was suspended ended
/// at its stored end time, not when the app noticed.
library;

import 'package:tracend/features/train/workout_draft.dart';

/// The longest rest the server stores (an hour). A longer gap is a pause,
/// not a rest, and is left unknown.
const maxRestSeconds = 3600;

/// The rest taken before a set that began at [start]: from the latest end
/// in [ends] at or before it. Null when either is unknown or the gap is
/// longer than [maxRestSeconds].
int? restTakenSeconds(DateTime? start, Iterable<DateTime> ends) {
  if (start == null) return null;
  DateTime? previous;
  for (final end in ends) {
    if (end.isAfter(start)) continue;
    if (previous == null || end.isAfter(previous)) previous = end;
  }
  if (previous == null) return null;
  final seconds = start.difference(previous).inSeconds;
  return seconds > maxRestSeconds ? null : seconds;
}

/// Records set starts and ends as the athlete logs.
///
/// A set starts at the end of the rest before it (Skip, or the timer's end)
/// or, outside a rest, at the athlete's first edit of its kg or reps. A set
/// ticked while its rest still runs began at an unknown moment, so it gets
/// no start; nothing is guessed.
class SetTimingRecorder {
  /// The workout draft field that holds [pendingStart] on this phone.
  static const draftKey = 'pending_set_start';

  /// When the last rest ended. The next set the athlete edits or ticks
  /// began then. Null when no rest has ended since the last tick.
  DateTime? pendingStart;

  /// A new rest began: an earlier rest's end no longer starts anything.
  void restStarted() => pendingStart = null;

  /// The rest ended at [at]: the moment of a Skip, or the timer's end.
  void restEnded(DateTime at) => pendingStart = at;

  /// The athlete edited [set]'s kg or reps at [now]. Returns the start this
  /// recorded, or null when the set already had one, is done, or a rest
  /// is still running (editing during a rest is getting ready).
  DateTime? touched(
    WorkoutSetDraft set, {
    required DateTime now,
    required bool resting,
  }) {
    if (set.completed || set.startedAt != null || resting) return null;
    final start = pendingStart ?? now;
    pendingStart = null;
    set.startedAt = start;
    return start;
  }

  /// [set] was ticked at [now]. Records its end, its start when the rest
  /// before it ended, the rest taken since the latest of [otherEnds] (the
  /// ends of the workout's other sets) and that the app timed it. Returns
  /// the start this recorded, or null.
  DateTime? completed(
    WorkoutSetDraft set, {
    required DateTime now,
    required bool resting,
    required Iterable<DateTime> otherEnds,
  }) {
    DateTime? recorded;
    final pending = pendingStart;
    if (set.startedAt == null &&
        !resting &&
        pending != null &&
        !pending.isAfter(now)) {
      set.startedAt = pending;
      recorded = pending;
    }
    pendingStart = null;
    final start = set.startedAt;
    if (start != null && start.isAfter(now)) {
      // The phone's clock moved back: this start cannot be right.
      set.startedAt = null;
      recorded = null;
    }
    set
      ..completedAt = now
      ..restBeforeSeconds = restTakenSeconds(set.startedAt, otherEnds)
      ..timingSource = SetTimingSource.app;
    return recorded;
  }
}
