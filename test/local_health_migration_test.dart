import 'dart:convert';

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

import 'memory_health_files.dart';

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

  test('a copy the store already holds is the newer one, and the old key '
      'goes', () async {
    await store.setString(TrainingHubCache.keyFor(_user), 'newer');

    await moveHealthCachesToStore(preferences: preferences);

    expect(await store.getString(TrainingHubCache.keyFor(_user)), 'newer');
    expect(await preferences.getString(TrainingHubCache.keyFor(_user)), isNull);
  });

  test('a key that cannot be written stays in preferences for the next '
      'launch', () async {
    final healthy = LocalHealthFiles.instance;
    LocalHealthFiles.instance = FailingHealthFiles(healthy);

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

  group('when the store holds a key that preferences still hold too', () {
    // A first move that stopped part way, then something saved offline.
    String envelope(String day, String key, {bool pain = false}) => jsonEncode({
      'idempotency_key': key,
      'local_date': day,
      'timezone': 'Asia/Kolkata',
      'payload': {'energy': 3, if (pain) 'pain_area': 'knee'},
    });

    String report(String key, {bool refused = false}) =>
        jsonEncode({'idempotency_key': key, 'refused': refused});

    test('check-ins waiting for different days both survive', () async {
      final key = CheckInQueue.queueStorageKeyFor(_user);
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({
          '2026-10-30': jsonDecode(envelope('2026-10-30', 'old')),
        }),
      });
      await store.setString(
        key,
        jsonEncode({'2026-10-31': jsonDecode(envelope('2026-10-31', 'new'))}),
      );

      await moveHealthCachesToStore(preferences: preferences);

      final kept = jsonDecode((await store.getString(key))!) as Map;
      expect(kept.keys, unorderedEquals(['2026-10-30', '2026-10-31']));
      expect(await CheckInQueue(store, userId: _user).pendingDays(), [
        '2026-10-30',
        '2026-10-31',
      ]);
    });

    test('an older check-in with a pain check that a newer answer for its '
        'day replaced goes to the earlier ones, as the queue does', () async {
      final key = CheckInQueue.queueStorageKeyFor(_user);
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({
          '2026-10-31': jsonDecode(envelope('2026-10-31', 'old', pain: true)),
        }),
      });
      await store.setString(
        key,
        jsonEncode({'2026-10-31': jsonDecode(envelope('2026-10-31', 'new'))}),
      );

      await moveHealthCachesToStore(preferences: preferences);

      final earlier =
          jsonDecode(
                (await store.getString(CheckInQueue.earlierKeyFor(_user)))!,
              )
              as List;
      expect(earlier.map((e) => (e as Map)['idempotency_key']), ['old']);
      final day = jsonDecode((await store.getString(key))!) as Map;
      expect((day['2026-10-31'] as Map)['idempotency_key'], 'new');
    });

    test('earlier check-ins and pain reports are joined by idempotency key, '
        'the store\'s copy of one both hold standing', () async {
      final earlierKey = CheckInQueue.earlierKeyFor(_user);
      final painKey = PainReportQueue.storageKeyFor(_user);
      SharedPreferences.setMockInitialValues({
        earlierKey: jsonEncode([jsonDecode(envelope('2026-10-29', 'a'))]),
        painKey: jsonEncode([
          jsonDecode(report('r1')),
          jsonDecode(report('r2')),
        ]),
      });
      await store.setString(
        earlierKey,
        jsonEncode([jsonDecode(envelope('2026-10-30', 'b'))]),
      );
      await store.setString(
        painKey,
        jsonEncode([
          jsonDecode(report('r2', refused: true)),
          jsonDecode(report('r3')),
        ]),
      );

      await moveHealthCachesToStore(preferences: preferences);

      List<Object?> keys(String? json) => [
        for (final item in jsonDecode(json!) as List)
          (item as Map)['idempotency_key'],
      ];
      expect(keys(await store.getString(earlierKey)), ['a', 'b']);
      expect(keys(await store.getString(painKey)), ['r1', 'r2', 'r3']);
      final pain = jsonDecode((await store.getString(painKey))!) as List;
      expect((pain[1] as Map)['refused'], isTrue);
    });

    test('queued discards and referrals read are joined', () async {
      final discards = WorkoutLocalKeys.discards(_user);
      final referrals = SafetyAcknowledgements.storageKeyFor(_user);
      SharedPreferences.setMockInitialValues({
        referrals: ['2026-10-29:urgent'],
      });
      await preferences.setStringList(discards, ['s1', 's2']);
      await store.setStringList(discards, ['s2', 's3']);
      await store.setStringList(referrals, ['2026-10-30:urgent']);

      await moveHealthCachesToStore(preferences: preferences);

      expect(await store.getStringList(discards), ['s1', 's2', 's3']);
      expect(await store.getStringList(referrals), [
        '2026-10-29:urgent',
        '2026-10-30:urgent',
      ]);
    });

    test(
      'a draft, the plan and the history keep the store\'s newer copy',
      () async {
        for (final key in [
          '${WorkoutLocalKeys.draftPrefix(_user)}workout-1',
          TrainingHubCache.keyFor(_user),
          WorkoutLocalKeys.exerciseHistory(_user),
        ]) {
          await store.setString(key, 'newer');
        }

        await moveHealthCachesToStore(preferences: preferences);

        for (final key in [
          '${WorkoutLocalKeys.draftPrefix(_user)}workout-1',
          TrainingHubCache.keyFor(_user),
          WorkoutLocalKeys.exerciseHistory(_user),
        ]) {
          expect(await store.getString(key), 'newer', reason: key);
        }
      },
    );
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
