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
    home: Scaffold(body: Center(child: child)),
  );
}

ComputedMetrics _metrics({
  int? recovery,
  RecoveryBreakdown? breakdown,
  String dataConfidence = 'medium',
}) {
  return ComputedMetrics(
    scores: ComputedScores(recovery: recovery, recoveryBreakdown: breakdown),
    baselines: const ComputedBaselines(),
    dataConfidence: dataConfidence,
  );
}

const _breakdown = RecoveryBreakdown(
  hrvZ: 0.5,
  rhrZ: -0.2,
  sleepZ: 0.8,
  respRateZ: 0.1,
  prevStrainZ: -0.3,
);

void main() {
  group('RecoveryReadoutCard', () {
    testWidgets('shows score, band chip, and derivation caption', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(RecoveryReadoutCard(computed: _metrics(recovery: 72))),
      );
      await tester.pumpAndSettle();

      expect(find.text('72'), findsOneWidget);
      expect(find.text('/ 100'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(
        find.text(
          'Derived from HRV, resting HR, sleep, respiratory rate, and prior strain.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows Excellent band for >= 80', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryReadoutCard(computed: _metrics(recovery: 85))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Excellent'), findsOneWidget);
    });

    testWidgets('shows Moderate band for 50-64', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryReadoutCard(computed: _metrics(recovery: 55))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Moderate'), findsOneWidget);
    });

    testWidgets('shows Low band for 35-49', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryReadoutCard(computed: _metrics(recovery: 40))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Low'), findsOneWidget);
    });

    testWidgets('shows Poor band for < 35', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryReadoutCard(computed: _metrics(recovery: 20))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Poor'), findsOneWidget);
    });

    testWidgets('null score shows -- and honest empty copy', (tester) async {
      await tester.pumpWidget(_wrap(RecoveryReadoutCard(computed: _metrics())));
      await tester.pumpAndSettle();

      expect(find.text('--'), findsOneWidget);
      expect(
        find.text(
          'Not enough data for a recovery score. Sync Apple Health and check '
          'in to build your baseline.',
        ),
        findsOneWidget,
      );
      expect(find.text('Good'), findsNothing);
    });

    testWidgets('shows Building baseline on cold start', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecoveryReadoutCard(
            computed: _metrics(recovery: 72, dataConfidence: 'cold_start'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Building baseline'), findsOneWidget);
    });

    testWidgets('shows Building baseline on low confidence', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecoveryReadoutCard(
            computed: _metrics(recovery: 72, dataConfidence: 'low'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Building baseline'), findsOneWidget);
    });

    testWidgets('shows driver rows with signed z values', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecoveryReadoutCard(
            computed: _metrics(recovery: 72, breakdown: _breakdown),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recovery drivers'), findsOneWidget);
      expect(find.text('HRV'), findsOneWidget);
      expect(find.text('RHR'), findsOneWidget);
      expect(find.text('Sleep'), findsOneWidget);
      expect(find.text('Resp'), findsOneWidget);
      expect(find.text('Strain'), findsOneWidget);
      expect(find.text('+0.5'), findsOneWidget);
      expect(find.text('-0.2'), findsOneWidget);
      expect(find.text('+0.8'), findsOneWidget);
      expect(find.text('+0.1'), findsOneWidget);
      expect(find.text('-0.3'), findsOneWidget);
    });

    testWidgets('no driver rows when breakdown is null', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryReadoutCard(computed: _metrics(recovery: 72))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recovery drivers'), findsNothing);
    });

    testWidgets('driver row announces the true z-score', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecoveryReadoutCard(
            computed: _metrics(recovery: 72, breakdown: _breakdown),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('HRV driver, z-score +0.5'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Strain driver, z-score -0.3'),
        findsOneWidget,
      );
    });

    testWidgets('missing components show No data, never a fake +0.0', (
      tester,
    ) async {
      const partial = RecoveryBreakdown(
        hrvZ: 0.3,
        rhrZ: 1.0,
        sleepZ: 0,
        respRateZ: 0,
        prevStrainZ: -0.5,
        missingComponents: ['sleep_minutes', 'resp_rate'],
      );
      await tester.pumpWidget(
        _wrap(
          RecoveryReadoutCard(
            computed: _metrics(recovery: 68, breakdown: partial),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No data'), findsNWidgets(2));
      expect(find.text('+0.3'), findsOneWidget);
      expect(find.text('+1.0'), findsOneWidget);
      expect(find.text('-0.5'), findsOneWidget);
      expect(find.text('+0.0'), findsNothing);
      expect(find.bySemanticsLabel('Sleep driver, no data'), findsOneWidget);
      expect(find.bySemanticsLabel('Resp driver, no data'), findsOneWidget);
      expect(find.bySemanticsLabel('HRV driver, z-score +0.3'), findsOneWidget);
    });

    testWidgets('all components missing renders five No data rows', (
      tester,
    ) async {
      const empty = RecoveryBreakdown(
        hrvZ: 0,
        rhrZ: 0,
        sleepZ: 0,
        respRateZ: 0,
        prevStrainZ: 0,
        missingComponents: [
          'hrv_sdnn',
          'resting_hr',
          'sleep_minutes',
          'resp_rate',
          'prev_strain',
        ],
      );
      await tester.pumpWidget(
        _wrap(RecoveryReadoutCard(computed: _metrics(breakdown: empty))),
      );
      await tester.pumpAndSettle();

      expect(find.text('--'), findsOneWidget);
      expect(find.text('No data'), findsNWidgets(5));
      expect(find.text('+0.0'), findsNothing);
    });

    testWidgets('score announces itself out of 100', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryReadoutCard(computed: _metrics(recovery: 72))),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Recovery score 72 out of 100'),
        findsOneWidget,
      );
    });

    testWidgets('score counts up when the value changes', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryReadoutCard(computed: _metrics(recovery: 40))),
      );
      await tester.pumpAndSettle();
      expect(find.text('40'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(RecoveryReadoutCard(computed: _metrics(recovery: 72))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('72'), findsOneWidget);
    });
  });
}
