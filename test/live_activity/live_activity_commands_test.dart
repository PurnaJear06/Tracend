import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/train/workout_events.dart';
import 'package:tracend/shared/live_activity/workout_activity_bridge.dart';

void main() {
  final at = DateTime.utc(2026, 10, 15, 9);

  group('each Live Activity button maps to one Contract 3 command', () {
    test('Done completes the set the card named', () {
      final command =
          workoutCommandFor(DoneSetButton(at, exerciseOrder: 2, setNumber: 3))
              as CompleteCurrentSet;
      expect((command.exerciseOrder, command.setNumber), (2, 3));
    });

    test('Skip skips the rest', () {
      expect(workoutCommandFor(SkipRestButton(at)), isA<SkipRest>());
    });

    test('+30s adds the seconds it carries', () {
      final command = workoutCommandFor(AddRestButton(at, 30));
      expect(command, isA<AddRest>());
      expect((command as AddRest).seconds, 30);
    });

    test('the channel arguments iOS sends read as those buttons', () {
      final stamp = at.millisecondsSinceEpoch;
      final done =
          LiveActivityButton.fromChannel({
                'button': 'done',
                'exercise_order': 1,
                'set_number': 2,
                'pressed_at_millis': stamp,
              })!
              as DoneSetButton;
      expect((done.exerciseOrder, done.setNumber), (1, 2));
      expect(done.pressedAt.isAtSameMomentAs(at), isTrue);
      expect(
        done.expiresAt.isAtSameMomentAs(
          at.add(LiveActivityButton.pressTimeout),
        ),
        isTrue,
      );
      expect(
        LiveActivityButton.fromChannel({
          'button': 'skip',
          'pressed_at_millis': stamp,
        }),
        isA<SkipRestButton>(),
      );
      final add = LiveActivityButton.fromChannel({
        'button': 'add_rest',
        'seconds': 30,
        'pressed_at_millis': stamp,
      });
      expect((add! as AddRestButton).seconds, 30);
      expect(LiveActivityButton.fromChannel('done'), isNull);
    });

    test('a Done without its set, or any press without a time, is refused', () {
      final stamp = at.millisecondsSinceEpoch;
      expect(
        LiveActivityButton.fromChannel({
          'button': 'done',
          'pressed_at_millis': stamp,
        }),
        isNull,
      );
      expect(
        LiveActivityButton.fromChannel({
          'button': 'done',
          'exercise_order': 1,
          'set_number': 2,
        }),
        isNull,
      );
      expect(LiveActivityButton.fromChannel({'button': 'skip'}), isNull);
    });
  });

  group('the command sink', () {
    test('send completes once the screen has acted on the command', () async {
      final hub = WorkoutEventHub();
      final acted = Completer<bool>();
      final seen = <WorkoutCommand>[];
      hub.handleCommands((command) {
        seen.add(command);
        return acted.future;
      });

      var done = false;
      final sending = hub.send(const SkipRest()).then((v) {
        done = true;
        return v;
      });
      await pumpEventQueue();
      expect(seen.single, isA<SkipRest>());
      expect(done, isFalse);

      acted.complete(true);
      expect(await sending, isTrue);
      expect(done, isTrue);
      hub.close();
    });

    test('commands reach the screen in the order they were sent', () async {
      final hub = WorkoutEventHub();
      final seen = <WorkoutCommand>[];
      hub.handleCommands((command) async {
        seen.add(command);
        return true;
      });

      hub.commands.add(
        const CompleteCurrentSet(exerciseOrder: 1, setNumber: 1),
      );
      await hub.send(const AddRest(30));
      await hub.send(const SkipRest());

      expect(seen.map((c) => c.runtimeType), [
        CompleteCurrentSet,
        AddRest,
        SkipRest,
      ]);
      hub.close();
    });

    test('a failing handler still answers the sender, false', () async {
      final hub = WorkoutEventHub();
      hub.handleCommands((_) async => throw StateError('closed'));

      expect(await hub.send(const SkipRest()), isFalse);
      hub.close();
    });

    test('a command starts only after the one before it finished', () async {
      final hub = WorkoutEventHub();
      final first = Completer<bool>();
      final started = <String>[];
      hub.handleCommands((command) {
        started.add(command.runtimeType.toString());
        return command is SkipRest ? first.future : Future.value(true);
      });

      final slow = hub.send(const SkipRest());
      final next = hub.send(const AddRest(30));
      await pumpEventQueue();
      expect(started, ['SkipRest']);

      first.complete(true);
      expect(await slow, isTrue);
      expect(await next, isTrue);
      expect(started, ['SkipRest', 'AddRest']);
      hub.close();
    });

    test(
      'a command that waited past its expiry is dropped unhandled',
      () async {
        final hub = WorkoutEventHub();
        var now = at;
        final first = Completer<bool>();
        final seen = <WorkoutCommand>[];
        hub.handleCommands((command) {
          seen.add(command);
          return command is SkipRest ? first.future : Future.value(true);
        }, clock: () => now);

        final slow = hub.send(const SkipRest());
        final late = hub.send(
          const AddRest(30),
          expiresAt: at.add(const Duration(seconds: 8)),
        );
        await pumpEventQueue();
        now = at.add(const Duration(seconds: 9));
        first.complete(true);

        expect(await slow, isTrue);
        expect(await late, isFalse);
        expect(seen.single, isA<SkipRest>());
        hub.close();
      },
    );

    test('closing answers a command still waiting, false', () async {
      final hub = WorkoutEventHub();
      final sending = hub.send(const SkipRest());

      hub.close();
      expect(await sending, isFalse);
      expect(await hub.send(const SkipRest()), isFalse);
    });
  });
}
