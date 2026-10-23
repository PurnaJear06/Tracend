import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/train/rest_timer.dart';
import 'package:tracend/shared/live_activity/workout_activity_bridge.dart';

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

/// Set 2 of 4 of Bench press, as the logger pre-fills it.
ActivitySet _set({
  int exerciseOrder = 1,
  int setNumber = 2,
  String target = '82.5 kg × 8',
  bool canLog = true,
}) => (
  exerciseOrder: exerciseOrder,
  setNumber: setNumber,
  setCount: 4,
  exerciseName: 'Bench press',
  target: target,
  canLog: canLog,
);

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
    activity = FakeWorkoutActivityBridge(clock: () => now);
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

  test('a rest carries the set the card turns into', () async {
    await controller.start(90, next: _set());

    expect(activity.calls.single.next, _set());
    expect(activity.set, _set());
    expect(activity.phase, 'rest');

    now = now.add(const Duration(seconds: 90));
    expect(activity.phase, 'set');
  });

  test('a zero rest starts nothing', () async {
    await controller.start(0);

    expect(activity.calls, isEmpty);
    expect(controller.timer, isNull);
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

  test('-15 past the end turns the card into the set now', () async {
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

  test('skip turns the card into the set now, so Log set can follow', () async {
    await controller.start(90, next: _set());
    now = now.add(const Duration(seconds: 30));
    await controller.skip();

    expect(activity.methods, ['startRest', 'updateRest']);
    expect(activity.showingUntil, now);
    expect(activity.phase, 'set');
    expect(activity.card, (exerciseOrder: 1, setNumber: 2));
    expect(controller.timer, isNull);
  });

  test(
    'a rest that ran out sends nothing: the card turns into the set itself',
    () async {
      await controller.start(90, next: _set());
      now = now.add(const Duration(seconds: 95));
      await controller.ranOut();

      expect(activity.methods, ['startRest']);
      expect(activity.phase, 'set');
      expect(controller.timer, isNull);
    },
  );

  test('the set in progress is never ended by the clock', () async {
    await controller.start(90, next: _set());
    now = now.add(const Duration(seconds: 90));
    await controller.ranOut();

    now = now.add(const Duration(hours: 1));
    controller.tick();

    expect(activity.methods, ['startRest']);
    expect(activity.phase, 'set');
  });

  test('the next rest replaces the set in progress', () async {
    await controller.start(90, next: _set());
    await controller.skip();
    now = now.add(const Duration(seconds: 40));
    await controller.start(90, next: _set(setNumber: 3));

    expect(activity.methods, ['startRest', 'updateRest', 'startRest']);
    expect(activity.phase, 'rest');
    expect(activity.card, (exerciseOrder: 1, setNumber: 3));
  });

  group('the set in progress', () {
    test('the workout opening asks for a card', () {
      controller.present(_set(), begin: true);

      expect(activity.calls.single.method, 'showSet');
      expect(activity.calls.single.begin, isTrue);
      expect(activity.calls.single.next, _set());
      expect(activity.phase, 'set');
    });

    test('an edit moves a card that is there, and never brings one back', () {
      controller.present(_set(), begin: true);
      controller.present(_set(target: '85 kg × 8'));
      expect(activity.set!.target, '85 kg × 8');

      activity.showingUntil = null; // the athlete dismissed it
      controller.present(_set(target: '87.5 kg × 8'));
      expect(activity.showing, isFalse);
      expect(activity.calls.last.begin, isFalse);
    });

    test('the same set again sends nothing, unless it begins', () {
      controller.present(_set(), begin: true);
      controller.present(_set());
      expect(activity.calls, hasLength(1));

      controller.present(_set(), begin: true);
      expect(activity.calls, hasLength(2));
    });

    test('during a rest only the set that follows is updated', () async {
      await controller.start(90, next: _set());
      controller.present(_set());
      expect(activity.calls, hasLength(1));

      controller.present(_set(exerciseOrder: 2, setNumber: 1));
      expect(activity.methods, ['startRest', 'updateRest']);
      expect(activity.calls.last.endsAt, controller.timer!.endsAt);
      expect(activity.calls.last.next!.exerciseOrder, 2);
      expect(activity.phase, 'rest');
      controller.present(null);
      expect(activity.calls, hasLength(2));
    });

    test('a set the app cannot log shows the card without a button', () {
      controller.present(_set(canLog: false), begin: true);

      expect(activity.set!.canLog, isFalse);
    });

    test('every set logged says so, and the card goes after two minutes', () {
      controller.present(_set(), begin: true);
      controller.present(null, begin: true);
      expect(activity.phase, 'finished');

      now = now.add(const Duration(seconds: 119));
      controller.tick();
      expect(activity.showing, isTrue);

      now = now.add(const Duration(seconds: 1));
      controller.tick();
      controller.tick();
      expect(activity.methods, ['showSet', 'showSet', 'end']);
      expect(activity.showing, isFalse);
    });

    test('a set logged again within those two minutes keeps the card', () {
      controller.present(null, begin: true);
      now = now.add(const Duration(seconds: 90));
      controller.present(_set());
      now = now.add(const Duration(minutes: 5));
      controller.tick();

      expect(activity.methods, ['showSet', 'showSet']);
      expect(activity.phase, 'set');
    });

    test('refresh redraws the card as it is, rest or set', () async {
      controller.present(_set(), begin: true);
      controller.refresh();
      expect(activity.calls.last.method, 'showSet');
      expect(activity.calls.last.begin, isFalse);
      expect(activity.calls.last.next, _set());

      await controller.start(90, next: _set(setNumber: 3));
      controller.refresh();
      expect(activity.calls.last.method, 'updateRest');
      expect(activity.calls.last.endsAt, controller.timer!.endsAt);
      expect(activity.calls.last.next, _set(setNumber: 3));
    });

    test('refresh with nothing shown sends nothing', () {
      controller.refresh();

      expect(activity.calls, isEmpty);
    });
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

  test('the screen going away ends the set in progress too', () async {
    controller.present(_set(), begin: true);
    controller.detach();
    controller.detach();

    expect(activity.methods, ['showSet', 'end']);
    expect(activity.showing, isFalse);
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

    test('a rest that ended while the app was closed leaves the card to '
        'the set in progress', () async {
      await controller.start(90, next: _set());
      final stored = controller.toDraft();

      now = now.add(const Duration(minutes: 5));
      final resumed = newController();
      await resumed.restore(stored);
      expect(activity.methods, ['startRest']);
      expect(resumed.timer, isNull);

      resumed.present(_set(), begin: true);
      expect(activity.methods, ['startRest', 'showSet']);
      expect(activity.phase, 'set');
    });

    test('nothing stored leaves the activity alone', () async {
      await controller.restore(null);

      expect(activity.calls, isEmpty);
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
