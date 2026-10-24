import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/train/unfinished_workout.dart';
import 'package:tracend/features/train/workout_repository.dart';

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(File('test/contract/fixtures/$name.json').readAsStringSync())
      as Map,
);

void main() {
  group('get_my_unfinished_workout_v1 1.0', () {
    test('carries its schema version and complete key lists', () {
      final json = _fixture('unfinished_workout_v1_0');
      expect(json.keys.toSet(), {'schema_version', 'workout'});
      expect(json['schema_version'], '1.0');
      expect((json['workout'] as Map).keys.toSet(), {
        'session_id',
        'planned_workout_id',
        'name',
        'local_date',
        'started_at',
        'logged_sets',
        'total_sets',
        'first_set_at',
        'last_set_at',
      });
    });

    test('the app reads the workout it offers', () {
      final workout = UnfinishedWorkout.fromJson(
        _fixture('unfinished_workout_v1_0')['workout'],
      )!;
      expect(workout.sessionId, 'd1450000-0000-4000-8000-000000000001');
      expect(workout.plannedWorkoutId, 'd1430000-0000-4000-8000-000000000001');
      expect(workout.name, 'Legs B');
      expect(workout.localDate, DateTime(2026, 10, 23));
      expect(workout.loggedSets, 23);
      expect(workout.totalSets, 25);
      expect(workout.unloggedSets, 2);
    });

    test('says nothing offered with a null workout', () {
      final json = _fixture('unfinished_workout_v1_0_none');
      expect(json.keys.toSet(), {'schema_version', 'workout'});
      expect(json['schema_version'], '1.0');
      expect(UnfinishedWorkout.fromJson(json['workout']), isNull);
    });
  });

  group('resolve_unfinished_workout_v1 1.0', () {
    test('a save carries the completion and the answer', () {
      final json = _fixture('resolve_unfinished_workout_v1_0_saved');
      expect(json.keys.toSet(), {
        'schema_version',
        'session_id',
        'completed_sets',
        'total_sets',
        'logging_completeness',
        'replayed',
        'state',
        'resolution',
      });
      expect(json['schema_version'], '1.0');
      expect(json['state'], 'completed');
      expect(json['resolution'], 'saved');
      expect(WorkoutCompletion.fromJson(json).completedSets, 23);
    });

    test('a discard carries the answer and stays abandoned', () {
      final json = _fixture('resolve_unfinished_workout_v1_0_discarded');
      expect(json.keys.toSet(), {
        'schema_version',
        'session_id',
        'state',
        'resolution',
        'replayed',
      });
      expect(json['schema_version'], '1.0');
      expect(json['state'], 'abandoned');
      expect(json['resolution'], 'discarded');
    });
  });
}
