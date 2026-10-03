import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/train/exercise_history.dart';

Object? _fixture() => jsonDecode(
  File('test/contract/fixtures/exercise_history_v1_0.json').readAsStringSync(),
);

void main() {
  group('get_my_exercise_history 1.0', () {
    late ExerciseHistoryResult result;

    setUp(() => result = ExerciseHistoryResult.fromJson(_fixture()));

    test('carries its schema version', () {
      expect((_fixture()! as Map)['schema_version'], '1.0');
      expect(result.fromCache, isFalse);
      expect(result.exercises.keys, [
        'barbell-bench-press',
        'pull-up',
        'assisted-pull-up',
        'Cable fly',
      ]);
    });

    test('a load exercise reads last session, best and top sets', () {
      final bench = result['barbell-bench-press']!;

      expect(bench.kind, ExerciseHistoryKind.load);
      expect(bench.isFirstLog, isFalse);
      expect(bench.lastSession!.localDate, DateTime(2026, 9, 25));
      expect(bench.lastSession!.sets, hasLength(3));
      expect(bench.lastSession!.sets.first.loadKg, 70);
      expect(bench.lastSession!.sets.first.repetitions, 8);
      expect(bench.lastSession!.sets.first.rpe, 7);
      expect(bench.lastSession!.sets.last.rpe, isNull);
      expect(bench.bestSet!.kind, ExerciseHistoryKind.load);
      expect(bench.bestSet!.loadKg, 72.5);
      expect(bench.bestSet!.repetitions, 6);
      expect(bench.bestSet!.localDate, DateTime(2026, 9, 11));
      expect(bench.topSets.map((top) => top.loadKg), [70, 70, 72.5, 67.5]);
    });

    test('bodyweight and assisted exercises keep their kind', () {
      expect(result['pull-up']!.kind, ExerciseHistoryKind.reps);
      expect(result['pull-up']!.bestSet!.loadKg, isNull);
      expect(result['pull-up']!.bestSet!.repetitions, 9);

      final assisted = result['assisted-pull-up']!;
      expect(assisted.kind, ExerciseHistoryKind.assistance);
      expect(assisted.bestSet!.loadKg, 25);
    });

    test('an exercise never logged is a first log', () {
      final fly = result[' Cable fly ']!;

      expect(fly.kind, isNull);
      expect(fly.lastSession, isNull);
      expect(fly.bestSet, isNull);
      expect(fly.topSets, isEmpty);
      expect(fly.isFirstLog, isTrue);
    });

    test('a key the answer does not hold is unknown, not a first log', () {
      expect(result['romanian-deadlift'], isNull);
    });
  });

  group('missing and mistyped fields read as unknown', () {
    test('an empty or foreign body has no exercises', () {
      expect(ExerciseHistoryResult.fromJson(null).exercises, isEmpty);
      expect(ExerciseHistoryResult.fromJson('oops').exercises, isEmpty);
      expect(
        ExerciseHistoryResult.fromJson({'exercises': 'none'}).exercises,
        isEmpty,
      );
    });

    test('entries without a key are left out', () {
      final result = ExerciseHistoryResult.fromJson({
        'exercises': [
          {'kind': 'load'},
          {'key': 7},
          'row',
          {'key': 'squat'},
        ],
      });
      expect(result.exercises.keys, ['squat']);
      expect(result['squat']!.isFirstLog, isTrue);
    });

    test('a partial entry keeps what it can read', () {
      final history = ExerciseHistory.fromJson({
        'key': 'squat',
        'kind': 'lifting',
        'last_session': {
          'local_date': 'yesterday',
          'sets': [
            {'set_number': 1, 'load_kg': '100', 'repetitions': 5.0},
            'set',
          ],
        },
        'best_set': {'kind': 'load', 'load_kg': 120, 'repetitions': 3},
        'top_sets': [
          {'load_kg': 100},
        ],
      })!;

      expect(history.kind, isNull);
      expect(history.lastSession!.localDate, isNull);
      expect(history.lastSession!.sets.single.loadKg, isNull);
      expect(history.lastSession!.sets.single.repetitions, 5);
      expect(history.bestSet!.kind, ExerciseHistoryKind.load);
      expect(history.topSets.single.localDate, isNull);
    });

    test('a best set with no readable kind is no best', () {
      final history = ExerciseHistory.fromJson({
        'key': 'squat',
        'best_set': {'load_kg': 120, 'repetitions': 3},
      })!;
      expect(history.bestSet, isNull);

      final withKind = ExerciseHistory.fromJson({
        'key': 'squat',
        'kind': 'load',
        'best_set': {'load_kg': 120, 'repetitions': 3},
      })!;
      expect(withKind.bestSet!.kind, ExerciseHistoryKind.load);
    });
  });
}
