import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/app.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';

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
  // never lays out the recovery ring, sleep card, driver bars, or trajectory
  // lens. Pump Today directly with a computed brief to cover those data-viz
  // layouts at the largest scale. Bounded pump: the NOW-dot pulse is an
  // intentional infinite loop.
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
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      _expectNoLayoutException(tester, 'Today computed');
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

void _expectNoLayoutException(WidgetTester tester, String tab) {
  final exception = tester.takeException();
  final detail = exception is FlutterError
      ? exception.toStringDeep()
      : exception?.toString();
  expect(exception, isNull, reason: '$tab layout failed:\n$detail');
}
