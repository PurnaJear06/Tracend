/// The heart-rate summary of one set (coaching platform Contract 4), worked
/// out on the phone from Apple Health samples. Only these summaries leave the
/// phone, never the samples. Heart rate never sets a load or a prescription.
library;

import 'package:flutter/foundation.dart';

/// One heart-rate reading from Apple Health.
@immutable
class HeartRateSample {
  const HeartRateSample({required this.at, required this.bpm});

  final DateTime at;
  final double bpm;
}

/// Where a set's samples came from, judged by how close together they are.
enum HeartRateSource {
  /// A Watch workout was sampling every few seconds.
  watchWorkout('watch_workout'),

  /// Sparser samples, such as the Watch's own background readings.
  background('background');

  const HeartRateSource(this.key);

  final String key;

  static HeartRateSource? fromKey(Object? key) {
    for (final source in values) {
      if (source.key == key) return source;
    }
    return null;
  }
}

/// How long after a set ends its recovery is watched.
const setHeartRateTail = Duration(seconds: 60);

/// The longest set that is summarised; a longer gap between a start and an end
/// is a clock error, not a set.
const maxSetHeartRateWindow = Duration(minutes: 20);

/// How far a reading may be from a moment and still stand for it. A read
/// reaches this far beyond a set's window so its first and last moments are
/// covered.
const heartRatePointTolerance = Duration(seconds: 10);

/// Coverage counts the slots of this length that hold at least one reading.
const _coverageSlot = Duration(seconds: 10);

/// Readings this close together (median) mean a Watch workout was running.
const _watchWorkoutGap = Duration(seconds: 10);

/// Readings outside this range are not heart rates (a sensor fault).
const _lowestBpm = 30;
const _highestBpm = 250;

/// What one set's heart rate did. A value is null when no reading was close
/// enough to its moment: nothing is guessed.
@immutable
class SetHeartRateSummary {
  const SetHeartRateSummary({
    required this.exerciseOrder,
    required this.setNumber,
    required this.coverage,
    required this.sampleCount,
    required this.source,
    this.startBpm,
    this.peakBpm,
    this.endBpm,
    this.drop30sBpm,
    this.drop60sBpm,
  });

  factory SetHeartRateSummary.fromJson(Map<String, dynamic> json) =>
      SetHeartRateSummary(
        exerciseOrder: (json['exercise_order'] as num).toInt(),
        setNumber: (json['set_number'] as num).toInt(),
        startBpm: (json['start_bpm'] as num?)?.toInt(),
        peakBpm: (json['peak_bpm'] as num?)?.toInt(),
        endBpm: (json['end_bpm'] as num?)?.toInt(),
        drop30sBpm: (json['drop_30s_bpm'] as num?)?.toInt(),
        drop60sBpm: (json['drop_60s_bpm'] as num?)?.toInt(),
        coverage: (json['coverage'] as num).toDouble(),
        sampleCount: (json['sample_count'] as num).toInt(),
        source:
            HeartRateSource.fromKey(json['source']) ??
            HeartRateSource.background,
      );

  final int exerciseOrder;
  final int setNumber;

  /// Beats per minute when the set began, at its end, and at the highest
  /// point during it.
  final int? startBpm;
  final int? peakBpm;
  final int? endBpm;

  /// How far the heart rate fell between the end of the set and 30 and 60
  /// seconds later; negative when it rose.
  final int? drop30sBpm;
  final int? drop60sBpm;

  /// The share, 0 to 1, of the set and the minute after it that has readings.
  final double coverage;
  final int sampleCount;
  final HeartRateSource source;

  /// The save payload, the keys `persist_set_heart_rate_v1` reads.
  Map<String, Object?> toJson() => {
    'exercise_order': exerciseOrder,
    'set_number': setNumber,
    'start_bpm': startBpm,
    'peak_bpm': peakBpm,
    'end_bpm': endBpm,
    'drop_30s_bpm': drop30sBpm,
    'drop_60s_bpm': drop60sBpm,
    'coverage': coverage,
    'sample_count': sampleCount,
    'source': source.key,
  };
}

/// Summarises the set that ran from [startedAt] to [completedAt] and the
/// [setHeartRateTail] after it from [samples]. Null when the set has no
/// reading in that window or its times are not a real set.
SetHeartRateSummary? summarizeSetHeartRate({
  required int exerciseOrder,
  required int setNumber,
  required DateTime startedAt,
  required DateTime completedAt,
  required List<HeartRateSample> samples,
}) {
  if (completedAt.isBefore(startedAt) ||
      completedAt.difference(startedAt) > maxSetHeartRateWindow) {
    return null;
  }
  final windowEnd = completedAt.add(setHeartRateTail);
  final readings = [
    for (final sample in samples)
      if (sample.bpm >= _lowestBpm && sample.bpm <= _highestBpm) sample,
  ]..sort((a, b) => a.at.compareTo(b.at));
  final inWindow = [
    for (final sample in readings)
      if (!sample.at.isBefore(startedAt) && !sample.at.isAfter(windowEnd))
        sample,
  ];
  if (inWindow.isEmpty) return null;

  HeartRateSample? near(DateTime moment) {
    HeartRateSample? best;
    var bestGap = heartRatePointTolerance + const Duration(microseconds: 1);
    for (final sample in readings) {
      final gap = sample.at.difference(moment).abs();
      if (gap < bestGap) {
        best = sample;
        bestGap = gap;
      }
    }
    return best;
  }

  final start = near(startedAt);
  final end = near(completedAt);
  int? drop(DateTime later) {
    final reading = near(later);
    if (end == null || reading == null) return null;
    return end.bpm.round() - reading.bpm.round();
  }

  final duringSet = [
    for (final sample in inWindow)
      if (!sample.at.isAfter(completedAt)) sample.bpm.round(),
    ?start?.bpm.round(),
    ?end?.bpm.round(),
  ];

  final totalMillis = windowEnd.difference(startedAt).inMilliseconds;
  final slotMillis = _coverageSlot.inMilliseconds;
  final slots = (totalMillis / slotMillis).ceil();
  final filled = <int>{
    for (final sample in inWindow)
      (sample.at.difference(startedAt).inMilliseconds ~/ slotMillis).clamp(
        0,
        slots - 1,
      ),
  };

  return SetHeartRateSummary(
    exerciseOrder: exerciseOrder,
    setNumber: setNumber,
    startBpm: start?.bpm.round(),
    peakBpm: duringSet.isEmpty
        ? null
        : duringSet.reduce((a, b) => a > b ? a : b),
    endBpm: end?.bpm.round(),
    drop30sBpm: drop(completedAt.add(const Duration(seconds: 30))),
    drop60sBpm: drop(windowEnd),
    coverage: (filled.length / slots * 1000).round() / 1000,
    sampleCount: inWindow.length,
    source: _isWatchWorkout(inWindow)
        ? HeartRateSource.watchWorkout
        : HeartRateSource.background,
  );
}

bool _isWatchWorkout(List<HeartRateSample> readings) {
  if (readings.length < 3) return false;
  final gaps = [
    for (var i = 1; i < readings.length; i++)
      readings[i].at.difference(readings[i - 1].at),
  ]..sort();
  return gaps[gaps.length ~/ 2] <= _watchWorkoutGap;
}
