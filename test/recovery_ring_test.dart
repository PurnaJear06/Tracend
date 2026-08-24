import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/recovery_ring.dart';

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

void main() {
  group('RecoveryRing', () {
    testWidgets('shows score and label for good recovery', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryRing(computed: _metrics(recovery: 72))),
      );

      expect(find.text('72'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('Recovery drivers'), findsNothing);
    });

    testWidgets('shows Excellent label for >= 80', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryRing(computed: _metrics(recovery: 85))),
      );

      expect(find.text('Excellent'), findsOneWidget);
    });

    testWidgets('shows Moderate label for 50-64', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryRing(computed: _metrics(recovery: 55))),
      );

      expect(find.text('Moderate'), findsOneWidget);
    });

    testWidgets('shows Low label for 35-49', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryRing(computed: _metrics(recovery: 40))),
      );

      expect(find.text('Low'), findsOneWidget);
    });

    testWidgets('shows Poor label for < 35', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryRing(computed: _metrics(recovery: 20))),
      );

      expect(find.text('Poor'), findsOneWidget);
    });

    testWidgets('shows No data when score is null', (tester) async {
      await tester.pumpWidget(_wrap(RecoveryRing(computed: _metrics())));

      expect(find.text('--'), findsOneWidget);
      expect(find.text('No data'), findsOneWidget);
    });

    testWidgets('shows Building baseline on cold start', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecoveryRing(
            computed: _metrics(recovery: 72, dataConfidence: 'cold_start'),
          ),
        ),
      );

      expect(find.text('Building baseline'), findsOneWidget);
    });

    testWidgets('shows Building baseline on low confidence', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecoveryRing(computed: _metrics(recovery: 72, dataConfidence: 'low')),
        ),
      );

      expect(find.text('Building baseline'), findsOneWidget);
    });

    testWidgets('shows driver breakdown when available', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecoveryRing(
            computed: _metrics(
              recovery: 72,
              breakdown: const RecoveryBreakdown(
                hrvZ: 0.517,
                rhrZ: 0.455,
                sleepZ: 0.798,
                respRateZ: 0.500,
                prevStrainZ: 0.300,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Recovery drivers'), findsOneWidget);
      expect(find.text('HRV'), findsOneWidget);
      expect(find.text('RHR'), findsOneWidget);
      expect(find.text('Sleep'), findsOneWidget);
      expect(find.text('Resp'), findsOneWidget);
      expect(find.text('Strain'), findsOneWidget);
    });

    testWidgets('no driver breakdown when breakdown is null', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryRing(computed: _metrics(recovery: 72))),
      );

      expect(find.text('Recovery drivers'), findsNothing);
    });

    testWidgets('score counts up when the value changes', (tester) async {
      await tester.pumpWidget(
        _wrap(RecoveryRing(computed: _metrics(recovery: 40))),
      );
      expect(find.text('40'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(RecoveryRing(computed: _metrics(recovery: 72))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('72'), findsOneWidget);
    });
  });
}
