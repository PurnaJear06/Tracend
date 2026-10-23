import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/shared/home_widgets/home_widget_eraser.dart';
import 'package:tracend/shared/home_widgets/today_widget_publisher.dart';

import '../live_activity/fake_workout_activity_bridge.dart';
import 'fake_home_widget_bridge.dart';

const _athlete = '11111111-1111-4111-8111-111111111111';
const _anotherAthlete = '22222222-2222-4222-8222-222222222222';

const _targets = NutritionTargets(
  calories: 2400,
  protein: 160,
  carbohydrate: 280,
  fat: 70,
);

DailyBrief _brief({num protein = 80}) => DailyBrief(
  localDate: '2026-10-18',
  workout: const {
    'name': 'Push day',
    'exercises': [
      {
        'order': 1,
        'name': 'Bench press',
        'set_count': 4,
        'rep_min': 6,
        'rep_max': 8,
      },
    ],
  },
  nutrition: {'calories': 1200, 'protein_g': protein},
);

void main() {
  // Turning numbers off also reaches the workout's Live Activity channel,
  // which has no native side here.
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeHomeWidgetBridge bridge;
  late DateTime now;
  late TodayWidgetPublisher publisher;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    bridge = FakeHomeWidgetBridge();
    now = DateTime.utc(2026, 10, 18, 8);
    publisher = TodayWidgetPublisher(
      bridge: bridge,
      preferences: SharedPreferencesAsync(),
      clock: () => now,
    );
  });

  Future<void> publish({num protein = 80}) => publisher.publish(
    brief: _brief(protein: protein),
    targets: _targets,
    checkedIn: true,
  );

  test(
    'Lock Screen numbers start off, so the snapshot has no lock section',
    () async {
      expect(await publisher.lockScreenNumbers(), isFalse);

      await publish();

      expect(bridge.stored!['lock'], isNull);
      expect(bridge.stored!['recovery'], isNull);
      expect((bridge.stored!['session'] as Map)['name'], 'Push day');
    },
  );

  test('an unchanged day is not written again within five minutes', () async {
    await publish();
    now = now.add(const Duration(minutes: 4));
    await publish();

    expect(bridge.writes, 1);
  });

  test(
    'an unchanged day is written again after five minutes, with a fresh time',
    () async {
      await publish();
      final first = bridge.stored!['generated_at_millis'];
      now = now.add(TodayWidgetPublisher.refreshAfter);
      await publish();

      expect(bridge.writes, 2);
      expect(bridge.stored!['generated_at_millis'], greaterThan(first as int));
    },
  );

  test('a changed number is written at once', () async {
    await publish();
    now = now.add(const Duration(seconds: 10));
    await publish(protein: 95);

    expect(bridge.writes, 2);
    expect((bridge.stored!['nutrition'] as Map)['protein_g'], 95);
  });

  test(
    'turning numbers on rewrites the snapshot with the lock section',
    () async {
      await publish();
      await publisher.setLockScreenNumbers(true);

      expect(bridge.writes, 2);
      expect(bridge.stored!['lock'], {
        'session': 'Push day',
        'session_state': 'planned',
        'recovery': null,
        'protein_g': 80,
        'protein_target_g': 160,
      });
    },
  );

  test('turning numbers off also takes the kg and reps off the workout card, '
      'turning them on does not touch it', () async {
    final activity = FakeWorkoutActivityBridge();
    final withCard = TodayWidgetPublisher(
      bridge: bridge,
      preferences: SharedPreferencesAsync(),
      clock: () => now,
      activity: activity,
    );

    await withCard.setLockScreenNumbers(true);
    expect(activity.calls, isEmpty);

    await withCard.setLockScreenNumbers(false);
    expect(activity.methods, ['hideNumbers']);
  });

  test('turning numbers off takes the lock section out at once', () async {
    await publish();
    await publisher.setLockScreenNumbers(true);
    await publisher.setLockScreenNumbers(false);

    expect(bridge.stored!['lock'], isNull);
  });

  test('numbers off removes the snapshot when the rewrite fails', () async {
    await publish();
    await publisher.setLockScreenNumbers(true);
    expect(bridge.stored!['lock'], isNotNull);

    bridge.failWrites = true;
    await publisher.setLockScreenNumbers(false);

    // The old lock section must not stay readable.
    expect(bridge.stored, isNull);
  });

  test('numbers off tries the removal twice when the first fails', () async {
    await publish();
    await publisher.setLockScreenNumbers(true);

    bridge
      ..failWrites = true
      ..failClears = 1;
    await publisher.setLockScreenNumbers(false);

    expect(bridge.stored, isNull);
    expect(bridge.calls.where((call) => call == 'clear'), hasLength(2));
  });

  test('an opt-out whose removal fails twice is saved and retried', () async {
    final eraser = HomeWidgetEraser(
      bridge,
      preferences: SharedPreferencesAsync(),
    );
    final shared = TodayWidgetPublisher(
      bridge: bridge,
      preferences: SharedPreferencesAsync(),
      eraser: eraser,
      clock: () => now,
    );
    await shared.publish(brief: _brief(), targets: _targets, checkedIn: true);
    await shared.setLockScreenNumbers(true);
    expect(bridge.stored!['lock'], isNotNull);

    bridge
      ..failWrites = true
      ..failClears = 2;
    final removed = await shared.setLockScreenNumbers(false);

    // The old numbers are still readable, so the athlete is told; but the
    // choice is Off for good and a retry is waiting.
    expect(removed, isFalse);
    expect(await shared.lockScreenNumbers(), isFalse);
    expect(bridge.stored!['lock'], isNotNull);
    expect(await eraser.isPending(), isTrue);

    // The next resume's retry works; the widgets get a snapshot again, and
    // it has no lock section.
    bridge.failWrites = false;
    await eraser.retryPending();
    await pumpEventQueue();
    expect(await eraser.isPending(), isFalse);
    expect(bridge.stored!['lock'], isNull);

    await shared.publish(
      brief: _brief(protein: 120),
      targets: _targets,
      checkedIn: true,
    );
    expect(bridge.stored!['lock'], isNull);
    final next = TodayWidgetPublisher(
      bridge: bridge,
      preferences: SharedPreferencesAsync(),
      clock: () => now,
    );
    expect(await next.lockScreenNumbers(), isFalse);
  });

  test('writing the last snapshot again keeps the load time', () async {
    final eraser = HomeWidgetEraser(
      bridge,
      preferences: SharedPreferencesAsync(),
    );
    final shared = TodayWidgetPublisher(
      bridge: bridge,
      preferences: SharedPreferencesAsync(),
      eraser: eraser,
      clock: () => now,
    );
    await shared.publish(brief: _brief(), targets: _targets, checkedIn: true);
    final loaded = bridge.stored!['generated_at_millis'] as int;
    expect(loaded, now.millisecondsSinceEpoch);

    // Hours later a choice change and a retried clear write it again; the
    // brief is no younger, so its 12-hour expiry still counts from the load.
    now = now.add(const Duration(hours: 3));
    await shared.setLockScreenNumbers(true);
    expect(bridge.stored!['generated_at_millis'], loaded);

    bridge
      ..failWrites = true
      ..failClears = 2;
    await shared.setLockScreenNumbers(false);
    bridge.failWrites = false;
    now = now.add(const Duration(hours: 2));
    await eraser.retryPending();
    await pumpEventQueue();
    expect(bridge.stored!['generated_at_millis'], loaded);
  });

  test(
    'a snapshot written over the old file settles a pending clear',
    () async {
      bridge.failClears = 2;
      await publish();
      await publisher.dispose();
      expect(await HomeWidgetEraser(bridge).isPending(), isTrue);

      final again = TodayWidgetPublisher(
        bridge: bridge,
        preferences: SharedPreferencesAsync(),
        clock: () => now,
      );
      await again.publish(brief: _brief(), targets: _targets, checkedIn: true);

      expect(bridge.stored, isNotNull);
      expect(await HomeWidgetEraser(bridge).isPending(), isFalse);
    },
  );

  test('a publish still reading the choice when the app screens go away '
      'writes nothing', () async {
    final held = _HeldPreferences();
    SharedPreferencesAsyncPlatform.instance = held;
    final slow = TodayWidgetPublisher(
      bridge: bridge,
      preferences: SharedPreferencesAsync(),
      clock: () => now,
    );
    held.hold = Completer<void>();

    final publishing = slow.publish(
      brief: _brief(),
      targets: _targets,
      checkedIn: true,
    );
    await slow.dispose();
    expect(bridge.calls, ['clear']);

    held.hold!.complete();
    await publishing;
    await pumpEventQueue();

    expect(bridge.calls, ['clear']);
    expect(bridge.stored, isNull);
  });

  test('a failed write is tried again by the next load', () async {
    bridge.failWrites = true;
    await publish();
    expect(bridge.stored, isNull);

    bridge.failWrites = false;
    await publish();

    expect(bridge.stored, isNotNull);
  });

  test(
    'turning numbers off with no Today loaded removes the snapshot',
    () async {
      await publisher.setLockScreenNumbers(true);
      expect(bridge.calls, isEmpty);

      await publisher.setLockScreenNumbers(false);

      expect(bridge.calls, ['clear']);
      expect(bridge.stored, isNull);
    },
  );

  test('the choice is kept for the next launch', () async {
    await publisher.setLockScreenNumbers(true);

    final next = TodayWidgetPublisher(
      bridge: bridge,
      preferences: SharedPreferencesAsync(),
      clock: () => now,
    );
    expect(await next.lockScreenNumbers(), isTrue);
    await next.publish(brief: _brief(), targets: _targets, checkedIn: false);
    expect(bridge.stored!['lock'], isNotNull);
  });

  test('the choice belongs to one athlete on this phone', () async {
    final athlete = TodayWidgetPublisher(
      bridge: bridge,
      userId: _athlete,
      preferences: SharedPreferencesAsync(),
      clock: () => now,
    );
    await athlete.setLockScreenNumbers(true);
    // An earlier build's phone-wide choice is never read for an athlete.
    await SharedPreferencesAsync().setBool(
      TodayWidgetPublisher.lockScreenNumbersKey,
      true,
    );

    final another = TodayWidgetPublisher(
      bridge: bridge,
      userId: _anotherAthlete,
      preferences: SharedPreferencesAsync(),
      clock: () => now,
    );
    expect(await another.lockScreenNumbers(), isFalse);
    await another.publish(brief: _brief(), targets: _targets, checkedIn: true);
    expect(bridge.stored!['lock'], isNull);

    final again = TodayWidgetPublisher(
      bridge: bridge,
      userId: _athlete,
      preferences: SharedPreferencesAsync(),
      clock: () => now,
    );
    expect(await again.lockScreenNumbers(), isTrue);
  });

  test('leaving the app clears the snapshot and stops publishing', () async {
    await publish();
    await publisher.dispose();
    expect(bridge.stored, isNull);

    await publish(protein: 120);

    expect(bridge.stored, isNull);
    expect(bridge.calls.last, 'clear');
  });
}

/// Answers every read only once [hold] completes, as a slow store would.
base class _HeldPreferences extends InMemorySharedPreferencesAsync {
  _HeldPreferences() : super.empty();

  Completer<void>? hold;

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async {
    await hold?.future;
    return super.getBool(key, options);
  }
}
