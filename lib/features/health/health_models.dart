import 'dart:convert';

import 'package:crypto/crypto.dart';

enum HealthMetric {
  steps('steps'),
  activeEnergy('active_energy'),
  sleep('sleep'),
  workouts('workouts'),
  weight('weight'),
  restingHeartRate('resting_heart_rate'),
  hrvSdnn('hrv_sdnn');

  const HealthMetric(this.code);
  final String code;

  String get label => switch (this) {
    HealthMetric.steps => 'Steps',
    HealthMetric.activeEnergy => 'Active energy',
    HealthMetric.sleep => 'Sleep',
    HealthMetric.workouts => 'Workouts',
    HealthMetric.weight => 'Weight',
    HealthMetric.restingHeartRate => 'Resting heart rate',
    HealthMetric.hrvSdnn => 'HRV',
  };
}

class HealthDay {
  const HealthDay({
    required this.date,
    required this.presentMetrics,
    this.steps,
    this.activeEnergyKcal,
    this.sleepMinutes,
    this.sleepDeepMinutes,
    this.sleepRemMinutes,
    this.workoutCount,
    this.workoutMinutes,
    this.weightKg,
    this.restingHeartRateBpm,
    this.hrvSdnnMs,
  });

  final DateTime date;
  final Set<HealthMetric> presentMetrics;
  final int? steps;
  final double? activeEnergyKcal;
  final int? sleepMinutes;
  final int? sleepDeepMinutes;
  final int? sleepRemMinutes;
  final int? workoutCount;
  final int? workoutMinutes;
  final double? weightKg;
  final double? restingHeartRateBpm;
  final double? hrvSdnnMs;
}

class HealthHistory {
  const HealthHistory(this.days);

  final List<HealthDay> days;

  HealthDay? get latest => days.isEmpty ? null : days.last;

  Set<HealthMetric> get availableMetrics => {
    for (final day in days) ...day.presentMetrics,
  };
}

enum SleepStage { asleep, awake, light, deep, rem }

enum HealthConnectionState {
  connected,
  partial,
  stale,
  manualOnly,
  unavailable,
}

class RawHealthSample {
  const RawHealthSample({
    required this.metric,
    required this.value,
    required this.start,
    required this.end,
    required this.sampleId,
    required this.sourceId,
    this.sleepStage,
    this.workoutActivityType,
    this.workoutEnergyKcal,
  });

  final HealthMetric metric;
  final double value;
  final DateTime start;
  final DateTime end;
  final String sampleId;
  final String sourceId;
  final SleepStage? sleepStage;
  final String? workoutActivityType;
  final double? workoutEnergyKcal;
}

List<Map<String, Object?>> healthWorkoutReferences(
  List<RawHealthSample> samples,
) => samples.where((sample) => sample.metric == HealthMetric.workouts).map((
  sample,
) {
  final local = sample.start.toLocal();
  return <String, Object?>{
    'sample_id_hash': _hash(sample.sampleId),
    'source_id_hash': _hash(sample.sourceId),
    'activity_type': sample.workoutActivityType ?? 'OTHER',
    'started_at': sample.start.toUtc().toIso8601String(),
    'ended_at': sample.end.toUtc().toIso8601String(),
    'duration_seconds': sample.end.difference(sample.start).inSeconds,
    if (sample.workoutEnergyKcal != null)
      'energy_kcal': DailyHealthSummary._rounded(sample.workoutEnergyKcal!),
    'local_date':
        '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}',
  };
}).toList();

class HealthReadResult {
  const HealthReadResult({
    required this.requestedMetrics,
    required this.returnedMetrics,
    required this.samples,
    this.unavailable = false,
  });

  final Set<HealthMetric> requestedMetrics;
  final Set<HealthMetric> returnedMetrics;
  final List<RawHealthSample> samples;
  final bool unavailable;
}

class DailyHealthSummary {
  const DailyHealthSummary({
    required this.localDate,
    required this.timezone,
    required this.presentMetrics,
    required this.sourceReferences,
    required this.sourceChecksum,
    required this.observedThrough,
    this.steps,
    this.activeEnergyKcal,
    this.sleepMinutes,
    this.sleepAwakeMinutes,
    this.sleepLightMinutes,
    this.sleepDeepMinutes,
    this.sleepRemMinutes,
    this.workoutCount,
    this.workoutMinutes,
    this.weightKg,
    this.restingHeartRateBpm,
    this.hrvSdnnMs,
  });

  final DateTime localDate;
  final String timezone;
  final Set<HealthMetric> presentMetrics;
  final List<Map<String, String>> sourceReferences;
  final String sourceChecksum;
  final DateTime observedThrough;
  final int? steps;
  final double? activeEnergyKcal;
  final int? sleepMinutes;
  final int? sleepAwakeMinutes;
  final int? sleepLightMinutes;
  final int? sleepDeepMinutes;
  final int? sleepRemMinutes;
  final int? workoutCount;
  final int? workoutMinutes;
  final double? weightKg;
  final double? restingHeartRateBpm;
  final double? hrvSdnnMs;

  String get dateKey =>
      '${localDate.year.toString().padLeft(4, '0')}-'
      '${localDate.month.toString().padLeft(2, '0')}-'
      '${localDate.day.toString().padLeft(2, '0')}';

  Map<String, Object?> toJson(Set<HealthMetric> requestedMetrics) => {
    'local_date': dateKey,
    'timezone': timezone,
    if (steps != null) 'steps': steps,
    if (activeEnergyKcal != null)
      'active_energy_kcal': _rounded(activeEnergyKcal!),
    if (sleepMinutes != null) 'sleep_minutes': sleepMinutes,
    if (sleepAwakeMinutes != null) 'sleep_awake_minutes': sleepAwakeMinutes,
    if (sleepLightMinutes != null) 'sleep_light_minutes': sleepLightMinutes,
    if (sleepDeepMinutes != null) 'sleep_deep_minutes': sleepDeepMinutes,
    if (sleepRemMinutes != null) 'sleep_rem_minutes': sleepRemMinutes,
    if (workoutCount != null) 'workout_count': workoutCount,
    if (workoutMinutes != null) 'workout_minutes': workoutMinutes,
    if (weightKg != null) 'weight_kg': _rounded(weightKg!),
    if (restingHeartRateBpm != null)
      'resting_heart_rate_bpm': _rounded(restingHeartRateBpm!),
    if (hrvSdnnMs != null) ...{
      'hrv_value_ms': _rounded(hrvSdnnMs!),
      'hrv_metric': 'sdnn',
      'hrv_unit': 'ms',
    },
    'present_types': presentMetrics.map((metric) => metric.code).toList()
      ..sort(),
    'source_refs': sourceReferences,
    'source_checksum': sourceChecksum,
    'completeness': presentMetrics.containsAll(requestedMetrics)
        ? 'complete'
        : 'partial',
    'observed_through': observedThrough.toUtc().toIso8601String(),
  };

  static double _rounded(double value) => (value * 100).roundToDouble() / 100;
}

class HealthSyncStatus {
  const HealthSyncStatus({
    required this.state,
    this.lastSuccessfulSync,
    this.availableMetrics = const {},
  });

  final HealthConnectionState state;
  final DateTime? lastSuccessfulSync;
  final Set<HealthMetric> availableMetrics;

  String get title => switch (state) {
    HealthConnectionState.connected => 'HealthKit connected',
    HealthConnectionState.partial => 'HealthKit partially connected',
    HealthConnectionState.stale => 'HealthKit needs a refresh',
    HealthConnectionState.manualOnly => 'Manual tracking',
    HealthConnectionState.unavailable => 'HealthKit unavailable',
  };

  String get detail => switch (state) {
    HealthConnectionState.connected =>
      'Daily activity and recovery summaries are up to date.',
    HealthConnectionState.partial =>
      'Available signals were synced. Missing signals remain unknown.',
    HealthConnectionState.stale =>
      'Your last successful summary is more than two days old.',
    HealthConnectionState.manualOnly =>
      'The app remains fully usable without Apple Health data.',
    HealthConnectionState.unavailable =>
      'This device cannot provide Apple Health data. Continue manually.',
  };
}

HealthConnectionState deriveHealthConnectionState({
  required DateTime now,
  required DateTime? lastSuccessfulSync,
  required Set<HealthMetric> availableMetrics,
  bool unavailable = false,
}) {
  if (unavailable) return HealthConnectionState.unavailable;
  if (lastSuccessfulSync == null) return HealthConnectionState.manualOnly;
  if (now.difference(lastSuccessfulSync) > const Duration(days: 2)) {
    return HealthConnectionState.stale;
  }
  return availableMetrics.length == HealthMetric.values.length
      ? HealthConnectionState.connected
      : HealthConnectionState.partial;
}

List<DailyHealthSummary> normalizeHealthSamples({
  required List<RawHealthSample> samples,
  required Set<HealthMetric> requestedMetrics,
  required String timezone,
}) {
  final unique = <String, RawHealthSample>{};
  for (final sample in samples) {
    if (_isValidSample(sample)) {
      unique.putIfAbsent(
        '${sample.metric.code}:${sample.sleepStage?.name}:${sample.sampleId}',
        () => sample,
      );
    }
  }
  final byDate = <String, List<RawHealthSample>>{};
  for (final sample in unique.values) {
    final local = sample.start.toLocal();
    final key =
        '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    byDate.putIfAbsent(key, () => []).add(sample);
  }

  final summaries = <DailyHealthSummary>[];
  for (final entry in byDate.entries) {
    final points = entry.value..sort((a, b) => a.end.compareTo(b.end));
    final present = points.map((point) => point.metric).toSet();
    final references =
        points
            .map(
              (point) => {
                'type': point.metric.code,
                'source_id_hash': _hash(point.sourceId),
                'sample_id_hash': _hash(
                  '${point.sleepStage?.name ?? 'none'}:${point.sampleId}',
                ),
              },
            )
            .toList()
          ..sort((left, right) {
            final typeOrder = left['type']!.compareTo(right['type']!);
            return typeOrder != 0
                ? typeOrder
                : left['sample_id_hash']!.compareTo(right['sample_id_hash']!);
          });
    final observedThrough = points
        .map((point) => point.end)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    final localDate = points.first.start.toLocal();
    final workouts = points
        .where((point) => point.metric == HealthMetric.workouts)
        .toList();

    summaries.add(
      DailyHealthSummary(
        localDate: DateTime(localDate.year, localDate.month, localDate.day),
        timezone: timezone,
        presentMetrics: present,
        sourceReferences: references,
        sourceChecksum: _hash(jsonEncode(references)),
        observedThrough: observedThrough,
        steps: _sum(points, HealthMetric.steps)?.round(),
        activeEnergyKcal: _sum(points, HealthMetric.activeEnergy),
        sleepMinutes: _sleepMinutes(points),
        sleepAwakeMinutes: _sleepStageMinutes(points, SleepStage.awake),
        sleepLightMinutes: _sleepStageMinutes(points, SleepStage.light),
        sleepDeepMinutes: _sleepStageMinutes(points, SleepStage.deep),
        sleepRemMinutes: _sleepStageMinutes(points, SleepStage.rem),
        workoutCount: workouts.isEmpty ? null : workouts.length,
        workoutMinutes: workouts.isEmpty
            ? null
            : workouts.fold<int>(
                0,
                (total, point) =>
                    total + point.end.difference(point.start).inMinutes,
              ),
        weightKg: _latest(points, HealthMetric.weight),
        restingHeartRateBpm: _average(points, HealthMetric.restingHeartRate),
        hrvSdnnMs: _average(points, HealthMetric.hrvSdnn),
      ),
    );
  }
  summaries.sort((left, right) => left.localDate.compareTo(right.localDate));
  return summaries;
}

double? _sum(List<RawHealthSample> samples, HealthMetric metric) {
  final values = samples.where((sample) => sample.metric == metric);
  return values.isEmpty
      ? null
      : values.fold<double>(0, (total, sample) => total + sample.value);
}

int? _durationMinutes(List<RawHealthSample> samples, HealthMetric metric) {
  final values = samples.where((sample) => sample.metric == metric);
  return values.isEmpty
      ? null
      : values.fold<int>(
          0,
          (total, sample) =>
              total + sample.end.difference(sample.start).inMinutes,
        );
}

int? _sleepMinutes(List<RawHealthSample> samples) {
  final asleep = _sleepStageMinutes(samples, SleepStage.asleep);
  if (asleep != null) return asleep;
  final stages = [
    _sleepStageMinutes(samples, SleepStage.light),
    _sleepStageMinutes(samples, SleepStage.deep),
    _sleepStageMinutes(samples, SleepStage.rem),
  ];
  final available = stages.whereType<int>().toList();
  return available.isEmpty
      ? _durationMinutes(samples, HealthMetric.sleep)
      : available.fold<int>(0, (total, value) => total + value);
}

int? _sleepStageMinutes(List<RawHealthSample> samples, SleepStage stage) {
  final values = samples.where((sample) => sample.sleepStage == stage);
  return values.isEmpty
      ? null
      : values.fold<int>(
          0,
          (total, sample) =>
              total + sample.end.difference(sample.start).inMinutes,
        );
}

double? _latest(List<RawHealthSample> samples, HealthMetric metric) {
  final values = samples.where((sample) => sample.metric == metric).toList()
    ..sort((left, right) => left.end.compareTo(right.end));
  return values.isEmpty ? null : values.last.value;
}

double? _average(List<RawHealthSample> samples, HealthMetric metric) {
  final values = samples.where((sample) => sample.metric == metric).toList();
  return values.isEmpty
      ? null
      : values.fold<double>(0, (total, sample) => total + sample.value) /
            values.length;
}

String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

bool _isValidSample(RawHealthSample sample) {
  if (!sample.value.isFinite || sample.end.isBefore(sample.start)) return false;
  final duration = sample.end.difference(sample.start);
  return switch (sample.metric) {
    HealthMetric.steps => sample.value >= 0 && sample.value <= 200000,
    HealthMetric.activeEnergy => sample.value >= 0 && sample.value <= 30000,
    HealthMetric.sleep => duration <= const Duration(days: 1),
    HealthMetric.workouts => duration <= const Duration(days: 1),
    HealthMetric.weight => sample.value >= 20 && sample.value <= 500,
    HealthMetric.restingHeartRate => sample.value >= 20 && sample.value <= 250,
    HealthMetric.hrvSdnn => sample.value >= 0 && sample.value <= 1000,
  };
}
