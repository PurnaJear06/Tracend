import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:tracend/features/health/health_models.dart';

abstract interface class HealthDataSource {
  Future<bool> requestReadAccess();
  Future<HealthReadResult> read(DateTime start, DateTime end);
}

class HealthKitDataSource implements HealthDataSource {
  HealthKitDataSource({Health? health}) : _health = health ?? Health();

  final Health _health;
  bool _configured = false;

  static const requestedMetrics = <HealthMetric>{
    HealthMetric.steps,
    HealthMetric.activeEnergy,
    HealthMetric.sleep,
    HealthMetric.workouts,
    HealthMetric.weight,
    HealthMetric.restingHeartRate,
    HealthMetric.hrvSdnn,
  };

  static const _types = <HealthDataType>[
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.WORKOUT,
    HealthDataType.WEIGHT,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
  ];

  static const _metricByType = <HealthDataType, HealthMetric>{
    HealthDataType.STEPS: HealthMetric.steps,
    HealthDataType.ACTIVE_ENERGY_BURNED: HealthMetric.activeEnergy,
    HealthDataType.SLEEP_ASLEEP: HealthMetric.sleep,
    HealthDataType.SLEEP_AWAKE: HealthMetric.sleep,
    HealthDataType.SLEEP_LIGHT: HealthMetric.sleep,
    HealthDataType.SLEEP_DEEP: HealthMetric.sleep,
    HealthDataType.SLEEP_REM: HealthMetric.sleep,
    HealthDataType.WORKOUT: HealthMetric.workouts,
    HealthDataType.WEIGHT: HealthMetric.weight,
    HealthDataType.RESTING_HEART_RATE: HealthMetric.restingHeartRate,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN: HealthMetric.hrvSdnn,
  };

  Future<void> _configure() async {
    if (!_configured) {
      await _health.configure();
      _configured = true;
    }
  }

  @override
  Future<bool> requestReadAccess() async {
    if (!Platform.isIOS) return false;
    try {
      await _configure();
      return await _health.requestAuthorization(
        _types,
        permissions: List.filled(_types.length, HealthDataAccess.READ),
      );
    } catch (e) {
      debugPrint('Non-critical error: $e');
      return false;
    }
  }

  @override
  Future<HealthReadResult> read(DateTime start, DateTime end) async {
    if (!Platform.isIOS) {
      return const HealthReadResult(
        requestedMetrics: requestedMetrics,
        returnedMetrics: {},
        samples: [],
        unavailable: true,
      );
    }
    try {
      await _configure();
      final samples = <RawHealthSample>[];
      final returned = <HealthMetric>{};
      var successfulQueries = 0;
      for (final type in _types) {
        final metric = _metricByType[type]!;
        try {
          final points = await _health.getHealthDataFromTypes(
            types: [type],
            startTime: start,
            endTime: end,
          );
          successfulQueries += 1;
          if (points.isNotEmpty) returned.add(metric);
          samples.addAll(
            points.map(
              (point) =>
                  _toRaw(point, metric, sleepStage: _sleepStageByType[type]),
            ),
          );
        } catch (e) {
          debugPrint('Non-critical error: $e');
          // A missing type remains unknown/partial; it is never treated as proof
          // that the user denied access.
        }
      }
      if (successfulQueries == 0) {
        return const HealthReadResult(
          requestedMetrics: requestedMetrics,
          returnedMetrics: {},
          samples: [],
          unavailable: true,
        );
      }
      return HealthReadResult(
        requestedMetrics: requestedMetrics,
        returnedMetrics: returned,
        samples: samples,
      );
    } catch (e) {
      debugPrint('Non-critical error: $e');
      return const HealthReadResult(
        requestedMetrics: requestedMetrics,
        returnedMetrics: {},
        samples: [],
        unavailable: true,
      );
    }
  }

  static const _sleepStageByType = <HealthDataType, SleepStage>{
    HealthDataType.SLEEP_ASLEEP: SleepStage.asleep,
    HealthDataType.SLEEP_AWAKE: SleepStage.awake,
    HealthDataType.SLEEP_LIGHT: SleepStage.light,
    HealthDataType.SLEEP_DEEP: SleepStage.deep,
    HealthDataType.SLEEP_REM: SleepStage.rem,
  };

  RawHealthSample _toRaw(
    HealthDataPoint point,
    HealthMetric metric, {
    SleepStage? sleepStage,
  }) {
    final value = point.value;
    final numeric = value is NumericHealthValue
        ? value.numericValue.toDouble()
        : 0.0;
    final workout = value is WorkoutHealthValue ? value : null;
    return RawHealthSample(
      metric: metric,
      value: numeric,
      start: point.dateFrom,
      end: point.dateTo,
      sampleId: point.uuid,
      sourceId: point.sourceId,
      sleepStage: sleepStage,
      workoutActivityType: workout?.workoutActivityType.name,
      workoutEnergyKcal: workout?.totalEnergyBurned?.toDouble(),
    );
  }
}

class UnavailableHealthDataSource implements HealthDataSource {
  const UnavailableHealthDataSource();

  @override
  Future<HealthReadResult> read(DateTime start, DateTime end) async =>
      const HealthReadResult(
        requestedMetrics: HealthKitDataSource.requestedMetrics,
        returnedMetrics: {},
        samples: [],
        unavailable: true,
      );

  @override
  Future<bool> requestReadAccess() async => false;
}
