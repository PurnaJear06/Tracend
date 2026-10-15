import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tracend/app/breadcrumbs.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/train/rest_timer.dart';
import 'package:tracend/shared/live_activity/workout_activity_bridge.dart';

/// Plays the native side of `tracend/live_activity` as
/// `ios/Runner/Native/WorkoutActivityBridge.swift` implements it: one rest
/// activity at most, every call answers whether one is showing, and
/// `attachButtons`/`detachButtons` say whether a workout takes the buttons.
class _NativeLiveActivity {
  final calls = <MethodCall>[];
  bool enabled = true;
  int? showingUntilMillis;
  bool buttonsAttached = false;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final arguments = call.arguments is Map
        ? Map<String, Object?>.from(call.arguments as Map)
        : const <String, Object?>{};
    switch (call.method) {
      case 'startRest':
        showingUntilMillis = null;
        if (!enabled) return false;
        showingUntilMillis = arguments['ends_at_millis']! as int;
        return true;
      case 'updateRest':
        if (showingUntilMillis == null) return false;
        showingUntilMillis = arguments['ends_at_millis']! as int;
        return true;
      case 'end':
        showingUntilMillis = null;
        return false;
      case 'attachButtons':
        buttonsAttached = true;
        return showingUntilMillis != null;
      case 'detachButtons':
        buttonsAttached = false;
        return showingUntilMillis != null;
    }
    throw MissingPluginException();
  }

  List<String> get methods => [for (final call in calls) call.method];
}

class _QuietAlerts implements RestAlertScheduler {
  @override
  Future<bool> scheduleRestAlert(int seconds) async => true;

  @override
  Future<void> cancelRestAlert() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NativeLiveActivity native;
  late List<Breadcrumb> breadcrumbs;
  final endsAt = DateTime.utc(2026, 10, 15, 9, 1, 30);
  const bridge = MethodChannelWorkoutActivityBridge();

  void setHandler(Future<Object?>? Function(MethodCall call)? handler) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(liveActivityChannel, handler);

  setUp(() {
    native = _NativeLiveActivity();
    breadcrumbs = [];
    AppBreadcrumbs.sink = breadcrumbs.add;
    setHandler(native.handle);
  });

  tearDown(() => setHandler(null));

  test('the channel name is the one SceneDelegate registers', () {
    expect(liveActivityChannel.name, 'tracend/live_activity');
  });

  test(
    'startRest sends the end in epoch milliseconds and the labels',
    () async {
      await bridge.startRest(
        endsAt: endsAt,
        nextLabel: 'Set 3 of Bench press',
        exerciseName: 'Bench press',
      );

      final call = native.calls.single;
      expect(call.method, 'startRest');
      expect(call.arguments, {
        'ends_at_millis': endsAt.millisecondsSinceEpoch,
        'next_label': 'Set 3 of Bench press',
        'exercise_name': 'Bench press',
      });
    },
  );

  test('updateRest sends the next label only when given', () async {
    await bridge.updateRest(endsAt: endsAt);
    await bridge.updateRest(endsAt: endsAt, nextLabel: 'Squat');

    expect(native.calls[0].arguments, {
      'ends_at_millis': endsAt.millisecondsSinceEpoch,
    });
    expect(native.calls[1].arguments, {
      'ends_at_millis': endsAt.millisecondsSinceEpoch,
      'next_label': 'Squat',
    });
  });

  test('end sends no arguments', () async {
    await bridge.end();

    expect(native.calls.single.method, 'end');
    expect(native.calls.single.arguments, isNull);
  });

  test(
    'breadcrumbs name the call and whether it shows, never values',
    () async {
      await bridge.startRest(
        endsAt: endsAt,
        nextLabel: 'Set 3 of Bench press',
        exerciseName: 'Bench press',
      );
      await bridge.end();

      expect(
        [for (final crumb in breadcrumbs) crumb.message],
        ['Rest live activity startRest', 'Rest live activity end'],
      );
      expect(breadcrumbs.first.category, 'workout');
      expect(breadcrumbs.first.data, {'showing': true});
      expect(breadcrumbs.last.data, {'showing': false});
    },
  );

  test('Live Activities turned off show nothing and throw nothing', () async {
    native.enabled = false;

    await bridge.startRest(endsAt: endsAt, nextLabel: '', exerciseName: '');

    expect(native.showingUntilMillis, isNull);
    expect(breadcrumbs.single.data, {'showing': false});
  });

  test('a refused request is swallowed', () async {
    setHandler((_) async => throw PlatformException(code: 'request_failed'));

    await bridge.startRest(endsAt: endsAt, nextLabel: '', exerciseName: '');
    await bridge.updateRest(endsAt: endsAt);
    await bridge.end();

    expect(breadcrumbs, hasLength(3));
    expect(breadcrumbs.every((c) => c.data!['showing'] == false), isTrue);
  });

  test('a missing native side is swallowed', () async {
    setHandler(null);

    await bridge.startRest(endsAt: endsAt, nextLabel: '', exerciseName: '');
    await bridge.end();

    expect(breadcrumbs, hasLength(2));
  });

  group('the rest timer drives the activity through the channel', () {
    late DateTime now;
    late RestTimerController controller;

    setUp(() {
      now = DateTime.utc(2026, 10, 15, 9);
      controller = RestTimerController(
        alerts: _QuietAlerts(),
        activity: bridge,
        clock: () => now,
      );
    });

    test('start, +15, skip', () async {
      await controller.start(90, nextLabel: 'Set 2 of Squat');
      await pumpEventQueue();
      expect(
        native.showingUntilMillis,
        now.add(const Duration(seconds: 90)).millisecondsSinceEpoch,
      );

      await controller.adjust(RestTimer.step);
      await pumpEventQueue();
      expect(
        native.showingUntilMillis,
        now.add(const Duration(seconds: 105)).millisecondsSinceEpoch,
      );

      await controller.skip();
      await pumpEventQueue();
      expect(native.methods, ['startRest', 'updateRest', 'updateRest']);
      expect(native.showingUntilMillis, now.millisecondsSinceEpoch);
    });

    test(
      'a relaunch with a stored rest moves the activity left showing',
      () async {
        await controller.start(90);
        await pumpEventQueue();
        final stored = controller.toDraft();

        now = now.add(const Duration(seconds: 30));
        final resumed = RestTimerController(
          alerts: _QuietAlerts(),
          activity: bridge,
          clock: () => now,
        );
        await resumed.restore(stored);
        await pumpEventQueue();

        expect(native.methods.last, 'updateRest');
        expect(
          native.showingUntilMillis,
          resumed.timer!.endsAt.millisecondsSinceEpoch,
        );
      },
    );
  });

  group('the buttons: iOS sends press, the open workout answers', () {
    const codec = StandardMethodCodec();

    /// Plays iOS tapping a button: sends `press` with [arguments] and
    /// returns the answer, or throws the error the app answered.
    Future<Object?> press(Object? arguments) async {
      final reply = await TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .handlePlatformMessage(
            liveActivityChannel.name,
            codec.encodeMethodCall(MethodCall('press', arguments)),
            (_) {},
          );
      return codec.decodeEnvelope(reply!);
    }

    final presses = <LiveActivityButton>[];
    Future<void> onPress(LiveActivityButton button) async =>
        presses.add(button);

    setUp(presses.clear);
    tearDown(() => bridge.detachButtons(onPress));

    test('attach and detach tell iOS whether a workout takes them', () async {
      await bridge.attachButtons(onPress);
      expect(native.buttonsAttached, isTrue);
      expect(native.calls.last.arguments, isNull);

      await bridge.detachButtons(onPress);
      expect(native.buttonsAttached, isFalse);
      expect(native.methods, ['attachButtons', 'detachButtons']);
    });

    test('a detach from an earlier handler leaves the current one', () async {
      Future<void> earlier(LiveActivityButton button) async {}
      await bridge.attachButtons(onPress);
      await bridge.detachButtons(earlier);

      expect(native.buttonsAttached, isTrue);
      expect(await press({'button': 'skip'}), isTrue);
    });

    test('each button arrives as its press and answers true', () async {
      await bridge.attachButtons(onPress);

      expect(await press({'button': 'done'}), isTrue);
      expect(await press({'button': 'skip'}), isTrue);
      expect(await press({'button': 'add_rest', 'seconds': 30}), isTrue);

      expect(presses[0], isA<DoneSetButton>());
      expect(presses[1], isA<SkipRestButton>());
      expect((presses[2] as AddRestButton).seconds, 30);
    });

    test('the answer waits for the workout to act', () async {
      final acted = Completer<void>();
      await bridge.attachButtons((_) => acted.future);

      var answered = false;
      final answer = press({'button': 'skip'}).then((v) => answered = true);
      await pumpEventQueue();
      expect(answered, isFalse);

      acted.complete();
      await answer;
      expect(answered, isTrue);
    });

    test('with no workout open the answer is false', () async {
      await bridge.attachButtons(onPress);
      await bridge.detachButtons(onPress);

      expect(await press({'button': 'done'}), isFalse);
      expect(presses, isEmpty);
    });

    test('a workout that fails to act answers false', () async {
      await bridge.attachButtons((_) async => throw StateError('closed'));

      expect(await press({'button': 'done'}), isFalse);
    });

    test('unknown buttons and bad seconds are refused', () async {
      await bridge.attachButtons(onPress);

      for (final arguments in [
        {'button': 'pause'},
        {'button': 'add_rest'},
        {'button': 'add_rest', 'seconds': 0},
        {'button': 'add_rest', 'seconds': 301},
        {'button': 'add_rest', 'seconds': '30'},
        null,
      ]) {
        await expectLater(
          press(arguments),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'invalid_arguments',
            ),
          ),
        );
      }
      expect(presses, isEmpty);
    });

    test('press breadcrumbs name the button only', () async {
      await bridge.attachButtons(onPress);
      breadcrumbs.clear();

      await press({'button': 'add_rest', 'seconds': 30});

      expect(breadcrumbs.single.message, 'Rest live activity press');
      expect(breadcrumbs.single.data, {'button': 'add_rest', 'taken': true});
    });
  });
}
