import 'dart:async';
import 'dart:io';

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

/// What Health shows for a failed sync attempt. Since functions_client 2.7 a
/// request that never reached the server arrives as [FunctionsFetchException]
/// (status 0) instead of the transport's own exception.
String healthSyncFailureMessage(Object error) => switch (error) {
  FunctionsFetchException() ||
  SocketException() => 'Connection lost. Check your internet and try again.',
  TimeoutException() =>
    'Sync timed out. The server may be starting up. Try again now.',
  _ => '$error',
};

class SupabaseHealthRepository implements HealthRepository {
  SupabaseHealthRepository(
    SupabaseClient client,
    SharedPreferencesAsync preferences, {
    HealthDataSource? source,
    DateTime Function()? now,
  }) : _client = client,
       _state = HealthPreferences(
         preferences,
         userId: () => client.auth.currentUser?.id,
         serverLastSync: () => _serverLastSync(client),
       ),
       _source = source ?? HealthKitDataSource(),
       _now = now ?? DateTime.now;

  static const _uuid = Uuid();

  final SupabaseClient _client;
  final HealthPreferences _state;
  final HealthDataSource _source;
  final DateTime Function() _now;

  /// The newest sync the server holds for the signed-in athlete (RLS limits
  /// the rows to their own).
  static Future<DateTime?> _serverLastSync(SupabaseClient client) async {
    final row = await client
        .from('daily_health_summaries')
        .select('last_synced_at')
        .order('last_synced_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final value = row?['last_synced_at'];
    return value is String ? DateTime.tryParse(value) : null;
  }

  @override
  Future<HealthSyncStatus> loadStatus() async {
    final keys = await _state.keys();
    if (keys == null) {
      return const HealthSyncStatus(state: HealthConnectionState.manualOnly);
    }
    final preferences = _state.preferences;
    final stored = await preferences.getString(keys.lastSync);
    final codes = await preferences.getStringList(keys.availableTypes) ?? [];
    final accessErrorCode = await preferences.getString(keys.accessError);
    final available = HealthMetric.values
        .where((metric) => codes.contains(metric.code))
        .toSet();
    if (stored == null) {
      return HealthSyncStatus(
        state: HealthConnectionState.manualOnly,
        accessError: _parseAccessError(accessErrorCode),
      );
    }
    final lastSync = DateTime.tryParse(stored);
    if (lastSync == null) {
      return HealthSyncStatus(
        state: HealthConnectionState.manualOnly,
        accessError: _parseAccessError(accessErrorCode),
      );
    }
    return HealthSyncStatus(
      state: deriveHealthConnectionState(
        now: _now(),
        lastSuccessfulSync: lastSync,
        availableMetrics: available,
      ),
      lastSuccessfulSync: lastSync,
      availableMetrics: available,
      accessError: _parseAccessError(accessErrorCode),
    );
  }

  HealthAccessError? _parseAccessError(String? code) {
    if (code == null) return null;
    return HealthAccessError.values.cast<HealthAccessError?>().firstWhere(
      (e) => e?.name == code,
      orElse: () => null,
    );
  }

  @override
  Future<HealthSyncStatus> connectAndSync() async {
    final keys = await _state.keys();
    if (keys == null) {
      return const HealthSyncStatus(state: HealthConnectionState.manualOnly);
    }
    final preferences = _state.preferences;
    final source = _source;
    if (source is HealthKitDataSource) {
      final configured = await source.isConfigured();
      if (!configured) {
        await preferences.setString(
          keys.accessError,
          HealthAccessError.configurationFailed.name,
        );
        return const HealthSyncStatus(
          state: HealthConnectionState.unavailable,
          accessError: HealthAccessError.configurationFailed,
        );
      }
    }
    final authorized = await source.requestReadAccess();
    if (!authorized) {
      await preferences.setString(
        keys.accessError,
        HealthAccessError.authorizationDenied.name,
      );
      return const HealthSyncStatus(
        state: HealthConnectionState.manualOnly,
        accessError: HealthAccessError.authorizationDenied,
      );
    }
    return sync();
  }

  @override
  Future<HealthHistory> loadHistory() async {
    final rows = await _client
        .from('daily_health_summaries')
        .select(
          'local_date,present_types,steps,active_energy_kcal,sleep_minutes,'
          'sleep_deep_minutes,sleep_rem_minutes,workout_count,workout_minutes,'
          'weight_kg,resting_heart_rate_bpm,hrv_value_ms,respiratory_rate_bpm',
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
          respRateBpm: (row['respiratory_rate_bpm'] as num?)?.toDouble(),
        );
      }).toList(),
    );
  }

  @override
  Future<HealthSyncStatus> sync() async {
    final keys = await _state.keys();
    if (keys == null) {
      return const HealthSyncStatus(state: HealthConnectionState.manualOnly);
    }
    final preferences = _state.preferences;
    final now = _now();
    final initialBackfillComplete =
        await preferences.getBool(keys.initialBackfillComplete) ?? false;
    final start = healthSyncStart(
      now: now,
      initialBackfillComplete: initialBackfillComplete,
    );
    final result = await _source.read(start, now);
    if (result.unavailable) {
      if (result.accessError != null) {
        await preferences.setString(keys.accessError, result.accessError!.name);
      }
      return HealthSyncStatus(
        state: HealthConnectionState.unavailable,
        accessError: result.accessError,
      );
    }
    await preferences.remove(keys.accessError);
    final timezone = await _loadTimezone();
    final summaries = normalizeHealthSamples(
      samples: result.samples,
      requestedMetrics: result.requestedMetrics,
      timezone: timezone,
    );
    await _invokeSync(result, summaries, start, now);
    await preferences.setString(keys.lastSync, now.toUtc().toIso8601String());
    await preferences.setStringList(
      keys.availableTypes,
      result.returnedMetrics.map((metric) => metric.code).toList(),
    );
    await preferences.setBool(keys.initialBackfillComplete, true);
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

  Future<void> _invokeSync(
    HealthReadResult result,
    List<DailyHealthSummary> summaries,
    DateTime start,
    DateTime now,
  ) async {
    Exception? lastException;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: attempt * attempt));
      }
      try {
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
        if (response.status >= 200 && response.status < 300) return;
        final detail = response.data is Map
            ? (response.data as Map)['error'] ?? '${response.status}'
            : '${response.status}';
        lastException = _HealthSyncException(detail.toString());
      } catch (error) {
        lastException = _HealthSyncException(healthSyncFailureMessage(error));
      }
    }
    throw lastException ?? _HealthSyncException('Sync failed.');
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<String> _loadTimezone() async {
    try {
      final response = await _client
          .from('user_accounts')
          .select('timezone')
          .limit(1)
          .maybeSingle();
      final timezone = response?['timezone'];
      return timezone is String && timezone.isNotEmpty ? timezone : 'UTC';
    } catch (_) {
      return 'UTC';
    }
  }
}

/// Calendar days before today a sync reads from: the first sync fills the
/// 28-day onboarding summary and the baselines (31 dates, today included, the
/// most health-sync accepts: a window of 31 days and 32 summaries); later
/// syncs refresh the last week.
const healthInitialBackfillDays = 30;
const healthRefreshDays = 7;

DateTime healthSyncStart({
  required DateTime now,
  required bool initialBackfillComplete,
}) {
  // Local midnight, so the fetch (which matches samples by start instant)
  // covers whole days; a night that began the evening before the first date
  // is only partly counted on that date, which the onboarding summary's 28
  // days never include.
  final localDay = DateTime(now.year, now.month, now.day);
  return localDay.subtract(
    Duration(
      days: initialBackfillComplete
          ? healthRefreshDays
          : healthInitialBackfillDays,
    ),
  );
}

/// The preference keys holding one athlete's Apple Health state.
class HealthPreferenceKeys {
  HealthPreferenceKeys(String userId)
    : lastSync = '${prefix(userId)}last_successful_sync',
      availableTypes = '${prefix(userId)}available_types',
      initialBackfillComplete = '${prefix(userId)}initial_backfill_complete',
      accessError = '${prefix(userId)}access_error';

  /// Every Apple Health key of one athlete starts with this.
  static String prefix(String userId) => 'health.$userId.';

  final String lastSync;
  final String availableTypes;
  final String initialBackfillComplete;
  final String accessError;
}

/// Apple Health state on this device, kept per athlete, so another account
/// signed in on the same phone starts as not connected.
///
/// Builds before 2026-10 kept one unscoped state. It is adopted only when it
/// provably belongs to the signed-in athlete: its last sync is within five
/// minutes of the newest sync the server holds for them. Otherwise it is
/// deleted and the athlete connects again. Either way the unscoped keys are
/// removed, so no later account can inherit them.
class HealthPreferences {
  HealthPreferences(
    this.preferences, {
    required String? Function() userId,
    required Future<DateTime?> Function() serverLastSync,
  }) : _userId = userId,
       _serverLastSync = serverLastSync;

  static const legacyLastSync = 'health.last_successful_sync';
  static const legacyAvailableTypes = 'health.available_types';
  static const legacyInitialBackfillComplete =
      'health.initial_31_day_backfill_complete';
  static const legacyAccessError = 'health.access_error';
  static const adoptionTolerance = Duration(minutes: 5);

  final SharedPreferencesAsync preferences;
  final String? Function() _userId;
  final Future<DateTime?> Function() _serverLastSync;
  final _settled = <String, Future<void>>{};

  /// The signed-in athlete's keys, after any older state is settled; null
  /// when nobody is signed in.
  Future<HealthPreferenceKeys?> keys() async {
    final userId = _userId();
    if (userId == null) return null;
    final keys = HealthPreferenceKeys(userId);
    try {
      await (_settled[userId] ??= _settleLegacy(keys));
    } catch (_) {
      // The server could not be asked; keep the old state and ask again later.
      _settled.remove(userId)?.ignore();
    }
    return keys;
  }

  Future<void> _settleLegacy(HealthPreferenceKeys keys) async {
    final legacy = await preferences.getString(legacyLastSync);
    if (legacy == null) return;
    final legacySync = DateTime.tryParse(legacy);
    final own = await preferences.getString(keys.lastSync);
    if (own == null && legacySync != null) {
      final server = await _serverLastSync();
      if (server != null &&
          server.difference(legacySync).abs() <= adoptionTolerance) {
        await preferences.setString(keys.lastSync, legacy);
        final types = await preferences.getStringList(legacyAvailableTypes);
        if (types != null) {
          await preferences.setStringList(keys.availableTypes, types);
        }
        // The backfill flag is not carried over: older builds read 9 days,
        // so the next sync reads the full 31 dates once.
        final accessError = await preferences.getString(legacyAccessError);
        if (accessError != null) {
          await preferences.setString(keys.accessError, accessError);
        }
      }
    }
    await preferences.remove(legacyLastSync);
    await preferences.remove(legacyAvailableTypes);
    await preferences.remove(legacyInitialBackfillComplete);
    await preferences.remove(legacyAccessError);
  }
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

class _HealthSyncException implements Exception {
  const _HealthSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}
