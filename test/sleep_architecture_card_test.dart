import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/sleep_architecture_card.dart';

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

ComputedMetrics _fullMetrics() => ComputedMetrics(
  scores: const ComputedScores(
    sleepQuality: 85,
    sleepBreakdown: SleepBreakdown(
      durationScore: 86.4,
      efficiencyScore: 92.8,
      restorativeScore: 43.4,
      consistencyScore: 95.6,
    ),
    sleepDebtMinutes: -65,
  ),
  baselines: const ComputedBaselines(
    hrv: BaselineMetric(ewma: 49.45, spread: 3.0, nObs: 6, confidence: 'low'),
    restingHr: BaselineMetric(
      ewma: 55.5,
      spread: 1.1,
      nObs: 6,
      confidence: 'low',
    ),
  ),
  dataConfidence: 'medium',
);

ComputedMetrics _emptyMetrics() => const ComputedMetrics(
  scores: ComputedScores(),
  baselines: ComputedBaselines(),
  dataConfidence: 'cold_start',
);

void main() {
  group('SleepArchitectureCard', () {
    testWidgets('shows sleep quality and label', (tester) async {
      await tester.pumpWidget(
        _wrap(SleepArchitectureCard(computed: _fullMetrics())),
      );

      expect(find.text('SLEEP ARCHITECTURE'), findsOneWidget);
      expect(find.text('85 / 100'), findsOneWidget);
      expect(find.text('Restorative'), findsWidgets);
    });

    testWidgets('shows sub-scores with numeric values', (tester) async {
      await tester.pumpWidget(
        _wrap(SleepArchitectureCard(computed: _fullMetrics())),
      );

      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('Efficiency'), findsOneWidget);
      expect(find.text('Restorative'), findsWidgets);
      expect(find.text('Consistency'), findsOneWidget);
      expect(find.text('86'), findsOneWidget);
      expect(find.text('93'), findsOneWidget);
      expect(find.text('43'), findsOneWidget);
      expect(find.text('96'), findsOneWidget);
    });

    testWidgets('shows sleep debt badge', (tester) async {
      await tester.pumpWidget(
        _wrap(SleepArchitectureCard(computed: _fullMetrics())),
      );

      expect(find.textContaining('Sleep debt'), findsOneWidget);
      expect(find.textContaining('1h 5m'), findsOneWidget);
    });

    testWidgets('shows sleep surplus badge', (tester) async {
      final m = ComputedMetrics(
        scores: const ComputedScores(sleepQuality: 80, sleepDebtMinutes: 30),
        baselines: const ComputedBaselines(),
        dataConfidence: 'medium',
      );
      await tester.pumpWidget(_wrap(SleepArchitectureCard(computed: m)));

      expect(find.textContaining('Sleep surplus'), findsOneWidget);
    });

    testWidgets('shows HRV and RHR baselines', (tester) async {
      await tester.pumpWidget(
        _wrap(SleepArchitectureCard(computed: _fullMetrics())),
      );

      expect(find.text('HRV BASELINE'), findsOneWidget);
      expect(find.text('49.5'), findsOneWidget);
      expect(find.text('RESTING HR'), findsOneWidget);
      expect(find.text('55.5'), findsOneWidget);
    });

    testWidgets('shows No data when sleep quality is null', (tester) async {
      await tester.pumpWidget(
        _wrap(SleepArchitectureCard(computed: _emptyMetrics())),
      );

      expect(find.text('No data'), findsOneWidget);
    });

    testWidgets('hides sub-scores when breakdown is null', (tester) async {
      await tester.pumpWidget(
        _wrap(SleepArchitectureCard(computed: _emptyMetrics())),
      );

      expect(find.text('Duration'), findsNothing);
      expect(find.text('Efficiency'), findsNothing);
    });

    testWidgets('hides debt badge when debt is null', (tester) async {
      await tester.pumpWidget(
        _wrap(SleepArchitectureCard(computed: _emptyMetrics())),
      );

      expect(find.textContaining('Sleep debt'), findsNothing);
    });

    testWidgets('shows Adequate label for 60-79', (tester) async {
      final m = ComputedMetrics(
        scores: const ComputedScores(sleepQuality: 65),
        baselines: const ComputedBaselines(),
        dataConfidence: 'medium',
      );
      await tester.pumpWidget(_wrap(SleepArchitectureCard(computed: m)));

      expect(find.text('Adequate'), findsOneWidget);
    });

    testWidgets('shows Light label for 40-59', (tester) async {
      final m = ComputedMetrics(
        scores: const ComputedScores(sleepQuality: 50),
        baselines: const ComputedBaselines(),
        dataConfidence: 'medium',
      );
      await tester.pumpWidget(_wrap(SleepArchitectureCard(computed: m)));

      expect(find.text('Light'), findsOneWidget);
    });

    testWidgets('shows Disrupted label for < 40', (tester) async {
      final m = ComputedMetrics(
        scores: const ComputedScores(sleepQuality: 30),
        baselines: const ComputedBaselines(),
        dataConfidence: 'medium',
      );
      await tester.pumpWidget(_wrap(SleepArchitectureCard(computed: m)));

      expect(find.text('Disrupted'), findsOneWidget);
    });
  });
}
