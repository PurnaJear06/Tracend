import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/train/muscle_groups.dart';
import 'package:tracend/features/train/workout_repository.dart';

/// Pure view models for the Train screen. Every value here is derived
/// deterministically from the hub or the daily brief; nothing is guessed.

// ---------------------------------------------------------------------------
// Plan week
// ---------------------------------------------------------------------------

/// The plan pill: "Week N of M", or "Week N" once the block has ended.
@immutable
class PlanWeek {
  const PlanWeek({required this.week, this.blockWeeks});

  /// 1-based week since the plan's effective date.
  final int week;

  /// The block length; null after the block ends or when the plan has none.
  final int? blockWeeks;

  String get label =>
      blockWeeks == null ? 'Week $week' : 'Week $week of $blockWeeks';

  /// Null when either date is missing (a cached 1.5 hub) or the plan has not
  /// started yet, so the pill is hidden rather than showing a false week.
  static PlanWeek? from({
    required DateTime? effectiveDate,
    required DateTime? localToday,
    int? blockWeeks,
  }) {
    if (effectiveDate == null || localToday == null) return null;
    final start = DateTime.utc(
      effectiveDate.year,
      effectiveDate.month,
      effectiveDate.day,
    );
    final today = DateTime.utc(
      localToday.year,
      localToday.month,
      localToday.day,
    );
    final days = today.difference(start).inDays;
    if (days < 0) return null;
    final week = days ~/ 7 + 1;
    final block = blockWeeks != null && blockWeeks > 0 && week <= blockWeeks
        ? blockWeeks
        : null;
    return PlanWeek(week: week, blockWeeks: block);
  }
}

// ---------------------------------------------------------------------------
// Readiness line
// ---------------------------------------------------------------------------

/// The five recovery bands of ALGORITHMS.md §1 "Recovery Score Bands".
enum RecoveryBand { excellent, good, moderate, low, poor }

/// One plain sentence about recovery state. It never adds advice, so it can
/// never contradict Today's coach decision.
@immutable
class ReadinessLine {
  const ReadinessLine._(this.text, {this.band, this.needsHealth = false});

  final String text;

  /// Null while the baseline builds or Apple Health is not connected.
  final RecoveryBand? band;

  /// Apple Health is not connected; the line links to Account.
  final bool needsHealth;

  static ReadinessLine from({
    required bool healthConnected,
    required int? recoveryScore,
  }) {
    if (!healthConnected) {
      return const ReadinessLine._(
        'Connect Apple Health to see recovery',
        needsHealth: true,
      );
    }
    final score = recoveryScore;
    if (score == null) return const ReadinessLine._('Building your baseline.');
    if (score >= 80) {
      return const ReadinessLine._(
        'Recovery is excellent.',
        band: RecoveryBand.excellent,
      );
    }
    if (score >= 65) {
      return const ReadinessLine._(
        'Recovery is good.',
        band: RecoveryBand.good,
      );
    }
    if (score >= 50) {
      return const ReadinessLine._(
        'Recovery is moderate.',
        band: RecoveryBand.moderate,
      );
    }
    if (score >= 35) {
      return const ReadinessLine._(
        'Recovery is low today.',
        band: RecoveryBand.low,
      );
    }
    return const ReadinessLine._(
      'Recovery is poor today.',
      band: RecoveryBand.poor,
    );
  }

  /// Connected, partial and stale all mean Apple Health is linked; manual-only
  /// and unavailable mean it is not.
  static bool isHealthConnected(HealthConnectionState state) => switch (state) {
    HealthConnectionState.connected ||
    HealthConnectionState.partial ||
    HealthConnectionState.stale => true,
    HealthConnectionState.manualOnly ||
    HealthConnectionState.unavailable => false,
  };
}

// ---------------------------------------------------------------------------
// Training load sheet
// ---------------------------------------------------------------------------

/// The ACWR zones of `LoadBand.forAcwr` (ALGORITHMS §4 "ACWR Bands").
enum LoadZone { low, normal, high }

/// A day bar's class. [calibrating] is a trained day whose effort was a
/// default, so it has no honest intensity yet.
enum LoadBarKind { rest, easy, moderate, hard, calibrating }

@immutable
class LoadDayBar {
  const LoadDayBar({
    required this.date,
    required this.kind,
    required this.isToday,
    required this.minutes,
    required this.strain,
    required this.heightFraction,
  });

  final DateTime date;
  final LoadBarKind kind;
  final bool isToday;
  final int minutes;
  final double strain;

  /// 0–1 of the chart height; 0 for rest days, which draw a socket.
  final double heightFraction;

  bool get trained => kind != LoadBarKind.rest;

  /// "M", "T", ... or "Today".
  String get shortLabel =>
      isToday ? 'Today' : _weekdayLetters[date.weekday - 1];

  /// "Tuesday 30" or "Today".
  String get dayName =>
      isToday ? 'Today' : '${_weekdayNames[date.weekday - 1]} ${date.day}';

  /// The tapped bar's line, for example "Tuesday 30: 52 min, hard".
  String get detail => switch (kind) {
    LoadBarKind.rest => '$dayName: ${isToday ? 'not trained yet' : 'rest day'}',
    LoadBarKind.calibrating =>
      '$dayName: $minutes min, effort not reported, calibrating',
    _ => '$dayName: $minutes min, ${kind.name}',
  };

  /// The bar's accessibility label.
  String get semanticsLabel => switch (kind) {
    LoadBarKind.rest => '$dayName: ${isToday ? 'not trained yet' : 'rest'}',
    LoadBarKind.calibrating => '$dayName: $minutes minutes, calibrating',
    _ => '$dayName: $minutes minutes, ${kind.name}',
  };
}

/// The "How this is calculated" disclosure.
@immutable
class LoadExplanation {
  const LoadExplanation({
    required this.strainText,
    required this.ratioText,
    required this.dayText,
    this.monotonyText,
  });

  final String strainText;

  /// The ratio and the 0.8–1.3 normal range, or why there is no ratio yet.
  final String ratioText;
  final String dayText;

  /// Null when monotony has no value yet.
  final String? monotonyText;

  List<String> get paragraphs => [
    strainText,
    ratioText,
    dayText,
    ?monotonyText,
  ];
}

/// The Training load sheet (Phase 0 round 3), built only from the hub's
/// `daily_load` and `computed`, with the thresholds of `LoadBand.forAcwr`
/// and the monotony rule of the week rail.
@immutable
class TrainingLoadSheetModel {
  const TrainingLoadSheetModel({
    required this.hasReading,
    required this.calibrating,
    required this.rowLabel,
    required this.verdict,
    required this.subtitle,
    required this.days,
    required this.advice,
    required this.explanation,
    this.zone,
    this.acwr,
    this.scalePosition,
  });

  /// Low end of the normal range (ALGORITHMS §4).
  static const normalLow = 0.8;

  /// High end of the normal range.
  static const normalHigh = 1.3;

  /// Above this the copy escalates to "scale back", never a fourth band.
  static const scaleBackAbove = 1.5;

  /// Monotony above this means the days are too similar.
  static const monotonyWarningAbove = 2.0;

  /// The ratio drawn at the scale's left and right ends.
  static const scaleMin = 0.5;
  static const scaleMax = 1.8;

  /// Sessions in the 28-day window beneath an honest ratio verdict (the week
  /// rail's thin-history gate, finding #6).
  static const minSessionsForReading = 4;

  /// Where the normal zone starts and ends on the 0–1 scale.
  static double get normalStartFraction => _scale(normalLow);
  static double get normalEndFraction => _scale(normalHigh);

  /// Strain drawn at full bar height unless a day was heavier.
  static const chartStrainCeiling = 50.0;

  static const footnote =
      'Calculated from your logged workouts. No AI estimates.';

  /// False in the new-user mode: no ratio, no scale marker.
  final bool hasReading;

  /// The 28-day window still holds default-effort sessions.
  final bool calibrating;

  /// The "This week" row value, for example "About normal, calibrating".
  final String rowLabel;

  /// The sheet's first line, for example "About normal for you".
  final String verdict;
  final String subtitle;

  final LoadZone? zone;
  final double? acwr;

  /// 0–1 position of the "You" marker; null without a reading.
  final double? scalePosition;

  /// The last 7 days, oldest first, ending today.
  final List<LoadDayBar> days;

  /// The legend lists "Calibrating" only while a shown day needs it.
  bool get showCalibratingLegend =>
      days.any((day) => day.kind == LoadBarKind.calibrating);

  /// The bar selected when the sheet opens: the latest trained day.
  int get initialSelectedIndex {
    for (var i = days.length - 1; i >= 0; i--) {
      if (days[i].trained) return i;
    }
    return days.isEmpty ? 0 : days.length - 1;
  }

  /// One line, chosen only from the ACWR band and monotony rules.
  final String advice;
  final LoadExplanation explanation;

  static const calibratingNote =
      'Calibrating. Older workouts used a default effort, so their days are '
      'shaded as unknown. This firms up as you rate each workout.';

  static double _scale(double ratio) =>
      ((ratio - scaleMin) / (scaleMax - scaleMin)).clamp(0.0, 1.0);

  static TrainingLoadSheetModel from({
    required List<DailyLoadDay> dailyLoad,
    required double? acwr,
    required double? monotony,
    DateTime? localToday,
  }) {
    final sessions = dailyLoad.fold<int>(0, (sum, day) => sum + day.sessions);
    final calibrating = dailyLoad.any(
      (day) => day.recorded && !day.effortReported,
    );
    final ratio = acwr != null && sessions >= minSessionsForReading
        ? acwr
        : null;
    final days = _bars(dailyLoad, localToday);
    final mono = ratio == null ? null : monotony;

    if (ratio == null) {
      return TrainingLoadSheetModel(
        hasReading: false,
        calibrating: calibrating,
        rowLabel: 'Builds as you train',
        verdict: 'Your load reading builds as you train',
        subtitle:
            'After about two weeks of workouts, this compares your last 7 '
            'days with your usual.',
        days: days,
        advice: 'Follow the plan as written.',
        explanation: _explanation(ratio: null, monotony: null, days: dailyLoad),
      );
    }

    final zone = ratio < normalLow
        ? LoadZone.low
        : ratio <= normalHigh
        ? LoadZone.normal
        : LoadZone.high;
    final short = switch (zone) {
      LoadZone.low => 'Lighter than normal',
      LoadZone.normal => 'About normal',
      LoadZone.high when ratio > scaleBackAbove => 'Much heavier than normal',
      LoadZone.high => 'Heavier than normal',
    };
    return TrainingLoadSheetModel(
      hasReading: true,
      calibrating: calibrating,
      rowLabel: calibrating ? '$short, calibrating' : '$short for you',
      verdict: '$short for you',
      subtitle: 'Last 7 days compared with your usual 4 weeks',
      zone: zone,
      acwr: ratio,
      scalePosition: _scale(ratio),
      days: days,
      advice: _advice(ratio, mono),
      explanation: _explanation(ratio: ratio, monotony: mono, days: dailyLoad),
    );
  }

  static String _advice(double ratio, double? monotony) {
    if (ratio > scaleBackAbove) {
      return 'Much heavier than your normal. Scale back to protect progress.';
    }
    if (monotony != null && monotony > monotonyWarningAbove) {
      return 'Your days are too similar. Vary how hard they are.';
    }
    if (ratio > normalHigh) {
      return 'Heavier than your normal, still in a workable range.';
    }
    if (monotony != null) return 'Your hard and easy days are well mixed.';
    return ratio < normalLow
        ? 'Lighter than your normal training.'
        : 'This matches your normal training.';
  }

  static LoadExplanation _explanation({
    required double? ratio,
    required double? monotony,
    required List<DailyLoadDay> days,
  }) {
    final personal = days.any(
      (day) => day.recorded && day.level != null && day.personalReference,
    );
    return LoadExplanation(
      strainText:
          'Each workout counts as minutes times how hard you said it felt, '
          'divided by 10.',
      ratioText: ratio == null
          ? 'The normal range needs about two weeks of workouts first.'
          : 'Your last 7 days divided by your 4-week average is '
                '${ratio.toStringAsFixed(2)}. From 0.8 to 1.3 counts as normal.',
      dayText: personal
          ? 'A day is easy, moderate or hard compared with your own last 4 '
                'weeks, not anyone else’s.'
          : 'Until you have 8 days of rated workouts, a day under 20 is '
                'easy, up to 40 is moderate, and above that is hard. After '
                'that, days are compared with your own last 4 weeks.',
      monotonyText: monotony == null
          ? null
          : monotony > monotonyWarningAbove
          ? 'Your days have been very alike in load, called monotony. Mixing '
                'hard and easy days helps you recover.'
          : 'Your hard and easy days are well mixed, so there is no sign of '
                'monotony.',
    );
  }

  static List<LoadDayBar> _bars(List<DailyLoadDay> load, DateTime? localToday) {
    if (load.isEmpty) return const [];
    final week = load.length <= 7 ? load : load.sublist(load.length - 7);
    final today = localToday ?? load.last.date;
    final peak = week.fold<double>(0, (m, day) => math.max(m, day.strain));
    final ceiling = math.max(chartStrainCeiling, peak);
    return [
      for (final day in week)
        LoadDayBar(
          date: day.date,
          isToday: _sameDay(day.date, today),
          minutes: day.minutes,
          strain: day.strain,
          kind: !day.recorded
              ? LoadBarKind.rest
              : switch (day.level) {
                  null => LoadBarKind.calibrating,
                  DayLoadLevel.rest => LoadBarKind.rest,
                  DayLoadLevel.easy => LoadBarKind.easy,
                  DayLoadLevel.moderate => LoadBarKind.moderate,
                  DayLoadLevel.hard => LoadBarKind.hard,
                },
          heightFraction: day.recorded ? day.strain / ceiling : 0,
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Muscle sets
// ---------------------------------------------------------------------------

/// How strongly a workout lights a muscle group on the map.
enum MuscleTone {
  /// At least 60% of the top group's sets.
  main,

  /// Worked, but less.
  also,
}

@immutable
class MuscleSets {
  const MuscleSets({
    required this.group,
    required this.sets,
    required this.tone,
  });
  final MuscleGroup group;
  final int sets;
  final MuscleTone tone;

  @override
  bool operator ==(Object other) =>
      other is MuscleSets &&
      other.group == group &&
      other.sets == sets &&
      other.tone == tone;

  @override
  int get hashCode => Object.hash(group, sets, tone);
}

/// Sets per group: each exercise adds its sets to every group in its
/// `primary_muscles`. Unlinked exercises add nothing. Sorted by sets, then
/// the catalog order.
List<MuscleSets> muscleSetsFor(Iterable<PlannedExercise> exercises) {
  final totals = <MuscleGroup, int>{};
  for (final exercise in exercises) {
    if (exercise.exerciseSlug == null) continue;
    for (final group in exercise.primaryMuscles.toSet()) {
      totals[group] = (totals[group] ?? 0) + exercise.setCount;
    }
  }
  if (totals.isEmpty) return const [];
  final top = totals.values.reduce(math.max);
  final entries = totals.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) {
      final bySets = b.value.compareTo(a.value);
      return bySets != 0 ? bySets : a.key.index.compareTo(b.key.index);
    });
  return [
    for (final entry in entries)
      MuscleSets(
        group: entry.key,
        sets: entry.value,
        tone: entry.value >= top * 0.6 ? MuscleTone.main : MuscleTone.also,
      ),
  ];
}

/// The map's input: each worked group's tone.
Map<MuscleGroup, MuscleTone> muscleTones(List<MuscleSets> sets) => {
  for (final entry in sets) entry.group: entry.tone,
};

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
