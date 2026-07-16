import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/health/health_data_source.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:uuid/uuid.dart';

abstract interface class HealthRepository {
  Future<HealthSyncStatus> loadStatus();
  Future<HealthHistory> loadHistory();
  Future<HealthSyncStatus> connectAndSync();
  Future<HealthSyncStatus> sync();
}

class SupabaseHealthRepository implements HealthRepository {
  SupabaseHealthRepository(
    this._client,
    this._preferences, {
    HealthDataSource? source,
    DateTime Function()? now,
  }) : _source = source ?? HealthKitDataSource(),
       _now = now ?? DateTime.now;

  static const _lastSyncKey = 'health.last_successful_sync';
  static const _availableTypesKey = 'health.available_types';
  static const _initialBackfillCompleteKey =
      'health.initial_31_day_backfill_complete';
  static const _uuid = Uuid();

  final SupabaseClient _client;
  final SharedPreferencesAsync _preferences;
  final HealthDataSource _source;
  final DateTime Function() _now;

  @override
  Future<HealthSyncStatus> loadStatus() async {
    final stored = await _preferences.getString(_lastSyncKey);
    final codes = await _preferences.getStringList(_availableTypesKey) ?? [];
    final available = HealthMetric.values
        .where((metric) => codes.contains(metric.code))
        .toSet();
    if (stored == null) {
      return const HealthSyncStatus(state: HealthConnectionState.manualOnly);
    }
    final lastSync = DateTime.tryParse(stored);
    if (lastSync == null) {
      return const HealthSyncStatus(state: HealthConnectionState.manualOnly);
    }
    return HealthSyncStatus(
      state: deriveHealthConnectionState(
        now: _now(),
        lastSuccessfulSync: lastSync,
        availableMetrics: available,
      ),
      lastSuccessfulSync: lastSync,
      availableMetrics: available,
    );
  }

  @override
  Future<HealthSyncStatus> connectAndSync() async {
    await _source.requestReadAccess();
    return sync();
  }

  @override
  Future<HealthHistory> loadHistory() async {
    final rows = await _client
        .from('daily_health_summaries')
        .select(
          'local_date,present_types,steps,active_energy_kcal,sleep_minutes,'
          'sleep_deep_minutes,sleep_rem_minutes,workout_count,workout_minutes,'
          'weight_kg,resting_heart_rate_bpm,hrv_value_ms',
        )
        .order('local_date', ascending: false)
        .limit(31);
    final orderedRows = rows.toList()
      ..sort(
        (a, b) =>
            (a['local_date'] as String).compareTo(b['local_date'] as String),
      );
    return HealthHistory(
      orderedRows.map((row) {
        final codes = (row['present_types'] as List).cast<String>().toSet();
        return HealthDay(
          date: DateTime.parse(row['local_date'] as String),
          presentMetrics: HealthMetric.values
              .where((metric) => codes.contains(metric.code))
              .toSet(),
          steps: row['steps'] as int?,
          activeEnergyKcal: (row['active_energy_kcal'] as num?)?.toDouble(),
          sleepMinutes: row['sleep_minutes'] as int?,
          sleepDeepMinutes: row['sleep_deep_minutes'] as int?,
          sleepRemMinutes: row['sleep_rem_minutes'] as int?,
          workoutCount: row['workout_count'] as int?,
          workoutMinutes: row['workout_minutes'] as int?,
          weightKg: (row['weight_kg'] as num?)?.toDouble(),
          restingHeartRateBpm: (row['resting_heart_rate_bpm'] as num?)
              ?.toDouble(),
          hrvSdnnMs: (row['hrv_value_ms'] as num?)?.toDouble(),
        );
      }).toList(),
    );
  }

  @override
  Future<HealthSyncStatus> sync() async {
    final now = _now();
    final initialBackfillComplete =
        await _preferences.getBool(_initialBackfillCompleteKey) ?? false;
    final start = healthSyncStart(
      now: now,
      initialBackfillComplete: initialBackfillComplete,
    );
    final result = await _source.read(start, now);
    if (result.unavailable) {
      return const HealthSyncStatus(state: HealthConnectionState.unavailable);
    }
    final timezone = await _loadTimezone();
    final summaries = normalizeHealthSamples(
      samples: result.samples,
      requestedMetrics: result.requestedMetrics,
      timezone: timezone,
    );
    final response = await _client.functions.invoke(
      'health-sync',
      body: {
        'schema_version': '1.0',
        'idempotency_key': _uuid.v4(),
        'requested_start': _dateKey(start),
        'requested_end': _dateKey(now),
        'requested_types': result.requestedMetrics
            .map((metric) => metric.code)
            .toList(),
        'returned_types': result.returnedMetrics
            .map((metric) => metric.code)
            .toList(),
        'summaries': summaries
            .map((summary) => summary.toJson(result.requestedMetrics))
            .toList(),
        'workouts': healthWorkoutReferences(result.samples),
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('Health summary sync failed.');
    }
    await _preferences.setString(_lastSyncKey, now.toUtc().toIso8601String());
    await _preferences.setStringList(
      _availableTypesKey,
      result.returnedMetrics.map((metric) => metric.code).toList(),
    );
    await _preferences.setBool(_initialBackfillCompleteKey, true);
    return HealthSyncStatus(
      state: deriveHealthConnectionState(
        now: now,
        lastSuccessfulSync: now,
        availableMetrics: result.returnedMetrics,
      ),
      lastSuccessfulSync: now,
      availableMetrics: result.returnedMetrics,
    );
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<String> _loadTimezone() async {
    final response = await _client
        .from('user_accounts')
        .select('timezone')
        .single();
    final timezone = response['timezone'];
    return timezone is String && timezone.isNotEmpty ? timezone : 'UTC';
  }
}

DateTime healthSyncStart({
  required DateTime now,
  required bool initialBackfillComplete,
}) {
  final localDay = DateTime(now.year, now.month, now.day);
  return localDay.subtract(Duration(days: initialBackfillComplete ? 6 : 31));
}

class ManualHealthRepository implements HealthRepository {
  const ManualHealthRepository();

  @override
  Future<HealthSyncStatus> connectAndSync() => loadStatus();

  @override
  Future<HealthSyncStatus> loadStatus() async =>
      const HealthSyncStatus(state: HealthConnectionState.manualOnly);

  @override
  Future<HealthHistory> loadHistory() async => const HealthHistory([]);

  @override
  Future<HealthSyncStatus> sync() => loadStatus();
}
