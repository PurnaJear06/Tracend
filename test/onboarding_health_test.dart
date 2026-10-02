import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tracend/features/account/account_time_zone.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/onboarding/health_activity.dart';
import 'package:tracend/features/onboarding/onboarding_proposal_view.dart';
import 'package:tracend/features/onboarding/onboarding_repository.dart';

void main() {
  group('Apple Health facts for onboarding', () {
    final now = DateTime(2026, 10, 3, 9);
    HealthDay day(DateTime date, {int? steps, double? weightKg}) => HealthDay(
      date: date,
      presentMetrics: {
        if (steps != null) HealthMetric.steps,
        if (weightKg != null) HealthMetric.weight,
      },
      steps: steps,
      weightKg: weightKg,
    );

    test(
      'steps average the four weeks before today, with seven days at least',
      () {
        final six = HealthHistory([
          for (var back = 1; back <= 6; back++)
            day(DateTime(2026, 10, 3 - back), steps: 8000),
          // Today is still going: never averaged.
          day(DateTime(2026, 10, 3), steps: 900),
        ]);
        expect(onboardingHealthFacts(six, now).stepsPerDay, isNull);
        final seven = HealthHistory([
          ...six.days,
          day(DateTime(2026, 9, 26), steps: 8000),
          // Older than 28 days.
          day(DateTime(2026, 9, 1), steps: 20000),
        ]);
        final facts = onboardingHealthFacts(seven, now);
        expect(facts.stepsPerDay, 8000);
        expect(facts.daysWithData, 7);
      },
    );

    test('the latest weight counts only from the last 14 days', () {
      expect(
        onboardingHealthFacts(
          HealthHistory([day(DateTime(2026, 9, 18), weightKg: 80)]),
          now,
        ).latestWeightKg,
        isNull,
      );
      final facts = onboardingHealthFacts(
        HealthHistory([
          day(DateTime(2026, 9, 25), weightKg: 80.4),
          day(DateTime(2026, 10, 1), weightKg: 79.6),
        ]),
        now,
      );
      expect(facts.latestWeightKg, 79.6);
      expect(facts.latestWeightDate, DateTime(2026, 10, 1));
    });

    test('steps suggest an activity answer, never physical labour', () {
      expect(activityFromSteps(4999), 'mostly_sitting');
      expect(activityFromSteps(5000), 'some_standing');
      expect(activityFromSteps(7499), 'some_standing');
      expect(activityFromSteps(7500), 'mostly_standing');
      expect(activityFromSteps(25000), 'mostly_standing');
      expect(roundedSteps(9132), '9,100');
      expect(roundedSteps(12960), '13,000');
      expect(roundedSteps(640), '600');
    });

    test('the proposal line reads only the metrics the server included', () {
      expect(
        OnboardingProposalView.appleHealthLine(
          const ProposalHealth(
            windowDays: 28,
            daysWithData: 26,
            stepsPerDay: 6400,
            weightTrendKgPerWeek: 0.02,
          ),
        ),
        'Apple Health, last 28 days: about 6,400 steps a day · weight steady.',
      );
      expect(
        OnboardingProposalView.appleHealthLine(
          const ProposalHealth(windowDays: 28, daysWithData: 4),
        ),
        'Apple Health: 4 of 28 days had data, not enough to average.',
      );
      expect(ProposalHealth.fromJson(null), isNull);
      expect(ProposalHealth.fromJson({'steps_per_day': 1}), isNull);
    });
  });

  group('Apple Health state per athlete', () {
    late SharedPreferencesAsync preferences;
    String? user;
    DateTime? server;
    var serverCalls = 0;

    HealthPreferences state() => HealthPreferences(
      preferences,
      userId: () => user,
      serverLastSync: () async {
        serverCalls++;
        return server;
      },
    );

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      preferences = SharedPreferencesAsync();
      user = 'athlete-a';
      server = null;
      serverCalls = 0;
    });

    Future<void> legacy(String lastSync) async {
      await preferences.setString(HealthPreferences.legacyLastSync, lastSync);
      await preferences.setStringList(HealthPreferences.legacyAvailableTypes, [
        HealthMetric.steps.code,
      ]);
      await preferences.setBool(
        HealthPreferences.legacyInitialBackfillComplete,
        true,
      );
    }

    test('nobody signed in has no keys', () async {
      user = null;
      expect(await state().keys(), isNull);
    });

    test('each athlete has their own keys', () async {
      final a = (await state().keys())!;
      user = 'athlete-b';
      final b = (await state().keys())!;
      expect(a.lastSync, isNot(b.lastSync));
      expect(a.lastSync, contains('athlete-a'));
    });

    test(
      'older shared state is kept when the server proves it is theirs',
      () async {
        await legacy('2026-10-02T08:00:00.000Z');
        server = DateTime.utc(2026, 10, 2, 8, 0, 4);
        final keys = (await state().keys())!;
        expect(
          await preferences.getString(keys.lastSync),
          '2026-10-02T08:00:00.000Z',
        );
        expect(await preferences.getStringList(keys.availableTypes), [
          HealthMetric.steps.code,
        ]);
        // The first sync after the update reads the full 31 dates once.
        expect(await preferences.getBool(keys.initialBackfillComplete), isNull);
        expect(
          await preferences.getString(HealthPreferences.legacyLastSync),
          isNull,
        );
      },
    );

    test('older shared state is deleted when it cannot be proven', () async {
      await legacy('2026-10-02T08:00:00.000Z');
      // Another account's sync: an hour apart.
      server = DateTime.utc(2026, 10, 2, 9);
      final keys = (await state().keys())!;
      expect(await preferences.getString(keys.lastSync), isNull);
      expect(
        await preferences.getString(HealthPreferences.legacyLastSync),
        isNull,
      );
      // And no later account inherits it.
      user = 'athlete-b';
      final other = (await state().keys())!;
      expect(await preferences.getString(other.lastSync), isNull);
    });

    test('an account with no server sync never adopts older state', () async {
      await legacy('2026-10-02T08:00:00.000Z');
      final keys = (await state().keys())!;
      expect(await preferences.getString(keys.lastSync), isNull);
    });

    test(
      'a failed server check keeps the older state and asks again',
      () async {
        await legacy('2026-10-02T08:00:00.000Z');
        final failing = HealthPreferences(
          preferences,
          userId: () => user,
          serverLastSync: () => Future.error(Exception('offline')),
        );
        final keys = (await failing.keys())!;
        expect(await preferences.getString(keys.lastSync), isNull);
        expect(
          await preferences.getString(HealthPreferences.legacyLastSync),
          isNotNull,
        );
        server = DateTime.utc(2026, 10, 2, 8);
        final retried = state();
        await retried.keys();
        await retried.keys();
        expect(await preferences.getString(keys.lastSync), isNotNull);
        // Settled once per athlete.
        expect(serverCalls, 1);
      },
    );
  });

  test('a sync carries at most the newest 100 workouts', () {
    final start = DateTime.utc(2026, 9, 3, 6);
    final samples = [
      for (var index = 0; index < 130; index++)
        RawHealthSample(
          metric: HealthMetric.workouts,
          value: 1,
          start: start.add(Duration(hours: index * 5)),
          end: start.add(Duration(hours: index * 5, minutes: 30)),
          sampleId: 'workout-$index',
          sourceId: 'watch',
          workoutActivityType: 'WALKING',
        ),
    ];
    final references = healthWorkoutReferences(samples);
    expect(references, hasLength(healthSyncMaxWorkouts));
    expect(
      references.first['started_at'],
      samples.last.start.toIso8601String(),
    );
    expect(references.last['started_at'], samples[30].start.toIso8601String());
  });

  group('account time zone', () {
    test('stores the device zone only when it changed', () async {
      final stored = <String>[];
      var current = 'UTC';
      final zone = AccountTimeZone(
        deviceZone: () async => 'Asia/Kolkata',
        storedZone: () async => current,
        storeZone: (value) async {
          stored.add(value);
          current = value;
        },
      );
      await zone.sync();
      await zone.sync();
      expect(stored, ['Asia/Kolkata']);
    });

    test(
      'never fails the app: no zone, or a failed write, changes nothing',
      () async {
        final stored = <String>[];
        await AccountTimeZone(
          deviceZone: () async => null,
          storedZone: () async => 'UTC',
          storeZone: (value) async => stored.add(value),
        ).sync();
        await AccountTimeZone(
          deviceZone: () async => 'Asia/Kolkata',
          storedZone: () async => 'UTC',
          storeZone: (_) => Future.error(Exception('offline')),
        ).sync();
        expect(stored, isEmpty);
      },
    );
  });
}
