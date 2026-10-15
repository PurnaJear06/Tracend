import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/train/workout_events.dart';
import 'package:tracend/shared/live_activity/workout_activity_bridge.dart';

void main() {
  group('each Live Activity button maps to one Contract 3 command', () {
    test('Done completes the current set', () {
      expect(
        workoutCommandFor(const DoneSetButton()),
        isA<CompleteCurrentSet>(),
      );
    });

    test('Skip skips the rest', () {
      expect(workoutCommandFor(const SkipRestButton()), isA<SkipRest>());
    });

    test('+30s adds the seconds it carries', () {
      final command = workoutCommandFor(const AddRestButton(30));
      expect(command, isA<AddRest>());
      expect((command as AddRest).seconds, 30);
    });

    test('the channel arguments iOS sends read as those buttons', () {
      expect(
        LiveActivityButton.fromChannel({'button': 'done'}),
        isA<DoneSetButton>(),
      );
      expect(
        LiveActivityButton.fromChannel({'button': 'skip'}),
        isA<SkipRestButton>(),
      );
      final add = LiveActivityButton.fromChannel({
        'button': 'add_rest',
        'seconds': 30,
      });
      expect((add! as AddRestButton).seconds, 30);
      expect(LiveActivityButton.fromChannel('done'), isNull);
    });
  });

  group('the command sink', () {
    test('send completes once the screen has acted on the command', () async {
      final hub = WorkoutEventHub();
      final acted = Completer<void>();
      final seen = <WorkoutCommand>[];
      hub.handleCommands((command) {
        seen.add(command);
        return acted.future;
      });

      var done = false;
      final sending = hub.send(const SkipRest()).then((_) => done = true);
      await pumpEventQueue();
      expect(seen.single, isA<SkipRest>());
      expect(done, isFalse);

      acted.complete();
      await sending;
      expect(done, isTrue);
      hub.close();
    });

    test('commands reach the screen in the order they were sent', () async {
      final hub = WorkoutEventHub();
      final seen = <WorkoutCommand>[];
      hub.handleCommands((command) async => seen.add(command));

      hub.commands.add(const CompleteCurrentSet());
      await hub.send(const AddRest(30));
      await hub.send(const SkipRest());

      expect(seen.map((c) => c.runtimeType), [
        CompleteCurrentSet,
        AddRest,
        SkipRest,
      ]);
      hub.close();
    });

    test('a failing handler still answers the sender', () async {
      final hub = WorkoutEventHub();
      hub.handleCommands((_) async => throw StateError('closed'));

      await hub.send(const SkipRest());
      hub.close();
    });

    test('closing answers a command still waiting', () async {
      final hub = WorkoutEventHub();
      final sending = hub.send(const SkipRest());

      hub.close();
      await sending;
      await hub.send(const SkipRest());
    });
  });
}
