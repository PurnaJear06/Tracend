import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/today/widgets/check_in_prompt_bar.dart';
import 'package:tracend/features/today/widgets/coach_perspective_card.dart';
import 'package:tracend/features/today/widgets/metabolic_target_card.dart';
import 'package:tracend/features/today/widgets/precision_divider.dart';
import 'package:tracend/features/today/widgets/recovery_readout_card.dart';
import 'package:tracend/features/today/widgets/session_plan_card.dart';
import 'package:tracend/features/today/widgets/today_hero.dart';
import 'package:tracend/shared/widgets/micro_motion.dart';

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
      await tester.pumpAndSettle();

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

    testWidgets('shows the real ACWR load row when present', (tester) async {
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

      expect(find.text('LOAD'), findsOneWidget);
      expect(find.text('1.05'), findsOneWidget);
      expect(find.text('Optimal'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Training load, ACWR 1.05, Optimal'),
        findsOneWidget,
      );
    });

    testWidgets('hides the load row when ACWR is null', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SessionPlanCard(workout: {'name': 'Push day'}, onOpen: _noop),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LOAD'), findsNothing);
    });

    testWidgets('flags high load above the optimal zone', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SessionPlanCard(
            workout: {'name': 'Push day'},
            acwr: 1.42,
            onOpen: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1.42'), findsOneWidget);
      expect(find.text('High load'), findsOneWidget);
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

  group('TodayScreen stagger entrances', () {
    testWidgets('wraps each loaded brief section in a staggered entrance', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [TracendColors.dark],
          ),
          home: TodayScreen(
            environment: const AppEnvironment(
              name: 'test',
              supabaseUrl: '',
              supabasePublishableKey: '',
            ),
            brief: _ComputedBriefRepository(),
          ),
        ),
      );
      // Bounded pump: the NOW-dot pulse is an intentional infinite loop and
      // the staggered entrances carry per-index delays. The brief resolves
      // during the first pump, so a second pump fires the entrance timers.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));

      // hero, recovery readout, 7-day trend, sleep, session, metabolic,
      // coach perspective, check-in bar
      expect(find.byType(MicroMotionEntrance), findsNWidgets(8));
    });

    testWidgets('keeps the brief mounted across a check-in reload', (
      tester,
    ) async {
      // Regression: swapping the brief future used to reset the FutureBuilder
      // to waiting, unmounting _BriefContent — replaying all eight stagger
      // entrances and re-creating the count-up statically. The retained
      // previous brief must stay mounted so score changes animate.
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [TracendColors.dark],
          ),
          home: Scaffold(
            body: TodayScreen(
              environment: const AppEnvironment(
                name: 'test',
                supabaseUrl: '',
                supabasePublishableKey: '',
              ),
              brief: _ReloadBriefRepository(),
            ),
          ),
        ),
      );
      // Bounded pumps: NOW-dot pulse is an intentional infinite loop.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('40'), findsWidgets);
      final readoutBefore = tester.element(find.byType(RecoveryReadoutCard));

      await tester.scrollUntilVisible(
        find.text('Morning status recorded'),
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 100,
      );
      await tester.ensureVisible(find.text('Morning status recorded'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Morning status recorded'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Save check-in'), findsOneWidget);

      await tester.ensureVisible(find.text('Save check-in'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Save check-in'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      final readoutAfter = tester.element(find.byType(RecoveryReadoutCard));
      expect(identical(readoutBefore, readoutAfter), isTrue);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('72'), findsWidgets);
    });
  });
}

class _ComputedBriefRepository implements DailyBriefRepository {
  @override
  Future<DailyBrief> load(DateTime date) async => _brief(
    workout: const {'name': 'Push day'},
    checkIn: const {'energy': 3},
    computed: _computed(recovery: 72, sleepQuality: 80),
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
