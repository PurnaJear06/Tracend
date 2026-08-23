import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/widgets/check_in_prompt_bar.dart';
import 'package:tracend/features/today/widgets/coach_perspective_card.dart';
import 'package:tracend/features/today/widgets/metabolic_target_card.dart';
import 'package:tracend/features/today/widgets/precision_divider.dart';
import 'package:tracend/features/today/widgets/readiness_strip.dart';
import 'package:tracend/features/today/widgets/session_plan_card.dart';
import 'package:tracend/features/today/widgets/today_hero.dart';

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
  int? sleepQuality,
  int? macroAdherencePct,
  double? acwr,
  double? dailyStrain,
  String dataConfidence = 'medium',
}) => ComputedMetrics(
  scores: ComputedScores(
    recovery: recovery,
    sleepQuality: sleepQuality,
    macroAdherencePct: macroAdherencePct,
    acwr: acwr,
    dailyStrain: dailyStrain,
  ),
  baselines: const ComputedBaselines(),
  dataConfidence: dataConfidence,
);

void main() {
  group('trajectoryPoints', () {
    test('maps real scores and resolves NOW from recovery', () {
      final points = trajectoryPoints(
        _computed(recovery: 72, sleepQuality: 80, macroAdherencePct: 91),
      );
      expect(points.map((p) => p.label), ['SLEEP', 'TRAIN', 'FUEL', 'NOW']);
      expect(points.last.value, 72);
    });

    test('NOW falls back to the last real point when recovery is null', () {
      final points = trajectoryPoints(_computed(sleepQuality: 80));
      expect(points.map((p) => p.label), ['SLEEP', 'NOW']);
      expect(points.last.value, 80);
    });

    test('returns no points (chip-rail fallback) when nothing exists', () {
      expect(trajectoryPoints(_computed()), isEmpty);
      expect(trajectoryPoints(null), isEmpty);
    });
  });

  group('TodayHero', () {
    testWidgets('shows decision headline, reason, and confidence pill', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          TodayHero(
            brief: _brief(
              workout: const {'name': 'Push day'},
              checkIn: const {'energy': 3},
              computed: _computed(recovery: 72),
            ),
          ),
        ),
      );
      // Bounded pump: the NOW-dot pulse is an intentional infinite loop.
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Complete Push day.'), findsOneWidget);
      expect(find.text('Medium confidence'), findsOneWidget);
      expect(find.text('Start session'), findsOneWidget);
    });

    testWidgets('shows Building baseline on cold start', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TodayHero(
            brief: _brief(computed: _computed(dataConfidence: 'cold_start')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Building baseline'), findsOneWidget);
    });

    testWidgets('disables Start session when no workout is planned', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          TodayHero(
            brief: _brief(checkIn: const {'energy': 3}),
            onStartSession: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start session'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('hides View analytics when not wired', (tester) async {
      await tester.pumpWidget(_wrap(TodayHero(brief: _brief())));
      await tester.pumpAndSettle();

      expect(find.text('View analytics'), findsNothing);
    });
  });

  group('ReadinessStrip', () {
    testWidgets('full state shows real scores and bands', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ReadinessStrip(
            brief: _brief(
              computed: _computed(
                recovery: 72,
                acwr: 1.05,
                macroAdherencePct: 91,
              ),
            ),
            onOpen: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('72'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('1.05'), findsOneWidget);
      expect(find.text('Optimal'), findsOneWidget);
      expect(find.text('91%'), findsOneWidget);
      expect(find.text('On track'), findsOneWidget);
    });

    testWidgets('cold start shows -- and honest fallbacks', (tester) async {
      await tester.pumpWidget(
        _wrap(ReadinessStrip(brief: _brief(), onOpen: (_, _) {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('--'), findsNWidgets(3));
      expect(find.text('Check in'), findsOneWidget);
      expect(find.text('Rest day'), findsOneWidget);
      expect(find.text('Up to date'), findsOneWidget);
    });
  });

  group('SessionPlanCard', () {
    testWidgets('full state shows name, counts, and objective', (tester) async {
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
            onOpen: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Push day'), findsOneWidget);
      expect(find.text('Build pressing strength.'), findsOneWidget);
      expect(find.text('2 MVMT'), findsOneWidget);
      expect(find.text('7 SETS'), findsOneWidget);
      expect(find.text('~60 MIN'), findsOneWidget);
    });

    testWidgets('null workout shows honest empty state', (tester) async {
      await tester.pumpWidget(
        _wrap(const SessionPlanCard(workout: null, onOpen: _noop)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No session planned'), findsOneWidget);
      expect(find.text('2 MVMT'), findsNothing);
    });
  });

  group('MetabolicTargetCard', () {
    const targets = NutritionTargets(
      calories: 2380,
      protein: 150,
      carbohydrate: 240,
      fat: 70,
    );

    testWidgets('full state shows target, consumed, and remaining', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MetabolicTargetCard(
            consumed: {'calories': 1500, 'protein_g': 126},
            targets: targets,
            onLog: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2380'), findsOneWidget);
      expect(find.text('126g PRO'), findsOneWidget);
      expect(find.text('24g REMAINING'), findsOneWidget);
      expect(find.text('LOG'), findsOneWidget);
    });

    testWidgets('no targets shows consumed only, no fabricated bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MetabolicTargetCard(
            consumed: {'calories': 1500, 'protein_g': 126},
            targets: null,
            onLog: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1500 kcal logged'), findsOneWidget);
      expect(find.text('No active nutrition target is set.'), findsOneWidget);
    });

    testWidgets('hides LOG button when not wired', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MetabolicTargetCard(
            consumed: null,
            targets: targets,
            onLog: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LOG'), findsNothing);
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

    testWidgets('shows training summary by default and real confidence', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(CoachPerspectiveCard(decision: decision)));
      await tester.pumpAndSettle();

      expect(find.text('Push day is on.'), findsOneWidget);
      expect(find.text('Complete the scheduled session.'), findsOneWidget);
      expect(find.text('Confidence: high'), findsOneWidget);
    });

    testWidgets('N-Coach toggle switches to nutrition summary', (tester) async {
      await tester.pumpWidget(_wrap(CoachPerspectiveCard(decision: decision)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('N-COACH'));
      await tester.pumpAndSettle();

      expect(find.text('Keep approved nutrition targets.'), findsOneWidget);
      expect(find.text('Complete the scheduled session.'), findsNothing);
    });
  });

  group('CheckInPromptBar', () {
    testWidgets('pending state prompts and opens check-in', (tester) async {
      var opened = false;
      await tester.pumpWidget(
        _wrap(CheckInPromptBar(onCheckIn: () => opened = true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update morning status?'), findsOneWidget);
      expect(find.text('CHECK-IN'), findsOneWidget);
      await tester.tap(find.text('Update morning status?'));
      expect(opened, isTrue);
    });

    testWidgets('completed state shows recorded copy', (tester) async {
      await tester.pumpWidget(
        _wrap(CheckInPromptBar(onCheckIn: () {}, completed: true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Morning status recorded'), findsOneWidget);
      expect(find.text('EDIT'), findsOneWidget);
    });
  });

  testWidgets('PrecisionDivider renders the label', (tester) async {
    await tester.pumpWidget(_wrap(const PrecisionDivider()));
    await tester.pumpAndSettle();

    expect(find.text('PRECISION READOUTS'), findsOneWidget);
  });
}

void _noop() {}
