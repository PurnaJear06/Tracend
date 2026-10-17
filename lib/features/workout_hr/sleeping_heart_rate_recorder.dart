import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/breadcrumbs.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/workout_hr/heart_rate_reader.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_summary.dart';
import 'package:tracend/features/workout_hr/sleeping_heart_rate.dart';

/// Saves nights of sleeping heart rate for the signed-in athlete.
abstract interface class SleepingHeartRateRepository {
  /// Saves [nights], replacing earlier rows for the same dates; completes with
  /// how many the server stored.
  Future<int> persist(List<SleepingHeartRateNight> nights);
}

class SupabaseSleepingHeartRateRepository
    implements SleepingHeartRateRepository {
  SupabaseSleepingHeartRateRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<int> persist(List<SleepingHeartRateNight> nights) async {
    final value = await _client.rpc(
      'persist_sleeping_heart_rate_v1',
      params: {
        'nights': [for (final night in nights) night.toJson()],
      },
    );
    return value is Map ? (value['saved'] as num?)?.toInt() ?? 0 : 0;
  }
}

/// After an Apple Health sync, works out the sleeping heart rate of the recent
/// nights from the sleep samples that sync already read and the heart-rate
/// samples around them, and saves one summary per night. SHADOW MODE (D10): the
/// rows are stored and exported and nothing scores them. Samples stay on the
/// phone. A night with too few readings, or no heart-rate access, gets no row.
class SleepingHeartRateRecorder {
  SleepingHeartRateRecorder({
    required this.reader,
    required this.repository,
    required SharedPreferencesAsync preferences,
    required String? Function() userId,
    DateTime Function() clock = DateTime.now,
  }) : _preferences = preferences,
       _userId = userId,
       _clock = clock;

  /// How far back nights are read.
  static const lookback = Duration(days: 7);

  /// A saved night is final once it ended this long ago (late Watch samples
  /// have arrived by then) and is not read again.
  static const finalAfter = Duration(days: 2);

  /// The longest stretch one read covers (the reader's limit is 4 hours).
  static const _longestRead = Duration(hours: 3, minutes: 30);

  final HeartRateReader reader;
  final SleepingHeartRateRepository repository;
  final SharedPreferencesAsync _preferences;
  final String? Function() _userId;
  final DateTime Function() _clock;

  String _finalKey(String userId) =>
      'tracend.sleeping_heart_rate.final.$userId';

  /// Reads and saves the recent nights found in [samples]. Never throws: the
  /// sync that called it must not fail because of a shadow measurement. The
  /// athlete signed in when it starts is the only one it saves for.
  Future<void> record(List<RawHealthSample> samples) async {
    try {
      final userId = _userId();
      if (userId == null) return;
      final now = _clock();
      final recent = [
        for (final night in sleepNightsFrom(samples))
          if (night.end.isAfter(now.subtract(lookback)) &&
              !night.end.isAfter(now))
            night,
      ];
      if (recent.isEmpty) return;
      final finals = {...?await _preferences.getStringList(_finalKey(userId))};
      final nights = [
        for (final night in recent)
          if (!finals.contains(night.localDate)) night,
      ];
      final summaries = <SleepingHeartRateNight>[];
      for (final night in nights) {
        final readings = await _readNight(night);
        final summary = summariseSleepingHeartRate(night, readings);
        if (summary != null) summaries.add(summary);
      }
      if (summaries.isEmpty) return;
      // The reads above take a while and this runs unawaited after a sync, so
      // another account may have signed in meanwhile. The save uses whoever is
      // signed in when it runs; these summaries belong to the athlete the
      // sync was for. Stop if that is no longer the signed-in athlete.
      if (_userId() != userId) return;
      final saved = await repository.persist(summaries);
      if (_userId() != userId) return;
      for (final summary in summaries) {
        final night = nights.firstWhere(
          (n) => n.localDate == summary.localDate,
        );
        if (night.end.isBefore(now.subtract(finalAfter))) {
          finals.add(summary.localDate);
        }
      }
      await _preferences.setStringList(
        _finalKey(userId),
        finals.toList()..sort(),
      );
      AppBreadcrumbs.workout(
        'Sleeping heart rate saved',
        data: {'nights': saved},
      );
    } catch (e) {
      debugPrint('Non-critical error: sleeping heart rate not saved: $e');
    }
  }

  Future<List<HeartRateSample>> _readNight(SleepNight night) async {
    final readings = <HeartRateSample>[];
    for (
      var from = night.start;
      from.isBefore(night.end);
      from = from.add(_longestRead)
    ) {
      final next = from.add(_longestRead);
      readings.addAll(
        await reader.readSamples(
          from,
          next.isBefore(night.end) ? next : night.end,
        ),
      );
    }
    return readings;
  }
}
