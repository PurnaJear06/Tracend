import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/readiness/pain_report_queue.dart';
import 'package:tracend/features/readiness/safety_acknowledgements.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/train/workout_repository.dart';
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

/// Copies [value] to [key] in [store]. When the store holds [key] already (a
/// first move that stopped part way, then a save made offline), a queue of
/// things not yet sent keeps the items of both, and anything else keeps the
/// store's copy, which is the newer. False when it could not be written.
Future<bool> _move(LocalHealthStore store, String key, Object? value) async {
  try {
    final stored = await store.getString(key);
    if (stored != null) {
      if (value is String) await _merge(store, key, stored, value);
      if (value is List && value.every((item) => item is String)) {
        await _mergeLists(store, key, List<String>.from(value));
      }
      return true;
    }
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

bool _isCheckInQueue(String key) =>
    key == CheckInQueue.queueStorageKey ||
    key.startsWith('${CheckInQueue.queueStorageKey}.');

bool _isEarlierCheckIns(String key) =>
    key.startsWith(CheckInQueue.earlierKeyFor(''));

bool _isPainReports(String key) =>
    key == PainReportQueue.storageKey ||
    key.startsWith('${PainReportQueue.storageKey}.');

Future<void> _merge(
  LocalHealthStore store,
  String key,
  String stored,
  String old,
) async {
  if (_isCheckInQueue(key)) {
    await _mergeCheckIns(store, key, stored, old);
  } else if (_isEarlierCheckIns(key) || _isPainReports(key)) {
    final merged = _mergeByIdempotencyKey(_list(old), _list(stored));
    await store.setString(key, jsonEncode(merged));
  }
}

/// Each day's waiting check-in of both, the store's for a day both hold. An
/// older one with a pain check that the store's replaced goes to the earlier
/// list, as the queue does when a day is answered again.
Future<void> _mergeCheckIns(
  LocalHealthStore store,
  String key,
  String stored,
  String old,
) async {
  final newer = _map(stored);
  final older = _map(old);
  final replaced = <Object?>[];
  for (final entry in older.entries) {
    final other = newer[entry.key];
    if (other == null) {
      newer[entry.key] = entry.value;
    } else if (other is Map &&
        entry.value is Map &&
        other['idempotency_key'] != (entry.value as Map)['idempotency_key'] &&
        ((entry.value as Map)['payload'] is Map) &&
        checkInPainKeys.any(
          ((entry.value as Map)['payload'] as Map).containsKey,
        )) {
      replaced.add(entry.value);
    }
  }
  await store.setString(key, jsonEncode(newer));
  if (replaced.isEmpty) return;
  final user = key == CheckInQueue.queueStorageKey
      ? ''
      : key.substring(CheckInQueue.queueStorageKey.length + 1);
  final earlierKey = CheckInQueue.earlierKeyFor(user);
  final earlier = _list(await store.getString(earlierKey) ?? '[]');
  await store.setString(
    earlierKey,
    jsonEncode(_mergeByIdempotencyKey(replaced, earlier)),
  );
}

/// [older] then the items of [newer] after it, one per idempotency key, the
/// newer copy of an item standing in the older one's place.
List<Object?> _mergeByIdempotencyKey(List<Object?> older, List<Object?> newer) {
  String? keyOf(Object? item) =>
      item is Map && item['idempotency_key'] is String
      ? item['idempotency_key'] as String
      : null;
  final latest = {
    for (final item in newer)
      if (keyOf(item) != null) keyOf(item)!: item,
  };
  final seen = <String>{};
  return [
    for (final item in older)
      if (keyOf(item) == null)
        item
      else if (seen.add(keyOf(item)!))
        latest[keyOf(item)] ?? item,
    for (final item in newer)
      if (keyOf(item) == null) item else if (seen.add(keyOf(item)!)) item,
  ];
}

/// The lists of text that queue things not yet done (queued discards,
/// referrals read), joined in order without repeats.
Future<void> _mergeLists(
  LocalHealthStore store,
  String key,
  List<String> old,
) async {
  final isDiscards = key.startsWith(WorkoutLocalKeys.discards(''));
  final isReferrals = key.startsWith(SafetyAcknowledgements.storageKey);
  if (!isDiscards && !isReferrals) return;
  final stored = await store.getStringList(key) ?? const [];
  final joined = [...old, ...stored].fold<List<String>>(
    [],
    (all, item) => all
      ..remove(item)
      ..add(item),
  );
  await store.setStringList(
    key,
    isReferrals && joined.length > SafetyAcknowledgements.kept
        ? joined.sublist(joined.length - SafetyAcknowledgements.kept)
        : joined,
  );
}

Map<String, Object?> _map(String json) {
  try {
    final decoded = jsonDecode(json);
    return decoded is Map ? Map<String, Object?>.from(decoded) : {};
  } on FormatException {
    return {};
  }
}

List<Object?> _list(String json) {
  try {
    final decoded = jsonDecode(json);
    return decoded is List ? decoded : [];
  } on FormatException {
    return [];
  }
}
