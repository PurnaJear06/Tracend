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
              {'set_count': 3},
              {'set_count': 4},
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
                onOpenProgress: () {},
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

        // Open the method disclosure and switch the coach perspective.
        await tester.ensureVisible(find.text('How this is calculated'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('How this is calculated'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Food').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Food').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(
          find.text('Heart rate variability: much lower than usual, 38 ms'),
          findsOneWidget,
        );
        expect(
          find.text('Training load: much heavier than usual'),
          findsOneWidget,
        );
        if (rest) expect(find.text('See your week'), findsOneWidget);
      });
    }
  }
}
