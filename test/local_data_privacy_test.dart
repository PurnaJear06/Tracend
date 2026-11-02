import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/keychain_session_storage.dart';
import 'package:tracend/features/auth/account_session.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/health/health_baseline.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/readiness/pain_report_queue.dart';
import 'package:tracend/features/readiness/safety_acknowledgements.dart';
import 'package:tracend/features/today/check_in_marks.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/train/training_hub_cache.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_recorder.dart';
import 'package:tracend/features/workout_hr/sleeping_heart_rate_recorder.dart';
import 'package:tracend/features/workout_hr/watch_workout_prompt.dart';
import 'package:tracend/shared/home_widgets/home_widget_eraser.dart';
import 'package:tracend/shared/home_widgets/today_widget_publisher.dart';
import 'package:tracend/shared/local_health_store.dart';

import 'memory_health_files.dart';

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';

/// Everything the app writes to this phone's storage, and whose it is. A key
/// is one of three kinds:
///
/// - per athlete: its name holds the athlete's id, so another account never
///   reads it;
/// - phone-wide and kept: [_phoneWide], settings with nothing of an athlete in
///   them, which stay when another account signs in;
/// - phone-wide and athlete's: [_endsWithSession], which an earlier build
///   or a queue shared between accounts keeps under one name, so it must go
///   when the session ends.
///
/// A file that stores something and is not in [_storingFiles] fails the last
/// test: decide which kind its keys are, and add them here.
Map<String, Object> _asyncPerAthlete(String id) => {
  HealthPreferenceKeys(id).lastSync: '2026-10-01T00:00:00Z',
  HealthPreferenceKeys(id).availableTypes: ['sleep'],
  HealthPreferenceKeys(id).initialBackfillComplete: true,
  HealthPreferenceKeys(id).accessError: 'denied',
  SupabaseHealthBaselineSource.historyMonthKey(id): '2026-10',
  TodayWidgetPublisher.lockScreenNumbersKeyFor(id): true,
  SleepingHeartRateRecorder.finalKeyFor(id): ['2026-10-01'],
};

Map<String, Object> _legacyPerAthlete(String id) => {
  CheckInMarks.savedOnKeyFor(id): '2026-10-01',
  CheckInMarks.skippedOnKeyFor(id): '2026-10-01',
};

Map<String, Object> _healthPerAthlete(String id) => {
  CheckInQueue.queueStorageKeyFor(id): '{}',
  CheckInQueue.earlierKeyFor(id): '[]',
  CheckInQueue.singleSlotKeyFor(id): '{}',
  PainReportQueue.storageKeyFor(id): '[]',
  SafetyAcknowledgements.storageKeyFor(id): ['2026-10-01:urgent'],
  '${WorkoutLocalKeys.draftPrefix(id)}workout-1': '{}',
  '${WorkoutLocalKeys.finishPrefix(id)}workout-1': '{}',
  WorkoutLocalKeys.discards(id): ['session-1'],
  WorkoutLocalKeys.exerciseHistory(id): '{}',
  TrainingHubCache.keyFor(id): '{}',
  TrainingHubCache.safetyKeyFor(id): '{}',
};

/// Settings of the phone. They hold nothing of an athlete.
final _phoneWide = <String>{
  'tracend_theme_mode',
  SupabaseWatchWorkoutPromptSource.mutedKey,
  SupabaseWatchWorkoutPromptSource.snoozedUntilKey,
  HomeWidgetEraser.pendingKey,
  KeychainSessionStorage.markerKey,
  // An opaque conversation id: only read when it is one of the signed-in
  // athlete's own threads. Deleting an account removes it.
  LocalCoachThreadMemory.storageKey,
  // One envelope an earlier build kept for the whole phone: the first athlete
  // to open the queue takes it, and a deleted account removes it.
  CheckInQueue.singleSlotKey,
};

/// Kept under one name for the whole phone, so they end with the session.
Map<String, Object> _endsWithSession() => {
  CheckInMarks.savedOnKey: '2026-10-01',
  CheckInMarks.skippedOnKey: '2026-10-01',
  TodayWidgetPublisher.lockScreenNumbersKey: true,
  SetHeartRateRecorder.pendingKey: '[]',
};

/// The files of `lib/` that store anything on the phone, apart from the
/// store itself and its move.
const _storingFiles = {
  'lib/app/app.dart',
  'lib/app/keychain_session_storage.dart',
  'lib/features/auth/account_session.dart',
  'lib/features/auth/phase_2_gate.dart',
  'lib/features/coach/coach_thread_memory.dart',
  'lib/features/health/health_baseline.dart',
  'lib/features/health/health_repository.dart',
  'lib/features/readiness/pain_report_queue.dart',
  'lib/features/readiness/pain_reporting.dart',
  'lib/features/readiness/safety_acknowledgements.dart',
  'lib/features/shell/app_shell.dart',
  'lib/features/today/check_in_queue.dart',
  'lib/features/today/check_in_sheet.dart',
  'lib/features/today/today_screen.dart',
  'lib/features/train/training_hub_cache.dart',
  'lib/features/train/workout_repository.dart',
  'lib/features/workout_hr/set_heart_rate_recorder.dart',
  'lib/features/workout_hr/sleeping_heart_rate_recorder.dart',
  'lib/features/workout_hr/watch_workout_prompt.dart',
  'lib/shared/home_widgets/home_widget_eraser.dart',
  'lib/shared/home_widgets/lock_screen_numbers.dart',
  'lib/shared/home_widgets/today_widget_publisher.dart',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = LocalHealthStore();
  late SharedPreferencesAsync preferences;

  Future<void> putAsync(Map<String, Object> values) async {
    for (final entry in values.entries) {
      final value = entry.value;
      switch (value) {
        case String():
          await preferences.setString(entry.key, value);
        case bool():
          await preferences.setBool(entry.key, value);
        case List<String>():
          await preferences.setStringList(entry.key, value);
        default:
          throw ArgumentError(entry.key);
      }
    }
  }

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
    final legacy = <String, Object>{
      ..._legacyPerAthlete(_a),
      ..._legacyPerAthlete(_b),
      KeychainSessionStorage.markerKey: 'keychain',
      CheckInMarks.savedOnKey: '2026-10-01',
      CheckInMarks.skippedOnKey: '2026-10-01',
    };
    SharedPreferences.setMockInitialValues(legacy);
    await putAsync({
      ..._asyncPerAthlete(_a),
      ..._asyncPerAthlete(_b),
      TodayWidgetPublisher.lockScreenNumbersKey: true,
      SetHeartRateRecorder.pendingKey: '[]',
      'tracend_theme_mode': 'dark',
      SupabaseWatchWorkoutPromptSource.mutedKey: true,
      SupabaseWatchWorkoutPromptSource.snoozedUntilKey: '2026-10-02T00:00:00Z',
      HomeWidgetEraser.pendingKey: true,
    });
    await seedHealthCache({
      ..._healthPerAthlete(_a),
      ..._healthPerAthlete(_b),
      LocalCoachThreadMemory.storageKey: 'thread-1',
      CheckInQueue.singleSlotKey: '{}',
    });
  });

  /// Every key the phone holds now, in preferences and in the health store.
  Future<Set<String>> remaining() async => {
    ...await preferences.getKeys(),
    ...(await SharedPreferences.getInstance()).getKeys(),
    ...await store.getKeys(),
  };

  Set<String> unexplained(Set<String> keys, {required Set<String> athletes}) =>
      keys
          .where(
            (key) =>
                !_phoneWide.contains(key) &&
                !athletes.any((athlete) => key.contains(athlete)),
          )
          .toSet();

  group('after an account switch on the same phone', () {
    test('signing out leaves only keys named for an athlete or kept for the '
        'phone', () async {
      final client = SupabaseClient('https://example.supabase.co', 'anon');
      await signOutAthlete(client, LocalAccountData(), _a);

      final left = await remaining();
      expect(unexplained(left, athletes: {_a, _b}), isEmpty);
      for (final key in _endsWithSession().keys) {
        expect(left, isNot(contains(key)), reason: '$key outlives the session');
      }
      expect(
        left.where((key) => key.contains(_b)),
        hasLength(
          _asyncPerAthlete(_b).length +
              _legacyPerAthlete(_b).length +
              _healthPerAthlete(_b).length,
        ),
        reason: 'another athlete keeps everything',
      );
      // A's marks are named for A, but they end with the sign-out.
      expect(left, isNot(contains(CheckInMarks.savedOnKeyFor(_a))));
      expect(left, isNot(contains(CheckInMarks.skippedOnKeyFor(_a))));
    });

    test('a refused session leaves only keys named for an athlete or kept for '
        'the phone', () async {
      await LocalAccountData().forgetSession(_a);

      final left = await remaining();
      expect(unexplained(left, athletes: {_a, _b}), isEmpty);
      for (final key in _endsWithSession().keys) {
        expect(left, isNot(contains(key)), reason: '$key outlives the session');
      }
      expect(left, isNot(contains(LocalCoachThreadMemory.storageKey)));
    });

    test('deleting the account leaves nothing named for it, and nothing of '
        'the phone-wide athlete data', () async {
      await LocalAccountData().clear(_a);

      final left = await remaining();
      expect(left.where((key) => key.contains(_a)), isEmpty);
      expect(unexplained(left, athletes: {_b}), isEmpty);
      for (final key in _endsWithSession().keys) {
        expect(left, isNot(contains(key)), reason: '$key outlives the account');
      }
      expect(left, isNot(contains(LocalCoachThreadMemory.storageKey)));
      expect(left, isNot(contains(CheckInQueue.singleSlotKey)));
      expect(left.where((key) => key.contains(_b)), isNotEmpty);
    });
  });

  test('signing out keeps the athlete\'s own queue, pain reports and drafts '
      'for their return', () async {
    final client = SupabaseClient('https://example.supabase.co', 'anon');
    await signOutAthlete(client, LocalAccountData(), _a);

    for (final key in [
      CheckInQueue.queueStorageKeyFor(_a),
      CheckInQueue.earlierKeyFor(_a),
      PainReportQueue.storageKeyFor(_a),
      SafetyAcknowledgements.storageKeyFor(_a),
      '${WorkoutLocalKeys.draftPrefix(_a)}workout-1',
      '${WorkoutLocalKeys.finishPrefix(_a)}workout-1',
      WorkoutLocalKeys.discards(_a),
      WorkoutLocalKeys.exerciseHistory(_a),
    ]) {
      expect(await store.getString(key), isNotNull, reason: key);
    }
    // The saved plan is the one thing of the athlete's that goes.
    expect(await store.getString(TrainingHubCache.keyFor(_a)), isNull);
  });

  test('a deletion whose listing fails still removes the named keys', () async {
    final healthy = LocalHealthFiles.instance;
    LocalHealthFiles.instance = FailingHealthFiles(
      healthy,
      failWrites: false,
      failListing: true,
    );

    await LocalAccountData().clear(_a);
    LocalHealthFiles.instance = healthy;

    for (final key in [
      CheckInQueue.queueStorageKeyFor(_a),
      CheckInQueue.earlierKeyFor(_a),
      PainReportQueue.storageKeyFor(_a),
      SafetyAcknowledgements.storageKeyFor(_a),
    ]) {
      expect(await store.getString(key), isNull, reason: key);
    }
    expect(
      await store.getString(CheckInQueue.queueStorageKeyFor(_b)),
      isNotNull,
    );
  });

  test('every file that stores something on the phone is classified above', () {
    final found =
        <String>{
          for (final entity in Directory('lib').listSync(recursive: true))
            if (entity is File && entity.path.endsWith('.dart'))
              if (RegExp(
                r'SharedPreferences|LocalHealthStore',
              ).hasMatch(entity.readAsStringSync()))
                entity.path,
        }..removeAll(const {
          'lib/shared/local_health_store.dart',
          'lib/shared/local_health_migration.dart',
        });

    expect(
      found,
      _storingFiles,
      reason:
          'A file now stores or no longer stores something on the phone: '
          'classify its keys in this file as per athlete, phone-wide and '
          'kept, or ending with the session, then update _storingFiles.',
    );
  });
}
