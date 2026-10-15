import 'dart:async';

import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/shared/live_activity/workout_activity_bridge.dart';

/// A running rest between sets. The end time, not the remaining seconds, is
/// what is kept, so the timer survives the app being killed: it is stored in
/// the local workout draft under [draftKey].
class RestTimer {
  const RestTimer({required this.endsAt, required this.totalSeconds});

  factory RestTimer.start(int seconds, {required DateTime now}) => RestTimer(
    endsAt: now.add(Duration(seconds: seconds)),
    totalSeconds: seconds,
  );

  /// The workout draft field that holds the running timer.
  static const draftKey = 'rest_timer';

  /// The step of the ± buttons.
  static const step = Duration(seconds: 15);

  /// Reads a stored timer. Null for anything unreadable.
  static RestTimer? fromJson(Object? json) {
    if (json is! Map) return null;
    final endsAt = json['ends_at'];
    final total = json['total_seconds'];
    if (endsAt is! String || total is! num || total <= 0) return null;
    final parsed = DateTime.tryParse(endsAt);
    return parsed == null
        ? null
        : RestTimer(endsAt: parsed, totalSeconds: total.toInt());
  }

  final DateTime endsAt;

  /// The rest length after adjustments, for the ring's progress.
  final int totalSeconds;

  Map<String, Object> toJson() => {
    'ends_at': endsAt.toUtc().toIso8601String(),
    'total_seconds': totalSeconds,
  };

  /// Whole seconds left, rounded up, never below zero.
  int remainingSeconds(DateTime now) {
    final millis = endsAt.difference(now).inMilliseconds;
    return millis <= 0 ? 0 : (millis + 999) ~/ 1000;
  }

  bool isExpired(DateTime now) => !endsAt.isAfter(now);

  /// Share of the rest already done, 0 to 1.
  double progress(DateTime now) {
    final done = 1 - remainingSeconds(now) / totalSeconds;
    return done.clamp(0, 1).toDouble();
  }

  /// Moves the end by [delta] (the ±15 s buttons).
  RestTimer adjusted(Duration delta) => RestTimer(
    endsAt: endsAt.add(delta),
    totalSeconds: totalSeconds + delta.inSeconds < 1
        ? 1
        : totalSeconds + delta.inSeconds,
  );
}

/// Runs the rest timer and keeps the lock-screen alert and the Live Activity
/// in step with it. Activity calls are never awaited, so the in-app timer
/// never waits on iOS, and each is sent before the alert is touched: channel
/// messages arrive in the order they are sent, so a stop that follows a
/// start can never reach iOS first.
///
/// The activity shows a rest from its start until the next set is ticked or
/// the workout closes. When the rest is over (it ran out, Skip, or -15 past
/// the end) it reads "Rest done" with a Done button for [doneLinger], so
/// the next set can be ticked from the Lock Screen; the next rest replaces
/// it in place. ActivityKit cannot dismiss an activity by itself (only app
/// code, or a push, can), so while the app is away nothing ends it on time:
/// it goes at the first [tick] after the app runs again, at the next launch
/// (the native sweep), or at the next button press once the time has passed.
class RestTimerController {
  RestTimerController({
    required RestAlertScheduler alerts,
    WorkoutActivityBridge activity = const MethodChannelWorkoutActivityBridge(),
    DateTime Function() clock = DateTime.now,
  }) : _alerts = alerts,
       _activity = activity,
       _clock = clock;

  /// How long "Rest done" shows after the rest is over
  /// (SECURITY_PRIVACY.md §10).
  static const doneLinger = Duration(minutes: 2);

  final RestAlertScheduler _alerts;
  final WorkoutActivityBridge _activity;
  final DateTime Function() _clock;
  RestTimer? _timer;

  /// When the "Rest done" activity goes, while no rest runs; null when none
  /// shows.
  DateTime? _doneUntil;

  /// The running timer, or null when no rest is running.
  RestTimer? get timer => _timer;

  /// The value to store in the workout draft under [RestTimer.draftKey].
  Map<String, Object>? toDraft() => _timer?.toJson();

  /// Starts a rest of [seconds] (a set's `rest_seconds`), replacing any
  /// running one, and shows it as the Live Activity with the exercise and
  /// what follows ([nextLabel], which names the set [nextExerciseOrder] /
  /// [nextSetNumber]: the card's Done button carries that set back). A rest
  /// of zero or less starts nothing and ends the activity.
  Future<void> start(
    int seconds, {
    String nextLabel = '',
    String exerciseName = '',
    int? nextExerciseOrder,
    int? nextSetNumber,
  }) async {
    if (seconds <= 0) return stop();
    final timer = RestTimer.start(seconds, now: _clock());
    _timer = timer;
    _doneUntil = null;
    unawaited(
      _activity.startRest(
        endsAt: timer.endsAt,
        nextLabel: nextLabel,
        exerciseName: exerciseName,
        nextExerciseOrder: nextExerciseOrder,
        nextSetNumber: nextSetNumber,
      ),
    );
    await _alerts.scheduleRestAlert(seconds);
  }

  /// The ±15 s buttons, and +30 s from the Live Activity. Taking the rest
  /// to its end finishes it now.
  Future<void> adjust(Duration delta) async {
    final timer = _timer;
    if (timer == null) return;
    final next = timer.adjusted(delta);
    final now = _clock();
    if (next.isExpired(now)) return _over(now);
    _timer = next;
    unawaited(_activity.updateRest(endsAt: next.endsAt));
    await _alerts.scheduleRestAlert(next.remainingSeconds(now));
  }

  /// Redraws the running rest's activity with its true end, which also
  /// clears "Open Tracend to continue". Used after a button press that
  /// changed nothing, so the card never shows a state the workout is not in.
  void refresh() {
    final timer = _timer;
    if (timer != null) unawaited(_activity.updateRest(endsAt: timer.endsAt));
  }

  /// Skip: the rest ends now and the activity reads "Rest done".
  Future<void> skip() => _over(_clock());

  /// The rest ran to its end (seen by the in-app timer, or late after the
  /// app was away). The activity already reads "Rest done" from its end
  /// time, so nothing is sent to it; it goes [doneLinger] after the end.
  Future<void> ranOut() async {
    final timer = _timer;
    if (timer == null) return;
    _timer = null;
    _doneUntil = timer.endsAt.add(doneLinger);
    await _alerts.cancelRestAlert();
  }

  /// Ends the "Rest done" activity once [doneLinger] has passed. The
  /// workout screen calls it every second while the app is on screen.
  void tick() {
    final until = _doneUntil;
    if (_timer != null || until == null || _clock().isBefore(until)) return;
    _doneUntil = null;
    unawaited(_activity.end());
  }

  /// Ends the rest, its alert and its Live Activity: finishing, discarding,
  /// or leaving the workout, a set with no rest after it, and an expired
  /// rest on resume.
  Future<void> stop() async {
    _timer = null;
    _doneUntil = null;
    unawaited(_activity.end());
    await _alerts.cancelRestAlert();
  }

  /// The workout screen went away without the athlete ending the workout
  /// (the app returned to sign-in, for example). Nothing runs the rest on
  /// screen any more, so its Live Activity ends; the stored rest and its
  /// alert stay, and reopening the workout brings the rest back in the app.
  void detach() {
    if (_timer == null && _doneUntil == null) return;
    _doneUntil = null;
    unawaited(_activity.end());
  }

  /// Resumes the timer stored in the draft after a relaunch. A rest that has
  /// already ended is cleared with its alert and activity; a running one
  /// keeps its end, and the activity still showing from before the relaunch
  /// is moved to that end.
  Future<void> restore(Object? stored) async {
    final timer = RestTimer.fromJson(stored);
    if (timer == null || timer.isExpired(_clock())) return stop();
    _timer = timer;
    _doneUntil = null;
    unawaited(_activity.updateRest(endsAt: timer.endsAt));
  }

  /// The rest ends at [now]: the activity reads "Rest done" from now on.
  Future<void> _over(DateTime now) async {
    if (_timer == null) return;
    _timer = null;
    _doneUntil = now.add(doneLinger);
    unawaited(_activity.updateRest(endsAt: now));
    await _alerts.cancelRestAlert();
  }
}
