import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/train/rest_timer.dart';

import 'fake_workout_activity_bridge.dart';

/// An alert scheduler whose scheduling waits until the test completes it.
class _SlowAlerts implements RestAlertScheduler {
  final pending = Completer<void>();

  @override
  Future<bool> scheduleRestAlert(int seconds) async {
    await pending.future;
    return true;
  }

  @override
  Future<void> cancelRestAlert() async {}
}

class _QuietAlerts implements RestAlertScheduler {
  @override
  Future<bool> scheduleRestAlert(int seconds) async => true;

  @override
  Future<void> cancelRestAlert() async {}
}

void main() {
  final start = DateTime.utc(2026, 10, 15, 9);
  late DateTime now;
  late FakeWorkoutActivityBridge activity;
  late RestTimerController controller;

  RestTimerController newController() => RestTimerController(
    alerts: _QuietAlerts(),
    activity: activity,
    clock: () => now,
  );

  setUp(() {
    now = start;
    activity = FakeWorkoutActivityBridge();
    controller = newController();
  });

  test('starting a rest shows it with its end and labels', () async {
    await controller.start(
      90,
      nextLabel: 'Set 3 of Bench press',
      exerciseName: 'Bench press',
    );

    final call = activity.calls.single;
    expect(call.method, 'startRest');
    expect(call.endsAt, start.add(const Duration(seconds: 90)));
    expect(call.endsAt, controller.timer!.endsAt);
    expect(call.nextLabel, 'Set 3 of Bench press');
    expect(call.exerciseName, 'Bench press');
  });

  test('a rest started without labels sends empty ones', () async {
    await controller.start(60);

    final call = activity.calls.single;
    expect(call.nextLabel, '');
    expect(call.exerciseName, '');
  });

  test('a new rest replaces the one showing', () async {
    await controller.start(90);
    now = now.add(const Duration(seconds: 20));
    await controller.start(60);

    expect(activity.methods, ['startRest', 'startRest']);
    expect(activity.showingUntil, now.add(const Duration(seconds: 60)));
  });

  test('a zero rest shows nothing and ends any leftover', () async {
    await controller.start(0);

    expect(activity.methods, ['end']);
    expect(activity.showingUntil, isNull);
  });

  test('+15 and -15 move the end that is showing', () async {
    await controller.start(90);
    now = now.add(const Duration(seconds: 40));

    await controller.adjust(RestTimer.step);
    expect(activity.calls.last.method, 'updateRest');
    expect(activity.calls.last.endsAt, start.add(const Duration(seconds: 105)));

    await controller.adjust(-RestTimer.step);
    expect(activity.calls.last.endsAt, start.add(const Duration(seconds: 90)));
    expect(activity.showingUntil, controller.timer!.endsAt);
  });

  test('-15 past the end turns it to "Rest done" now', () async {
    await controller.start(90);
    now = now.add(const Duration(seconds: 80));

    await controller.adjust(-RestTimer.step);

    expect(activity.methods, ['startRest', 'updateRest']);
    expect(activity.calls.last.endsAt, now);
    expect(controller.timer, isNull);
  });

  test('+30 from the Live Activity moves the end', () async {
    await controller.start(90);
    now = now.add(const Duration(seconds: 50));

    await controller.adjust(const Duration(seconds: 30));

    expect(activity.calls.last.method, 'updateRest');
    expect(activity.calls.last.endsAt, start.add(const Duration(seconds: 120)));
  });

  test('adjusting without a running rest does nothing', () async {
    await controller.adjust(RestTimer.step);

    expect(activity.calls, isEmpty);
  });

  test('skip turns it to "Rest done" now, so Done can follow', () async {
    await controller.start(90);
    now = now.add(const Duration(seconds: 30));
    await controller.skip();

    expect(activity.methods, ['startRest', 'updateRest']);
    expect(activity.showingUntil, now);
    expect(controller.timer, isNull);
  });

  test(
    'a rest that ran out sends nothing: it already reads "Rest done"',
    () async {
      await controller.start(90);
      now = now.add(const Duration(seconds: 95));
      await controller.ranOut();

      expect(activity.methods, ['startRest']);
      expect(controller.timer, isNull);
    },
  );

  test('"Rest done" goes two minutes after the end of the rest', () async {
    await controller.start(90);
    now = now.add(const Duration(seconds: 90));
    await controller.ranOut();

    now = now.add(const Duration(seconds: 119));
    controller.tick();
    expect(activity.methods, ['startRest']);

    now = now.add(const Duration(seconds: 1));
    controller.tick();
    controller.tick();
    expect(activity.methods, ['startRest', 'end']);
  });

  test('"Rest done" after a skip goes two minutes after the skip', () async {
    await controller.start(90);
    now = now.add(const Duration(seconds: 10));
    await controller.skip();

    now = now.add(RestTimerController.doneLinger);
    controller.tick();

    expect(activity.methods, ['startRest', 'updateRest', 'end']);
  });

  test('the next rest replaces "Rest done" and nothing ends it', () async {
    await controller.start(90);
    await controller.skip();
    now = now.add(const Duration(seconds: 40));
    await controller.start(90);

    now = now.add(RestTimerController.doneLinger);
    controller.tick();

    expect(activity.methods, ['startRest', 'updateRest', 'startRest']);
  });

  test('finishing, discarding or leaving the workout ends it', () async {
    await controller.start(90);
    now = now.add(const Duration(seconds: 10));
    await controller.stop();

    expect(activity.methods, ['startRest', 'end']);
    expect(controller.timer, isNull);
  });

  test(
    'a stop while the start waits on the alert leaves nothing showing',
    () async {
      final alerts = _SlowAlerts();
      final slow = RestTimerController(
        alerts: alerts,
        activity: activity,
        clock: () => now,
      );

      final starting = slow.start(90);
      await slow.stop();
      alerts.pending.complete();
      await starting;

      expect(activity.methods, ['startRest', 'end']);
      expect(activity.showingUntil, isNull);
    },
  );

  test('the screen going away ends a running rest\'s activity only', () async {
    await controller.start(90);
    controller.detach();

    expect(activity.methods, ['startRest', 'end']);
    expect(controller.timer, isNotNull);
    expect(controller.toDraft(), isNotNull);
  });

  test('the screen going away ends "Rest done" too', () async {
    await controller.start(90);
    await controller.skip();
    controller.detach();

    expect(activity.methods, ['startRest', 'updateRest', 'end']);
  });

  test('the screen going away with nothing showing sends nothing', () async {
    controller.detach();
    await controller.start(90);
    await controller.stop();
    controller.detach();

    expect(activity.methods, ['startRest', 'end']);
  });

  group('after a relaunch', () {
    test('a running rest moves the activity to its stored end', () async {
      await controller.start(90);
      final stored = controller.toDraft();

      now = now.add(const Duration(seconds: 30));
      final resumed = newController();
      await resumed.restore(stored);

      expect(activity.methods, ['startRest', 'updateRest']);
      expect(
        activity.calls.last.endsAt,
        start.add(const Duration(seconds: 90)),
      );
      expect(activity.calls.last.nextLabel, isNull);
      expect(activity.showingUntil, resumed.timer!.endsAt);
    });

    test('a rest that ended while the app was closed ends it', () async {
      await controller.start(90);
      final stored = controller.toDraft();

      now = now.add(const Duration(minutes: 5));
      final resumed = newController();
      await resumed.restore(stored);

      expect(activity.methods, ['startRest', 'end']);
      expect(resumed.timer, isNull);
    });

    test('nothing stored ends any leftover activity', () async {
      await controller.restore(null);

      expect(activity.methods, ['end']);
    });
  });

  group('waiting for the activity update', () {
    test(
      'activityUpdated waits for a slow update, in app code it does not',
      () async {
        final gate = Completer<void>();
        activity.hold = gate.future;
        // Starting a rest returns without waiting on the activity.
        await controller.start(90, nextLabel: 'Set 2');
        var settled = false;
        unawaited(controller.activityUpdated().then((_) => settled = true));
        await Future<void>.delayed(Duration.zero);
        expect(settled, isFalse);

        gate.complete();
        await Future<void>.delayed(Duration.zero);
        expect(settled, isTrue);
        expect(activity.showingUntil, controller.timer!.endsAt);
      },
    );

    test('a hanging update is waited for only activityWait', () async {
      activity.hold = Completer<void>().future;
      controller = RestTimerController(
        alerts: _QuietAlerts(),
        activity: activity,
        clock: () => now,
        activityWait: const Duration(milliseconds: 20),
      );
      await controller.start(90);

      await controller.activityUpdated();

      expect(activity.methods, ['startRest']);
      expect(controller.timer, isNotNull);
    });

    test('a failing update neither throws nor undoes the rest', () async {
      activity.failWith = StateError('no activity');
      await controller.start(90);
      await controller.adjust(const Duration(seconds: 30));

      await controller.activityUpdated();

      expect(controller.timer!.totalSeconds, 120);
    });
  });
}
