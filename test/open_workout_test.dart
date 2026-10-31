import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/train/open_workout.dart';
import 'package:tracend/features/train/workout_logic.dart';

/// A draft as the logger saves it: [done] sets marked done, the last one at
/// [lastDone], logged under [date] when it is given.
String _draft({
  int done = 2,
  String? date,
  String? name,
  DateTime? startedAt,
  DateTime? lastDone,
  String sessionId = 'session-1',
}) => jsonEncode({
  'workout_id': 'ignored',
  'session_id': sessionId,
  'revision': 4,
  'actual_started_at': (startedAt ?? DateTime.utc(2026, 10, 31, 11, 30))
      .toIso8601String(),
  'session_local_date': ?date,
  'workout_name': ?name,
  'exercises': [
    {
      'order': 1,
      'sets': [
        for (var i = 0; i < 3; i++)
          {
            'number': i + 1,
            'completed': i < done,
            if (i < done && lastDone != null)
              'completed_at': lastDone
                  .subtract(Duration(minutes: done - 1 - i))
                  .toIso8601String(),
          },
      ],
    },
  ],
});

void main() {
  group('reading one draft', () {
    test('a draft with done sets names its workout, day and sets', () {
      final open = OpenWorkout.fromDraft(
        'legs-b',
        _draft(date: '2026-10-30', name: 'Legs B'),
      )!;

      expect(open.workoutId, 'legs-b');
      expect(open.name, 'Legs B');
      expect(open.date, DateTime(2026, 10, 30));
      expect(open.doneSets, 2);
      expect(open.sessionId, 'session-1');
      expect(open.isOn('legs-b', DateTime(2026, 10, 30, 18)), isTrue);
      expect(open.isOn('legs-b', DateTime(2026, 10, 31)), isFalse);
      expect(open.isOn('shoulder', DateTime(2026, 10, 30)), isFalse);
    });

    test('a draft saved before the date was kept is on the day it began', () {
      final started = DateTime(2026, 10, 29, 18);
      final open = OpenWorkout.fromDraft('w', _draft(startedAt: started))!;

      expect(open.date, DateTime(2026, 10, 29));
      expect(open.name, isEmpty);
      expect(open.nameOr('Upper body A'), 'Upper body A');
      expect(open.nameOr(null), 'Your workout');
    });

    test(
      'a draft with no done set, or one that cannot be read, is not open',
      () {
        expect(OpenWorkout.fromDraft('w', _draft(done: 0)), isNull);
        expect(OpenWorkout.fromDraft('w', 'not json'), isNull);
        expect(OpenWorkout.fromDraft('w', '[]'), isNull);
      },
    );

    test('the stored session date is read as a plain day', () {
      expect(
        draftSessionDate({'session_local_date': '2026-10-30'}),
        DateTime(2026, 10, 30),
      );
      expect(draftSessionDate({'session_local_date': 'Friday'}), isNull);
      expect(draftSessionDate(const {}), isNull);
    });
  });

  group('the lookup', () {
    test('lists open workouts newest first, by the last set done', () {
      final open = openWorkoutsFrom({
        'legs-b': _draft(
          date: '2026-10-30',
          lastDone: DateTime.utc(2026, 10, 31, 11, 33),
        ),
        'shoulder': _draft(
          date: '2026-10-31',
          lastDone: DateTime.utc(2026, 10, 31, 11, 40),
        ),
        'empty': _draft(done: 0),
      });

      expect(open.map((o) => o.workoutId), ['shoulder', 'legs-b']);
    });

    test('a workout with a finish waiting is not open', () {
      final open = openWorkoutsFrom(
        {
          'legs-b': _draft(date: '2026-10-30'),
          'done': _draft(date: '2026-10-29'),
        },
        finished: {'done'},
      );

      expect(open.map((o) => o.workoutId), ['legs-b']);
    });

    test('the same drafts always give the same order', () {
      final drafts = {
        'b': _draft(date: '2026-10-30'),
        'a': _draft(date: '2026-10-30'),
        'c': _draft(date: '2026-10-31'),
      };
      final first = openWorkoutsFrom(drafts).map((o) => o.workoutId).toList();
      final reversed = openWorkoutsFrom(
        Map.fromEntries(drafts.entries.toList().reversed),
      ).map((o) => o.workoutId).toList();

      expect(first, ['c', 'a', 'b']);
      expect(reversed, first);
    });
  });

  test('a resume request is taken once', () {
    final requests = ResumeRequests();
    addTearDown(requests.dispose);
    var told = 0;
    requests.addListener(() => told++);
    final open = OpenWorkout.fromDraft('w', _draft(date: '2026-10-30'))!;

    requests.request(open);

    expect(told, 1);
    expect(requests.take(), same(open));
    expect(requests.take(), isNull);
  });

  group('left on an earlier day', () {
    final now = DateTime(2026, 10, 31, 21);

    test('a stored day before today, begun over three hours ago, is left '
        'over: the server closes it by its own date', () {
      expect(
        workoutLeftOnEarlierDay(
          startedAt: DateTime(2026, 10, 31, 17),
          loggedOn: DateTime(2026, 10, 30),
          now: now,
          sessionDate: now,
          maxSeconds: maxWorkoutSeconds,
        ),
        isTrue,
      );
    });

    test('the same draft opened for its own day is not left over', () {
      expect(
        workoutLeftOnEarlierDay(
          startedAt: DateTime(2026, 10, 31, 17),
          loggedOn: DateTime(2026, 10, 30),
          now: now,
          sessionDate: DateTime(2026, 10, 30),
          maxSeconds: maxWorkoutSeconds,
        ),
        isFalse,
      );
    });

    test('begun within three hours, it is not left over yet', () {
      expect(
        workoutLeftOnEarlierDay(
          startedAt: DateTime(2026, 10, 31, 19),
          loggedOn: DateTime(2026, 10, 30),
          now: now,
          sessionDate: now,
          maxSeconds: maxWorkoutSeconds,
        ),
        isFalse,
      );
    });

    test('without a stored day the day it began counts, as before', () {
      expect(
        workoutLeftOnEarlierDay(
          startedAt: DateTime(2026, 10, 31, 17),
          now: now,
          sessionDate: now,
          maxSeconds: maxWorkoutSeconds,
        ),
        isFalse,
      );
    });
  });
}
