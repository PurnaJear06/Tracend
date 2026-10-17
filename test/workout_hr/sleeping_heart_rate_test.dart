import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/workout_hr/heart_rate_reader.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_summary.dart';
import 'package:tracend/features/workout_hr/sleeping_heart_rate.dart';
import 'package:tracend/features/workout_hr/sleeping_heart_rate_recorder.dart';

// Local times, so the night's date does not depend on the machine's zone.
DateTime _at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 10, day, hour, minute);

RawHealthSample _sleep(
  DateTime start,
  DateTime end,
  SleepStage stage, [
  String id = 's',
]) => RawHealthSample(
  metric: HealthMetric.sleep,
  value: 0,
  start: start,
  end: end,
  sampleId: '$id-${start.microsecondsSinceEpoch}',
  sourceId: 'watch',
  sleepStage: stage,
);

/// 23:00 on the 15th to 07:00 on the 16th: core sleep, a wake-up at 03:00
/// for 20 minutes, then more sleep.
List<RawHealthSample> _night() => [
  _sleep(_at(15, 23), _at(16, 3), SleepStage.light),
  _sleep(_at(16, 3), _at(16, 3, 20), SleepStage.awake),
  _sleep(_at(16, 3, 20), _at(16, 7), SleepStage.deep),
];

/// A reading every [everyMinutes] minutes from [from] to [to].
List<HeartRateSample> _readings(
  DateTime from,
  DateTime to, {
  int everyMinutes = 5,
  double Function(DateTime)? bpm,
}) => [
  for (
    var at = from;
    at.isBefore(to);
    at = at.add(Duration(minutes: everyMinutes))
  )
    HeartRateSample(at: at, bpm: bpm == null ? 52 : bpm(at)),
];

class _FakeReader implements HeartRateReader {
  List<HeartRateSample> samples = [];
  bool failing = false;
  final reads = <(DateTime, DateTime)>[];

  @override
  Future<void> requestAccess() async {}

  @override
  Future<List<HeartRateSample>> readSamples(DateTime from, DateTime to) async {
    reads.add((from, to));
    if (failing) throw StateError('cannot read');
    return [
      for (final sample in samples)
        if (!sample.at.isBefore(from) && sample.at.isBefore(to)) sample,
    ];
  }
}

class _FakeRepository implements SleepingHeartRateRepository {
  final saved = <List<SleepingHeartRateNight>>[];
  Object? failure;

  @override
  Future<int> persist(List<SleepingHeartRateNight> nights) async {
    final error = failure;
    if (error != null) throw error;
    saved.add(nights);
    return nights.length;
  }
}

void main() {
  group('nights from Apple Health sleep', () {
    test('a night is one session, dated by the day it ends', () {
      final nights = sleepNightsFrom(_night());
      expect(nights, hasLength(1));
      expect(nights.single.localDate, '2026-10-16');
      expect(nights.single.start, _at(15, 23));
      expect(nights.single.end, _at(16, 7));
    });

    test('awake time is taken out of the asleep spans', () {
      final night = sleepNightsFrom(_night()).single;
      expect(night.asleep, hasLength(2));
      expect(night.asleepMinutes, 7 * 60 + 40);
      expect(night.asleep.first.end, _at(16, 3));
      expect(night.asleep.last.start, _at(16, 3, 20));
    });

    test('an awake span overlapping another source is still taken out', () {
      final night = sleepNightsFrom([
        _sleep(_at(15, 23), _at(16, 7), SleepStage.asleep, 'a'),
        _sleep(_at(16, 2), _at(16, 3), SleepStage.awake, 'b'),
      ]).single;
      expect(night.asleepMinutes, 8 * 60 - 60);
    });

    test('a nap or a short session is not a night', () {
      expect(
        sleepNightsFrom([
          _sleep(_at(16, 14), _at(16, 15, 30), SleepStage.asleep),
        ]),
        isEmpty,
      );
      expect(
        sleepNightsFrom([
          _sleep(_at(15, 23), _at(16, 3), SleepStage.awake, 'a'),
          _sleep(_at(16, 3), _at(16, 4), SleepStage.light, 'b'),
        ]),
        isEmpty,
      );
    });

    test('sessions less than an hour apart join; further apart they split', () {
      final joined = sleepNightsFrom([
        _sleep(_at(15, 23), _at(16, 3), SleepStage.light, 'a'),
        _sleep(_at(16, 3, 50), _at(16, 7), SleepStage.deep, 'b'),
      ]);
      expect(joined, hasLength(1));
      final split = sleepNightsFrom([
        _sleep(_at(14, 23), _at(15, 6), SleepStage.light, 'a'),
        _sleep(_at(15, 23), _at(16, 6), SleepStage.light, 'b'),
      ]);
      expect(split.map((n) => n.localDate), ['2026-10-15', '2026-10-16']);
    });

    test('other metrics are ignored', () {
      expect(
        sleepNightsFrom([
          RawHealthSample(
            metric: HealthMetric.steps,
            value: 10,
            start: _at(16, 1),
            end: _at(16, 2),
            sampleId: 'x',
            sourceId: 'phone',
          ),
        ]),
        isEmpty,
      );
    });
  });

  group('summarising a night', () {
    final night = sleepNightsFrom(_night()).single;

    test('median, lowest slot mean, count and coverage', () {
      final summary = summariseSleepingHeartRate(
        night,
        _readings(_at(15, 22), _at(16, 8), bpm: (at) => at.hour == 5 ? 46 : 54),
      )!;
      expect(summary.localDate, '2026-10-16');
      expect(summary.medianBpm, 54);
      expect(summary.lowestBpm, 46);
      expect(summary.asleepMinutes, 460);
      // Readings every 5 minutes from 22:00: only those asleep count (not
      // 22:00-23:00, the 4 taken in the 20 awake minutes or 07:00-08:00).
      expect(summary.sampleCount, 92);
      expect(summary.coverage, 1);
    });

    test('lowest never exceeds the median', () {
      final summary = summariseSleepingHeartRate(
        night,
        _readings(_at(15, 23), _at(16, 7)),
      )!;
      expect(summary.lowestBpm, lessThanOrEqualTo(summary.medianBpm));
    });

    test('readings awake or implausible do not count', () {
      final readings = [
        ..._readings(_at(15, 23), _at(16, 7)),
        HeartRateSample(at: _at(16, 3, 5), bpm: 40),
        HeartRateSample(at: _at(16, 4), bpm: 250),
        HeartRateSample(at: _at(16, 4, 1), bpm: 10),
      ];
      final summary = summariseSleepingHeartRate(night, readings)!;
      expect(summary.medianBpm, 52);
      expect(summary.lowestBpm, 52);
      expect(summary.sampleCount, 92);
    });

    test('too few readings or too little coverage gives no row', () {
      expect(
        summariseSleepingHeartRate(
          night,
          _readings(_at(15, 23), _at(16, 7), everyMinutes: 30),
        ),
        isNull,
      );
      expect(
        summariseSleepingHeartRate(
          night,
          _readings(_at(15, 23), _at(16, 1), everyMinutes: 2),
        ),
        isNull,
      );
      expect(summariseSleepingHeartRate(night, const []), isNull);
    });
  });

  group('the recorder', () {
    late _FakeReader reader;
    late _FakeRepository repository;
    late SleepingHeartRateRecorder recorder;
    var now = _at(16, 9);

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      reader = _FakeReader()..samples = _readings(_at(15, 22), _at(16, 8));
      repository = _FakeRepository();
      now = _at(16, 9);
      recorder = SleepingHeartRateRecorder(
        reader: reader,
        repository: repository,
        preferences: SharedPreferencesAsync(),
        userId: () => 'user-1',
        clock: () => now,
      );
    });

    test('reads the night in short windows and saves one summary', () async {
      await recorder.record(_night());
      expect(repository.saved, hasLength(1));
      expect(repository.saved.single.single.localDate, '2026-10-16');
      expect(repository.saved.single.single.medianBpm, 52);
      expect(reader.reads, hasLength(3));
      for (final (from, to) in reader.reads) {
        expect(
          to.difference(from),
          lessThanOrEqualTo(const Duration(hours: 4)),
        );
      }
      expect(reader.reads.first.$1, _at(15, 23));
      expect(reader.reads.last.$2, _at(16, 7));
    });

    test('no sleep means no reads and no save', () async {
      await recorder.record(const []);
      expect(reader.reads, isEmpty);
      expect(repository.saved, isEmpty);
    });

    test('a night that ended over a week ago is left alone', () async {
      now = _at(25, 9);
      await recorder.record(_night());
      expect(reader.reads, isEmpty);
      expect(repository.saved, isEmpty);
    });

    test('no heart-rate access means no row, not an invented one', () async {
      reader.samples = [];
      await recorder.record(_night());
      expect(repository.saved, isEmpty);
    });

    test('a failing read or save never throws', () async {
      reader.failing = true;
      await recorder.record(_night());
      reader.failing = false;
      repository.failure = StateError('offline');
      await recorder.record(_night());
      expect(repository.saved, isEmpty);
    });

    test('a night is read again until it is two days old, then kept', () async {
      await recorder.record(_night());
      await recorder.record(_night());
      expect(repository.saved, hasLength(2));
      now = _at(19, 9);
      await recorder.record(_night());
      expect(repository.saved, hasLength(3));
      final reads = reader.reads.length;
      await recorder.record(_night());
      expect(repository.saved, hasLength(3));
      expect(reader.reads.length, reads);
    });

    test('nobody signed in means nothing happens', () async {
      final signedOut = SleepingHeartRateRecorder(
        reader: reader,
        repository: repository,
        preferences: SharedPreferencesAsync(),
        userId: () => null,
        clock: () => now,
      );
      await signedOut.record(_night());
      expect(reader.reads, isEmpty);
    });
  });
}
