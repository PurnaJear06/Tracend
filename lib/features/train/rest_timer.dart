import 'package:tracend/features/account/notification_repository.dart';

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

/// Runs the rest timer and keeps the lock-screen alert in step with it:
/// every way a rest ends early cancels the alert.
class RestTimerController {
  RestTimerController({
    required RestAlertScheduler alerts,
    DateTime Function() clock = DateTime.now,
  }) : _alerts = alerts,
       _clock = clock;

  final RestAlertScheduler _alerts;
  final DateTime Function() _clock;
  RestTimer? _timer;

  /// The running timer, or null when no rest is running.
  RestTimer? get timer => _timer;

  /// The value to store in the workout draft under [RestTimer.draftKey].
  Map<String, Object>? toDraft() => _timer?.toJson();

  /// Starts a rest of [seconds] (a set's `rest_seconds`), replacing any
  /// running one. A rest of zero or less starts nothing.
  Future<void> start(int seconds) async {
    if (seconds <= 0) return stop();
    _timer = RestTimer.start(seconds, now: _clock());
    await _alerts.scheduleRestAlert(seconds);
  }

  /// The ±15 s buttons. Taking the rest to its end finishes it.
  Future<void> adjust(Duration delta) async {
    final timer = _timer;
    if (timer == null) return;
    final next = timer.adjusted(delta);
    final now = _clock();
    if (next.isExpired(now)) return stop();
    _timer = next;
    await _alerts.scheduleRestAlert(next.remainingSeconds(now));
  }

  /// Skip: the rest ends now.
  Future<void> skip() => stop();

  /// Ends the rest and its alert: finishing, discarding, or leaving the
  /// workout, the in-app end of the rest, and an expired rest on resume.
  Future<void> stop() async {
    _timer = null;
    await _alerts.cancelRestAlert();
  }

  /// Resumes the timer stored in the draft after a relaunch. A rest that has
  /// already ended is cleared with its alert; a running one keeps its end.
  Future<void> restore(Object? stored) async {
    final timer = RestTimer.fromJson(stored);
    if (timer == null || timer.isExpired(_clock())) return stop();
    _timer = timer;
  }
}
