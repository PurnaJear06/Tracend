import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_summary.dart';

final _start = DateTime.utc(2026, 10, 16, 9, 0, 0);

// A 40 second set; the window runs to 100 seconds (set plus 60 seconds).
final _end = _start.add(const Duration(seconds: 40));

HeartRateSample _at(int second, double bpm) => HeartRateSample(
  at: _start.add(Duration(seconds: second)),
  bpm: bpm,
);

SetHeartRateSummary? _summary(List<HeartRateSample> samples) =>
    summarizeSetHeartRate(
      exerciseOrder: 1,
      setNumber: 2,
      startedAt: _start,
      completedAt: _end,
      samples: samples,
    );

/// A reading every [step] seconds across the whole window, rising to 150 at
/// the end of the set and falling 1 bpm per second after it.
List<HeartRateSample> _steady({int step = 5}) => [
  for (var second = 0; second <= 100; second += step)
    _at(second, second <= 40 ? 110 + second * 1.0 : 150 - (second - 40) * 1.0),
];

void main() {
  group('summarizeSetHeartRate', () {
    test('a Watch workout gives every value and full coverage', () {
      final summary = _summary(_steady())!;

      expect(summary.exerciseOrder, 1);
      expect(summary.setNumber, 2);
      expect(summary.startBpm, 110);
      expect(summary.peakBpm, 150);
      expect(summary.endBpm, 150);
      expect(summary.drop30sBpm, 30);
      expect(summary.drop60sBpm, 60);
      expect(summary.coverage, 1);
      expect(summary.sampleCount, 21);
      expect(summary.source, HeartRateSource.watchWorkout);
    });

    test('no samples gives no summary', () {
      expect(_summary(const []), isNull);
    });

    test('samples only outside the window give no summary', () {
      expect(_summary([_at(-60, 90), _at(200, 80)]), isNull);
    });

    test('readings that are not heart rates are ignored', () {
      expect(_summary([_at(5, 0), _at(10, 400)]), isNull);
      final summary = _summary([..._steady(), _at(12, 0), _at(14, 400)])!;
      expect(summary.sampleCount, 21);
      expect(summary.peakBpm, 150);
    });

    test('coverage is the share of 10 second slots that hold a reading', () {
      // Ten slots in 100 seconds; readings in the first five only.
      final summary = _summary([
        _at(2, 100),
        _at(15, 105),
        _at(25, 110),
        _at(35, 112),
        _at(45, 120),
      ])!;

      expect(summary.coverage, 0.5);
      expect(summary.sampleCount, 5);
    });

    test('a gap in the middle lowers coverage and keeps the rest', () {
      final readings = [
        for (final reading in _steady())
          if (reading.at.difference(_start).inSeconds < 20 ||
              reading.at.difference(_start).inSeconds >= 60)
            reading,
      ];
      final summary = _summary(readings)!;

      expect(summary.coverage, closeTo(0.6, 0.001));
      expect(summary.startBpm, 110);
      // Nothing near the end of the set, so there is no drop to measure.
      expect(summary.endBpm, isNull);
      expect(summary.drop60sBpm, isNull);
    });

    test('a reading exactly at the end of the window counts', () {
      final summary = _summary([_at(100, 90)])!;
      expect(summary.sampleCount, 1);
      expect(summary.coverage, 0.1);
    });

    test('a value with no reading near its moment stays empty', () {
      // One reading at 25 s: nothing within 10 s of the start (0 s), the end
      // (40 s is 15 s away), 70 s or 100 s.
      final summary = _summary([_at(25, 130)])!;

      expect(summary.startBpm, isNull);
      expect(summary.endBpm, isNull);
      expect(summary.drop30sBpm, isNull);
      expect(summary.drop60sBpm, isNull);
      expect(summary.peakBpm, 130);
      expect(summary.sampleCount, 1);
    });

    test(
      'a drop needs a reading near the end and one near the later moment',
      () {
        final summary = _summary([_at(45, 140), _at(52, 138)])!;

        expect(summary.endBpm, 140);
        expect(summary.drop30sBpm, isNull);
        expect(summary.drop60sBpm, isNull);
      },
    );

    test('the drop is negative when the heart rate kept rising', () {
      final summary = _summary([
        _at(0, 100),
        _at(40, 130),
        _at(70, 150),
        _at(100, 155),
      ])!;

      expect(summary.endBpm, 130);
      expect(summary.drop30sBpm, -20);
      expect(summary.drop60sBpm, -25);
      expect(summary.peakBpm, 130);
    });

    test('the peak is the highest reading during the set only', () {
      final summary = _summary([_at(10, 120), _at(30, 140), _at(50, 170)])!;
      expect(summary.peakBpm, 140);
    });

    test('sparse readings are background, even with full-minute spacing', () {
      final summary = _summary([_at(0, 100), _at(50, 110), _at(100, 105)])!;
      expect(summary.source, HeartRateSource.background);
    });

    test('fewer than three readings are never a Watch workout', () {
      expect(
        _summary([_at(0, 100), _at(5, 101)])!.source,
        HeartRateSource.background,
      );
    });

    test('readings every 5 seconds with a few gaps are still a workout', () {
      final readings = [
        for (final reading in _steady())
          if (reading.at.difference(_start).inSeconds != 20) reading,
      ];
      expect(_summary(readings)!.source, HeartRateSource.watchWorkout);
    });

    test('unsorted readings give the same summary', () {
      final shuffled = _steady().reversed.toList();
      final a = _summary(shuffled)!;
      final b = _summary(_steady())!;
      expect(a.toJson(), b.toJson());
    });

    test(
      'a set that ends before it starts or runs too long has no summary',
      () {
        expect(
          summarizeSetHeartRate(
            exerciseOrder: 1,
            setNumber: 1,
            startedAt: _end,
            completedAt: _start,
            samples: _steady(),
          ),
          isNull,
        );
        expect(
          summarizeSetHeartRate(
            exerciseOrder: 1,
            setNumber: 1,
            startedAt: _start,
            completedAt: _start.add(const Duration(minutes: 21)),
            samples: _steady(),
          ),
          isNull,
        );
      },
    );

    test('a set ticked at the instant it started still has a window', () {
      final summary = summarizeSetHeartRate(
        exerciseOrder: 1,
        setNumber: 1,
        startedAt: _start,
        completedAt: _start,
        samples: [_at(0, 100), _at(30, 95), _at(60, 90)],
      )!;
      expect(summary.startBpm, 100);
      expect(summary.endBpm, 100);
      expect(summary.drop30sBpm, 5);
      expect(summary.drop60sBpm, 10);
    });

    test('the save payload holds whole beats and the source key', () {
      final json = _summary([_at(0, 100.4), _at(40, 130.6)])!.toJson();
      expect(json['start_bpm'], 100);
      expect(json['end_bpm'], 131);
      expect(json['source'], 'background');
    });
  });
}
