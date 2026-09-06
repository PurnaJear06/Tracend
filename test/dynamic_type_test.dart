import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/app.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

void main() {
  // Plan §8.2: Dynamic Type 1.0 / 1.3 / largest — wraps before truncating,
  // no overflow at 320pt. 1.0 is covered by the width matrix in
  // frontend_smoke_test.dart; this file covers 1.3 and the largest iOS
  // accessibility scale (~2.0) at the narrowest supported width.
  for (final scale in [1.3, 2.0]) {
    testWidgets('all tabs render without overflow at 320pt × $scale text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        const TracendApp(environment: _environment, themeMode: ThemeMode.dark),
      );
      await tester.pumpAndSettle();
      _expectNoLayoutException(tester, 'Today');

      for (final tab in ['Train', 'Coach', 'Nutrition', 'Progress']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        _expectNoLayoutException(tester, tab);
      }
    });
  }

  // The default fixture brief carries no `computed`, so the shell test above
  // never lays out the recovery readout, driver rows, sleep card, or 7-day
  // trend. Pump Today directly with a computed brief and a 7-day health
  // history to cover those data-viz layouts at the largest scale. Bounded
  // pump: the NOW-dot pulse is an intentional infinite loop.
  testWidgets(
    'Today computed data-viz renders without overflow at 320pt × 2.0',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [TracendColors.dark],
          ),
          home: TodayScreen(
            environment: _environment,
            brief: _ComputedBriefRepository(),
            health: _FixtureHealthRepository(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      _expectNoLayoutException(tester, 'Today computed');
    },
  );

  // Train with real week-rail data: four sessions (the honest floor for a
  // ratio verdict) plus a computed brief carrying ACWR/strain/monotony, so
  // the verdict, band chip, day columns, mix advice, and ratio footnote all
  // lay out under the largest accessibility scale. Bounded pump: the chart's
  // grow-in reveal is a bounded animation.
  testWidgets(
    'Train computed week rail renders without overflow at 320pt × 2.0',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final now = DateTime.now();
      final monday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [TracendColors.dark],
          ),
          home: TrainScreen(
            repository: _WeekRailHubRepository(monday),
            brief: _ComputedBriefRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectNoLayoutException(tester, 'Train computed');
    },
  );
}

class _ComputedBriefRepository implements DailyBriefRepository {
  @override
  Future<DailyBrief> load(DateTime date) async => DailyBrief(
    localDate: '2026-08-24',
    workout: const {'name': 'Push day', 'objective': 'Complete the sets.'},
    checkIn: const {'energy': 3},
    computed: ComputedMetrics(
      scores: ComputedScores(
        recovery: 72,
        sleepQuality: 80,
        macroAdherencePct: 91,
        acwr: 1.05,
        dailyStrain: 4.2,
        recoveryBreakdown: const RecoveryBreakdown(
          hrvZ: 0.5,
          rhrZ: 0.4,
          sleepZ: 0.8,
          respRateZ: 0.1,
          prevStrainZ: -0.3,
        ),
        sleepBreakdown: const SleepBreakdown(
          durationScore: 82,
          efficiencyScore: 74,
          restorativeScore: 68,
          consistencyScore: 91,
        ),
      ),
      baselines: const ComputedBaselines(),
      dataConfidence: 'medium',
    ),
  );
}

/// 7-day HRV history so the trend curve (not just its cold-start state) is
/// laid out under Dynamic Type.
class _FixtureHealthRepository implements HealthRepository {
  @override
  Future<HealthSyncStatus> connectAndSync() => loadStatus();

  @override
  Future<HealthSyncStatus> loadStatus() async =>
      const HealthSyncStatus(state: HealthConnectionState.manualOnly);

  @override
  Future<HealthHistory> loadHistory() async => HealthHistory([
    for (var i = 6; i >= 0; i--)
      HealthDay(
        date: DateTime(2026, 8, 24).subtract(Duration(days: i)),
        presentMetrics: const {HealthMetric.hrvSdnn},
        hrvSdnnMs: 42.0 + (6 - i) * 2,
      ),
  ]);

  @override
  Future<HealthSyncStatus> sync() => loadStatus();
}

/// Hub payload with four real sessions in the current week so the week rail
/// charts columns (not just sockets) and passes the ≥4-session floor for a
/// ratio verdict at accessibility scales.
class _WeekRailHubRepository extends FixtureWorkoutRepository {
  _WeekRailHubRepository(this.monday);

  final DateTime monday;

  @override
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28}) async =>
      TrainingHubData(
        planTitle: 'Approved training plan',
        workouts: const [PlannedWorkout.fixture],
        recentSessions: [
          TrainingSessionSummary(
            name: 'Push day',
            date: monday,
            durationSeconds: 2700,
          ),
          TrainingSessionSummary(
            name: 'Pull day',
            date: monday.add(const Duration(days: 1)),
            durationSeconds: 3300,
          ),
          TrainingSessionSummary(
            name: 'Leg day',
            date: monday.add(const Duration(days: 2)),
            durationSeconds: 1800,
          ),
          TrainingSessionSummary(
            name: 'Push day',
            date: monday.add(const Duration(days: 3)),
            durationSeconds: 3000,
          ),
        ],
        completedSessions: 1,
        plannedSessions: 4,
        progression: const [],
      );
}

void _expectNoLayoutException(WidgetTester tester, String tab) {
  final exception = tester.takeException();
  final detail = exception is FlutterError
      ? exception.toStringDeep()
      : exception?.toString();
  expect(exception, isNull, reason: '$tab layout failed:\n$detail');
}
