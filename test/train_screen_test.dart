import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/train/exercise_history.dart';
import 'package:tracend/features/train/muscle_groups.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/train_view_models.dart';
import 'package:tracend/features/train/widgets/exercise_detail_sheet.dart';
import 'package:tracend/features/train/widgets/muscle_map.dart';
import 'package:tracend/features/train/widgets/muscles_sheet.dart';
import 'package:tracend/features/train/widgets/training_load_sheet.dart';
import 'package:tracend/features/train/widgets/workout_hero.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_skeleton.dart';

import 'train_fixtures.dart';
import 'widgets/haptics_recorder.dart';

Future<T> _pumpTrain<T extends WorkoutRepository>(
  WidgetTester tester, {
  required T repository,
  TrainBriefRepository? brief,
  HealthRepository? health,
  VoidCallback? onOpenAccount,
  TracendMotionLevel motion = TracendMotionLevel.static,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    TracendMotionScope(
      level: motion,
      child: MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: TrainScreen(
            repository: repository,
            brief: brief ?? TrainBriefRepository(computed: trainComputed()),
            coach: const TrainCoachRepository(),
            health: health,
            onOpenAccount: onOpenAccount,
            now: trainNow,
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return repository;
}

Future<void> _tapDay(WidgetTester tester, String iso) async {
  await tester.tap(find.byKey(ValueKey('day-box-$iso')));
  await tester.pumpAndSettle();
}

class _HealthStatus implements HealthRepository {
  _HealthStatus(this.state);
  final HealthConnectionState state;

  @override
  Future<HealthSyncStatus> loadStatus() async => HealthSyncStatus(state: state);

  @override
  Future<HealthHistory> loadHistory() => throw UnimplementedError();

  @override
  Future<HealthSyncStatus> connectAndSync() => throw UnimplementedError();

  @override
  Future<HealthSyncStatus> sync() => throw UnimplementedError();
}

class _AttentionRepository extends TrainFixtureRepository
    implements WorkoutRepairRepository, WorkoutReconciliationRepository {
  final repaired = <String>[];
  final responses = <(String, bool)>[];

  @override
  Future<List<WorkoutRepairCandidate>> loadRepairCandidates() async => [
    WorkoutRepairCandidate(
      sessionId: 'session-repair',
      localDate: DateTime(2026, 9, 29),
      workoutName: 'Upper body B',
      recordedDurationSeconds: 600,
      healthkitDurationSeconds: 2760,
      recommendedStartedAt: DateTime(2026, 9, 29, 7),
      recommendedEndedAt: DateTime(2026, 9, 29, 7, 46),
    ),
  ];

  @override
  Future<void> confirmRepair(WorkoutRepairCandidate candidate) async =>
      repaired.add(candidate.sessionId);

  @override
  Future<List<WorkoutReconciliation>> loadReconciliations() async => [
    WorkoutReconciliation(
      id: 'match-1',
      status: 'matched',
      confidence: 0.92,
      durationDifferenceSeconds: 60,
      activityType: 'TRADITIONAL_STRENGTH_TRAINING',
      healthDurationSeconds: 3120,
      workoutName: 'Lower body A',
      localDate: DateTime(2026, 9, 30),
    ),
  ];

  @override
  Future<void> respondToReconciliation(
    String id, {
    required bool accept,
  }) async => responses.add((id, accept));
}

class _PendingRepository extends TrainFixtureRepository {
  final completer = Completer<TrainingHubData>();

  @override
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28}) =>
      completer.future;
}

void main() {
  group('Train header and today', () {
    testWidgets('shows the date, the plan week and the plan sheet', (
      tester,
    ) async {
      await _pumpTrain(tester, repository: TrainFixtureRepository());
      expect(find.text('Friday 2 October'), findsOneWidget);
      await tester.tap(find.text('Week 3 of 6'));
      await tester.pumpAndSettle();
      expect(find.text('Strength foundation'), findsOneWidget);
      expect(find.text('6 weeks, 4 workouts a week'), findsOneWidget);
      expect(find.text('Plan rule'), findsOneWidget);
      expect(
        find.textContaining('You approved this plan on 15 September'),
        findsOneWidget,
      );
    });

    testWidgets('today shows the workout, its muscles and its exercises', (
      tester,
    ) async {
      await _pumpTrain(tester, repository: TrainFixtureRepository());
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Upper body A'), findsOneWidget);
      expect(find.text('6 exercises, about 48 min'), findsOneWidget);
      expect(find.text('Muscles worked'), findsOneWidget);
      for (final muscle in ['Triceps', 'Back', 'Biceps', 'Chest']) {
        expect(find.text(muscle), findsWidgets);
      }
      expect(find.byType(MuscleMap), findsOneWidget);
      expect(find.text('Start workout'), findsOneWidget);
      expect(find.text('Exercises'), findsOneWidget);
      expect(find.text('16 sets'), findsOneWidget);
      expect(find.text('3 × 6 to 8 at 72.5 kg'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('2 of 4  done', findRichText: true), findsOneWidget);
      expect(find.text('About normal for you'), findsOneWidget);
      expect(find.text('2 workouts in 4 weeks'), findsOneWidget);
    });

    testWidgets('the Front and Back control turns the map', (tester) async {
      await _pumpTrain(tester, repository: TrainFixtureRepository());
      expect(
        tester.widget<MuscleMap>(find.byType(MuscleMap)).side,
        BodySide.front,
      );
      await tester.tap(find.text('Back').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MuscleMap>(find.byType(MuscleMap)).side,
        BodySide.back,
      );
    });

    testWidgets(
      'unlinked exercises light no muscles and say when the map comes',
      (tester) async {
        final unlinked = PlannedWorkout(
          id: 'w-plain',
          name: 'Plain day',
          objective: 'No catalog links.',
          estimatedMinutes: 30,
          weekday: 5,
          exercises: const [
            PlannedExercise(
              order: 1,
              name: 'Mystery press',
              setCount: 3,
              repMin: 8,
              repMax: 8,
              targetRpe: 8,
            ),
          ],
        );
        await _pumpTrain(
          tester,
          repository: TrainFixtureRepository(
            hub: trainHub(workouts: [unlinked]),
          ),
        );
        expect(find.text('Plain day'), findsOneWidget);
        expect(find.byType(MuscleMap), findsNothing);
        expect(find.text('Muscles worked'), findsNothing);
        expect(
          find.text('Muscle map appears with your next plan.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Start workout plays the heavy haptic and opens logging', (
      tester,
    ) async {
      final haptics = recordHaptics(tester);
      await _pumpTrain(tester, repository: TrainFixtureRepository());
      await tester.tap(find.text('Start workout'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(haptics, contains('HapticFeedbackType.heavyImpact'));
      final route = ModalRoute.of(
        tester.element(find.byType(TrainScreen, skipOffstage: false)),
      );
      expect(route?.isCurrent, isFalse);
    });
  });

  group('Train day switching', () {
    testWidgets('a done day shows when it was done and View summary', (
      tester,
    ) async {
      final repository = TrainFixtureRepository(
        session: {
          'state': 'completed',
          'local_date': '2026-09-30',
          'duration_seconds': 3120,
          'session_effort': 8,
          'session_effort_source': 'athlete',
          'completion_source': 'manual',
          'exercises': [
            {
              'order': 1,
              'performed_name': 'Back squat',
              'status': 'completed',
              'sets': [
                {
                  'number': 1,
                  'load_kg': 90,
                  'repetitions': 5,
                  'completed': true,
                },
                {
                  'number': 2,
                  'load_kg': 90,
                  'repetitions': 5,
                  'completed': true,
                },
              ],
            },
            {
              'order': 2,
              'performed_name': 'Romanian deadlift',
              'status': 'skipped',
              'sets': <Object>[],
            },
          ],
        },
      );
      await _pumpTrain(tester, repository: repository);
      await _tapDay(tester, '2026-09-30');
      expect(find.text('Done on Wednesday'), findsOneWidget);
      expect(find.text('52 min, 2 exercises'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);
      expect(find.text('Auto-completed from Apple Health'), findsNothing);
      await tester.tap(find.text('View summary'));
      await tester.pumpAndSettle();
      expect(find.text('Done on Wednesday 30 September'), findsOneWidget);
      expect(find.text('52 min'), findsOneWidget);
      expect(find.text('2 of 6'), findsOneWidget);
      expect(find.text('8 of 10'), findsOneWidget);
      expect(find.text('90 kg × 5, 5'), findsOneWidget);
      expect(find.text('Skipped'), findsOneWidget);
      expect(find.text(WorkoutSummaryBody.healthkitNote), findsNothing);
    });

    testWidgets('an Apple Health completion says so only for that source', (
      tester,
    ) async {
      final repository = TrainFixtureRepository(
        session: {
          'state': 'completed',
          'local_date': '2026-09-29',
          'completion_source': 'healthkit',
          'session_effort': 5,
          'session_effort_source': 'healthkit_default',
          'exercises': <Object>[],
        },
      );
      await _pumpTrain(tester, repository: repository);
      await _tapDay(tester, '2026-09-29');
      expect(find.text('Auto-completed from Apple Health'), findsOneWidget);
      await tester.tap(find.text('View summary'));
      await tester.pumpAndSettle();
      expect(find.text(WorkoutSummaryBody.healthkitNote), findsOneWidget);
      expect(find.text('Not rated'), findsOneWidget);
    });

    testWidgets('a past day with nothing logged can still be logged', (
      tester,
    ) async {
      await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(
          hub: trainHub(completed: {DateTime(2026, 9, 30)}),
        ),
      );
      await _tapDay(tester, '2026-09-29');
      expect(find.text('Tuesday, not logged'), findsOneWidget);
      expect(find.text('Log this workout'), findsOneWidget);
    });

    testWidgets('a coming rest day names the next workout and jumps to it', (
      tester,
    ) async {
      await _pumpTrain(tester, repository: TrainFixtureRepository());
      await _tapDay(tester, '2026-10-03');
      expect(find.text('Rest day'), findsOneWidget);
      expect(
        find.textContaining('Your next workout is Lower body B on Sunday'),
        findsOneWidget,
      );
      await tester.tap(find.text('See Sunday’s workout'));
      await tester.pumpAndSettle();
      expect(find.text('Lower body B'), findsOneWidget);
      expect(find.text('Sunday'), findsOneWidget);
    });

    testWidgets('a past rest day reads as rest without a jump', (tester) async {
      await _pumpTrain(tester, repository: TrainFixtureRepository());
      await _tapDay(tester, '2026-10-01');
      expect(
        find.text('You took the day off. Recovery is part of the plan.'),
        findsOneWidget,
      );
      expect(find.textContaining('workout', findRichText: true), findsWidgets);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('a day change slides at full motion', (tester) async {
      await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(),
        motion: TracendMotionLevel.full,
        settle: false,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('day-box-2026-09-30')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        find.ancestor(
          of: find.text('Lower body A'),
          matching: find.byType(SlideTransition),
        ),
        findsWidgets,
      );
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Reduce Motion crossfades the day without a slide', (
      tester,
    ) async {
      await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(),
        motion: TracendMotionLevel.reduced,
        settle: false,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('day-box-2026-09-30')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        find.ancestor(
          of: find.text('Lower body A'),
          matching: find.byType(SlideTransition),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.text('Lower body A'),
          matching: find.byType(FadeTransition),
        ),
        findsWidgets,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Lower body A'), findsOneWidget);
    });

    testWidgets('a swipe pages back a week and This week returns', (
      tester,
    ) async {
      await _pumpTrain(tester, repository: TrainFixtureRepository());
      await tester.fling(
        find.byKey(const ValueKey('day-box-2026-10-01')),
        const Offset(300, 0),
        1500,
      );
      await tester.pumpAndSettle();
      expect(find.text('Week of 21 September'), findsOneWidget);
      expect(find.byKey(const ValueKey('day-box-2026-09-25')), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'This week'));
      await tester.pumpAndSettle();
      expect(find.text('Week of 21 September'), findsNothing);
      expect(find.text('Upper body A'), findsOneWidget);
    });
  });

  group('Readiness line', () {
    testWidgets('one sentence, today’s verdict, and plain words in the sheet', (
      tester,
    ) async {
      await _pumpTrain(tester, repository: TrainFixtureRepository());
      expect(find.text('Recovery is excellent.'), findsOneWidget);
      expect(find.text('Today: Train as planned.'), findsOneWidget);
      await tester.tap(find.text('Recovery is excellent.'));
      await tester.pumpAndSettle();
      expect(find.text('Recovery today'), findsOneWidget);
      expect(find.text('7 h 42 min'), findsOneWidget);
      expect(find.text('More than usual'), findsOneWidget);
      expect(find.text('58 ms'), findsOneWidget);
      expect(find.text('Normal for you, usually 55 ms'), findsOneWidget);
      expect(find.text('54 bpm'), findsOneWidget);
      expect(find.textContaining('z-score'), findsNothing);
      expect(find.textContaining('σ'), findsNothing);
    });

    testWidgets('without Apple Health it asks to connect and opens Account', (
      tester,
    ) async {
      var opened = 0;
      await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(),
        brief: TrainBriefRepository(health: false),
        health: _HealthStatus(HealthConnectionState.manualOnly),
        onOpenAccount: () => opened++,
      );
      expect(find.text('Connect Apple Health to see recovery'), findsOneWidget);
      await tester.tap(find.text('Connect Apple Health to see recovery'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Open Account from the Today tab'), findsOne);
      await tester.tap(find.text('Open Account'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('a connected athlete without a score builds a baseline', (
      tester,
    ) async {
      await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(),
        brief: TrainBriefRepository(computed: trainComputed(recovery: null)),
      );
      expect(find.text('Building your baseline.'), findsOneWidget);
    });

    testWidgets('a failed brief says so with the beta diagnostic', (
      tester,
    ) async {
      await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(),
        brief: TrainBriefRepository(error: StateError('brief offline')),
      );
      expect(
        find.text('Recovery could not load. Pull down to try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('brief offline'), findsOneWidget);
    });
  });

  group('Training load sheet', () {
    Future<void> openLoad(WidgetTester tester) async {
      await tester.tap(find.text('Training load'));
      await tester.pumpAndSettle();
    }

    testWidgets('a reading leads with the verdict and places the marker', (
      tester,
    ) async {
      await _pumpTrain(tester, repository: TrainFixtureRepository());
      await openLoad(tester);
      expect(find.text('About normal for you'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('load-scale-marker')), findsOneWidget);
      expect(find.text('Easy'), findsOneWidget);
      expect(find.text('Calibrating'), findsNothing);
      expect(find.text('Wednesday 30: 52 min, hard'), findsOneWidget);
      expect(find.text('Your hard and easy days are well mixed.'), findsOne);
      expect(find.textContaining('1.07'), findsNothing);
      await tester.tap(find.text('How this is calculated'));
      await tester.pumpAndSettle();
      expect(find.textContaining('is 1.07. From 0.8 to 1.3'), findsOneWidget);
    });

    testWidgets('a tapped bar names its day', (tester) async {
      await _pumpTrain(tester, repository: TrainFixtureRepository());
      await openLoad(tester);
      final bars = find.descendant(
        of: find.byType(LoadDayChart),
        matching: find.byType(Pressable),
      );
      await tester.tap(bars.first);
      await tester.pumpAndSettle();
      expect(find.text('Saturday 26: 48 min, easy'), findsOneWidget);
      await tester.tap(bars.last);
      await tester.pumpAndSettle();
      expect(find.text('Today: not trained yet'), findsOneWidget);
    });

    testWidgets('calibrating days are hatched and explained', (tester) async {
      await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(hub: trainHub(calibrating: true)),
      );
      expect(find.text('About normal, calibrating'), findsOneWidget);
      await openLoad(tester);
      expect(find.text(TrainingLoadSheetModel.calibratingNote), findsOneWidget);
      expect(find.text('Calibrating'), findsOneWidget);
      expect(
        find.text('Saturday 26: 48 min, effort not reported, calibrating'),
        findsNothing,
      );
    });

    testWidgets('a brand-new athlete sees the reading build as they train', (
      tester,
    ) async {
      final hub = TrainingHubData(
        planTitle: 'Strength foundation',
        localToday: trainToday,
        workouts: [upperA],
        recentSessions: const [],
        completedSessions: 0,
        plannedSessions: 4,
        progression: const [],
        dailyLoad: [
          for (var back = 27; back >= 0; back--)
            DailyLoadDay(
              date: trainToday.subtract(Duration(days: back)),
              recorded: false,
              strain: 0,
              minutes: 0,
              sessions: 0,
              effortReported: false,
              level: DayLoadLevel.rest,
            ),
        ],
      );
      await _pumpTrain(tester, repository: TrainFixtureRepository(hub: hub));
      expect(find.text('Builds as you train'), findsOneWidget);
      expect(find.text('History'), findsNothing);
      await openLoad(tester);
      expect(find.text('Your load reading builds as you train'), findsOne);
      expect(find.byKey(const ValueKey('load-scale-marker')), findsNothing);
      expect(find.text('Today: not trained yet'), findsOneWidget);
    });
  });

  group('Muscles sheet', () {
    testWidgets('rows and muscles select each other', (tester) async {
      await _pumpTrain(tester, repository: TrainFixtureRepository());
      await tester.tap(find.byType(MuscleMap));
      await tester.pumpAndSettle();
      expect(find.byType(MusclesSheetBody), findsOneWidget);
      expect(find.text('8 sets'), findsOneWidget);
      expect(
        find.textContaining('5 of 6 exercises are linked'),
        findsOneWidget,
      );
      MuscleMapPair pair() => tester.widget(find.byType(MuscleMapPair));
      expect(pair().selected, isNull);
      // A selected muscle pulses, so time is pumped rather than settled.
      await tester.tap(find.text('Bench press').last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(pair().selected, MuscleGroup.chest);
      pair().onMuscleTap!(MuscleGroup.back);
      await tester.pump(const Duration(milliseconds: 400));
      expect(pair().selected, MuscleGroup.back);
      pair().onMuscleTap!(MuscleGroup.back);
      await tester.pump(const Duration(milliseconds: 400));
      expect(pair().selected, isNull);
    });
  });

  group('Exercise sheet', () {
    Future<void> openBench(WidgetTester tester) async {
      await tester.tap(find.text('Bench press'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows today, last time, your best, the chart and the tip', (
      tester,
    ) async {
      final repository = await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(),
      );
      await openBench(tester);
      expect(repository.historyRequests.last, ['bench-press']);
      expect(find.text('Upper body A, exercise 1 of 6'), findsOneWidget);
      expect(find.text('72.5 kg'), findsOneWidget);
      expect(find.text('3 × 6–8'), findsOneWidget);
      expect(find.text('Last time'), findsOneWidget);
      expect(find.text('70 kg × 8, 8, 7'), findsOneWidget);
      expect(find.text('Your best'), findsOneWidget);
      expect(find.text('72.5 kg × 6'), findsOneWidget);
      expect(find.byType(TopSetChart), findsOneWidget);
      expect(find.text('From your plan'), findsOneWidget);
      expect(
        find.text('If all three sets reach 8 reps, add 2.5 kg next time.'),
        findsOneWidget,
      );
    });

    testWidgets('a first-ever exercise says so and shows the plan rule', (
      tester,
    ) async {
      await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(
          history: const ExerciseHistoryResult(
            exercises: {'barbell-row': ExerciseHistory(key: 'barbell-row')},
          ),
        ),
      );
      await tester.tap(find.text('Barbell row'));
      await tester.pumpAndSettle();
      expect(find.text(ExerciseDetailBody.firstTime), findsOneWidget);
      expect(find.text('Last time'), findsNothing);
      expect(find.text('Plan rule'), findsOneWidget);
    });

    testWidgets('offline without a saved copy hides history', (tester) async {
      await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(
          history: const ExerciseHistoryResult(exercises: {}, fromCache: true),
        ),
      );
      await openBench(tester);
      expect(find.text('Last time loads when you’re online.'), findsOneWidget);
      expect(find.text(ExerciseDetailBody.firstTime), findsNothing);
    });

    testWidgets('a saved copy shows offline with a note', (tester) async {
      await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(
          history: benchHistory(fromCache: true),
        ),
      );
      await openBench(tester);
      expect(find.text('70 kg × 8, 8, 7'), findsOneWidget);
      expect(
        find.text('Saved on this phone. It updates when you’re online.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed history request shows the beta diagnostic', (
      tester,
    ) async {
      await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(
          historyError: StateError('history 500'),
        ),
      );
      await openBench(tester);
      expect(
        find.text('Your history for this exercise could not load.'),
        findsOneWidget,
      );
      expect(find.textContaining('history 500'), findsOneWidget);
    });

    test('one logged session is not enough for a chart', () {
      const chart = TopSetChart(
        topSets: [ExerciseTopSet(loadKg: 70, repetitions: 8)],
        kind: ExerciseHistoryKind.load,
      );
      expect(chart.points, isEmpty);
    });
  });

  group('Workout overview', () {
    testWidgets('the hero opens the overview with Start workout', (
      tester,
    ) async {
      await _pumpTrain(tester, repository: TrainFixtureRepository());
      await tester.tap(find.text('6 exercises, about 48 min'));
      await tester.pumpAndSettle();
      expect(find.text('Warm-up'), findsOneWidget);
      expect(find.text('Cooldown and cardio'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start workout'), findsWidgets);
      expect(find.text('Begin first exercise'), findsNothing);
    });

    testWidgets('a done day overview offers View summary, never Start', (
      tester,
    ) async {
      await _pumpTrain(tester, repository: TrainFixtureRepository());
      await _tapDay(tester, '2026-09-30');
      await tester.tap(find.text('52 min, 2 exercises'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, 'View summary'), findsWidgets);
      expect(find.text('Start workout'), findsNothing);
    });

    testWidgets('the pushed page shows View summary for a finished day', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: WorkoutDetailScreen(
            repository: TrainFixtureRepository(
              session: const {
                'state': 'completed',
                'local_date': '2026-10-02',
                'exercises': <Object>[],
              },
            ),
            workout: upperA,
            sessionDate: trainToday,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('View summary'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);
      expect(find.text('Begin first exercise'), findsNothing);
    });

    testWidgets('the pushed page starts an unfinished workout', (tester) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: WorkoutDetailScreen(
            repository: TrainFixtureRepository(),
            workout: upperA,
            sessionDate: trainToday,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start workout'), findsOneWidget);
    });
  });

  group('History', () {
    testWidgets('one row opens a sheet with friendly dates', (tester) async {
      await _pumpTrain(tester, repository: TrainFixtureRepository());
      await tester.tap(find.text('2 workouts in 4 weeks'));
      await tester.pumpAndSettle();
      expect(find.text('Wed 30 Sep, 52 min'), findsOneWidget);
      expect(
        find.text('Tue 29 Sep, 46 min, from Apple Health'),
        findsOneWidget,
      );
    });
  });

  group('Apple Health cards', () {
    testWidgets('repairs and matches sit in one group above the hero', (
      tester,
    ) async {
      await _pumpTrain(tester, repository: _AttentionRepository());
      expect(find.text('Needs your attention'), findsOneWidget);
      expect(find.text('Workout record needs review'), findsOneWidget);
      expect(find.text('Apple Health workout match'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Needs your attention')).dy,
        lessThan(tester.getTopLeft(find.byType(WorkoutHero)).dy),
      );
    });

    testWidgets('Switch to that day selects the match’s day', (tester) async {
      await _pumpTrain(tester, repository: _AttentionRepository());
      await tester.tap(find.text('Switch to that day'));
      await tester.pumpAndSettle();
      expect(find.text('Done on Wednesday'), findsOneWidget);
      expect(find.text('Switch to that day'), findsNothing);
    });

    testWidgets('a repair asks first with a native confirm', (tester) async {
      final repository = await _pumpTrain(
        tester,
        repository: _AttentionRepository(),
      );
      await tester.tap(find.text('Review and correct'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('Correct this workout record?'), findsOneWidget);
      await tester.tap(find.text('Confirm correction'));
      await tester.pumpAndSettle();
      expect(repository.repaired, ['session-repair']);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('confirming a match saves the answer', (tester) async {
      final repository = await _pumpTrain(
        tester,
        repository: _AttentionRepository(),
      );
      await tester.tap(find.text('Confirm match'));
      await tester.pumpAndSettle();
      expect(repository.responses, [('match-1', true)]);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('the completion prompt replaces Start inside the hero', (
      tester,
    ) async {
      await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(
          candidate: HealthkitCompletionCandidate(
            plannedWorkoutId: upperA.id,
            plannedWorkoutName: 'Upper body A',
            workoutCount: 1,
            workoutMinutes: 47,
            localDate: trainToday,
          ),
        ),
      );
      final prompt = find.descendant(
        of: find.byType(WorkoutHero),
        matching: find.text('Yes, mark complete'),
      );
      expect(prompt, findsOneWidget);
      expect(find.text('Apple Health detected workout'), findsOneWidget);
      expect(
        find.textContaining('Apple Health recorded a 47 min workout today'),
        findsOneWidget,
      );
      expect(find.text('Start workout'), findsNothing);
    });
  });

  group('Train states', () {
    testWidgets('skeletons stand in while the hub loads', (tester) async {
      final repository = _PendingRepository();
      await _pumpTrain(tester, repository: repository, settle: false);
      await tester.pump();
      expect(find.byType(TracendSkeleton), findsWidgets);
      expect(find.bySemanticsLabel('Loading Train'), findsOneWidget);
      repository.completer.complete(trainHub());
      await tester.pumpAndSettle();
      expect(find.byType(TracendSkeleton), findsNothing);
      expect(find.text('Upper body A'), findsOneWidget);
    });

    testWidgets('a failed hub shows the reason and retries', (tester) async {
      final repository = await _pumpTrain(
        tester,
        repository: TrainFixtureRepository()..hubError = StateError('hub 503'),
      );
      expect(find.text('Your plan could not load'), findsOneWidget);
      expect(find.textContaining('hub 503'), findsOneWidget);
      repository.hubError = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Upper body A'), findsOneWidget);
    });

    testWidgets('offline keeps the loaded plan and says so', (tester) async {
      final repository = await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(),
      );
      repository.hubError = const SocketException('offline');
      await tester.drag(find.text('Friday 2 October'), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        find.text('Offline. Showing your plan from earlier.'),
        findsOneWidget,
      );
      expect(find.text('Upper body A'), findsOneWidget);
      expect(repository.hubLoads, greaterThan(1));
    });

    testWidgets('no active plan asks to finish setting one up', (tester) async {
      await _pumpTrain(
        tester,
        repository: TrainFixtureRepository(
          hub: trainHub(withPlan: false, workouts: const []),
        ),
      );
      expect(find.text('No active plan'), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);
    });

    testWidgets('a cached 1.5 hub renders without the 1.6 extras', (
      tester,
    ) async {
      final hub = TrainingHubData.fromHubJson(
        json.decode(
              File(
                'test/contract/fixtures/training_hub_v1_5.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      await _pumpTrain(tester, repository: TrainFixtureRepository(hub: hub));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Week '), findsNothing);
      expect(find.text('Builds as you train'), findsOneWidget);
    });
  });
}
