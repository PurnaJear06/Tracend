import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:tracend/features/train/workout_events.dart';
import 'package:tracend/features/workout_hr/heart_rate_reader.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_recorder.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_repository.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_summary.dart';

final _t0 = DateTime.utc(2026, 10, 16, 9, 0, 0);

DateTime _after(int seconds) => _t0.add(Duration(seconds: seconds));

class _FakeReader implements HeartRateReader {
  List<HeartRateSample> samples = [];
  bool failing = false;
  int accessRequests = 0;
  final reads = <(DateTime, DateTime)>[];

  @override
  Future<void> requestAccess() async => accessRequests += 1;

  @override
  Future<List<HeartRateSample>> readSamples(DateTime from, DateTime to) async {
    reads.add((from, to));
    if (failing) throw StateError('cannot read');
    return samples;
  }
}

class _FakeRepository implements SetHeartRateRepository {
  final saved = <(String, List<SetHeartRateSummary>)>[];
  Object? failure;

  @override
  Future<int> persist(
    String sessionId,
    List<SetHeartRateSummary> summaries,
  ) async {
    final error = failure;
    if (error != null) throw error;
    saved.add((sessionId, summaries));
    return summaries.length;
  }

  @override
  Future<SetHeartRateReport> load(String sessionId) async =>
      const SetHeartRateReport([]);
}

/// A reading every 5 seconds from [from] to [to] seconds after the start.
List<HeartRateSample> _readings({int from = 0, int to = 100}) => [
  for (var second = from; second <= to; second += 5)
    HeartRateSample(
      at: _after(second),
      bpm: second <= 40 ? 110 + second * 1.0 : 150 - (second - 40) * 1.0,
    ),
];

/// Two finished sets: 0-40 seconds, and 100-140 seconds.
Map<String, dynamic> _twoSetSession() => {
  'session_id': 'session-1',
  'state': 'completed',
  'exercises': [
    {
      'order': 1,
      'sets': [
        {
          'number': 1,
          'completed': true,
          'started_at': _after(0).toIso8601String(),
          'completed_at': _after(40).toIso8601String(),
        },
        {
          'number': 2,
          'completed': true,
          'started_at': _after(100).toIso8601String(),
          'completed_at': _after(140).toIso8601String(),
        },
      ],
    },
  ],
};

/// One finished workout: a 40 second set, and a second one a minute later.
Map<String, dynamic> _session({bool timed = true}) => {
  'session_id': 'session-1',
  'state': 'completed',
  'exercises': [
    {
      'order': 1,
      'sets': [
        {
          'number': 1,
          'completed': true,
          'started_at': timed ? _after(0).toIso8601String() : null,
          'completed_at': timed ? _after(40).toIso8601String() : null,
        },
        {'number': 2, 'completed': false},
      ],
    },
  ],
};

void main() {
  late _FakeReader reader;
  late _FakeRepository repository;
  late WorkoutEventHub hub;
  late DateTime now;
  late Map<String, dynamic>? session;

  SetHeartRateRecorder newRecorder() {
    final recorder = SetHeartRateRecorder(
      reader: reader,
      repository: repository,
      preferences: SharedPreferencesAsync(),
      clock: () => now,
      observeLifecycle: false,
    );
    addTearDown(recorder.dispose);
    return recorder;
  }

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    reader = _FakeReader()..samples = _readings();
    repository = _FakeRepository();
    hub = WorkoutEventHub();
    addTearDown(hub.close);
    now = _after(200);
    session = _session();
  });

  void listen(SetHeartRateRecorder recorder) =>
      recorder.listen(hub.events, loadSession: () async => session);

  Future<void> finish({bool completed = true}) async {
    hub.emit(WorkoutEnded(at: now, completed: completed));
    await pumpEventQueue(times: 60);
  }

  test('a finished workout saves one summary per timed set', () async {
    listen(newRecorder());
    await finish();

    expect(repository.saved, hasLength(1));
    final (sessionId, summaries) = repository.saved.single;
    expect(sessionId, 'session-1');
    expect(summaries, hasLength(1));
    expect(summaries.single.exerciseOrder, 1);
    expect(summaries.single.setNumber, 1);
    expect(summaries.single.peakBpm, 150);
    expect(summaries.single.drop60sBpm, 60);
    expect(summaries.single.coverage, 1);
    expect(summaries.single.source, HeartRateSource.watchWorkout);
    expect(reader.accessRequests, 1);
  });

  test('it reads the set window plus its minute and a small margin', () async {
    listen(newRecorder());
    await finish();

    final (from, to) = reader.reads.single;
    expect(from, _after(0).subtract(heartRatePointTolerance));
    expect(to, _after(100).add(heartRatePointTolerance));
  });

  test('it waits for the minute after the last set before reading', () async {
    now = _after(70);
    final recorder = newRecorder();
    listen(recorder);
    await finish();

    expect(reader.reads, isEmpty);
    expect(repository.saved, isEmpty);

    now = _after(101);
    await recorder.processDue();

    expect(reader.reads, hasLength(1));
    expect(repository.saved, hasLength(1));
  });

  test('a workout that was left or discarded saves nothing', () async {
    listen(newRecorder());
    await finish(completed: false);

    expect(reader.accessRequests, 0);
    expect(reader.reads, isEmpty);
    expect(repository.saved, isEmpty);
  });

  test('other events do nothing', () async {
    listen(newRecorder());
    hub
      ..emit(SetStarted(at: now, exerciseOrder: 1, setNumber: 1))
      ..emit(SetCompleted(at: now, exerciseOrder: 1, setNumber: 1))
      ..emit(ExerciseAdvanced(at: now, exerciseOrder: 2, name: 'Row'));
    await pumpEventQueue(times: 60);

    expect(reader.accessRequests, 0);
    expect(repository.saved, isEmpty);
  });

  test(
    'sets without both times, and a workout with none, are skipped',
    () async {
      session = _session(timed: false);
      listen(newRecorder());
      await finish();

      expect(reader.reads, isEmpty);
      expect(repository.saved, isEmpty);
    },
  );

  test('a workout that cannot be read back saves nothing', () async {
    session = null;
    listen(newRecorder());
    await finish();

    expect(reader.reads, isEmpty);
    expect(repository.saved, isEmpty);
  });

  test('no samples save nothing and stop after three reads', () async {
    reader.samples = [];
    final recorder = newRecorder();
    listen(recorder);
    await finish();
    for (var read = 1; read < 5; read++) {
      now = now.add(SetHeartRateRecorder.retryAfter);
      await recorder.processDue();
    }

    expect(reader.reads, hasLength(SetHeartRateRecorder.maxAttempts));
    expect(repository.saved, isEmpty);
  });

  test(
    'too little coverage is read again and a better read replaces it',
    () async {
      reader.samples = _readings(to: 40);
      final recorder = newRecorder();
      listen(recorder);
      await finish();

      expect(repository.saved, hasLength(1));
      expect(repository.saved.single.$2.single.coverage, lessThan(0.8));

      // Too soon: nothing happens.
      now = now.add(const Duration(minutes: 1));
      await recorder.processDue();
      expect(reader.reads, hasLength(1));

      // The Watch's later samples arrived.
      reader.samples = _readings();
      now = now.add(SetHeartRateRecorder.retryAfter);
      await recorder.processDue();
      expect(repository.saved, hasLength(2));
      expect(repository.saved.last.$2.single.coverage, 1);

      // Covered enough: the workout is off the waiting list.
      now = now.add(SetHeartRateRecorder.retryAfter);
      await recorder.processDue();
      expect(reader.reads, hasLength(2));
    },
  );

  test(
    'a read with fewer samples than a saved one does not replace it',
    () async {
      reader.samples = _readings(to: 60);
      final recorder = newRecorder();
      listen(recorder);
      await finish();
      expect(repository.saved, hasLength(1));

      reader.samples = _readings(to: 30);
      now = now.add(SetHeartRateRecorder.retryAfter);
      await recorder.processDue();

      expect(reader.reads, hasLength(2));
      expect(repository.saved, hasLength(1));
    },
  );

  test(
    'a full-coverage read with fewer samples replaces a partial one with more',
    () async {
      session = _twoSetSession();
      now = _after(300);
      // Only the first set, read densely.
      reader.samples = [
        for (var second = 0; second <= 60; second++)
          HeartRateSample(at: _after(second), bpm: 120),
      ];
      final recorder = newRecorder();
      listen(recorder);
      await finish();
      expect(repository.saved, hasLength(1));
      expect(repository.saved.single.$2, hasLength(1));

      // Both sets, read sparsely, with fewer samples in all.
      reader.samples = [
        for (var second = 0; second <= 200; second += 5)
          HeartRateSample(at: _after(second), bpm: 120),
      ];
      now = now.add(SetHeartRateRecorder.retryAfter);
      await recorder.processDue();
      expect(repository.saved, hasLength(2));
      final better = repository.saved.last.$2;
      expect(better, hasLength(2));
      expect(
        better.fold<double>(0, (sum, item) => sum + item.coverage) / 2,
        greaterThanOrEqualTo(SetHeartRateRecorder.enoughCoverage),
      );

      // The persisted best is enough, so the job has ended.
      now = now.add(SetHeartRateRecorder.retryAfter);
      await recorder.processDue();
      expect(reader.reads, hasLength(2));
    },
  );

  test('a worse retry is not saved and the job is not ended', () async {
    session = _twoSetSession();
    now = _after(300);
    reader.samples = _readings(to: 140);
    final recorder = newRecorder();
    listen(recorder);
    await finish();
    expect(repository.saved, hasLength(1));

    reader.samples = _readings(to: 60);
    now = now.add(SetHeartRateRecorder.retryAfter);
    await recorder.processDue();
    expect(repository.saved, hasLength(1));
    expect(reader.reads, hasLength(2));
  });

  test('a good read that could not be saved does not end the job', () async {
    repository.failure = StateError('offline');
    final recorder = newRecorder();
    listen(recorder);
    await finish();
    expect(repository.saved, isEmpty);

    // The full read was never saved, so the job still waits.
    repository.failure = null;
    now = now.add(SetHeartRateRecorder.retryAfter);
    await recorder.processDue();
    expect(repository.saved, hasLength(1));
  });

  test('a job saved before the ranking existed still loads', () async {
    final preferences = SharedPreferencesAsync();
    await preferences.setString(
      SetHeartRateRecorder.pendingKey,
      jsonEncode([
        {
          'session_id': 'session-1',
          'next_attempt_at': _after(100).toIso8601String(),
          'expires_at': _after(100000).toIso8601String(),
          'attempts': 1,
          'best_samples': 500,
          'sets': [
            {
              'exercise_order': 1,
              'set_number': 1,
              'started_at': _after(0).toIso8601String(),
              'completed_at': _after(40).toIso8601String(),
            },
          ],
        },
      ]),
    );
    final recorder = newRecorder();
    listen(recorder);
    await pumpEventQueue(times: 60);

    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.$1, 'session-1');
  });

  test('a read that fails is tried again later', () async {
    reader.failing = true;
    final recorder = newRecorder();
    listen(recorder);
    await finish();
    expect(repository.saved, isEmpty);

    reader.failing = false;
    now = now.add(SetHeartRateRecorder.retryAfter);
    await recorder.processDue();
    expect(repository.saved, hasLength(1));
  });

  test('the server refusing the summaries ends the work', () async {
    repository.failure = const PostgrestException(
      message: 'bad',
      code: '22023',
    );
    final recorder = newRecorder();
    listen(recorder);
    await finish();

    repository.failure = null;
    now = now.add(SetHeartRateRecorder.retryAfter);
    await recorder.processDue();
    expect(reader.reads, hasLength(1));
    expect(repository.saved, isEmpty);
  });

  test('an expired session or a server error waits and tries again', () async {
    for (final code in ['PGRST301', '500', null]) {
      repository.failure = PostgrestException(message: 'transient', code: code);
      final recorder = newRecorder();
      listen(recorder);
      await finish();
      expect(repository.saved, isEmpty, reason: '$code');

      repository.failure = null;
      now = now.add(SetHeartRateRecorder.retryAfter);
      await recorder.processDue();
      expect(repository.saved, isNotEmpty, reason: '$code');
      repository.saved.clear();
    }
  });

  test(
    'no connection keeps the workout waiting without using a read',
    () async {
      repository.failure = StateError('offline');
      final recorder = newRecorder();
      listen(recorder);
      await finish();
      expect(repository.saved, isEmpty);

      repository.failure = null;
      for (var read = 0; read < 5; read++) {
        now = now.add(SetHeartRateRecorder.retryAfter);
        await recorder.processDue();
        if (repository.saved.isNotEmpty) break;
      }
      expect(repository.saved, hasLength(1));
    },
  );

  test('the waiting list survives the app closing', () async {
    now = _after(70);
    listen(newRecorder());
    await finish();
    expect(repository.saved, isEmpty);

    // The app opens again after the minute has passed: a new recorder.
    now = _after(500);
    final reopened = newRecorder();
    listen(reopened);
    await pumpEventQueue(times: 60);

    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.$1, 'session-1');
  });

  test('a workout past its keeping time is dropped', () async {
    reader.samples = [];
    now = _after(70);
    final recorder = newRecorder();
    listen(recorder);
    await finish();

    now = _after(
      100,
    ).add(SetHeartRateRecorder.keepFor).add(const Duration(hours: 1));
    await recorder.processDue();
    expect(reader.reads, hasLength(1));
    now = now.add(SetHeartRateRecorder.retryAfter);
    await recorder.processDue();
    expect(reader.reads, hasLength(1));
  });

  test('the same workout finished twice is one entry', () async {
    now = _after(70);
    final recorder = newRecorder();
    listen(recorder);
    await finish();
    await finish();

    now = _after(101);
    await recorder.processDue();

    expect(repository.saved, hasLength(1));
  });
}
