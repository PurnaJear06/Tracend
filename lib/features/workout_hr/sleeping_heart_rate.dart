/// Sleeping heart rate per night (coaching platform chunk C3, program decision
/// D10): worked out on the phone from Apple Health sleep and heart-rate
/// samples. Only one summary per night leaves the phone. It is in SHADOW MODE:
/// stored and exported, used by no score, readiness line or Coach context
/// until a later reviewed change. Heart rate never sets a load (D9).
library;

import 'package:flutter/foundation.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_summary.dart';

/// Sleep sessions are joined when the gap between them is at most this, and the
/// night belongs to the local day it ends (the same rule the daily sleep totals
/// use).
const sleepSessionGap = Duration(hours: 1);

/// A night needs at least this much sleep; a nap is not a night.
const minimumNightSleep = Duration(hours: 3);

/// Coverage counts 10-minute slots of the night that hold at least one reading.
const sleepCoverageSlot = Duration(minutes: 10);

/// A night is summarised only with this many readings asleep and this share of
/// its slots covered. Less is no row, never a guess.
const minimumSleepingReadings = 20;
const minimumSleepingCoverage = 0.5;

/// Readings outside this range are not sleeping heart rates (a sensor fault).
const _lowestBpm = 30;
const _highestBpm = 200;

/// A half-open interval of time.
@immutable
class TimeSpan {
  const TimeSpan(this.start, this.end);

  final DateTime start;
  final DateTime end;

  Duration get length => end.difference(start);

  bool contains(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(end);
}

/// One night of sleep: the asleep spans (every stage but awake, awake time
/// taken out) inside the session that ends on [localDate].
@immutable
class SleepNight {
  const SleepNight({
    required this.localDate,
    required this.start,
    required this.end,
    required this.asleep,
  });

  /// `YYYY-MM-DD`, the local day the session ends on.
  final String localDate;
  final DateTime start;
  final DateTime end;
  final List<TimeSpan> asleep;

  int get asleepMinutes =>
      asleep.fold<int>(0, (total, span) => total + span.length.inMinutes);
}

List<TimeSpan> _union(List<TimeSpan> spans) {
  final sorted = [...spans]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <TimeSpan>[];
  for (final span in sorted) {
    if (merged.isNotEmpty && !span.start.isAfter(merged.last.end)) {
      if (span.end.isAfter(merged.last.end)) {
        merged[merged.length - 1] = TimeSpan(merged.last.start, span.end);
      }
    } else {
      merged.add(span);
    }
  }
  return merged;
}

List<TimeSpan> _subtract(List<TimeSpan> spans, List<TimeSpan> removed) {
  var rest = spans;
  for (final cut in removed) {
    final next = <TimeSpan>[];
    for (final span in rest) {
      if (!cut.start.isBefore(span.end) || !cut.end.isAfter(span.start)) {
        next.add(span);
        continue;
      }
      if (cut.start.isAfter(span.start)) {
        next.add(TimeSpan(span.start, cut.start));
      }
      if (cut.end.isBefore(span.end)) next.add(TimeSpan(cut.end, span.end));
    }
    rest = next;
  }
  return rest;
}

String _dateKey(DateTime moment) {
  final local = moment.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// The nights in Apple Health's sleep samples, oldest first. A session shorter
/// than three hours, or with under three hours asleep, is a nap and is left out.
List<SleepNight> sleepNightsFrom(List<RawHealthSample> samples) {
  final sleep =
      samples
          .where(
            (sample) =>
                sample.metric == HealthMetric.sleep &&
                sample.sleepStage != null &&
                sample.end.isAfter(sample.start) &&
                sample.end.difference(sample.start) <= const Duration(days: 1),
          )
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  final nights = <SleepNight>[];
  var from = 0;
  var sessionEnd = sleep.isEmpty ? null : sleep.first.end;
  for (var i = 1; i <= sleep.length; i++) {
    if (i < sleep.length &&
        sleep[i].start.difference(sessionEnd!) <= sleepSessionGap) {
      if (sleep[i].end.isAfter(sessionEnd)) sessionEnd = sleep[i].end;
      continue;
    }
    final session = sleep.sublist(from, i);
    final start = session.first.start;
    final end = sessionEnd!;
    final awake = _union([
      for (final s in session)
        if (s.sleepStage == SleepStage.awake) TimeSpan(s.start, s.end),
    ]);
    final asleep = _subtract(
      _union([
        for (final s in session)
          if (s.sleepStage != SleepStage.awake) TimeSpan(s.start, s.end),
      ]),
      awake,
    );
    final night = SleepNight(
      localDate: _dateKey(end),
      start: start,
      end: end,
      asleep: asleep,
    );
    if (end.difference(start) >= minimumNightSleep &&
        night.asleepMinutes >= minimumNightSleep.inMinutes) {
      nights.add(night);
    }
    from = i;
    if (i < sleep.length) sessionEnd = sleep[i].end;
  }
  return nights;
}

/// One night's sleeping heart rate, as `persist_sleeping_heart_rate_v1` takes it.
@immutable
class SleepingHeartRateNight {
  const SleepingHeartRateNight({
    required this.localDate,
    required this.medianBpm,
    required this.lowestBpm,
    required this.sampleCount,
    required this.asleepMinutes,
    required this.coverage,
  });

  final String localDate;

  /// The median of the readings taken asleep.
  final int medianBpm;

  /// The lowest mean of any 10-minute slot asleep (never a single reading).
  final int lowestBpm;
  final int sampleCount;
  final int asleepMinutes;

  /// Share (0 to 1) of the night's 10-minute slots that have readings.
  final double coverage;

  Map<String, Object> toJson() => {
    'local_date': localDate,
    'median_bpm': medianBpm,
    'lowest_bpm': lowestBpm,
    'sample_count': sampleCount,
    'asleep_minutes': asleepMinutes,
    'coverage': (coverage * 1000).round() / 1000,
  };
}

/// The night's sleeping heart rate from [samples], or null when too few
/// readings were taken asleep to say anything (nothing is invented).
SleepingHeartRateNight? summariseSleepingHeartRate(
  SleepNight night,
  List<HeartRateSample> samples,
) {
  final asleep =
      samples
          .where(
            (sample) =>
                sample.bpm >= _lowestBpm &&
                sample.bpm <= _highestBpm &&
                night.asleep.any((span) => span.contains(sample.at)),
          )
          .toList()
        ..sort((a, b) => a.at.compareTo(b.at));
  if (asleep.length < minimumSleepingReadings) return null;
  final slots = <int, List<double>>{};
  for (final sample in asleep) {
    final slot =
        sample.at.difference(night.start).inMinutes ~/
        sleepCoverageSlot.inMinutes;
    slots.putIfAbsent(slot, () => []).add(sample.bpm);
  }
  final totalSlots = (night.asleepMinutes / sleepCoverageSlot.inMinutes).ceil();
  final coverage = totalSlots == 0
      ? 0.0
      : (slots.length / totalSlots).clamp(0.0, 1.0);
  if (coverage < minimumSleepingCoverage) return null;
  final values = [for (final sample in asleep) sample.bpm]..sort();
  final middle = values.length ~/ 2;
  final median = values.length.isOdd
      ? values[middle]
      : (values[middle - 1] + values[middle]) / 2;
  final slotMeans = [
    for (final readings in slots.values)
      readings.reduce((a, b) => a + b) / readings.length,
  ]..sort();
  final medianBpm = median.round();
  final lowestBpm = slotMeans.first.round();
  return SleepingHeartRateNight(
    localDate: night.localDate,
    medianBpm: medianBpm,
    lowestBpm: lowestBpm < medianBpm ? lowestBpm : medianBpm,
    sampleCount: asleep.length,
    asleepMinutes: night.asleepMinutes,
    coverage: coverage,
  );
}
