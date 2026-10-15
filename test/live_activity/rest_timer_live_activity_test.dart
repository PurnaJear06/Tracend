import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/train/rest_timer.dart';

import 'fake_workout_activity_bridge.dart';

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
      workoutTitle: 'Push day',
    );

    final call = activity.calls.single;
    expect(call.method, 'startRest');
    expect(call.endsAt, start.add(const Duration(seconds: 90)));
    expect(call.endsAt, controller.timer!.endsAt);
    expect(call.nextLabel, 'Set 3 of Bench press');
    expect(call.exerciseName, 'Bench press');
    expect(call.workoutTitle, 'Push day');
  });

  test('a rest started without labels sends empty ones', () async {
    await controller.start(60);

    final call = activity.calls.single;
    expect(call.nextLabel, '');
    expect(call.exerciseName, '');
    expect(call.workoutTitle, '');
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

  test('-15 past the end ends it', () async {
    await controller.start(90);
    now = now.add(const Duration(seconds: 80));

    await controller.adjust(-RestTimer.step);

    expect(activity.methods, ['startRest', 'end']);
    expect(controller.timer, isNull);
  });

  test('adjusting without a running rest does nothing', () async {
    await controller.adjust(RestTimer.step);

    expect(activity.calls, isEmpty);
  });

  test('skip ends it', () async {
    await controller.start(90);
    await controller.skip();

    expect(activity.methods, ['startRest', 'end']);
    expect(activity.showingUntil, isNull);
  });

  test('the in-app end of the rest ends it', () async {
    await controller.start(90);
    now = now.add(const Duration(seconds: 90));
    await controller.stop();

    expect(activity.methods.last, 'end');
    expect(activity.showingUntil, isNull);
  });

  test('finishing, discarding or leaving the workout ends it', () async {
    await controller.start(90);
    now = now.add(const Duration(seconds: 10));
    await controller.stop();

    expect(activity.methods, ['startRest', 'end']);
    expect(controller.timer, isNull);
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
}
