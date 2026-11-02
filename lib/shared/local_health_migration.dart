import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/readiness/pain_report_queue.dart';
import 'package:tracend/features/readiness/safety_acknowledgements.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/local_health_store.dart';

/// Set once every health cache of an earlier build has moved to the store.
const healthStoreMovedKey = 'tracend.health_store.moved';

/// The key prefixes earlier builds cached health data under in preferences,
/// which iCloud Backup and computer backups copy. Those read through the
/// legacy `SharedPreferences` first, then those read through
/// `SharedPreferencesAsync`.
const legacyHealthKeyPrefixes = [
  CheckInQueue.queueStorageKey,
  CheckInQueue.singleSlotKey,
  PainReportQueue.storageKey,
  SafetyAcknowledgements.storageKey,
  LocalCoachThreadMemory.storageKey,
];

const asyncHealthKeyPrefixes = [
  'training_hub_cache_',
  'training_safety_notes_',
  'workout_draft_',
  'workout_finish_',
  'workout_discards_',
  'exercise_history_',
];

/// Moves what earlier builds cached in preferences into [store], once. Each
/// key is written to the store and only then removed from preferences, so a
/// failure leaves it to be moved at the next launch; a key the store already
/// holds is the newer copy and is kept. Never throws.
Future<void> moveHealthCachesToStore({
  LocalHealthStore store = const LocalHealthStore(),
  SharedPreferencesAsync? preferences,
  Future<SharedPreferences> Function()? legacyPreferences,
}) async {
  try {
    final async = preferences ?? SharedPreferencesAsync();
    if (await async.getBool(healthStoreMovedKey) ?? false) return;
    final legacy = await (legacyPreferences ?? SharedPreferences.getInstance)();
    var moved = true;
    for (final key in legacy.getKeys().where(
      (key) => legacyHealthKeyPrefixes.any(key.startsWith),
    )) {
      if (await _move(store, key, legacy.get(key))) {
        await legacy.remove(key);
      } else {
        moved = false;
      }
    }
    final all = await async.getAll();
    for (final entry in all.entries.where(
      (entry) => asyncHealthKeyPrefixes.any(entry.key.startsWith),
    )) {
      if (await _move(store, entry.key, entry.value)) {
        await async.remove(entry.key);
      } else {
        moved = false;
      }
    }
    if (moved) await async.setBool(healthStoreMovedKey, true);
  } catch (e) {
    logNonCritical(e, 'health caches not moved');
  }
}

/// Copies [value] to [key] in [store] unless it holds [key] already. False
/// when it could not be written.
Future<bool> _move(LocalHealthStore store, String key, Object? value) async {
  try {
    if (await store.getString(key) != null) return true;
    // A value of another type could never be read by the cache that wrote it,
    // so there is nothing to keep.
    if (value is String) {
      await store.setString(key, value);
    } else if (value is List && value.every((item) => item is String)) {
      await store.setStringList(key, List<String>.from(value));
    }
    return true;
  } catch (e) {
    logNonCritical(e, 'health cache not moved');
    return false;
  }
}
