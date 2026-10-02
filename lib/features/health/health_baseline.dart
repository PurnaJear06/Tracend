import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/health/health_data_source.dart';
import 'package:tracend/features/health/health_models.dart';

/// The athlete's usual months from Apple Health: monthly totals for the 11
/// completed calendar months before this one, computed on the device and sent
/// to the server (save_health_history) without any raw sample. The server
/// decides what counts for the plan (health_history.ts); the app shows the
/// same comparison, with the same thresholds, so the athlete sees what the
/// plan will use.
const healthHistoryMonths = 11;
const healthHistoryMinimumSleepNights = 20;
const healthHistoryMinimumMonths = 3;

/// HealthKit workout types that count as strength training (as on the server).
const strengthWorkoutTypes = {
  'TRADITIONAL_STRENGTH_TRAINING',
  'FUNCTIONAL_STRENGTH_TRAINING',
};

/// What the history reads: workouts, sleep and weight, nothing else.
const healthHistoryMetrics = {
  HealthMetric.workouts,
  HealthMetric.sleep,
  HealthMetric.weight,
};

@immutable
class HealthMonthTotals {
  const HealthMonthTotals({
    required this.month,
    required this.workouts,
    required this.strengthWorkouts,
    required this.workoutMinutes,
    required this.sleepNights,
    required this.sleepMinutesAvg,
    required this.weightDays,
    required this.weightKgAvg,
    required this.dataDays,
    required this.firstDataDate,
    required this.lastDataDate,
  });

  /// The first day of the month.
  final DateTime month;
  final int workouts;
  final int strengthWorkouts;
  final int workoutMinutes;
  final int sleepNights;
  final int? sleepMinutesAvg;
  final int weightDays;
  final double? weightKgAvg;
  final int dataDays;
  final DateTime? firstDataDate;
  final DateTime? lastDataDate;

  int get daysInMonth => DateTime(month.year, month.month + 1, 0).day;

  Map<String, Object?> toJson() => {
    'month': _date(month),
    'workouts': workouts,
    'strength_workouts': strengthWorkouts,
    'workout_minutes': workoutMinutes,
    'sleep_nights': sleepNights,
    'sleep_minutes_avg': sleepMinutesAvg,
    'weight_days': weightDays,
    'weight_kg_avg': weightKgAvg,
    'data_days': dataDays,
    'first_data_date': firstDataDate == null ? null : _date(firstDataDate!),
    'last_data_date': lastDataDate == null ? null : _date(lastDataDate!),
  };
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// The first instant the history reads from: the start of the month 11 months
/// before this one.
DateTime healthHistoryStart(DateTime now) =>
    DateTime(now.year, now.month - healthHistoryMonths, 1);

/// Monthly totals for the completed months in the window, from raw samples.
/// Sleep is attributed to the night's waking day and weight to its day, as the
/// daily sync does; a month with no data at all is left out.
List<HealthMonthTotals> healthMonthTotals(
  List<RawHealthSample> samples,
  DateTime now,
) {
  final first = healthHistoryStart(now);
  final thisMonth = DateTime(now.year, now.month);
  final days = normalizeHealthSamples(
    samples: samples,
    requestedMetrics: healthHistoryMetrics,
    timezone: now.timeZoneName,
  );
  final workouts = samples
      .where((sample) => sample.metric == HealthMetric.workouts)
      .toList();
  final months = <HealthMonthTotals>[];
  for (var index = 0; index < healthHistoryMonths; index++) {
    final month = DateTime(first.year, first.month + index);
    if (!month.isBefore(thisMonth)) break;
    bool inMonth(DateTime day) =>
        day.year == month.year && day.month == month.month;
    final monthDays = days.where((day) => inMonth(day.localDate)).toList();
    final monthWorkouts = workouts
        .where((sample) => inMonth(sample.start.toLocal()))
        .toList();
    final sleep = [
      for (final day in monthDays)
        if ((day.sleepMinutes ?? 0) > 0) day.sleepMinutes!,
    ];
    final weights = [
      for (final day in monthDays)
        if ((day.weightKg ?? 0) > 0) day.weightKg!,
    ];
    final dataDates = {
      for (final day in monthDays) day.localDate,
      for (final sample in monthWorkouts)
        DateTime(
          sample.start.toLocal().year,
          sample.start.toLocal().month,
          sample.start.toLocal().day,
        ),
    }.toList()..sort();
    if (dataDates.isEmpty) continue;
    months.add(
      HealthMonthTotals(
        month: month,
        workouts: monthWorkouts.length,
        strengthWorkouts: monthWorkouts
            .where(
              (sample) => strengthWorkoutTypes.contains(
                sample.workoutActivityType?.toUpperCase(),
              ),
            )
            .length,
        workoutMinutes: monthWorkouts.fold(
          0,
          (total, sample) =>
              total + sample.end.difference(sample.start).inMinutes,
        ),
        sleepNights: sleep.length,
        sleepMinutesAvg: sleep.isEmpty
            ? null
            : (sleep.reduce((a, b) => a + b) / sleep.length).round(),
        weightDays: weights.length,
        weightKgAvg: weights.isEmpty
            ? null
            : (weights.reduce((a, b) => a + b) / weights.length * 10).round() /
                  10,
        dataDays: dataDates.length,
        firstDataDate: dataDates.first,
        lastDataDate: dataDates.last,
      ),
    );
  }
  return months;
}

/// Usual vs recent, as the Apple Health step shows it.
@immutable
class HealthBaseline {
  const HealthBaseline({
    required this.months,
    this.usualStrengthPerWeek,
    this.recentStrengthPerWeek,
    this.usualSleepMinutes,
  });

  /// Months with any data.
  final int months;

  /// Median strength workouts a week, from the first month with a workout.
  final double? usualStrengthPerWeek;

  /// Strength workouts a week over the last 28 complete days.
  final double? recentStrengthPerWeek;
  final int? usualSleepMinutes;

  bool get hasUsual =>
      usualStrengthPerWeek != null || usualSleepMinutes != null;
}

double _oneDecimal(double value) => (value * 10).round() / 10;

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

HealthBaseline healthBaseline(
  List<HealthMonthTotals> months,
  List<RawHealthSample> samples,
  DateTime now,
) {
  final firstWorkout = months
      .where((month) => month.workouts > 0)
      .map((month) => month.month)
      .firstOrNull;
  final strength = firstWorkout == null
      ? <double>[]
      : [
          for (final month in months)
            if (!month.month.isBefore(firstWorkout))
              month.strengthWorkouts / (month.daysInMonth / 7),
        ];
  final sleep = months
      .where(
        (month) =>
            month.sleepMinutesAvg != null &&
            month.sleepNights >= healthHistoryMinimumSleepNights,
      )
      .toList();
  final today = DateTime(now.year, now.month, now.day);
  final recentFrom = today.subtract(const Duration(days: 28));
  final recentStrength = samples.where((sample) {
    final start = sample.start.toLocal();
    return sample.metric == HealthMetric.workouts &&
        strengthWorkoutTypes.contains(
          sample.workoutActivityType?.toUpperCase(),
        ) &&
        !start.isBefore(recentFrom) &&
        start.isBefore(today);
  }).length;
  final hasWorkouts = samples.any(
    (sample) => sample.metric == HealthMetric.workouts,
  );
  return HealthBaseline(
    months: months.length,
    usualStrengthPerWeek: strength.length >= healthHistoryMinimumMonths
        ? _oneDecimal(_median(strength))
        : null,
    recentStrengthPerWeek: hasWorkouts ? _oneDecimal(recentStrength / 4) : null,
    usualSleepMinutes: sleep.length >= healthHistoryMinimumMonths
        ? (sleep.fold(0, (total, month) => total + month.sleepMinutesAvg!) /
                  sleep.length)
              .round()
        : null,
  );
}

/// Reads the history from HealthKit, sends it, and returns what it shows.
abstract interface class HealthBaselineSource {
  /// Reads and sends the history; null when Apple Health cannot be read.
  Future<HealthBaseline?> load();

  /// Sends the history when the stored copy is from an earlier month.
  Future<void> refreshIfDue();
}

class SupabaseHealthBaselineSource implements HealthBaselineSource {
  SupabaseHealthBaselineSource(
    this._client,
    this._preferences, {
    HealthKitDataSource? source,
    DateTime Function()? now,
  }) : _source = source ?? HealthKitDataSource(),
       _now = now ?? DateTime.now;

  final SupabaseClient _client;
  final SharedPreferencesAsync _preferences;
  final HealthKitDataSource _source;
  final DateTime Function() _now;

  String? get _key {
    final user = _client.auth.currentUser?.id;
    return user == null ? null : 'tracend.$user.health_history_month';
  }

  @override
  Future<HealthBaseline?> load() async {
    final now = _now();
    final result = await _source.readMetrics(
      healthHistoryStart(now),
      now,
      healthHistoryMetrics,
    );
    if (result.unavailable) return null;
    final months = healthMonthTotals(result.samples, now);
    await _client.rpc(
      'save_health_history',
      params: {'months': months.map((month) => month.toJson()).toList()},
    );
    final key = _key;
    if (key != null) {
      await _preferences.setString(key, '${now.year}-${now.month}');
    }
    return healthBaseline(months, result.samples, now);
  }

  @override
  Future<void> refreshIfDue() async {
    final key = _key;
    if (key == null) return;
    final now = _now();
    if (await _preferences.getString(key) == '${now.year}-${now.month}') return;
    try {
      await load();
    } catch (e) {
      debugPrint('Non-critical error: $e');
    }
  }
}
