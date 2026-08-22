import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/train/training_load_gauge.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      extensions: const [TracendColors.dark],
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

ComputedMetrics _fullMetrics() => ComputedMetrics(
  scores: const ComputedScores(
    acwr: 1.15,
    trainingMonotony: 1.8,
    dailyStrain: 42.0,
  ),
  baselines: const ComputedBaselines(),
  dataConfidence: 'medium',
);

ComputedMetrics _emptyMetrics() => const ComputedMetrics(
  scores: ComputedScores(),
  baselines: ComputedBaselines(),
  dataConfidence: 'cold_start',
);

void main() {
  group('TrainingLoadGauge', () {
    testWidgets('shows ACWR value and Elevated zone', (tester) async {
      await tester.pumpWidget(
        _wrap(TrainingLoadGauge(computed: _fullMetrics())),
      );

      expect(find.textContaining('ACWR 1.15'), findsOneWidget);
      expect(find.text('Elevated'), findsOneWidget);
    });

    testWidgets('shows strain badge', (tester) async {
      await tester.pumpWidget(
        _wrap(TrainingLoadGauge(computed: _fullMetrics())),
      );

      expect(find.textContaining('Strain 42.0'), findsOneWidget);
    });

    testWidgets('shows monotony with Balanced label', (tester) async {
      await tester.pumpWidget(
        _wrap(TrainingLoadGauge(computed: _fullMetrics())),
      );

      expect(find.textContaining('Monotony: 1.8'), findsOneWidget);
      expect(find.textContaining('Balanced'), findsOneWidget);
    });

    testWidgets('shows High monotony warning', (tester) async {
      final m = ComputedMetrics(
        scores: const ComputedScores(acwr: 0.9, trainingMonotony: 2.5),
        baselines: const ComputedBaselines(),
        dataConfidence: 'medium',
      );
      await tester.pumpWidget(_wrap(TrainingLoadGauge(computed: m)));

      expect(find.textContaining('Monotony: 2.5'), findsOneWidget);
      expect(find.textContaining('High'), findsOneWidget);
    });

    testWidgets('shows Elevated risk zone for high ACWR', (tester) async {
      final m = ComputedMetrics(
        scores: const ComputedScores(acwr: 1.4),
        baselines: const ComputedBaselines(),
        dataConfidence: 'medium',
      );
      await tester.pumpWidget(_wrap(TrainingLoadGauge(computed: m)));

      expect(find.text('Elevated'), findsOneWidget);
    });

    testWidgets('shows Undertraining zone for low ACWR', (tester) async {
      final m = ComputedMetrics(
        scores: const ComputedScores(acwr: 0.5),
        baselines: const ComputedBaselines(),
        dataConfidence: 'medium',
      );
      await tester.pumpWidget(_wrap(TrainingLoadGauge(computed: m)));

      expect(find.text('Undertraining'), findsOneWidget);
    });

    testWidgets('shows High risk zone for very high ACWR', (tester) async {
      final m = ComputedMetrics(
        scores: const ComputedScores(acwr: 1.8),
        baselines: const ComputedBaselines(),
        dataConfidence: 'medium',
      );
      await tester.pumpWidget(_wrap(TrainingLoadGauge(computed: m)));

      expect(find.text('High risk'), findsOneWidget);
    });

    testWidgets('shows No data when ACWR is null', (tester) async {
      await tester.pumpWidget(
        _wrap(TrainingLoadGauge(computed: _emptyMetrics())),
      );

      expect(find.text('No data'), findsOneWidget);
    });

    testWidgets('hides monotony when null', (tester) async {
      await tester.pumpWidget(
        _wrap(TrainingLoadGauge(computed: _emptyMetrics())),
      );

      expect(find.textContaining('Monotony'), findsNothing);
    });

    testWidgets('hides strain badge when null', (tester) async {
      await tester.pumpWidget(
        _wrap(TrainingLoadGauge(computed: _emptyMetrics())),
      );

      expect(find.textContaining('Strain'), findsNothing);
    });
  });
}
