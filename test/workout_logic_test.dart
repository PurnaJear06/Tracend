import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/train/exercise_history.dart';
import 'package:tracend/features/train/workout_logic.dart';

ExerciseHistory _history(
  ExerciseHistoryKind kind, {
  num? loadKg,
  required int reps,
}) => ExerciseHistory(
  key: 'exercise',
  kind: kind,
  lastSession: const ExerciseLastSession(),
  bestSet: ExerciseBestSet(kind: kind, loadKg: loadKg, repetitions: reps),
);

LoggedSet _done(num? load, int reps) =>
    LoggedSet(completed: true, loadKg: load, repetitions: reps);

void main() {
  group('new best', () {
    test('load: heavier wins, then more reps at the same load', () {
      final history = _history(ExerciseHistoryKind.load, loadKg: 80, reps: 5);
      expect(
        newBestSetIndexes(
          history: history,
          sets: [_done(80, 5), _done(80, 6), _done(82.5, 3), _done(75, 12)],
        ),
        {1, 2},
      );
    });

    test('a set must also beat the strongest earlier set this workout', () {
      final history = _history(ExerciseHistoryKind.load, loadKg: 80, reps: 5);
      expect(
        newBestSetIndexes(
          history: history,
          sets: [_done(85, 5), _done(85, 5), _done(82.5, 8), _done(85, 6)],
        ),
        {0, 3},
      );
    });

    test('un-ticking the record set hands the record to the next one', () {
      final history = _history(ExerciseHistoryKind.load, loadKg: 80, reps: 5);
      final sets = [_done(85, 5), _done(85, 5)];
      expect(newBestSetIndexes(history: history, sets: sets), {0});

      sets[0] = const LoggedSet(completed: false, loadKg: 85, repetitions: 5);
      expect(newBestSetIndexes(history: history, sets: sets), {1});
    });

    test('load: a set without added weight is not ranked', () {
      final history = _history(ExerciseHistoryKind.load, loadKg: 20, reps: 5);
      expect(
        newBestSetIndexes(
          history: history,
          sets: [_done(null, 30), _done(0, 30)],
        ),
        isEmpty,
      );
    });

    test('reps: more reps wins, load is ignored', () {
      final history = _history(ExerciseHistoryKind.reps, reps: 9);
      expect(
        newBestSetIndexes(
          history: history,
          sets: [
            _done(null, 9),
            _done(null, 10),
            _done(10, 10),
            _done(null, 11),
          ],
        ),
        {1, 3},
      );
    });

    test('assistance: less help wins, 0 is unassisted, then more reps', () {
      final history = _history(
        ExerciseHistoryKind.assistance,
        loadKg: 25,
        reps: 6,
      );
      expect(
        newBestSetIndexes(
          history: history,
          sets: [
            _done(30, 10),
            _done(25, 6),
            _done(25, 7),
            _done(20, 5),
            _done(0, 3),
            _done(null, 12),
          ],
        ),
        {2, 3, 4},
      );
    });

    test('no history, unknown history, and an unticked set never count', () {
      expect(
        newBestSetIndexes(
          history: const ExerciseHistory(key: 'exercise'),
          sets: [_done(100, 10)],
        ),
        isEmpty,
      );
      expect(newBestSetIndexes(history: null, sets: [_done(100, 10)]), isEmpty);
      expect(
        newBestSetIndexes(
          history: _history(ExerciseHistoryKind.load, loadKg: 80, reps: 5),
          sets: const [
            LoggedSet(completed: false, loadKg: 100, repetitions: 5),
          ],
        ),
        isEmpty,
      );
    });

    test('sets without reps are not ranked', () {
      expect(
        newBestSetIndexes(
          history: _history(ExerciseHistoryKind.load, loadKg: 80, reps: 5),
          sets: [const LoggedSet(completed: true, loadKg: 100)],
        ),
        isEmpty,
      );
    });

    test('first log means no history at all', () {
      expect(const ExerciseHistory(key: 'exercise').isFirstLog, isTrue);
      expect(_history(ExerciseHistoryKind.reps, reps: 5).isFirstLog, isFalse);
    });
  });

  group('weight lifted', () {
    test('sums load x reps over completed sets with a logged load', () {
      final total = weightLiftedKg([
        LoggedExercise(
          sets: [
            _done(22.5, 10),
            _done(22.5, 8),
            const LoggedSet(completed: false, loadKg: 22.5, repetitions: 8),
          ],
        ),
        LoggedExercise(sets: [_done(null, 12), _done(0, 12)]),
        LoggedExercise(sets: [_done(0.1, 3)]),
      ]);
      // A dumbbell load counts once, as entered.
      expect(total, 405.3);
    });

    test('assisted exercises add nothing', () {
      expect(
        weightLiftedKg([
          LoggedExercise(assisted: true, sets: [_done(30, 8)]),
          LoggedExercise(sets: [_done(50, 5)]),
        ]),
        250,
      );
    });

    test('is zero with nothing weighted', () {
      expect(weightLiftedKg(const []), 0);
    });
  });

  test('draft text reads like the server reads it', () {
    final set = LoggedSet.fromDraft({
      'load_kg': ' 62.5 ',
      'repetitions': '8',
      'completed': true,
    });
    expect(set.loadKg, 62.5);
    expect(set.repetitions, 8);
    expect(set.completed, isTrue);

    final unreadable = LoggedSet.fromDraft({
      'load_kg': '62,5',
      'repetitions': '',
      'completed': 'yes',
    });
    expect(unreadable.loadKg, isNull);
    expect(unreadable.repetitions, isNull);
    expect(unreadable.completed, isFalse);
  });

  test('assisted exercises follow the server rule', () {
    expect(isAssistedExercise(slug: 'assisted-pull-up', name: 'x'), isTrue);
    expect(
      isAssistedExercise(slug: 'pull-up', name: 'Assisted pull-up'),
      isFalse,
    );
    expect(isAssistedExercise(name: '  Assisted   dip'), isTrue);
    expect(isAssistedExercise(name: 'Assistedish row'), isFalse);
  });
}
