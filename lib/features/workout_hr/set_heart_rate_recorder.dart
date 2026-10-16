import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/breadcrumbs.dart';
import 'package:tracend/features/train/workout_events.dart';
import 'package:tracend/features/workout_hr/heart_rate_reader.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_repository.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_summary.dart';

/// Turns a finished workout's heart-rate samples into one summary per set and
/// saves the summaries (coaching platform Contract 4).
///
/// It only listens to the workout's events and reads the sets back from the
/// server once the workout is finished; it never writes sets. Apple Health
/// gets the Watch's samples some time after they are recorded, and the last
/// set needs a minute of recovery, so the work waits for the last set plus a
/// minute and reads again a few minutes later when too little is covered.
/// The waiting list is kept on the phone, so a workout whose time came while
/// the app was closed or asleep is read the next time the app opens. A set
/// whose samples never arrive simply has no summary. Heart rate never changes
/// a load or a prescription, and the Coach does not use it yet.
class SetHeartRateRecorder with WidgetsBindingObserver {
  SetHeartRateRecorder({
    required this.reader,
    required this.repository,
    required SharedPreferencesAsync preferences,
    DateTime Function() clock = DateTime.now,
    bool observeLifecycle = true,
  }) : _preferences = preferences,
       _clock = clock,
       _observeLifecycle = observeLifecycle;

  /// The recorder the app uses, built on first use.
  static SetHeartRateRecorder shared(SupabaseClient client) =>
      _shared ??= SetHeartRateRecorder(
        reader: const MethodChannelHeartRateReader(),
        repository: SupabaseSetHeartRateRepository(client),
        preferences: SharedPreferencesAsync(),
      );
  static SetHeartRateRecorder? _shared;

  /// Where the waiting list is kept.
  static const pendingKey = 'tracend.set_heart_rate.pending';

  /// How long to wait before reading again when too little was covered.
  static const retryAfter = Duration(minutes: 5);

  /// How many reads a workout gets while the app is able to read.
  static const maxAttempts = 3;

  /// How long a workout stays on the waiting list.
  static const keepFor = Duration(days: 2);

  /// Enough of the sets and their recovery minutes are covered, on average,
  /// that reading again would add little.
  static const enoughCoverage = 0.8;

  /// The longest stretch one read may cover (the reader's limit is 4 hours).
  static const _longestRead = Duration(hours: 3, minutes: 30);

  final HeartRateReader reader;
  final SetHeartRateRepository repository;
  final SharedPreferencesAsync _preferences;
  final DateTime Function() _clock;
  final bool _observeLifecycle;

  Future<void> _tail = Future<void>.value();
  Timer? _timer;
  bool _observing = false;

  /// Listens to [events] for the end of a finished workout. [loadSession]
  /// reads the finished workout from the server (`get_my_workout_session`).
  /// Also takes up any workout still waiting from an earlier run. Cancel the
  /// returned subscription when the workout screen goes away; work already
  /// started carries on.
  StreamSubscription<WorkoutEvent> listen(
    Stream<WorkoutEvent> events, {
    required Future<Map<String, dynamic>?> Function() loadSession,
  }) {
    if (_observeLifecycle && !_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    unawaited(processDue());
    return events.listen((event) {
      if (event is WorkoutEnded && event.completed) {
        unawaited(_enqueue(loadSession));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(processDue());
  }

  /// Stops the timer and the lifecycle listener.
  void dispose() {
    _timer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _observing = false;
  }

  /// Reads every waiting workout whose time has come. Completes when done.
  Future<void> processDue() => _exclusive(() async {
    final now = _clock();
    final kept = <_Job>[];
    for (final job in await _load()) {
      if (now.isBefore(job.nextAttemptAt)) {
        kept.add(job);
        continue;
      }
      final next = await _attempt(job, now);
      if (next != null) kept.add(next);
    }
    await _store(kept);
    _wake(kept);
  });

  Future<void> _enqueue(
    Future<Map<String, dynamic>?> Function() loadSession,
  ) async {
    await reader.requestAccess();
    final Map<String, dynamic>? session;
    try {
      session = await loadSession();
    } catch (e) {
      debugPrint(
        'Non-critical error: heart rate could not read the workout: $e',
      );
      return;
    }
    final job = session == null ? null : _Job.fromSession(session, _clock());
    if (job == null) return;
    await _exclusive(() async {
      final jobs = [
        for (final waiting in await _load())
          if (waiting.sessionId != job.sessionId) waiting,
        job,
      ];
      await _store(jobs);
    });
    await processDue();
  }

  /// Reads one workout once. Completes with the job to keep waiting, or null
  /// when it is finished or can never succeed.
  Future<_Job?> _attempt(_Job job, DateTime now) async {
    final List<HeartRateSample> samples;
    try {
      samples = await reader.readSamples(
        job.firstStart.subtract(heartRatePointTolerance),
        job.lastEnd.add(setHeartRateTail + heartRatePointTolerance),
      );
    } catch (e) {
      debugPrint('Non-critical error: heart rate could not be read: $e');
      return job.tried(now, best: job.best);
    }
    final summaries = [
      for (final window in job.sets)
        ?summarizeSetHeartRate(
          exerciseOrder: window.exerciseOrder,
          setNumber: window.setNumber,
          startedAt: window.startedAt,
          completedAt: window.completedAt,
          samples: samples,
        ),
    ];
    final candidate = _Best(
      setsCovered: summaries.length,
      coverage:
          summaries.fold<double>(0, (sum, item) => sum + item.coverage) /
          job.sets.length,
      samples: summaries.fold<int>(0, (sum, item) => sum + item.sampleCount),
    );
    var best = job.best;
    if (summaries.isNotEmpty && candidate.isBetterThan(best)) {
      try {
        await repository.persist(job.sessionId, summaries);
        best = candidate;
        AppBreadcrumbs.workout(
          'Set heart rate saved',
          data: {'sets': summaries.length},
        );
      } catch (e) {
        if (e is PostgrestException && _refusedForGood(e)) {
          debugPrint('Non-critical error: heart rate was refused: ${e.code}');
          return null;
        }
        debugPrint('Non-critical error: heart rate waits to be sent: $e');
        return now.isAfter(job.expiresAt)
            ? null
            : job.waiting(now.add(retryAfter));
      }
    }
    if (best.coverage >= enoughCoverage) return null;
    return job.tried(now, best: best);
  }

  /// The database refused these summaries and would refuse them again:
  /// invalid values (class 22), a constraint (23), a permission or schema
  /// error (42) or a raised exception (P0). Anything else (an expired
  /// session, a server error) waits and tries again like a lost connection.
  static bool _refusedForGood(PostgrestException e) {
    final code = e.code ?? '';
    return code.startsWith('22') ||
        code.startsWith('23') ||
        code.startsWith('42') ||
        code.startsWith('P0');
  }

  void _wake(List<_Job> jobs) {
    _timer?.cancel();
    _timer = null;
    if (jobs.isEmpty) return;
    final next = jobs
        .map((job) => job.nextAttemptAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final wait = next.difference(_clock());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () {
      unawaited(processDue());
    });
  }

  Future<List<_Job>> _load() async {
    final raw = await _preferences.getString(pendingKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      return [
        for (final item in decoded is List ? decoded : const [])
          ?_Job.fromJson(item),
      ];
    } on FormatException {
      return [];
    }
  }

  Future<void> _store(List<_Job> jobs) => jobs.isEmpty
      ? _preferences.remove(pendingKey)
      : _preferences.setString(
          pendingKey,
          jsonEncode([for (final job in jobs) job.toJson()]),
        );

  /// Runs [action] after everything queued before it.
  Future<void> _exclusive(Future<void> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }
}

/// A set's window as the server stores it.
class _SetWindow {
  const _SetWindow(
    this.exerciseOrder,
    this.setNumber,
    this.startedAt,
    this.completedAt,
  );

  final int exerciseOrder;
  final int setNumber;
  final DateTime startedAt;
  final DateTime completedAt;
}

/// What a save was made from, ranked by the sets it covers, then by the average
/// coverage across all of the workout's sets, then by the readings it holds.
class _Best {
  const _Best({
    required this.setsCovered,
    required this.coverage,
    required this.samples,
  });

  static const none = _Best(setsCovered: 0, coverage: 0, samples: 0);

  /// A saved job from before the ranking existed has no figures: it ranks
  /// lowest, so the next read with any summary replaces it.
  static _Best fromJson(Map<dynamic, dynamic> json) {
    final sets = json['best_sets_covered'];
    final coverage = json['best_coverage'];
    final samples = json['best_samples'];
    return _Best(
      setsCovered: sets is int ? sets : 0,
      coverage: coverage is num ? coverage.toDouble() : 0,
      samples: samples is int ? samples : 0,
    );
  }

  final int setsCovered;
  final double coverage;
  final int samples;

  bool isBetterThan(_Best other) {
    if (setsCovered != other.setsCovered) {
      return setsCovered > other.setsCovered;
    }
    if ((coverage - other.coverage).abs() > _tolerance) {
      return coverage > other.coverage;
    }
    return samples > other.samples;
  }

  Map<String, Object?> toJson() => {
    'best_sets_covered': setsCovered,
    'best_coverage': coverage,
    'best_samples': samples,
  };

  static const _tolerance = 1e-9;
}

/// A finished workout waiting to be read.
class _Job {
  const _Job({
    required this.sessionId,
    required this.sets,
    required this.nextAttemptAt,
    required this.expiresAt,
    this.attempts = 0,
    this.best = _Best.none,
  });

  /// The workout's sets that have both times, or null when it has none or
  /// they span more than one read can cover.
  static _Job? fromSession(Map<String, dynamic> session, DateTime now) {
    final id = session['session_id'];
    if (id is! String) return null;
    final windows = <_SetWindow>[];
    final exercises = session['exercises'];
    for (final exercise in exercises is List ? exercises : const []) {
      if (exercise is! Map) continue;
      final order = exercise['order'];
      final sets = exercise['sets'];
      if (order is! int) continue;
      for (final set in sets is List ? sets : const []) {
        if (set is! Map || set['completed'] == false) continue;
        final number = set['number'];
        final start = DateTime.tryParse('${set['started_at'] ?? ''}');
        final end = DateTime.tryParse('${set['completed_at'] ?? ''}');
        if (number is! int || start == null || end == null) continue;
        if (end.isBefore(start)) continue;
        windows.add(_SetWindow(order, number, start, end));
      }
    }
    if (windows.isEmpty) return null;
    final first = windows.map((w) => w.startedAt).reduce(_earlier);
    final last = windows.map((w) => w.completedAt).reduce(_later);
    if (last.difference(first) > SetHeartRateRecorder._longestRead) return null;
    final ready = last.add(setHeartRateTail);
    return _Job(
      sessionId: id,
      sets: windows,
      nextAttemptAt: ready,
      expiresAt: (ready.isAfter(now) ? ready : now).add(
        SetHeartRateRecorder.keepFor,
      ),
    );
  }

  static _Job? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['session_id'];
    final next = DateTime.tryParse('${json['next_attempt_at'] ?? ''}');
    final expires = DateTime.tryParse('${json['expires_at'] ?? ''}');
    final rows = json['sets'];
    if (id is! String || next == null || expires == null || rows is! List) {
      return null;
    }
    final sets = <_SetWindow>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final start = DateTime.tryParse('${row['started_at'] ?? ''}');
      final end = DateTime.tryParse('${row['completed_at'] ?? ''}');
      final order = row['exercise_order'];
      final number = row['set_number'];
      if (start == null || end == null || order is! int || number is! int) {
        continue;
      }
      sets.add(_SetWindow(order, number, start, end));
    }
    if (sets.isEmpty) return null;
    return _Job(
      sessionId: id,
      sets: sets,
      nextAttemptAt: next,
      expiresAt: expires,
      attempts: json['attempts'] is int ? json['attempts'] as int : 0,
      best: _Best.fromJson(json),
    );
  }

  final String sessionId;
  final List<_SetWindow> sets;
  final DateTime nextAttemptAt;
  final DateTime expiresAt;
  final int attempts;

  /// The best result saved so far; a later read replaces it only when it ranks
  /// higher.
  final _Best best;

  DateTime get firstStart => sets.map((w) => w.startedAt).reduce(_earlier);
  DateTime get lastEnd => sets.map((w) => w.completedAt).reduce(_later);

  /// The job after a read at [now] that did not cover enough: read again in
  /// a few minutes, unless the reads or the time ran out.
  _Job? tried(DateTime now, {required _Best best}) {
    final used = attempts + 1;
    if (used >= SetHeartRateRecorder.maxAttempts || now.isAfter(expiresAt)) {
      return null;
    }
    return _Job(
      sessionId: sessionId,
      sets: sets,
      nextAttemptAt: now.add(SetHeartRateRecorder.retryAfter),
      expiresAt: expiresAt,
      attempts: used,
      best: best,
    );
  }

  /// The same job, waiting until [at] without using up a read.
  _Job waiting(DateTime at) => _Job(
    sessionId: sessionId,
    sets: sets,
    nextAttemptAt: at,
    expiresAt: expiresAt,
    attempts: attempts,
    best: best,
  );

  Map<String, Object?> toJson() => {
    'session_id': sessionId,
    'next_attempt_at': nextAttemptAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'attempts': attempts,
    ...best.toJson(),
    'sets': [
      for (final window in sets)
        {
          'exercise_order': window.exerciseOrder,
          'set_number': window.setNumber,
          'started_at': window.startedAt.toUtc().toIso8601String(),
          'completed_at': window.completedAt.toUtc().toIso8601String(),
        },
    ],
  };
}

DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
