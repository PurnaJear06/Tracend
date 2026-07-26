import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/progress/weight_trend_indicator.dart';
import 'package:tracend/shared/widgets/metric_sparkline.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      extensions: const [TracendColors.dark],
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('WeightTrendIndicator', () {
    ComputedMetrics metrics({
      double? trend7,
      double? trend28,
      double? r2,
    }) {
      return ComputedMetrics(
        scores: ComputedScores(
          weightTrend7d: trend7,
          weightTrend28d: trend28,
          weightTrendR2: r2,
        ),
        baselines: const ComputedBaselines(),
        dataConfidence: 'medium',
      );
    }

    testWidgets('shows 7-day trend', (tester) async {
      final m = metrics(trend7: -0.0714, trend28: -0.0357, r2: 0.85);
      await tester.pumpWidget(_wrap(WeightTrendIndicator(computed: m)));

      expect(find.textContaining('-0.07 kg/day'), findsOneWidget);
      expect(find.textContaining('0.04 kg/day'), findsOneWidget);
      expect(find.textContaining('0.85'), findsOneWidget);
    });

    testWidgets('shows positive trend', (tester) async {
      final m = metrics(trend7: 0.1);
      await tester.pumpWidget(_wrap(WeightTrendIndicator(computed: m)));

      expect(find.textContaining('+0.1 kg/day'), findsOneWidget);
    });

    testWidgets('shows No data when trends are null', (tester) async {
      final m = metrics();
      await tester.pumpWidget(_wrap(WeightTrendIndicator(computed: m)));

      expect(find.text('No data'), findsOneWidget);
    });

    testWidgets('shows only 7-day when 28-day is null', (tester) async {
      final m = metrics(trend7: -0.05);
      await tester.pumpWidget(_wrap(WeightTrendIndicator(computed: m)));

      expect(find.text('7-day'), findsOneWidget);
      expect(find.text('28-day'), findsNothing);
    });
  });

  group('MetricSparkline', () {
    testWidgets('renders sparkline with multiple values', (tester) async {
      await tester.pumpWidget(_wrap(
        MetricSparkline(
          values: [1.0, 2.0, 1.5, 3.0, 2.5],
          label: 'test sparkline',
        ),
      ));

      expect(find.byType(MetricSparkline), findsOneWidget);
    });

    testWidgets('shows dash for single value', (tester) async {
      await tester.pumpWidget(_wrap(
        MetricSparkline(values: [1.0], label: 'single value'),
      ));

      expect(find.text('\u2014'), findsOneWidget);
    });

    testWidgets('renders empty gracefully', (tester) async {
      await tester.pumpWidget(_wrap(
        MetricSparkline(values: [], label: 'empty'),
      ));

      expect(find.byType(MetricSparkline), findsOneWidget);
    });
  });
}
