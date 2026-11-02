import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/readiness/pain_report_queue.dart';
import 'package:tracend/features/readiness/safety_acknowledgements.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/train/training_hub_cache.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/local_health_migration.dart';
import 'package:tracend/shared/local_health_store.dart';

const _user = '11111111-1111-4111-8111-111111111111';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = LocalHealthStore();
  late SharedPreferencesAsync preferences;

  /// What the phone's preferences held for health before this build.
  final legacyHealth = <String, Object>{
    CheckInQueue.queueStorageKeyFor(_user): '{"2026-10-30":{}}',
    CheckInQueue.earlierKeyFor(_user): '[]',
    CheckInQueue.singleSlotKey: '{}',
    PainReportQueue.storageKeyFor(_user): '[{"pain":"red flag"}]',
    SafetyAcknowledgements.storageKeyFor(_user): ['2026-10-30:urgent'],
    LocalCoachThreadMemory.storageKey: 'thread-1',
  };
  final asyncHealth = <String, Object>{
    '${WorkoutLocalKeys.draftPrefix(_user)}workout-1': '{"sets":1}',
    '${WorkoutLocalKeys.finishPrefix(_user)}workout-1': '{}',
    WorkoutLocalKeys.discards(_user): ['session-1'],
    WorkoutLocalKeys.exerciseHistory(_user): '{}',
    TrainingHubCache.keyFor(_user): '{"v":1}',
    TrainingHubCache.safetyKeyFor(_user): '{"v":1}',
  };
  Future<void> seedPreferences() async {
    SharedPreferences.setMockInitialValues({
      for (final entry in legacyHealth.entries) entry.key: entry.value,
    });
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
    for (final entry in asyncHealth.entries) {
      final value = entry.value;
      if (value is String) {
        await preferences.setString(entry.key, value);
      } else {
        await preferences.setStringList(entry.key, value as List<String>);
      }
    }
    await preferences.setString('tracend_theme_mode', 'dark');
    await preferences.setBool('tracend.watch_prompt.muted', true);
    await preferences.setString(
      'health.$_user.last_successful_sync',
      '2026-10-01T00:00:00Z',
    );
  }

  setUp(seedPreferences);

  test('moves every health cache into the store and out of preferences, '
      'once', () async {
    await moveHealthCachesToStore(preferences: preferences);

    for (final entry in {...legacyHealth, ...asyncHealth}.entries) {
      final value = entry.value;
      if (value is String) {
        expect(await store.getString(entry.key), value, reason: entry.key);
      } else {
        expect(await store.getStringList(entry.key), value, reason: entry.key);
      }
    }
    final legacy = await SharedPreferences.getInstance();
    expect(legacy.getKeys(), isEmpty);
    expect(
      (await preferences.getKeys()).where(
        (key) => asyncHealthKeyPrefixes.any(key.startsWith),
      ),
      isEmpty,
    );
    // What is not health stays where it was.
    expect(await preferences.getString('tracend_theme_mode'), 'dark');
    expect(await preferences.getBool('tracend.watch_prompt.muted'), isTrue);
    expect(
      await preferences.getString('health.$_user.last_successful_sync'),
      isNotNull,
    );
    expect(await preferences.getBool(healthStoreMovedKey), isTrue);
  });

  test('does not look again once everything has moved', () async {
    await moveHealthCachesToStore(preferences: preferences);
    await preferences.setString(
      WorkoutLocalKeys.exerciseHistory(_user),
      'written by a build that still used preferences',
    );

    await moveHealthCachesToStore(preferences: preferences);

    expect(
      await preferences.getString(WorkoutLocalKeys.exerciseHistory(_user)),
      isNotNull,
    );
    expect(
      await store.getString(WorkoutLocalKeys.exerciseHistory(_user)),
      '{}',
    );
  });

  test('a copy the store already holds is the newer one', () async {
    await store.setString(CheckInQueue.queueStorageKeyFor(_user), 'newer');

    await moveHealthCachesToStore(preferences: preferences);

    expect(
      await store.getString(CheckInQueue.queueStorageKeyFor(_user)),
      'newer',
    );
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('a key that cannot be written stays in preferences for the next '
      'launch', () async {
    final healthy = LocalHealthFiles.instance;
    LocalHealthFiles.instance = _FailingWrites(healthy);

    await moveHealthCachesToStore(preferences: preferences);

    final legacy = await SharedPreferences.getInstance();
    expect(legacy.getKeys(), unorderedEquals(legacyHealth.keys));
    expect(
      await preferences.getString(TrainingHubCache.keyFor(_user)),
      isNotNull,
    );
    expect(await preferences.getBool(healthStoreMovedKey), isNull);

    LocalHealthFiles.instance = healthy;
    await moveHealthCachesToStore(preferences: preferences);

    expect(await store.getString(TrainingHubCache.keyFor(_user)), '{"v":1}');
    expect(legacy.getKeys(), isEmpty);
    expect(await preferences.getBool(healthStoreMovedKey), isTrue);
  });

  test('knows every key the caches write', () {
    // A cache that writes under a new prefix must be listed to be moved.
    final keys = [
      CheckInQueue.queueStorageKey,
      CheckInQueue.queueStorageKeyFor(_user),
      CheckInQueue.singleSlotKey,
      CheckInQueue.singleSlotKeyFor(_user),
      CheckInQueue.earlierKeyFor(_user),
      PainReportQueue.storageKey,
      PainReportQueue.storageKeyFor(_user),
      SafetyAcknowledgements.storageKey,
      SafetyAcknowledgements.storageKeyFor(_user),
      LocalCoachThreadMemory.storageKey,
    ];
    for (final key in keys) {
      expect(legacyHealthKeyPrefixes.any(key.startsWith), isTrue, reason: key);
    }
    final asyncKeys = [
      '${WorkoutLocalKeys.draftPrefix(_user)}w',
      '${WorkoutLocalKeys.finishPrefix(_user)}w',
      WorkoutLocalKeys.discards(_user),
      WorkoutLocalKeys.exerciseHistory(_user),
      TrainingHubCache.keyFor(_user),
      TrainingHubCache.safetyKeyFor(_user),
    ];
    for (final key in asyncKeys) {
      expect(asyncHealthKeyPrefixes.any(key.startsWith), isTrue, reason: key);
    }
  });
}

/// Files whose writes fail, as when the disk is full.
class _FailingWrites implements LocalHealthFiles {
  _FailingWrites(this._inner);

  final LocalHealthFiles _inner;

  @override
  Future<String?> read(String name) => _inner.read(name);

  @override
  Future<void> write(String name, String contents) =>
      throw const FileSystemException('disk full');

  @override
  Future<void> delete(String name) => _inner.delete(name);

  @override
  Future<List<String>> names() => _inner.names();
}
