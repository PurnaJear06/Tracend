import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/widgets/recovery_readout_card.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.dark}) {
  final isDark = brightness == Brightness.dark;
  return MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      extensions: [isDark ? TracendColors.dark : TracendColors.light],
    ),
    // Today scrolls; the open method panel is taller than one screen.
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

ComputedMetrics _metrics({
  int? recovery,
  int? sleepQuality,
  RecoveryBreakdown? breakdown,
  String dataConfidence = 'medium',
  TodayRaw? todayRaw,
  String? recoveryMode,
}) {
  return ComputedMetrics(
    scores: ComputedScores(
      recovery: recovery,
      recoveryMode: recoveryMode,
      sleepQuality: sleepQuality,
      recoveryBreakdown: breakdown,
    ),
    baselines: const ComputedBaselines(),
    dataConfidence: dataConfidence,
    todayRaw: todayRaw,
  );
}

const _breakdown = RecoveryBreakdown(
  hrvZ: 0.5,
  rhrZ: -0.2,
  sleepZ: 0.8,
  respRateZ: 0.1,
  prevStrainZ: -0.3,
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('How this is calculated'));
  await tester.pumpAndSettle();
}

void main() {
  group('RecoveryReadoutCard', () {
    testWidgets('drivers read as plain rows with today\'s values', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RecoveryReadoutCard(
            computed: _metrics(
              recovery: 72,
              breakdown: _breakdown,
              todayRaw: const TodayRaw(
                hrvMs: 58,
                restingHrBpm: 52,
                sleepMinutes: 411,
                respRateBpm: 14.2,
                dailyStrain: 42,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Heart rate variability: normal for you, 58 ms'),
        findsOneWidget,
      );
      expect(
        find.text('Resting heart rate: normal for you, 52 bpm'),
        findsOneWidget,
      );
      expect(find.text('Sleep: normal for you, 6 h 51 min'), findsOneWidget);
      expect(
        find.text('Breathing rate: normal for you, 14 breaths a minute'),
        findsOneWidget,
      );
      expect(
        find.text('Recent training: normal for you, strain 42.0 today'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Heart rate variability: normal for you, 58 ms'),
        findsOneWidget,
      );
    });

    testWidgets('a morning estimate reads its own rows and weights', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RecoveryReadoutCard(
            computed: _metrics(
              recovery: 41,
              recoveryMode: 'morning',
              breakdown: const RecoveryBreakdown(
                hrvZ: -0.9,
                rhrZ: 0.2,
                sleepZ: 0,
                respRateZ: 0,
                prevStrainZ: 0,
                checkInZ: 1.25,
                missingComponents: [
                  'sleep_minutes',
                  'resp_rate',
                  'prev_strain',
                ],
                weights: {
                  'hrv_sdnn': 40,
                  'check_in': 25,
                  'resting_hr': 20,
                  'sleep_minutes': 10,
                  'resp_rate': 0,
                  'prev_strain': 5,
                },
              ),
              todayRaw: const TodayRaw(
                hrvMs: 52,
                hrvScoredMs: 39,
                restingHrBpm: 70,
                restingHrScoredBpm: 61,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Morning HRV: normal for you, 39 ms'), findsOneWidget);
      expect(find.text('Morning check-in: feeling good'), findsOneWidget);
      expect(
        find.text('Resting heart rate: normal for you, 61 bpm yesterday'),
        findsOneWidget,
      );
      expect(find.textContaining('Breathing rate'), findsNothing);

      await _open(tester);
      expect(find.text('Morning HRV · 40%'), findsOneWidget);
      expect(find.text('Morning check-in · 25%'), findsOneWidget);
      expect(find.textContaining('settles at noon'), findsOneWidget);
    });

    testWidgets('z-scores stay behind How this is calculated', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryReadoutCard(computed: _metrics(breakdown: _breakdown))),
      );
      await tester.pumpAndSettle();

      expect(find.text('+0.5'), findsNothing);
      final disclosure = tester.getSemantics(
        find.bySemanticsLabel('How this is calculated'),
      );
      expect(disclosure.flagsCollection.isExpanded, Tristate.isFalse);

      await _open(tester);

      expect(find.text('+0.5'), findsOneWidget);
      expect(find.text('-0.2'), findsOneWidget);
      expect(find.text('+0.8'), findsOneWidget);
      expect(find.text('+0.1'), findsOneWidget);
      expect(find.text('-0.3'), findsOneWidget);
      expect(find.text('Heart rate variability · 55%'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Heart rate variability, z-score +0.5, weight 55 percent',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Calculated from your Apple Health data and logged workouts. No AI.',
        ),
        findsOneWidget,
      );

      await _open(tester);
      expect(find.text('+0.5'), findsNothing);
    });

    testWidgets('renders nothing without a breakdown', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryReadoutCard(computed: _metrics(recovery: 72))),
      );
      await tester.pumpAndSettle();

      expect(find.text('How this is calculated'), findsNothing);
      expect(find.textContaining('Heart rate variability'), findsNothing);
    });

    testWidgets('missing components read not enough data yet', (tester) async {
      const partial = RecoveryBreakdown(
        hrvZ: 0.3,
        rhrZ: 1.0,
        sleepZ: 0,
        respRateZ: 0,
        prevStrainZ: -0.5,
        missingComponents: ['sleep_minutes', 'resp_rate'],
      );
      await tester.pumpWidget(
        _wrap(RecoveryReadoutCard(computed: _metrics(breakdown: partial))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sleep: not enough data yet'), findsOneWidget);
      expect(find.text('Breathing rate: not enough data yet'), findsOneWidget);
      expect(find.text('Resting heart rate: lower than usual'), findsOneWidget);

      await _open(tester);
      expect(find.text('Not used today'), findsNWidgets(2));
      expect(find.text('+0.0'), findsNothing);
      expect(find.bySemanticsLabel('Sleep, not used today'), findsOneWidget);
    });

    testWidgets('unmeasured components never show a number', (tester) async {
      // The owner's watch-off day: sleep and breathing measured nowhere.
      const partial = RecoveryBreakdown(
        hrvZ: -1.2,
        rhrZ: 0.5,
        sleepZ: 0,
        respRateZ: 0,
        prevStrainZ: 0,
        missingComponents: ['sleep_minutes', 'resp_rate', 'prev_strain'],
      );
      await tester.pumpWidget(
        _wrap(
          RecoveryReadoutCard(
            computed: _metrics(
              recovery: 54,
              breakdown: partial,
              todayRaw: const TodayRaw(hrvMs: 38, restingHrBpm: 52),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Heart rate variability: lower than usual, 38 ms'),
        findsOneWidget,
      );
      expect(
        find.text('Resting heart rate: normal for you, 52 bpm'),
        findsOneWidget,
      );
      expect(find.textContaining('not enough data yet'), findsNWidgets(3));
    });

    testWidgets(
      'regression: screenshot 2026-09-10 — valid sleep, immature baseline',
      (tester) async {
        // Sleep measured (144 min, passed the backend's 1–960 gate, sleep
        // quality computed) but the sleep baseline lacks 3 observations, so
        // the driver is missing from recovery. The row shows the reading with
        // an honest note, never "not enough data".
        const partial = RecoveryBreakdown(
          hrvZ: 0.3,
          rhrZ: 1.9,
          sleepZ: 0,
          respRateZ: -0.6,
          prevStrainZ: -0.6,
          missingComponents: ['sleep_minutes'],
        );
        await tester.pumpWidget(
          _wrap(
            RecoveryReadoutCard(
              computed: _metrics(
                recovery: 85,
                breakdown: partial,
                sleepQuality: 50,
                todayRaw: const TodayRaw(
                  hrvMs: 77,
                  restingHrBpm: 52,
                  sleepMinutes: 144,
                  respRateBpm: 17,
                  dailyStrain: 0,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Sleep: 2 h 24 min, baseline still building'),
          findsOneWidget,
        );
        expect(find.text('Sleep: not enough data yet'), findsNothing);
        expect(
          find.text('Resting heart rate: lower than usual, 52 bpm'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a valid sleep value stays missing when quality is null', (
      tester,
    ) async {
      const partial = RecoveryBreakdown(
        hrvZ: 0.3,
        rhrZ: 0,
        sleepZ: 0,
        respRateZ: 0,
        prevStrainZ: 0,
        missingComponents: ['sleep_minutes'],
      );
      await tester.pumpWidget(
        _wrap(
          RecoveryReadoutCard(
            computed: _metrics(
              breakdown: partial,
              todayRaw: const TodayRaw(sleepMinutes: 144),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sleep: not enough data yet'), findsOneWidget);
      expect(find.textContaining('2 h 24 min'), findsNothing);
    });

    testWidgets('older briefs without today_raw keep the words alone', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(RecoveryReadoutCard(computed: _metrics(breakdown: _breakdown))),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Heart rate variability: normal for you'),
        findsOneWidget,
      );
    });
  });

  group('driverComparison', () {
    test('within one spread is normal for you', () {
      expect(driverComparison(0.99, inverted: false), 'normal for you');
      expect(driverComparison(-0.99, inverted: true), 'normal for you');
    });

    test('reports direction, and much from two spreads', () {
      expect(driverComparison(1.2, inverted: false), 'higher than usual');
      expect(driverComparison(-2.1, inverted: false), 'much lower than usual');
    });

    test('inverted drivers read the measurement, not the z sign', () {
      // A positive resting-heart-rate z means a LOWER heart rate.
      expect(driverComparison(1.5, inverted: true), 'lower than usual');
      expect(driverComparison(-1.5, inverted: true), 'higher than usual');
    });

    test('sleep and training speak in more and less', () {
      expect(
        driverComparison(-1.4, inverted: false, more: 'more', less: 'less'),
        'less than usual',
      );
    });
  });
}
