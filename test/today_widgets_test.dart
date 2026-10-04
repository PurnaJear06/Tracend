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
import 'package:tracend/features/today/check_in_gate.dart';
import 'package:tracend/features/today/widgets/fuel_rail_card.dart';
import 'package:tracend/features/today/widgets/plan_progress_line.dart';
import 'package:tracend/features/today/widgets/recovery_readout_card.dart';
import 'package:tracend/features/today/widgets/recovery_tick_ring.dart';
import 'package:tracend/features/today/widgets/today_hero.dart';
import 'package:tracend/features/today/widgets/today_session_card.dart';
import 'package:tracend/features/today/widgets/today_tiles.dart';
import 'package:tracend/features/today/widgets/your_week_card.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
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
  int? recoveryPrevious,
  TodayPlan? plan,
  List<TodayWeekDay> week = const [],
  TodaySession? todaySession,
}) => DailyBrief(
  localDate: '2026-08-23',
  workout: workout,
  nextMeal: nextMeal,
  checkIn: checkIn,
  health: health,
  nutrition: nutrition,
  computed: computed,
  decision: decision,
  recoveryPrevious: recoveryPrevious,
  plan: plan,
  week: week,
  todaySession: todaySession,
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
    const steady = RecoveryBreakdown(
      hrvZ: 0.4,
      rhrZ: 0,
      sleepZ: 0,
      respRateZ: 0,
      prevStrainZ: 0,
    );

    testWidgets('shows the verdict, the ring score, band, change and '
        'confidence', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TodayHero(
            brief: _brief(
              computed: _computed(
                recovery: 72,
                breakdown: steady,
                dataConfidence: 'high',
              ),
              recoveryPrevious: 66,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Well recovered'), findsOneWidget);
      expect(
        find.text('Everything that counted today is normal for you.'),
        findsOneWidget,
      );
      expect(find.text('72'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('+6 from yesterday'), findsOneWidget);
      expect(find.text('Recovery score · High confidence'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Recovery 72, Good\. \+6 from')),
        findsOneWidget,
      );
      expect(find.byType(RecoveryTickRing), findsOneWidget);
      // The hero is a verdict, not an action surface.
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('maps each score to its band and verdict', (tester) async {
      for (final (score, band, verdict) in [
        (85, 'Excellent', 'Fully recovered'),
        (70, 'Good', 'Well recovered'),
        (55, 'Moderate', 'Partly recovered'),
        (40, 'Low', 'Under-recovered'),
        (20, 'Poor', 'Very under-recovered'),
      ]) {
        await tester.pumpWidget(
          _wrap(
            TodayHero(
              brief: _brief(
                computed: _computed(recovery: score, breakdown: steady),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(band), findsOneWidget, reason: '$score → $band');
        expect(find.text(verdict), findsOneWidget, reason: '$score');
      }
    });

    testWidgets('names the driver that pulls the score down, and a chip '
        'opens the drivers', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TodayHero(
            brief: _brief(
              computed: _computed(
                recovery: 61,
                sleepQuality: 70,
                breakdown: const RecoveryBreakdown(
                  hrvZ: 0.3,
                  rhrZ: 0,
                  sleepZ: -1.4,
                  respRateZ: 0,
                  prevStrainZ: 0,
                  missingComponents: ['resp_rate'],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Sleep less than usual. Everything else is normal for you.'),
        findsOneWidget,
      );
      expect(find.text('Sleep short'), findsOneWidget);
      expect(find.text('Breathing no data'), findsOneWidget);
      expect(find.byType(RecoveryReadoutCard), findsNothing);

      await tester.tap(find.text('Sleep short'));
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryReadoutCard), findsOneWidget);
      final ring = tester.widget<RecoveryTickRing>(
        find.byType(RecoveryTickRing),
      );
      // Breathing did not count, so sleep is the third lit segment.
      expect(ring.segments, hasLength(4));
      expect(ring.focus, 2);
    });

    testWidgets('HRV and resting heart rate sit under the ring against your '
        'normal', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TodayHero(
            brief: _brief(
              computed: const ComputedMetrics(
                scores: ComputedScores(
                  recovery: 72,
                  recoveryBreakdown: RecoveryBreakdown(
                    hrvZ: 1.2,
                    rhrZ: 0,
                    sleepZ: 0,
                    respRateZ: 0,
                    prevStrainZ: 0,
                  ),
                ),
                baselines: ComputedBaselines(),
                dataConfidence: 'medium',
                todayRaw: TodayRaw(hrvMs: 61, restingHrBpm: 52),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HRV · higher than usual'), findsOneWidget);
      expect(find.text('Resting HR · normal'), findsOneWidget);
    });

    testWidgets('a missing score reads -- with honest copy and no band', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(TodayHero(brief: _brief(computed: _computed()))),
      );
      await tester.pumpAndSettle();

      expect(find.text('--'), findsOneWidget);
      expect(find.text('Recovery not scored yet'), findsOneWidget);
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
      expect(find.byType(RecoveryTickRing), findsNothing);
      expect(find.text('Your day'), findsOneWidget);
    });

    testWidgets('the verdict uses the Archivo display face', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TodayHero(
                brief: _brief(computed: _computed(recovery: 72)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final verdict = tester.widget<Text>(find.text('Well recovered'));
      expect(verdict.style?.fontFamily, TracendFonts.displayFamily);
      expect(verdict.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('the check-in chip reads Checked in, or Check in when it is '
        'offered', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _wrap(
          TodayHero(
            brief: _brief(),
            checkedIn: true,
            onCheckIn: () => opened++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Checked in'));
      expect(opened, 1);

      await tester.pumpWidget(
        _wrap(
          TodayHero(
            brief: _brief(),
            offerCheckIn: true,
            onCheckIn: () => opened++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check in'));
      expect(opened, 2);
    });

    testWidgets('at full motion the score counts up as the ticks light', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          TracendMotionScope(
            level: TracendMotionLevel.full,
            child: TodayHero(
              brief: _brief(
                computed: _computed(recovery: 72, breakdown: steady),
              ),
            ),
          ),
        ),
      );
      expect(find.text('0'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('72'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('72'), findsOneWidget);
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

  group('PlanProgressLine', () {
    testWidgets('says the week of the block', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlanProgressLine(
            plan: TodayPlan(
              title: 'Strength foundation',
              weekNumber: 3,
              blockWeeks: 20,
            ),
          ),
        ),
      );
      expect(find.text('Strength foundation'), findsOneWidget);
      expect(find.text('Week 3 of 20'), findsOneWidget);
    });

    testWidgets('past the block it says the block is done', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlanProgressLine(
            plan: TodayPlan(title: 'Base', weekNumber: 22, blockWeeks: 20),
          ),
        ),
      );
      expect(find.text('Week 22 · block of 20 done'), findsOneWidget);
    });
  });

  group('TodaySessionCard', () {
    const workout = {
      'name': 'Upper body A',
      'estimated_minutes': 48,
      'exercises': [
        {'order': 1, 'name': 'Bench press', 'set_count': 4},
        {'order': 2, 'name': 'Barbell row', 'set_count': 3},
      ],
    };
    CoachDecision decision({
      String localDate = '2026-08-23',
      List<String> adjustments = const [],
    }) => CoachDecision(
      id: 'd1',
      localDate: localDate,
      trainingAction: 'ADJUST_TODAY',
      trainingSummary: 'Keep the session as planned.',
      nutritionAction: 'MAINTAIN_TARGETS',
      nutritionSummary: 'Keep approved nutrition targets.',
      finalDecision: 'Train today.',
      reason: 'Recovery is steady.',
      confidence: 'medium',
      evidence: const [],
      missingData: const [],
      riskFlags: const [],
      createdAt: DateTime(2026, 8, 23),
      trainingAdjustments: adjustments,
    );
    List<Color> blocks(WidgetTester tester) => [
      for (final box in tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(TodaySessionCard),
          matching: find.byType(AnimatedContainer),
        ),
      ))
        (box.decoration! as BoxDecoration).color!,
    ];

    testWidgets('shows the session, one block per set, and opens it', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        _wrap(
          TodaySessionCard(
            brief: _brief(workout: workout),
            decision: null,
            aiAllowed: true,
            onOpen: () => opened++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Today's session"), findsOneWidget);
      expect(find.text('Upper body A'), findsOneWidget);
      expect(find.text('2 exercises · 7 sets · about 48 min'), findsOneWidget);
      expect(blocks(tester), hasLength(7));
      expect(find.text('Bench press'), findsOneWidget);
      await tester.tap(find.text('Open in Train'));
      await tester.tap(find.text('Upper body A'));
      expect(opened, 2);
    });

    testWidgets('logged sets fill their blocks and the count follows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          TodaySessionCard(
            brief: _brief(
              workout: workout,
              todaySession: const TodaySession(
                state: 'in_progress',
                completedSets: {1: 4, 2: 1},
              ),
            ),
            decision: null,
            aiAllowed: true,
            onOpen: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('5 of 7 sets logged'), findsOneWidget);
      final lit = blocks(
        tester,
      ).where((color) => color == TracendColors.dark.accentSignalRing).length;
      expect(lit, 5);
    });

    testWidgets("today's coach adjustment is shown as advice", (tester) async {
      await tester.pumpWidget(
        _wrap(
          TodaySessionCard(
            brief: _brief(workout: workout),
            decision: decision(adjustments: ['Drop the last bench set today.']),
            aiAllowed: true,
            onOpen: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Coach · medium confidence'), findsOneWidget);
      expect(find.text('Drop the last bench set today.'), findsOneWidget);
      // Advice never changes the prescribed blocks.
      expect(blocks(tester), hasLength(7));
    });

    testWidgets('a decision from another day is not shown', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TodaySessionCard(
            brief: _brief(workout: workout),
            decision: decision(localDate: '2026-08-22'),
            aiAllowed: true,
            onOpen: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Keep the session as planned.'), findsNothing);
      expect(
        find.text('Tap Sync to generate an evidence-backed daily decision.'),
        findsOneWidget,
      );
    });

    testWidgets('with AI coaching off it says so', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TodaySessionCard(
            brief: _brief(workout: workout),
            decision: null,
            aiAllowed: false,
            onOpen: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'AI coaching is off, so no daily decision is generated. Turn it on '
          'in Account.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no workout is a rest day that names the next session', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          TodaySessionCard(
            brief: _brief(
              week: [
                for (var i = 0; i < 7; i++)
                  TodayWeekDay(
                    date: DateTime(2026, 8, 17 + i),
                    trained: false,
                    planned: i == 0 || i == 2,
                  ),
              ],
            ),
            decision: null,
            aiAllowed: true,
            onOpen: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rest day'), findsOneWidget);
      expect(find.text('Open in Train'), findsNothing);
    });

    test('summaries leave out what the plan does not carry', () {
      expect(
        workoutSummary(const {
          'exercises': [
            {'set_count': 1},
          ],
        }),
        '1 exercise · 1 set',
      );
      expect(workoutSummary(const {'name': 'Push day'}), '');
    });
  });

  group('TodayTiles', () {
    const targets = NutritionTargets(
      calories: 2300,
      protein: 150,
      carbohydrate: 240,
      fat: 70,
    );
    final week = [
      for (var i = 0; i < 7; i++)
        TodayWeekDay(
          date: DateTime(2026, 8, 17 + i),
          strain: i < 6 ? (i + 1).toDouble() : null,
          trained: i.isEven,
          planned: true,
        ),
    ];
    Widget tiles({double? acwr = 1.05}) => _wrap(
      SizedBox(
        width: 360,
        child: TodayTiles(
          computed: ComputedMetrics(
            scores: ComputedScores(
              acwr: acwr,
              sleepQuality: 74,
              sleepDebtMinutes: 72,
            ),
            baselines: const ComputedBaselines(),
            dataConfidence: 'medium',
            todayRaw: const TodayRaw(sleepMinutes: 408),
          ),
          week: week,
          today: DateTime(2026, 8, 23),
          consumed: const {'calories': 1240, 'protein_g': 58},
          targets: targets,
          fuelDay: null,
          sleepDay: null,
          onLogMeal: _noop,
        ),
      ),
    );

    testWidgets('sleep, load and fuel read at a glance', (tester) async {
      await tester.pumpWidget(tiles());
      await tester.pumpAndSettle();

      expect(find.text('6h 48m'), findsOneWidget);
      expect(find.text('1h 12m sleep debt'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('92 g'), findsOneWidget);
      expect(find.text('protein to go'), findsOneWidget);
    });

    testWidgets('a tile opens its card, one at a time', (tester) async {
      await tester.pumpWidget(tiles());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Load'));
      await tester.pumpAndSettle();
      expect(find.text('Training load about normal'), findsOneWidget);
      expect(find.textContaining('ratio 1.05'), findsOneWidget);

      await tester.tap(find.text('Fuel'));
      await tester.pumpAndSettle();
      expect(find.byType(FuelRailCard), findsOneWidget);
      expect(find.text('Training load about normal'), findsNothing);

      await tester.tap(find.text('Fuel'));
      await tester.pumpAndSettle();
      expect(find.byType(FuelRailCard), findsNothing);
    });

    testWidgets('load without a ratio says it is building', (tester) async {
      await tester.pumpWidget(tiles(acwr: null));
      await tester.pumpAndSettle();
      expect(find.text('Building'), findsOneWidget);
    });

    test('load words follow the app-wide ACWR bands', () {
      expect(trainingLoadWords(0.79), 'lighter than usual');
      expect(trainingLoadWords(0.8), 'about normal');
      expect(trainingLoadWords(1.3), 'about normal');
      expect(trainingLoadWords(1.42), 'heavier than usual');
      expect(trainingLoadWords(1.6), 'much heavier than usual');
      expect(sleepDuration(408), '6h 48m');
      expect(sleepDuration(45), '45m');
      expect(sleepDuration(420), '7h');
    });
  });

  group('YourWeekCard', () {
    final week = [
      TodayWeekDay(
        date: DateTime(2026, 8, 17),
        recovery: 64,
        trained: true,
        planned: true,
      ),
      TodayWeekDay(
        date: DateTime(2026, 8, 18),
        recovery: 48,
        trained: false,
        planned: true,
      ),
      TodayWeekDay(date: DateTime(2026, 8, 19), trained: false, planned: false),
      TodayWeekDay(
        date: DateTime(2026, 8, 20),
        recovery: 71,
        trained: false,
        planned: true,
      ),
      for (var i = 4; i < 7; i++)
        TodayWeekDay(
          date: DateTime(2026, 8, 17 + i),
          trained: false,
          planned: i == 5,
        ),
    ];

    testWidgets('counts sessions and averages only the scored days', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(YourWeekCard(week: week, today: DateTime(2026, 8, 20))),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 of 4 sessions done'), findsOneWidget);
      expect(find.text('Recovery averaged 61 this week'), findsOneWidget);
      expect(find.text('no\ndata'), findsOneWidget);
      expect(
        find.text('Today · recovery 71 · session planned'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a day names it', (tester) async {
      await tester.pumpWidget(
        _wrap(YourWeekCard(week: week, today: DateTime(2026, 8, 20))),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsLabel('Tuesday · recovery 48 · planned, not logged'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Tuesday · recovery 48 · planned, not logged'),
        findsOneWidget,
      );
    });
  });

  group('CheckInGateBar', () {
    testWidgets('checks in, or lets the athlete through', (tester) async {
      var checkIns = 0;
      var skips = 0;
      await tester.pumpWidget(
        _wrap(
          CheckInGateBar(
            onCheckIn: () => checkIns++,
            onSkip: () => skips++,
            floating: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Check in to start your day'), findsOneWidget);
      await tester.tap(find.text('Check in to start your day'));
      await tester.tap(find.text('Not today'));
      expect(checkIns, 1);
      expect(skips, 1);
    });

    test('the gate notifies only when it changes', () {
      final gate = CheckInGate();
      var changes = 0;
      gate.addListener(() => changes++);
      gate.update(required: true);
      gate.update(required: true);
      gate.update(required: false);
      expect(changes, 2);
      gate.dispose();
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

      // hero, tiles, today's session (this brief has no plan or week)
      expect(find.byType(MicroMotionEntrance), findsNWidgets(3));
      expect(find.byType(TodayHero), findsOneWidget);
      expect(find.byType(TodayTiles), findsOneWidget);
      expect(find.byType(TodaySessionCard), findsOneWidget);
      expect(find.byType(YourWeekCard), findsNothing);
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

      await tester.tap(find.text('Checked in'));
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

    testWidgets('Log a meal in the Fuel tile goes to Nutrition', (
      tester,
    ) async {
      var nutrition = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: TodayScreen(
              environment: _environment,
              brief: _ComputedBriefRepository(),
              onOpenNutrition: () => nutrition++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Fuel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fuel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Log a meal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log a meal'));
      expect(nutrition, 1);
    });

    testWidgets('the gate is required until today is checked in', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final gate = CheckInGate();
      addTearDown(gate.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: TodayScreen(
              environment: _environment,
              brief: _NoCheckInBriefRepository(),
              checkInGate: gate,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(gate.required, isTrue);
      // The gate bar lives in the shell, so Today offers no chip of its own.
      expect(find.text('Check in'), findsNothing);

      gate.checkIn();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save check-in'));
      await tester.pumpAndSettle();
      expect(gate.required, isFalse);
      expect(find.text('Checked in'), findsOneWidget);
    });

    testWidgets('Not today lets the athlete through and keeps a Check in '
        'chip', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final gate = CheckInGate();
      addTearDown(gate.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: TodayScreen(
              environment: _environment,
              brief: _NoCheckInBriefRepository(),
              checkInGate: gate,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(gate.required, isTrue);

      gate.skip();
      await tester.pumpAndSettle();
      expect(gate.required, isFalse);
      expect(find.text('Check in'), findsOneWidget);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('today_check_in_skipped_on'), '2026-08-23');
    });

    testWidgets('a day put off earlier stays open after a relaunch', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'today_check_in_skipped_on': '2026-08-23',
      });
      final gate = CheckInGate();
      addTearDown(gate.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: TodayScreen(
              environment: _environment,
              brief: _NoCheckInBriefRepository(),
              checkInGate: gate,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(gate.required, isFalse);
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

      await tester.ensureVisible(find.text('Pull day'));
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

      await tester.ensureVisible(find.text('Pull day'));
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

class _NoCheckInBriefRepository implements DailyBriefRepository {
  @override
  Future<DailyBrief> load(DateTime date) async => _brief(
    workout: const {'name': 'Push day'},
    computed: _computed(recovery: 72, sleepQuality: 80),
  );
}

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
