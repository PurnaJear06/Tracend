import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/train/workout_draft.dart';
import 'package:tracend/features/train/workout_repository.dart';

Map<String, dynamic> _fixture() =>
    jsonDecode(
          File(
            'test/contract/fixtures/workout_session_v1_1.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Map<String, dynamic> _exercise(Map<String, dynamic> session) =>
    Map<String, dynamic>.from((session['exercises'] as List).single as Map);

List<Map<String, dynamic>> _sets(Map<String, dynamic> session) => [
  for (final set in _exercise(session)['sets'] as List)
    Map<String, dynamic>.from(set as Map),
];

const _bench = PlannedExercise(
  order: 1,
  name: 'Barbell bench press',
  setCount: 3,
  repMin: 6,
  repMax: 8,
  targetRpe: 8,
  restSeconds: 120,
  exerciseSlug: 'barbell-bench-press',
);

void main() {
  group('get_my_workout_session 1.1', () {
    test('carries its schema version and complete key lists', () {
      final session = _fixture();
      expect(session['schema_version'], '1.1');
      expect(session.keys.toSet(), {
        'schema_version',
        'session_id',
        'state',
        'revision',
        'idempotency_key',
        'local_date',
        'actual_started_at',
        'actual_ended_at',
        'duration_seconds',
        'notes',
        'completion_source',
        'session_effort',
        'session_effort_source',
        'exercises',
      });
      expect(_exercise(session).keys.toSet(), {
        'performance_id',
        'order',
        'status',
        'performance_kind',
        'performed_name',
        'exercise_slug',
        'substitution_reason',
        'pain_flag',
        'note',
        'rest_seconds',
        'sets',
      });
      for (final set in _sets(session)) {
        expect(set.keys.toSet(), {
          'number',
          'repetitions',
          'load_kg',
          'rpe',
          'completed',
          'started_at',
          'completed_at',
          'rest_before_seconds',
          'rir',
          'timing_source',
        });
      }
    });

    test('the logging screen reads each set\'s times and reps left', () {
      final draft = ExerciseDraft(_bench)..restore(_exercise(_fixture()));
      final second = draft.sets[1];

      expect(second.completed, isTrue);
      expect(second.load, '72.5');
      expect(second.reps, '7');
      expect(second.rpe, '9');
      expect(second.rir, 1);
      expect(second.startedAt, DateTime.utc(2026, 10, 15, 3, 33, 41, 900));
      expect(second.completedAt, DateTime.utc(2026, 10, 15, 3, 34, 20, 100));
      expect(second.restBeforeSeconds, 120);
      expect(second.timingSource, SetTimingSource.app);
      expect(draft.sets[0].restBeforeSeconds, isNull);

      final open = draft.sets[2];
      expect(open.completed, isFalse);
      expect(open.startedAt, isNull);
      expect(open.rir, isNull);
      expect(open.timingSource, isNull);
    });

    test('a set read back syncs the same values', () {
      final draft = ExerciseDraft(_bench)..restore(_exercise(_fixture()));
      final sent = draft.sets[1].toMap();
      expect(sent['rir'], 1);
      expect(sent['rest_before_seconds'], 120);
      expect(sent['timing_source'], 'app');
      expect(
        DateTime.parse(sent['started_at'] as String),
        DateTime.utc(2026, 10, 15, 3, 33, 41, 900),
      );
    });

    test('a 1.0 session without set timing reads as unknown', () {
      final session = _fixture();
      final exercise = _exercise(session);
      exercise['sets'] = [
        for (final set in _sets(session))
          {
            for (final entry in set.entries)
              if (const {
                'number',
                'repetitions',
                'load_kg',
                'rpe',
                'completed',
              }.contains(entry.key))
                entry.key: entry.value,
          },
      ];
      final draft = ExerciseDraft(_bench)..restore(exercise);
      expect(draft.sets[1].reps, '7');
      expect(draft.sets[1].rpe, '9');
      expect(draft.sets[1].rir, isNull);
      expect(draft.sets[1].startedAt, isNull);
      expect(draft.sets[1].restBeforeSeconds, isNull);
      expect(draft.sets[1].timingSource, isNull);
    });
  });
}
