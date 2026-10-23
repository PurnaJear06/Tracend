import 'package:flutter/foundation.dart';

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

/// Runs the rest timer and is the only driver of the workout's Live Activity:
/// the set in progress, the rest between sets, and the card that says every
/// set is logged. In the app the activity calls are never awaited, so the
/// timer never waits on iOS; each is sent before the alert is touched
/// (channel messages arrive in the order they are sent, so a stop that follows
/// a start can never reach iOS first), and is remembered until it completes.
/// A Live Activity button press, after which iOS may suspend the app, waits
/// for those with [activityUpdated] before it answers.
///
/// The activity shows the set in progress ([present]) from the moment the
/// workout opens. A rest replaces it ([start]) and carries the set that
/// follows, so when the rest is over (it ran out, Skip, or -15 past the end)
/// the card turns into that set on its own, even with the app suspended; the
/// next rest replaces it in place. After the last set the card says every set
/// is logged and goes [doneLinger] later. The athlete leaves with Finish,
/// Discard or Save and leave ([stop]). ActivityKit cannot dismiss an
/// activity by itself (only app code, or a push, can), so while the app is
/// away the finished card goes at the first [tick] after the app runs again,
/// at the next launch (the native sweep), or at the next button press once
/// the time has passed.
class RestTimerController {
  RestTimerController({
    required RestAlertScheduler alerts,
    WorkoutActivityBridge activity = const MethodChannelWorkoutActivityBridge(),
    DateTime Function() clock = DateTime.now,
    this.activityWait = defaultActivityWait,
  }) : _alerts = alerts,
       _activity = activity,
       _clock = clock;

  /// The longest a button press waits for the activity update. The press
  /// then still has to answer inside iOS's 8 s (`LiveActivityButton`'s
  /// `pressTimeout`) after a save of at most 5 s.
  static const defaultActivityWait = Duration(milliseconds: 1500);

  /// How long [activityUpdated] waits at most.
  final Duration activityWait;

  /// How long the card that says every set is logged shows
  /// (SECURITY_PRIVACY.md §10).
  static const doneLinger = Duration(minutes: 2);

  final RestAlertScheduler _alerts;
  final WorkoutActivityBridge _activity;
  final DateTime Function() _clock;
  RestTimer? _timer;

  /// The activity calls sent and not yet finished.
  final _pending = <Future<void>>{};

  /// When the card that says every set is logged goes; null when it does not
  /// show.
  DateTime? _doneUntil;

  /// The set the activity names (null: every set is logged) as last sent,
  /// or null when nothing was sent since the workout opened. A rest carries
  /// it too, so it is also the set the card turns into when the rest ends.
  ({ActivitySet? set})? _drawn;

  /// The running timer, or null when no rest is running.
  RestTimer? get timer => _timer;

  /// Sends an activity call now and remembers it until it finishes. A failure
  /// is logged and dropped: the activity is a display of the workout, so it
  /// never blocks or undoes a change to it.
  void _send(Future<void> call) {
    late final Future<void> tracked;
    tracked = call
        .catchError((Object e) {
          debugPrint('Non-critical error: live activity update failed: $e');
        })
        .whenComplete(() => _pending.remove(tracked));
    _pending.add(tracked);
  }

  /// Completes when every activity call sent so far has finished, or after
  /// [activityWait], whichever comes first; never throws. A Live Activity
  /// button press awaits it before answering, so iOS does not suspend the
  /// app with the card still showing the old state.
  Future<void> activityUpdated() async {
    if (_pending.isEmpty) return;
    await Future.wait(_pending.toList()).timeout(
      activityWait,
      onTimeout: () {
        debugPrint('Non-critical error: live activity update timed out');
        return const [];
      },
    );
  }

  /// The value to store in the workout draft under [RestTimer.draftKey].
  Map<String, Object>? toDraft() => _timer?.toJson();

  /// Shows [set] as the one in progress, or that every set is logged when it
  /// is null. While a rest runs only the set that follows it changes (the
  /// card turns into it when the rest ends). With [begin] a card is requested
  /// when none shows (the workout opened, a set was logged); without it
  /// nothing appears, so a card the athlete dismissed stays gone. The same
  /// set again sends nothing, unless [begin].
  void present(ActivitySet? set, {bool begin = false}) {
    final drawn = _drawn;
    if (!begin && drawn != null && drawn.set == set) return;
    final timer = _timer;
    if (timer != null) {
      if (set == null) return;
      _drawn = (set: set);
      _send(_activity.updateRest(endsAt: timer.endsAt, next: set));
      return;
    }
    _drawn = (set: set);
    _doneUntil = set == null ? _clock().add(doneLinger) : null;
    _send(_activity.showSet(set, begin: begin));
  }

  /// Starts a rest of [seconds] (a set's `rest_seconds`), replacing any
  /// running one, and shows it as the Live Activity with the exercise and
  /// what follows ([nextLabel], which names the set [next]: the card turns
  /// into that set when the rest ends, and its "Log set" carries that set
  /// back). A rest of zero or less starts nothing.
  Future<void> start(
    int seconds, {
    String nextLabel = '',
    String exerciseName = '',
    ActivitySet? next,
  }) async {
    if (seconds <= 0) return;
    final timer = RestTimer.start(seconds, now: _clock());
    _timer = timer;
    _doneUntil = null;
    _drawn = (set: next);
    _send(
      _activity.startRest(
        endsAt: timer.endsAt,
        nextLabel: nextLabel,
        exerciseName: exerciseName,
        next: next,
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
    _send(_activity.updateRest(endsAt: next.endsAt));
    await _alerts.scheduleRestAlert(next.remainingSeconds(now));
  }

  /// Redraws the activity with its true state, which also clears "Open
  /// Tracend": the running rest with its end, else the set in progress. Used
  /// after a button press that changed nothing, so the card never shows a
  /// state the workout is not in.
  void refresh() {
    final timer = _timer;
    final drawn = _drawn;
    if (timer != null) {
      _send(_activity.updateRest(endsAt: timer.endsAt, next: drawn?.set));
    } else if (drawn != null) {
      _send(_activity.showSet(drawn.set, begin: false));
    }
  }

  /// Skip: the rest ends now and the card turns into the set that follows.
  Future<void> skip() => _over(_clock());

  /// The rest ran to its end (seen by the in-app timer, or late after the
  /// app was away). The activity already turned into the set that follows
  /// from its end time, so nothing is sent to it.
  Future<void> ranOut() async {
    if (_timer == null) return;
    _timer = null;
    await _alerts.cancelRestAlert();
  }

  /// Ends the card that says every set is logged once [doneLinger] has
  /// passed. The workout screen calls it every second while the app is on
  /// screen.
  void tick() {
    final until = _doneUntil;
    if (_timer != null || until == null || _clock().isBefore(until)) return;
    _doneUntil = null;
    _drawn = null;
    _send(_activity.end());
  }

  /// Ends the rest, its alert and the Live Activity: finishing, discarding,
  /// or leaving the workout.
  Future<void> stop() async {
    _timer = null;
    _doneUntil = null;
    _drawn = null;
    _send(_activity.end());
    await _alerts.cancelRestAlert();
  }

  /// The workout screen went away without the athlete ending the workout
  /// (the app returned to sign-in, for example). Nothing drives the activity
  /// any more, so it ends; the stored rest and its alert stay, and reopening
  /// the workout brings the rest back in the app.
  void detach() {
    if (_timer == null && _drawn == null) return;
    _doneUntil = null;
    _drawn = null;
    _send(_activity.end());
  }

  /// Resumes the timer stored in the draft after a relaunch. A rest that has
  /// already ended is cleared with its alert; the activity still showing
  /// from before the relaunch is left for [present] to move to the set in
  /// progress. A running one keeps its end, and the activity is moved to it.
  Future<void> restore(Object? stored) async {
    final timer = RestTimer.fromJson(stored);
    if (timer == null || timer.isExpired(_clock())) {
      await _alerts.cancelRestAlert();
      return;
    }
    _timer = timer;
    _doneUntil = null;
    _send(_activity.updateRest(endsAt: timer.endsAt));
  }

  /// The rest ends at [now]: the activity turns into the set that follows.
  Future<void> _over(DateTime now) async {
    if (_timer == null) return;
    _timer = null;
    _send(_activity.updateRest(endsAt: now));
    await _alerts.cancelRestAlert();
  }
}
