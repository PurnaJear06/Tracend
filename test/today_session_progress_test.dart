import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_session_progress.dart';

const _workout = {
  'name': 'Push day',
  'exercises': [
    {'order': 1, 'name': 'Bench press', 'set_count': 4},
    {'order': 2, 'name': 'Overhead press', 'set_count': 20},
    {'order': 3, 'set_count': 2},
  ],
};

DailyBrief _brief({TodaySession? session, bool workout = true}) => DailyBrief(
  localDate: '2026-10-18',
  workout: workout ? _workout : null,
  todaySession: session,
);

void main() {
  test('no workout is a rest day with nothing to count', () {
    final progress = TodaySessionProgress.of(_brief(workout: false));

    expect(progress.state, 'rest');
    expect(progress.exercises, isEmpty);
    expect((progress.total, progress.logged), (0, 0));
  });

  test('a workout nobody started is planned, with sets capped at 12', () {
    final progress = TodaySessionProgress.of(_brief());

    expect(progress.state, 'planned');
    expect([for (final e in progress.exercises) e.sets], [4, 12, 2]);
    expect(progress.exercises.last.name, 'Exercise');
    expect((progress.total, progress.logged), (18, 0));
  });

  test('logged sets never pass what an exercise prescribes', () {
    final progress = TodaySessionProgress.of(
      _brief(
        session: const TodaySession(
          state: 'in_progress',
          completedSets: {1: 3, 2: 99, 7: 5},
        ),
      ),
    );

    expect(progress.state, 'in_progress');
    expect(progress.logged, 3 + 12);
    expect(progress.doneFor(progress.exercises[1]), 12);
    expect(progress.doneFor(progress.exercises[2]), 0);
  });

  test('a completed session says so', () {
    final progress = TodaySessionProgress.of(
      _brief(
        session: const TodaySession(state: 'completed', completedSets: {1: 4}),
      ),
    );

    expect(progress.state, 'completed');
  });
}
