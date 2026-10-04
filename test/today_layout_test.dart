import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

class _Brief implements DailyBriefRepository {
  const _Brief({required this.rest});

  final bool rest;

  @override
  Future<DailyBrief> load(DateTime date) async => DailyBrief(
    localDate: '2026-10-03',
    workout: rest
        ? null
        : const {
            'name': 'Upper body A with a long accessory finisher',
            'estimated_minutes': 55,
            'exercises': [
              {'order': 1, 'name': 'Incline dumbbell press', 'set_count': 3},
              {'order': 2, 'name': 'Chest-supported row', 'set_count': 4},
            ],
          },
    checkIn: rest ? null : const {'energy': 4},
    health: const {'last_synced_at': '2026-10-03T08:05:00+00:00'},
    nutrition: const {'calories': 1240, 'protein_g': 96},
    computed: const ComputedMetrics(
      scores: ComputedScores(
        recovery: 58,
        recoveryBreakdown: RecoveryBreakdown(
          hrvZ: -2.4,
          rhrZ: 1.3,
          sleepZ: -1.1,
          respRateZ: 0,
          prevStrainZ: 0.2,
          missingComponents: ['resp_rate'],
        ),
        sleepQuality: 66,
        sleepBreakdown: SleepBreakdown(
          durationScore: 82,
          efficiencyScore: 91,
          restorativeScore: 64,
          consistencyScore: 55,
        ),
        sleepDebtMinutes: 65,
        acwr: 1.62,
      ),
      baselines: ComputedBaselines(),
      dataConfidence: 'medium',
      todayRaw: TodayRaw(
        hrvMs: 38,
        restingHrBpm: 51,
        sleepMinutes: 412,
        dailyStrain: 31,
      ),
    ),
    recoveryPrevious: 64,
    plan: const TodayPlan(
      title: 'Strength foundation with a long name',
      weekNumber: 3,
      blockWeeks: 20,
    ),
    week: [
      for (var i = 0; i < 7; i++)
        TodayWeekDay(
          date: DateTime(2026, 9, 28 + i),
          recovery: i == 2 ? null : 50 + i * 4,
          strain: i < 6 ? 4.0 + i : null,
          trained: i.isEven && i < 5,
          planned: i != 3,
        ),
    ],
    todaySession: rest
        ? null
        : const TodaySession(state: 'in_progress', completedSets: {1: 2}),
  );
}

class _Health implements HealthRepository {
  const _Health();

  @override
  Future<HealthHistory> loadHistory() async => HealthHistory([
    for (var i = 6; i >= 0; i--)
      HealthDay(
        date: DateTime(2026, 10, 3).subtract(Duration(days: i)),
        presentMetrics: const {HealthMetric.hrvSdnn},
        hrvSdnnMs: 40.0 + i * 3,
      ),
  ]);

  @override
  Future<HealthSyncStatus> loadStatus() async =>
      const HealthSyncStatus(state: HealthConnectionState.manualOnly);

  @override
  Future<HealthSyncStatus> connectAndSync() => loadStatus();

  @override
  Future<HealthSyncStatus> sync() => loadStatus();
}

class _Coach extends FixtureCoachRepository {
  const _Coach();

  @override
  Future<CoachDecision?> loadLatest() async => CoachDecision(
    id: 'd',
    localDate: '2026-10-03',
    trainingAction: 'REDUCE_VOLUME',
    trainingSummary: 'Drop one working set from each lift today.',
    nutritionAction: 'MAINTAIN_TARGETS',
    nutritionSummary: 'Keep the approved targets.',
    finalDecision: 'Train lighter today.',
    reason: 'Heart rate variability is well below your normal.',
    confidence: 'medium',
    evidence: const [],
    missingData: const [],
    riskFlags: const [],
    createdAt: DateTime(2026, 10, 3),
  );
}

void main() {
  for (final dark in [true, false]) {
    for (final rest in [false, true]) {
      testWidgets('Today lays out at 320pt × 2.0 text '
          '(${dark ? 'dark' : 'light'}, ${rest ? 'rest day' : 'workout'})', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? TracendTheme.dark : TracendTheme.light,
            home: Scaffold(
              body: TodayScreen(
                environment: _environment,
                brief: _Brief(rest: rest),
                health: const _Health(),
                nutrition: const FixtureNutritionRepository(),
                coach: const _Coach(),
                onOpenNutrition: () {},
                onOpenTrain: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // The large title falls back to "Today" so no word breaks.
        expect(find.text('Today'), findsWidgets);
        expect(find.textContaining('Good '), findsOneWidget);

        // Open the drivers from a chip, every tile, and a day of the week.
        await tester.ensureVisible(find.text('HRV low'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('HRV low'));
        await tester.pumpAndSettle();
        expect(
          find.text('Heart rate variability: much lower than usual, 38 ms'),
          findsOneWidget,
        );
        for (final tile in ['Sleep', 'Load', 'Fuel']) {
          await tester.ensureVisible(find.text(tile).first);
          await tester.pumpAndSettle();
          await tester.tap(find.text(tile).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: tile);
        }
        await tester.ensureVisible(find.text('Your week'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text('Week 3 of 20'), findsOneWidget);
        expect(
          find.text('Drop one working set from each lift today.'),
          findsOneWidget,
        );
        if (rest) {
          expect(find.text('Rest day'), findsOneWidget);
        } else {
          expect(find.text('2 of 7 sets logged'), findsOneWidget);
        }
      });
    }
  }
}
