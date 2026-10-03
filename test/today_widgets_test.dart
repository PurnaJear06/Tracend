import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/today/widgets/check_in_prompt_bar.dart';
import 'package:tracend/features/today/widgets/coach_perspective_card.dart';
import 'package:tracend/features/today/widgets/fuel_rail_card.dart';
import 'package:tracend/features/today/widgets/session_plan_card.dart';
import 'package:tracend/features/today/widgets/today_hero.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/micro_motion.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_skeleton.dart';

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

DailyBrief _brief({
  Map<String, dynamic>? workout,
  Map<String, dynamic>? nextMeal,
  Map<String, dynamic>? checkIn,
  Map<String, dynamic>? health,
  Map<String, dynamic>? nutrition,
  ComputedMetrics? computed,
  Map<String, dynamic>? decision,
}) => DailyBrief(
  localDate: '2026-08-23',
  workout: workout,
  nextMeal: nextMeal,
  checkIn: checkIn,
  health: health,
  nutrition: nutrition,
  computed: computed,
  decision: decision,
);

ComputedMetrics _computed({
  int? recovery,
  RecoveryBreakdown? breakdown,
  int? sleepQuality,
  int? macroAdherencePct,
  double? acwr,
  double? dailyStrain,
  String dataConfidence = 'medium',
}) => ComputedMetrics(
  scores: ComputedScores(
    recovery: recovery,
    recoveryBreakdown: breakdown,
    sleepQuality: sleepQuality,
    macroAdherencePct: macroAdherencePct,
    acwr: acwr,
    dailyStrain: dailyStrain,
  ),
  baselines: const ComputedBaselines(),
  dataConfidence: dataConfidence,
);

void main() {
  group('TodayHero', () {
    testWidgets('shows the score, band chip, confidence and sentence', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          TodayHero(
            brief: _brief(
              workout: const {'name': 'Push day'},
              checkIn: const {'energy': 3},
              computed: _computed(recovery: 72, dataConfidence: 'high'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('72'), findsOneWidget);
      expect(find.text('Recovery'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Recovery score 72 out of 100'),
        findsOneWidget,
      );
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('Recovery score · High confidence'), findsOneWidget);
      expect(find.text('Complete Push day.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Recovery score 72 out of 100'),
        findsOneWidget,
      );
      // The hero is a verdict, not an action surface.
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('maps each score to its band', (tester) async {
      for (final (score, band) in [
        (85, 'Excellent'),
        (70, 'Good'),
        (55, 'Moderate'),
        (40, 'Low'),
        (20, 'Poor'),
      ]) {
        await tester.pumpWidget(
          _wrap(
            TodayHero(
              brief: _brief(computed: _computed(recovery: score)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(band), findsOneWidget, reason: '$score → $band');
      }
    });

    testWidgets('a missing score reads -- with honest copy and no band', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(TodayHero(brief: _brief(computed: _computed()))),
      );
      await tester.pumpAndSettle();

      expect(find.text('--'), findsOneWidget);
      expect(
        find.text(
          'Not enough data yet for a recovery score. Sync Apple Health and '
          'check in to build your baseline.',
        ),
        findsOneWidget,
      );
      expect(find.text('Good'), findsNothing);
    });

    testWidgets('a cold start says Building baseline', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TodayHero(
            brief: _brief(
              computed: _computed(recovery: 50, dataConfidence: 'cold_start'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recovery score · Building baseline'), findsOneWidget);
    });

    testWidgets('a brief without computed data leaves the score out', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(TodayHero(brief: _brief(checkIn: const {'energy': 3}))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recovery'), findsNothing);
      expect(find.text('Keep the approved plan.'), findsOneWidget);
    });

    testWidgets('the readiness sentence uses the Archivo headline token', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TodayHero(
                brief: _brief(
                  workout: const {'name': 'Push day'},
                  checkIn: const {'energy': 3},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final headline = tester.widget<Text>(find.text('Complete Push day.'));
      expect(headline.style?.fontSize, 24);
      expect(headline.style?.fontFamily, TracendFonts.displayFamily);
    });

    testWidgets('a sync issue stays on the card', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TodayHero(
            brief: _brief(),
            onSync: () {},
            syncIssue: 'Could not refresh Apple Health.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not refresh Apple Health.'), findsOneWidget);
    });
  });

  group('SessionPlanCard', () {
    testWidgets("shows today's workout with real counts and opens it", (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        _wrap(
          SessionPlanCard(
            workout: const {
              'name': 'Push day',
              'objective': 'Build pressing strength.',
              'estimated_minutes': 60,
              'exercises': [
                {'set_count': 3},
                {'set_count': 4},
              ],
            },
            onOpen: () => opened++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Today's workout"), findsOneWidget);
      expect(find.text('Push day'), findsOneWidget);
      expect(find.text('60 min'), findsOneWidget);
      expect(find.text('2 exercises'), findsOneWidget);
      expect(find.text('7 sets'), findsOneWidget);
      expect(find.text('View workout'), findsOneWidget);
      await tester.tap(find.text('Push day'));
      expect(opened, 1);
    });

    testWidgets('leaves out counts the plan does not carry', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SessionPlanCard(
            workout: {
              'name': 'Push day',
              'exercises': [
                {'set_count': 1},
              ],
            },
            onOpen: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 exercise'), findsOneWidget);
      expect(find.text('1 set'), findsOneWidget);
      expect(find.textContaining('min'), findsNothing);
    });

    testWidgets('no workout is a rest day with an enabled week action', (
      tester,
    ) async {
      var week = 0;
      await tester.pumpWidget(
        _wrap(
          SessionPlanCard(
            workout: null,
            onOpen: _noop,
            onOpenWeek: () => week++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rest day'), findsOneWidget);
      expect(find.textContaining('exercise'), findsNothing);
      final action = find.widgetWithText(OutlinedButton, 'See your week');
      expect(tester.widget<OutlinedButton>(action).onPressed, isNotNull);
      await tester.tap(action);
      expect(week, 1);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('the rest day leaves the action out when not wired', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const SessionPlanCard(workout: null, onOpen: _noop)),
      );
      await tester.pumpAndSettle();

      expect(find.text('See your week'), findsNothing);
    });

    testWidgets('says the training load in words, with the ratio', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SessionPlanCard(
            workout: {'name': 'Push day'},
            acwr: 1.05,
            onOpen: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Training load: about normal'), findsOneWidget);
      expect(
        find.text('Last 7 days against your 4-week average · ratio 1.05'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Training load: about normal. Ratio 1.05.'),
        findsOneWidget,
      );
      expect(find.text('LOAD'), findsNothing);
    });

    testWidgets('hides the load row when ACWR is null', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SessionPlanCard(workout: {'name': 'Push day'}, onOpen: _noop),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Training load'), findsNothing);
    });

    test('load words follow the app-wide ACWR bands', () {
      expect(trainingLoadWords(0.79), 'lighter than usual');
      expect(trainingLoadWords(0.8), 'about normal');
      expect(trainingLoadWords(1.3), 'about normal');
      expect(trainingLoadWords(1.42), 'heavier than usual');
      expect(trainingLoadWords(1.6), 'much heavier than usual');
    });
  });

  group('FuelDay', () {
    ScheduledMeal slot(
      String id,
      String label,
      String time, {
      String? status,
    }) => ScheduledMeal(
      id: id,
      slotKey: id,
      label: label,
      time: time,
      foods: const [],
      status: status ?? 'upcoming',
      optional: false,
      reminderEnabled: false,
    );
    MealEntry meal(String type, int hour, double protein, {String? slotId}) =>
        MealEntry(
          id: 'm-$type-$hour',
          type: type,
          status: 'confirmed',
          source: 'manual',
          loggedAt: DateTime(2026, 10, 3, hour, 10),
          scheduleItemId: slotId,
          items: [
            MealItem(
              name: 'Food',
              calories: 400,
              protein: protein,
              carbohydrate: 40,
              fat: 10,
            ),
          ],
        );
    final plan = NutritionSchedule(
      title: 'Plan',
      items: [
        slot('b', 'Breakfast', '08:00'),
        slot('l', 'Lunch', '13:30'),
        slot('s', 'Snack', '16:30'),
        slot('d', 'Dinner', '20:30'),
      ],
    );

    test('splits the protein left evenly over the meals still ahead', () {
      final day = FuelDay.from(
        proteinEaten: 58,
        proteinTarget: 150,
        schedule: plan,
        loggedMeals: [meal('breakfast', 8, 58, slotId: 'b')],
        now: DateTime(2026, 10, 3, 13, 5),
      );
      expect(day.proteinLeft, 92);
      expect(day.mealsLeft, 3);
      expect(day.perMeal!.round(), 31);
      expect(
        [for (final m in day.meals) m.label],
        ['Breakfast', 'Lunch', 'Snack', 'Dinner'],
      );
      expect(day.meals.first.state, FuelMealState.logged);
      expect(day.meals.first.protein, 58);
      expect(day.meals[1].state, FuelMealState.planned);
    });

    test('a slot an hour past with nothing logged is missed, not ahead', () {
      final day = FuelDay.from(
        proteinEaten: 0,
        proteinTarget: 150,
        schedule: plan,
        loggedMeals: const [],
        now: DateTime(2026, 10, 3, 9, 30),
      );
      expect(day.meals.first.state, FuelMealState.missed);
      expect(day.mealsLeft, 3);
      expect(day.perMeal, 50);
    });

    test('an off-plan meal stands at its logged time under its type', () {
      final day = FuelDay.from(
        proteinEaten: 20,
        proteinTarget: 150,
        schedule: const NutritionSchedule(title: '', items: []),
        loggedMeals: [meal('snack', 11, 20)],
        now: DateTime(2026, 10, 3, 12),
      );
      expect(day.hasPlan, isFalse);
      expect(day.meals.single.label, 'Snack');
      expect(day.meals.single.minute, 11 * 60 + 10);
      expect(day.perMeal, isNull);
    });

    test('drafts do not count, and the rail widens for a late meal', () {
      final day = FuelDay.from(
        proteinEaten: 0,
        proteinTarget: 150,
        schedule: NutritionSchedule(
          title: 'Plan',
          items: [slot('x', 'Late snack', '23:15')],
        ),
        loggedMeals: [
          MealEntry(
            id: 'draft',
            type: 'lunch',
            status: 'draft',
            source: 'photo_analysis',
            loggedAt: DateTime(2026, 10, 3, 12),
          ),
        ],
        now: DateTime(2026, 10, 3, 12),
      );
      expect(day.meals.single.label, 'Late snack');
      expect(day.startMinute, 6 * 60);
      expect(day.endMinute, 24 * 60);
    });
  });

  group('FuelRailCard', () {
    const targets = NutritionTargets(
      calories: 2300,
      protein: 150,
      carbohydrate: 240,
      fat: 70,
    );
    final day = FuelDay(
      meals: const [
        FuelRailMeal(
          label: 'Breakfast',
          minute: 8 * 60 + 10,
          state: FuelMealState.logged,
          protein: 58,
        ),
        FuelRailMeal(
          label: 'Lunch',
          minute: 13 * 60 + 30,
          state: FuelMealState.planned,
          protein: 92 / 3,
        ),
        FuelRailMeal(
          label: 'Snack',
          minute: 16 * 60 + 30,
          state: FuelMealState.planned,
          protein: 92 / 3,
        ),
        FuelRailMeal(
          label: 'Dinner',
          minute: 20 * 60 + 30,
          state: FuelMealState.planned,
          protein: 92 / 3,
        ),
      ],
      nowMinute: 13 * 60 + 5,
      proteinLeft: 92,
      mealsLeft: 3,
      planLoaded: true,
      hasPlan: true,
    );

    testWidgets('leads with protein to go and how to spread it', (
      tester,
    ) async {
      var logged = 0;
      await tester.pumpWidget(
        _wrap(
          FuelRailCard(
            consumed: const {'calories': 1240, 'protein_g': 58},
            targets: targets,
            day: day,
            onLog: () => logged++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('92 g protein to go'), findsOneWidget);
      expect(find.text('3 meals left, about 31 g each'), findsOneWidget);
      expect(find.text('1,240 of 2,300 kcal'), findsOneWidget);
      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('58 g'), findsOneWidget);
      expect(find.text('~31 g'), findsWidgets);
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^Meals today\. Breakfast, logged, 58 grams protein\. '
            r'Lunch at 13:30, planned, about 31 grams protein',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Log a meal'));
      expect(logged, 1);
    });

    testWidgets('a met protein target says so', (tester) async {
      await tester.pumpWidget(
        _wrap(
          FuelRailCard(
            consumed: const {'calories': 2400, 'protein_g': 160},
            targets: targets,
            day: day,
            onLog: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Protein target reached'), findsOneWidget);
      expect(find.text('160 of 150 g protein eaten'), findsOneWidget);
      expect(find.text('2,400 of 2,300 kcal'), findsOneWidget);
    });

    testWidgets('says when there is no plan, or the plan did not load', (
      tester,
    ) async {
      FuelDay bare({required bool loaded}) => FuelDay(
        meals: const [],
        nowMinute: 600,
        proteinLeft: 150,
        mealsLeft: 0,
        planLoaded: loaded,
        hasPlan: false,
      );
      await tester.pumpWidget(
        _wrap(
          FuelRailCard(
            consumed: null,
            targets: targets,
            day: bare(loaded: true),
            onLog: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No meal plan is set for today.'), findsOneWidget);
      expect(find.text('Log a meal'), findsNothing);

      await tester.pumpWidget(
        _wrap(
          FuelRailCard(
            consumed: null,
            targets: targets,
            day: bare(loaded: false),
            onLog: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Your meal plan didn’t load. Pull to refresh.'),
        findsOneWidget,
      );
    });

    testWidgets('no targets shows what was eaten, no fabricated target', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FuelRailCard(
            consumed: const {'calories': 1500, 'protein_g': 126},
            targets: null,
            day: day,
            onLog: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1,500 kcal eaten'), findsOneWidget);
      expect(find.text('No nutrition target is set yet.'), findsOneWidget);
    });

    testWidgets('at full motion the headline counts up and the rail draws in', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          TracendMotionScope(
            level: TracendMotionLevel.full,
            child: FuelRailCard(
              consumed: const {'calories': 1240, 'protein_g': 58},
              targets: targets,
              day: day,
              onLog: null,
            ),
          ),
        ),
      );
      String shown() => tester
          .widget<RichText>(
            find.descendant(
              of: find.bySemanticsLabel('92 g protein to go'),
              matching: find.byType(RichText),
            ),
          )
          .text
          .toPlainText();
      expect(shown(), '0 g protein to go');
      await tester.pump(const Duration(milliseconds: 200));
      expect(shown(), isNot('0 g protein to go'));
      await tester.pumpAndSettle();
      expect(shown(), '92 g protein to go');
      expect(tester.takeException(), isNull);
    });

    test('groups thousands', () {
      expect(groupedThousands(0), '0');
      expect(groupedThousands(999), '999');
      expect(groupedThousands(1240), '1,240');
      expect(groupedThousands(1234567), '1,234,567');
    });
  });

  group('CoachPerspectiveCard', () {
    final decision = CoachDecision(
      id: 'd1',
      localDate: '2026-08-23',
      trainingAction: 'PROCEED_AS_PLANNED',
      trainingSummary: 'Complete the scheduled session.',
      nutritionAction: 'MAINTAIN_TARGETS',
      nutritionSummary: 'Keep approved nutrition targets.',
      finalDecision: 'Push day is on.',
      reason: 'Recovery is steady.',
      confidence: 'high',
      evidence: const [],
      missingData: const [],
      riskFlags: const [],
      createdAt: DateTime(2026, 8, 23),
    );

    testWidgets('shows the training perspective and the real confidence', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(CoachPerspectiveCard(decision: decision)));
      await tester.pumpAndSettle();

      expect(find.text('Push day is on.'), findsOneWidget);
      expect(find.text('Complete the scheduled session.'), findsOneWidget);
      expect(
        find.text(
          'High confidence · decided ${friendlyDate(DateTime(2026, 8, 23))}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a decision made today is labelled today, not dated', (
      tester,
    ) async {
      final now = DateTime.now();
      final todayKey =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final fresh = CoachDecision(
        id: 'd2',
        localDate: todayKey,
        trainingAction: 'PROCEED_AS_PLANNED',
        trainingSummary: 'Complete the scheduled session.',
        nutritionAction: 'MAINTAIN_TARGETS',
        nutritionSummary: 'Keep approved nutrition targets.',
        finalDecision: 'Push day is on.',
        reason: 'Recovery is steady.',
        confidence: 'medium',
        evidence: const [],
        missingData: const [],
        riskFlags: const [],
        createdAt: now,
      );
      await tester.pumpWidget(_wrap(CoachPerspectiveCard(decision: fresh)));
      await tester.pumpAndSettle();

      expect(find.text('Medium confidence · decided today'), findsOneWidget);
    });

    testWidgets('the Food segment switches to the nutrition summary', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(CoachPerspectiveCard(decision: decision)));
      await tester.pumpAndSettle();

      expect(find.text('T-COACH'), findsNothing);
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();

      expect(find.text('Keep approved nutrition targets.'), findsOneWidget);
      expect(find.text('Complete the scheduled session.'), findsNothing);
    });
  });

  group('CheckInPromptBar', () {
    testWidgets('pending state prompts and opens the check-in', (tester) async {
      var opened = false;
      await tester.pumpWidget(
        _wrap(CheckInPromptBar(onCheckIn: () => opened = true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Morning check-in'), findsOneWidget);
      expect(
        find.text("About a minute. It sharpens today's advice."),
        findsOneWidget,
      );
      await tester.tap(find.text('Morning check-in'));
      expect(opened, isTrue);
    });

    testWidgets('completed state says it is done', (tester) async {
      await tester.pumpWidget(
        _wrap(CheckInPromptBar(onCheckIn: () {}, completed: true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Done. Tap to update it.'), findsOneWidget);
    });
  });

  group('TodayScreen', () {
    testWidgets('wraps each loaded section in a staggered entrance', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: TodayScreen(
            environment: _environment,
            brief: _ComputedBriefRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // hero, check-in, workout, recovery drivers, 7-day trend, sleep,
      // food, coach note
      expect(find.byType(MicroMotionEntrance), findsNWidgets(8));
      expect(find.text('PRECISION READOUTS'), findsNothing);
      expect(find.text('Recovery drivers'), findsOneWidget);
    });

    testWidgets('keeps the brief mounted across a check-in reload', (
      tester,
    ) async {
      // Regression: swapping the brief future used to reset the FutureBuilder
      // to waiting, unmounting _BriefContent — replaying the stagger
      // entrances and re-creating the count-up statically. The retained
      // previous brief must stay mounted so score changes animate.
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: TodayScreen(
              environment: _environment,
              brief: _ReloadBriefRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('40'), findsWidgets);
      final heroBefore = tester.element(find.byType(TodayHero));

      await tester.tap(find.text('Morning check-in'));
      await tester.pumpAndSettle();
      expect(find.text('Save check-in'), findsOneWidget);

      await tester.tap(find.text('Save check-in'));
      await tester.pumpAndSettle();

      final heroAfter = tester.element(find.byType(TodayHero));
      expect(identical(heroBefore, heroAfter), isTrue);
      expect(find.text('72'), findsWidgets);
      expect(find.text('Check-in saved'), findsOneWidget);
    });

    testWidgets('pull to refresh reruns the sync pipeline', (tester) async {
      final brief = _ReloadBriefRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: TodayScreen(environment: _environment, brief: brief),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = brief.loads;

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(brief.loads, greaterThan(before));
      // No Apple Health connection in this test, so the pipeline says so.
      expect(find.textContaining('Apple Health is not connected'), findsOne);
    });

    testWidgets('shows skeletons, not a spinner, while the brief loads', (
      tester,
    ) async {
      final pending = Completer<DailyBrief>();
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: TodayScreen(
              environment: _environment,
              brief: _PendingBriefRepository(pending.future),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Loading Today'), findsOneWidget);
      expect(find.byType(TracendSkeleton), findsWidgets);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      pending.complete(_brief());
      await tester.pumpAndSettle();
    });

    testWidgets('the account avatar keeps its Open account tooltip', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: TodayScreen(
            environment: _environment,
            brief: _ComputedBriefRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Open account'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Open account')), findsOneWidget);
    });

    testWidgets('Food and More trends go to their tabs', (tester) async {
      var nutrition = 0;
      var progress = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: TodayScreen(
              environment: _environment,
              brief: _ComputedBriefRepository(),
              onOpenNutrition: () => nutrition++,
              onOpenProgress: () => progress++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('More trends in Progress'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More trends in Progress'));
      await tester.ensureVisible(find.text('Log a meal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log a meal'));
      expect(progress, 1);
      expect(nutrition, 1);
    });
  });

  group("TodayScreen today's workout", () {
    testWidgets("opens the brief's workout when Train is not wired", (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: TodayScreen(
              environment: _environment,
              brief: _PlannedBriefRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pull day'));
      await tester.pumpAndSettle();

      final detail = find.byType(WorkoutDetailScreen);
      expect(detail, findsOneWidget);
      final screen = tester.widget<WorkoutDetailScreen>(detail);
      expect(screen.workout?.id, 'b1d6c1a2-0000-4000-8000-000000000001');
      expect(screen.workout?.name, 'Pull day');
      expect(screen.workout?.exercises.single.name, 'Lat pulldown');
      expect(screen.sessionDate, DateTime(2026, 8, 23));
    });

    testWidgets('goes to Train when the shell wires it', (tester) async {
      var train = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: TodayScreen(
              environment: _environment,
              brief: _PlannedBriefRepository(),
              onOpenTrain: () => train++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pull day'));
      await tester.pumpAndSettle();

      expect(train, 1);
      expect(find.byType(WorkoutDetailScreen), findsNothing);
    });
  });
}

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

class _PendingBriefRepository implements DailyBriefRepository {
  _PendingBriefRepository(this.future);

  final Future<DailyBrief> future;

  @override
  Future<DailyBrief> load(DateTime date) => future;
}

class _ComputedBriefRepository implements DailyBriefRepository {
  @override
  Future<DailyBrief> load(DateTime date) async => _brief(
    workout: const {'name': 'Push day'},
    checkIn: const {'energy': 3},
    computed: _computed(
      recovery: 72,
      sleepQuality: 80,
      breakdown: const RecoveryBreakdown(
        hrvZ: 0.4,
        rhrZ: 0,
        sleepZ: 0,
        respRateZ: 0,
        prevStrainZ: 0,
      ),
    ),
  );
}

class _ReloadBriefRepository implements DailyBriefRepository {
  int loads = 0;

  @override
  Future<DailyBrief> load(DateTime date) async {
    loads++;
    return _brief(
      workout: const {'name': 'Push day'},
      checkIn: const {'energy': 3},
      computed: _computed(recovery: loads == 1 ? 40 : 72, sleepQuality: 80),
    );
  }
}

void _noop() {}

class _PlannedBriefRepository implements DailyBriefRepository {
  @override
  Future<DailyBrief> load(DateTime date) async => _brief(
    workout: const {
      'id': 'b1d6c1a2-0000-4000-8000-000000000001',
      'weekday': 7,
      'name': 'Pull day',
      'objective': 'Build pulling strength.',
      'estimated_minutes': 45,
      'warm_up': 'Easy rowing.',
      'cooldown_cardio': 'Walk.',
      'exercises': [
        {
          'id': 'e1',
          'order': 1,
          'name': 'Lat pulldown',
          'set_count': 3,
          'rep_min': 8,
          'rep_max': 10,
          'target_rpe': 8,
          'rest_seconds': 120,
          'notes': '',
        },
      ],
    },
    checkIn: const {'energy': 3},
    computed: _computed(recovery: 72, sleepQuality: 80),
  );
}
