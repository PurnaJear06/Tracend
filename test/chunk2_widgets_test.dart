import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/nutrition_screen.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_insight_card.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/widgets/prescription_cards.dart';
import 'package:tracend/features/train/widgets/workout_hero.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/date_pill_strip.dart';
import 'package:tracend/shared/widgets/targets_grid.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      extensions: const [TracendColors.dark],
    ),
    home: Scaffold(
      body: SingleChildScrollView(child: Center(child: child)),
    ),
  );
}

CoachDecision _decision() => CoachDecision(
  id: 'decision-1',
  localDate: '2026-08-23',
  trainingAction: 'Proceed',
  trainingSummary: 'Training stays as planned.',
  nutritionAction: 'Keep intake unchanged',
  nutritionSummary: 'Prioritize protein across your remaining meals.',
  finalDecision: 'Keep the approved plan.',
  reason: 'Evidence supports the current plan.',
  confidence: 'high',
  evidence: const [],
  missingData: const [],
  riskFlags: const [],
  createdAt: DateTime(2026, 8, 23),
);

void main() {
  group('DatePillStrip', () {
    testWidgets('renders seven day pills for the current week', (tester) async {
      final selected = DateTime(2026, 8, 19);
      await tester.pumpWidget(
        _wrap(DatePillStrip(selectedDate: selected, onSelectedDate: (_) {})),
      );
      for (var day = 17; day <= 23; day++) {
        expect(find.byKey(ValueKey('date-pill-2026-08-$day')), findsOneWidget);
      }
    });

    testWidgets('tapping a pill reports the normalized date', (tester) async {
      DateTime? picked;
      await tester.pumpWidget(
        _wrap(
          DatePillStrip(
            selectedDate: DateTime(2026, 8, 19),
            onSelectedDate: (date) => picked = date,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('date-pill-2026-08-21')));
      expect(picked, DateTime(2026, 8, 21));
    });

    testWidgets('chevrons appear only when callbacks are provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          DatePillStrip(
            selectedDate: DateTime(2026, 8, 19),
            onSelectedDate: (_) {},
          ),
        ),
      );
      expect(find.byKey(const ValueKey('date-strip-previous')), findsNothing);
      expect(find.byKey(const ValueKey('date-strip-next')), findsNothing);

      await tester.pumpWidget(
        _wrap(
          DatePillStrip(
            selectedDate: DateTime(2026, 8, 19),
            onSelectedDate: (_) {},
            onPreviousWeek: () {},
            onNextWeek: () {},
          ),
        ),
      );
      expect(find.byKey(const ValueKey('date-strip-previous')), findsOneWidget);
      expect(find.byKey(const ValueKey('date-strip-next')), findsOneWidget);
    });

    testWidgets('disabled pill does not fire selection', (tester) async {
      DateTime? picked;
      await tester.pumpWidget(
        _wrap(
          DatePillStrip(
            selectedDate: DateTime(2026, 8, 19),
            onSelectedDate: (date) => picked = date,
            isDateEnabled: (date) => date.day != 21,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('date-pill-2026-08-21')));
      expect(picked, isNull);
      await tester.tap(find.byKey(const ValueKey('date-pill-2026-08-20')));
      expect(picked, DateTime(2026, 8, 20));
    });

    test('mondayOf normalizes to the week start', () {
      expect(mondayOf(DateTime(2026, 8, 19)), DateTime(2026, 8, 17));
      expect(mondayOf(DateTime(2026, 8, 17)), DateTime(2026, 8, 17));
      expect(mondayOf(DateTime(2026, 8, 23)), DateTime(2026, 8, 17));
    });
  });

  // IntensityBar group removed (2026-09-04 Train redesign): the widget is
  // retired — prescription stats and the planned/recorded effort bar are
  // merged into ExerciseListCard rows. The 'logged RPE' and 'RPE N'
  // assertions live on in the TrainScreen recorded-RPE tests below.

  group('TargetsGrid', () {
    testWidgets('shows consumed vs target with remaining protein', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TargetsGrid(
            summary: NutritionSummary(
              calories: 1620,
              protein: 108,
              carbohydrate: 172,
              fat: 48,
              confirmedMeals: 3,
            ),
            targets: NutritionTargets(
              calories: 2200,
              protein: 160,
              carbohydrate: 240,
              fat: 70,
            ),
          ),
        ),
      );
      expect(find.text('1620'), findsOneWidget);
      expect(find.text('/ 2200 kcal'), findsOneWidget);
      expect(find.text('108'), findsOneWidget);
      expect(find.text('52g left'), findsOneWidget);
      expect(find.text('172'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
      expect(find.text('74%'), findsOneWidget);
    });

    testWidgets('no targets shows honest note, no fabricated bars', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TargetsGrid(
            summary: NutritionSummary(
              calories: 540,
              protein: 35,
              carbohydrate: 62,
              fat: 18,
              confirmedMeals: 1,
            ),
            targets: null,
          ),
        ),
      );
      expect(find.text('540 kcal logged'), findsOneWidget);
      expect(find.text('No active nutrition target is set.'), findsOneWidget);
      expect(find.text('PROTEIN'), findsNothing);
    });

    testWidgets('cold start shows targets with zero consumed', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TargetsGrid(
            summary: null,
            targets: NutritionTargets(
              calories: 2200,
              protein: 160,
              carbohydrate: 240,
              fat: 70,
            ),
          ),
        ),
      );
      expect(find.text('0'), findsWidgets);
      expect(find.text('/ 2200 kcal'), findsOneWidget);
      expect(find.text('160g left'), findsOneWidget);
    });
  });

  group('NutritionInsightCard', () {
    testWidgets('shows real decision fields and confidence', (tester) async {
      await tester.pumpWidget(
        _wrap(NutritionInsightCard(decision: _decision())),
      );
      expect(find.text('Keep intake unchanged'), findsOneWidget);
      expect(
        find.text('Prioritize protein across your remaining meals.'),
        findsOneWidget,
      );
      expect(find.text('Confidence: high'), findsOneWidget);
    });
  });

  group('TrainScreen recorded RPE', () {
    Future<void> scrollToExercises(WidgetTester tester) async {
      // 2026-09-04 Train redesign: the merged exercise list sits below the
      // week rail and hero, and SliverList builds lazily — scroll until the
      // unique RPE 9 row is built (rows above it follow), then settle the
      // entrance staggers of sections mounted mid-scroll.
      await tester.scrollUntilVisible(
        find.textContaining('RPE 9'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'completed day shows averaged logged RPE, filtering out-of-range values',
      (tester) async {
        final repository = _RecordedRpeRepository();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              extensions: const [TracendColors.dark],
            ),
            home: TrainScreen(repository: repository),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Completed'), findsOneWidget);
        await scrollToExercises(tester);
        expect(find.textContaining('logged 8.5'), findsOneWidget);
        expect(find.textContaining('logged 7.0'), findsOneWidget);
      },
    );

    testWidgets('incomplete day shows planned RPE without logged markers', (
      tester,
    ) async {
      final repository = _RecordedRpeRepository(completed: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [TracendColors.dark],
          ),
          home: TrainScreen(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      await scrollToExercises(tester);
      // 'logged 8.5'-style stat chips never appear on an incomplete day.
      // (Looser matchers false-hit the Execution card's empty-state copy
      // about "comparable logged sets".)
      expect(find.textContaining(RegExp('logged [0-9]')), findsNothing);
      expect(find.textContaining('RPE 8'), findsWidgets);
    });
  });

  group('RecentSessionsCard', () {
    testWidgets('openable session shows chevron', (tester) async {
      final workout = PlannedWorkout.fixture;
      await tester.pumpWidget(
        _wrap(
          RecentSessionsCard(
            sessions: [
              TrainingSessionSummary(
                name: 'Push day',
                date: DateTime(2026, 8, 20),
                durationSeconds: 3600,
                workoutId: workout.id,
              ),
            ],
            workoutForId: (id) => id == workout.id ? workout : null,
            repository: FixtureWorkoutRepository(),
          ),
        ),
      );
      expect(find.text('Push day'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_right), findsOneWidget);
    });

    testWidgets('session without workout_id is display-only (no chevron)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RecentSessionsCard(
            sessions: [
              TrainingSessionSummary(
                name: 'Old session',
                date: DateTime(2026, 8, 18),
                durationSeconds: 2400,
                workoutId: null,
              ),
            ],
            workoutForId: (_) => null,
            repository: FixtureWorkoutRepository(),
          ),
        ),
      );
      expect(find.text('Old session'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_right), findsNothing);
    });

    testWidgets('session with unresolvable workout_id is display-only', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RecentSessionsCard(
            sessions: [
              TrainingSessionSummary(
                name: 'Orphan session',
                date: DateTime(2026, 8, 17),
                durationSeconds: 1800,
                workoutId: 'nonexistent-id',
              ),
            ],
            workoutForId: (_) => null,
            repository: FixtureWorkoutRepository(),
          ),
        ),
      );
      expect(find.text('Orphan session'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_right), findsNothing);
    });
  });

  group('WorkoutHero coach insight', () {
    testWidgets('hides insight line when coachInsight is null', (tester) async {
      await tester.pumpWidget(
        _wrap(
          WorkoutHero(
            workout: PlannedWorkout.fixture,
            source: FixtureWorkoutRepository(),
            coachInsight: null,
          ),
        ),
      );
      expect(find.text('COACH INSIGHT'), findsNothing);
      expect(find.text('Push day'), findsOneWidget);
    });

    testWidgets('shows insight line when coachInsight is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          WorkoutHero(
            workout: PlannedWorkout.fixture,
            source: FixtureWorkoutRepository(),
            coachInsight: 'Recovery looks solid. Push as planned.',
          ),
        ),
      );
      expect(find.text('COACH INSIGHT'), findsOneWidget);
      expect(
        find.text('Recovery looks solid. Push as planned.'),
        findsOneWidget,
      );
    });
  });

  group('NutritionScreen insight card visibility', () {
    testWidgets('hides NutritionInsightCard when coach returns null', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [TracendColors.dark],
          ),
          home: const NutritionScreen(
            repository: FixtureNutritionRepository(),
            coach: FixtureCoachRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NutritionInsightCard), findsNothing);
    });

    testWidgets('shows NutritionInsightCard when coach returns a decision', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [TracendColors.dark],
          ),
          home: NutritionScreen(
            repository: const FixtureNutritionRepository(),
            coach: _DecisionCoachRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NutritionInsightCard), findsOneWidget);
      expect(find.text('Keep intake unchanged'), findsOneWidget);
    });
  });
}

/// Hub repository whose today workout is completed and whose session draft
/// carries per-set RPE values, including out-of-range values that
/// `_loadRecordedRpe` must filter out before averaging.
class _RecordedRpeRepository
    implements WorkoutRepository, TrainingHubRepository {
  _RecordedRpeRepository({this.completed = true});
  final bool completed;

  @override
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28}) async =>
      TrainingHubData(
        planTitle: 'Approved training plan',
        workouts: [PlannedWorkout.fixture],
        recentSessions: [],
        completedSessions: completed ? 1 : 0,
        plannedSessions: 4,
        progression: [],
        completedDays: completed ? {DateTime.now()} : const {},
      );

  @override
  Future<PlannedWorkout> loadTodayWorkout() async => PlannedWorkout.fixture;

  @override
  Future<String?> loadDraft(String workoutId) async => null;

  @override
  Future<Map<String, dynamic>?> loadSession(
    PlannedWorkout workout, {
    DateTime? localDate,
  }) async => {
    'exercises': [
      {
        'order': 1,
        'sets': [
          {'rpe': 8},
          {'rpe': 9},
          {'rpe': 15},
        ],
      },
      {
        'order': 2,
        'sets': [
          {'rpe': 7},
          {'rpe': 0},
        ],
      },
      {
        'order': 3,
        'sets': [
          {'rpe': null},
        ],
      },
    ],
  };

  @override
  Future<void> saveDraft(String workoutId, String json) async {}

  @override
  Future<void> clearDraft(String workoutId) async {}

  @override
  Future<String> start(
    PlannedWorkout workout,
    String idempotencyKey, {
    DateTime? localDate,
  }) async => 'session-1';

  @override
  Future<void> sync(
    String sessionId,
    int revision,
    Map<String, dynamic> draft,
  ) async {}

  @override
  Future<void> complete(
    String sessionId,
    int revision,
    int durationSeconds,
    Map<String, dynamic> draft,
  ) async {}
}

class _DecisionCoachRepository implements CoachRepository {
  @override
  Future<CoachDecision?> loadLatest() async => _decision();

  @override
  Future<CoachDecision> generate() => throw StateError('not needed');

  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
}
