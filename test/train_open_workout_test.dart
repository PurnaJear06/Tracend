import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/open_workout.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

import 'train_fixtures.dart';

/// A draft as the logger saves it for [workout], logged under [day], with
/// [done] sets of its first exercise done, the last at [lastDone].
String _draft(
  PlannedWorkout workout,
  DateTime day, {
  int done = 2,
  DateTime? lastDone,
}) {
  final last = lastDone ?? DateTime(2026, 10, 2, 8);
  return jsonEncode({
    'workout_id': workout.id,
    'session_id': 'session-${workout.id}',
    'idempotency_key': 'key-${workout.id}',
    'revision': 5,
    'workout_name': workout.name,
    'session_local_date':
        '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}',
    'actual_started_at': last
        .subtract(const Duration(minutes: 20))
        .toUtc()
        .toIso8601String(),
    'exercises': [
      {
        'order': 1,
        'sets': [
          for (var i = 0; i < 3; i++)
            {
              'number': i + 1,
              'completed': i < done,
              'load_kg': i < done ? '60' : '',
              'repetitions': i < done ? '8' : '',
              if (i < done)
                'completed_at': last
                    .subtract(Duration(minutes: done - 1 - i))
                    .toUtc()
                    .toIso8601String(),
            },
        ],
      },
    ],
  });
}

/// Train's fixture with a draft per workout, as the phone keeps them, and the
/// open-workout lookup over them.
class _Drafts extends TrainFixtureRepository implements OpenWorkoutRepository {
  _Drafts({super.hub});

  final drafts = <String, String>{};

  @override
  Future<String?> loadDraft(String workoutId) async => drafts[workoutId];

  @override
  Future<void> saveDraft(String workoutId, String json) async =>
      drafts[workoutId] = json;

  @override
  Future<void> clearDraft(String workoutId) async => drafts.remove(workoutId);

  @override
  Future<List<OpenWorkout>> loadOpenWorkouts() async =>
      openWorkoutsFrom(Map.of(drafts));
}

/// The plan's week with nothing done yet: Tuesday and Wednesday are missed.
TrainingHubData _week() => trainHub(completed: const {}, sessions: const []);

final _tuesday = DateTime(2026, 9, 29);
final _wednesday = DateTime(2026, 9, 30);

void main() {
  late _Drafts repository;

  setUp(() => repository = _Drafts(hub: _week()));

  Future<void> pumpTrain(
    WidgetTester tester, {
    ValueNotifier<int>? workoutRequests,
    ResumeRequests? resumeRequests,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TracendMotionScope(
        level: TracendMotionLevel.static,
        child: MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: TrainScreen(
              repository: repository,
              brief: TrainBriefRepository(computed: trainComputed()),
              coach: const TrainCoachRepository(),
              now: trainNow,
              workoutRequests: workoutRequests,
              resumeRequests: resumeRequests,
            ),
          ),
        ),
      ),
    );
    // A workout that opens on its own keeps its clock ticking, so the screen
    // never settles; the logger helper below pumps it up instead.
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> tapDay(WidgetTester tester, DateTime day) async {
    final iso =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    await tester.tap(find.byKey(ValueKey('day-box-$iso')));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  /// The logger that opened, once its route has come up.
  Future<ActiveWorkoutScreen?> logger(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 600));
    final found = find.byType(ActiveWorkoutScreen);
    if (found.evaluate().isEmpty) return null;
    return tester.widget<ActiveWorkoutScreen>(found);
  }

  group('the Resume card', () {
    testWidgets('names the open workout and its day, and opens it there', (
      tester,
    ) async {
      repository.drafts[lowerA.id] = _draft(lowerA, _wednesday);
      await pumpTrain(tester);

      expect(find.text('Workout in progress'), findsOneWidget);
      expect(
        find.text('Lower body A · Wed 30 Sep · 2 sets logged'),
        findsOneWidget,
      );

      await tapText(tester, find.widgetWithText(FilledButton, 'Resume').first);
      final screen = await logger(tester);
      expect(screen?.workout.id, lowerA.id);
      expect(screen?.sessionDate, _wednesday);
    });

    testWidgets('shows the newest and lists the others, each resumable', (
      tester,
    ) async {
      repository.drafts
        ..[lowerA.id] = _draft(
          lowerA,
          _wednesday,
          lastDone: DateTime(2026, 10, 2, 7),
        )
        ..[upperB.id] = _draft(
          upperB,
          _tuesday,
          done: 1,
          lastDone: DateTime(2026, 10, 2, 8),
        );
      await pumpTrain(tester);

      expect(
        find.text('Upper body B · Tue 29 Sep · 1 set logged'),
        findsOneWidget,
      );
      expect(find.text('Also in progress'), findsOneWidget);
      expect(
        find.text('Lower body A · Wed 30 Sep · 2 sets logged'),
        findsOneWidget,
      );

      await tapText(
        tester,
        find.byKey(ValueKey('open-workout-resume-${lowerA.id}')),
      );
      final screen = await logger(tester);
      expect(screen?.workout.id, lowerA.id);
      expect(screen?.sessionDate, _wednesday);
    });

    testWidgets('a workout with no set done is not offered', (tester) async {
      repository.drafts[lowerA.id] = _draft(lowerA, _wednesday, done: 0);
      await pumpTrain(tester);

      expect(find.text('Workout in progress'), findsNothing);
    });
  });

  group('a day\'s status', () {
    testWidgets('a past day with an open workout is in progress and resumes', (
      tester,
    ) async {
      repository.drafts[lowerA.id] = _draft(lowerA, _wednesday);
      await pumpTrain(tester);
      await tapDay(tester, _wednesday);

      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Wednesday, missed'), findsNothing);
      expect(find.textContaining('I did it'), findsNothing);
      // The card's Resume and the day's own.
      expect(find.widgetWithText(FilledButton, 'Resume'), findsNWidgets(2));

      await tapText(tester, find.widgetWithText(FilledButton, 'Resume').last);
      final screen = await logger(tester);
      expect(screen?.workout.id, lowerA.id);
      expect(screen?.sessionDate, _wednesday);
    });

    testWidgets('a missed day offers Do it today, never Start', (tester) async {
      await pumpTrain(tester);
      await tapDay(tester, _tuesday);

      expect(find.text('Tuesday, missed'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Do it today'), findsOneWidget);

      await tapText(tester, find.widgetWithText(FilledButton, 'Do it today'));
      final screen = await logger(tester);
      expect(screen?.workout.id, upperB.id);
      expect(screen?.sessionDate, trainToday);
    });

    testWidgets('a missed day\'s overview offers Do it today', (tester) async {
      await pumpTrain(tester);
      await tapDay(tester, _tuesday);
      await tester.tap(find.text('2 exercises, about 46 min'));
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutOverviewBody), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start workout'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Do it today'), findsWidgets);
    });

    testWidgets('"I did it" asks first, then logs the workout for its day', (
      tester,
    ) async {
      await pumpTrain(tester);
      await tapDay(tester, _tuesday);
      final logIt = find.widgetWithText(
        TextButton,
        'I did it, log it for Tue 29 Sep',
      );
      expect(logIt, findsOneWidget);

      await tapText(tester, logIt);
      await tester.pumpAndSettle();
      expect(
        find.text('Log Upper body B for Tuesday 29 September?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      expect(await logger(tester), isNull);
      await tester.pumpAndSettle();

      await tapText(tester, logIt);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log for Tuesday'));
      final screen = await logger(tester);
      expect(screen?.workout.id, upperB.id);
      expect(screen?.sessionDate, _tuesday);
    });

    testWidgets('today keeps its Start, with no question when nothing is '
        'open', (tester) async {
      await pumpTrain(tester);

      expect(find.text('Today'), findsOneWidget);
      await tapText(tester, find.widgetWithText(FilledButton, 'Start workout'));
      final screen = await logger(tester);
      expect(screen?.workout.id, upperA.id);
      expect(screen?.sessionDate, trainToday);
      expect(find.byType(CupertinoActionSheet), findsNothing);
    });
  });

  group('one workout at a time', () {
    setUp(() => repository.drafts[lowerA.id] = _draft(lowerA, _wednesday));

    Future<void> startToday(WidgetTester tester) async {
      await pumpTrain(tester);
      await tapText(tester, find.widgetWithText(FilledButton, 'Start workout'));
      await tester.pumpAndSettle();
    }

    testWidgets('starting another workout asks first; Resume it opens the '
        'open one on its day', (tester) async {
      await startToday(tester);

      expect(
        find.text('Lower body A (Wed) has 2 sets logged.'),
        findsOneWidget,
      );
      expect(find.text('Start this one anyway'), findsOneWidget);
      await tester.tap(find.text('Resume it'));
      final screen = await logger(tester);
      expect(screen?.workout.id, lowerA.id);
      expect(screen?.sessionDate, _wednesday);
    });

    testWidgets('Start this one anyway keeps the other draft as it is', (
      tester,
    ) async {
      final kept = repository.drafts[lowerA.id];
      await startToday(tester);

      await tester.tap(find.text('Start this one anyway'));
      final screen = await logger(tester);
      expect(screen?.workout.id, upperA.id);
      expect(screen?.sessionDate, trainToday);
      expect(repository.drafts[lowerA.id], kept);
    });

    testWidgets('Cancel starts nothing', (tester) async {
      await startToday(tester);

      await tester.tap(find.text('Cancel'));
      expect(await logger(tester), isNull);
    });

    testWidgets('the same workout open on another day can only be resumed', (
      tester,
    ) async {
      repository.drafts
        ..clear()
        ..[upperA.id] = _draft(upperA, DateTime(2026, 9, 25));
      await startToday(tester);

      expect(
        find.text('Upper body A (Fri) has 2 sets logged.'),
        findsOneWidget,
      );
      expect(find.text('Start this one anyway'), findsNothing);
      await tester.tap(find.text('Resume it'));
      final screen = await logger(tester);
      expect(screen?.sessionDate, DateTime(2026, 9, 25));
    });
  });

  group('asked to reopen', () {
    testWidgets('the Live Activity opens the newest open workout, whatever '
        'its day', (tester) async {
      repository.drafts[lowerA.id] = _draft(lowerA, _wednesday);
      final requests = ValueNotifier<int>(1);
      addTearDown(requests.dispose);

      await pumpTrain(tester, workoutRequests: requests, settle: false);
      final screen = await logger(tester);
      expect(screen?.workout.id, lowerA.id);
      expect(screen?.sessionDate, _wednesday);
    });

    testWidgets('Today\'s Resume card opens the workout it named', (
      tester,
    ) async {
      repository.drafts
        ..[lowerA.id] = _draft(
          lowerA,
          _wednesday,
          lastDone: DateTime(2026, 10, 2, 8),
        )
        ..[upperB.id] = _draft(
          upperB,
          _tuesday,
          lastDone: DateTime(2026, 10, 2, 7),
        );
      final requests = ResumeRequests();
      addTearDown(requests.dispose);
      requests.request(
        OpenWorkout.fromDraft(upperB.id, repository.drafts[upperB.id]!)!,
      );

      await pumpTrain(tester, resumeRequests: requests, settle: false);
      final screen = await logger(tester);
      expect(screen?.workout.id, upperB.id);
      expect(screen?.sessionDate, _tuesday);
    });
  });
}
