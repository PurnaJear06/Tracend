import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/widgets/weight_trend_card.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

final _now = DateTime(2026, 8, 25);

final _weighIns = [
  BodyMeasurement(date: DateTime(2026, 8, 1), weightKg: 80),
  BodyMeasurement(date: DateTime(2026, 8, 15), weightKg: 79.2),
  BodyMeasurement(date: DateTime(2026, 8, 22), weightKg: 79),
];

ComputedMetrics _metrics({double? trend7, double? trend28, double? r2}) =>
    ComputedMetrics(
      scores: ComputedScores(
        weightTrend7d: trend7,
        weightTrend28d: trend28,
        weightTrendR2: r2,
      ),
      baselines: const ComputedBaselines(),
      dataConfidence: 'medium',
    );

Widget _wrap(Widget child) => MaterialApp(
  theme: TracendTheme.dark,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

WeightHeroCard _card({
  List<BodyMeasurement>? weighIns,
  ComputedMetrics? computed,
  String? goal,
}) {
  final values = weighIns ?? _weighIns;
  return WeightHeroCard(
    measurements: values,
    periodMeasurements: values,
    computed: computed,
    goal: goal,
    onRecord: () {},
    now: _now,
  );
}

Color? _changeColor(WidgetTester tester) =>
    tester.widget<Text>(find.textContaining('since 1 Aug')).style?.color;

Color? _changeFill(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .ancestor(
          of: find.textContaining('since 1 Aug'),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).color;
}

void main() {
  testWidgets('shows the latest weigh-in, change, and weekly rate', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(_card(computed: _metrics(trend7: -0.05, trend28: -0.04, r2: 0.8))),
    );
    expect(find.text('79.0 kg'), findsWidgets);
    expect(find.text('Last weigh-in · Sat 22 Aug'), findsOneWidget);
    expect(find.text('1.0 kg since 1 Aug'), findsOneWidget);
    expect(find.text('−0.3 kg/week'), findsOneWidget);
    expect(find.text('Steady trend'), findsOneWidget);
    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('WEIGHT'), findsNothing);
    expect(find.textContaining('kg/day'), findsNothing);
    expect(find.textContaining('R²'), findsNothing);
  });

  testWidgets('falls back to the 7-day rate without an R² label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(_card(computed: _metrics(trend7: 0.1, r2: 0.9))),
    );
    expect(find.text('+0.7 kg/week'), findsOneWidget);
    expect(find.text('Steady trend'), findsNothing);
  });

  testWidgets('hides the rate when the server has no trend', (tester) async {
    await tester.pumpWidget(_wrap(_card(computed: _metrics())));
    expect(find.textContaining('kg/week'), findsNothing);
    expect(find.text('1.0 kg since 1 Aug'), findsOneWidget);
  });

  testWidgets('the change takes the lime signal only toward the goal', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_card(goal: 'fat_loss')));
    expect(_changeColor(tester), TracendColors.dark.accentSignalInk);
    expect(_changeFill(tester), TracendColors.dark.accentSignalTint);
    expect(
      find.bySemanticsLabel('Down 1.0 kg since 1 Aug, toward your goal'),
      findsOneWidget,
    );

    await tester.pumpWidget(_wrap(_card(goal: 'muscle_gain')));
    expect(_changeColor(tester), TracendColors.dark.textPrimary);
    expect(_changeFill(tester), TracendColors.dark.surfaceRaised);

    await tester.pumpWidget(_wrap(_card(goal: 'strength')));
    expect(_changeColor(tester), TracendColors.dark.textPrimary);
  });

  testWidgets('one weigh-in asks for another instead of drawing a trend', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_card(weighIns: [_weighIns.last])));
    expect(find.text('Record one more weigh-in to see your trend.'), findsOne);
    expect(find.textContaining('since'), findsNothing);
  });

  testWidgets('no weigh-ins shows the first-weigh-in prompt', (tester) async {
    await tester.pumpWidget(_wrap(_card(weighIns: const [])));
    expect(find.text('Add your first weigh-in'), findsOneWidget);
    expect(find.text('Record measurement'), findsOneWidget);
  });

  testWidgets('the explainer opens as a titled sheet', (tester) async {
    await tester.pumpWidget(_wrap(_card()));
    await tester.tap(find.byTooltip('How this is calculated'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(TracendSheetHeader),
        matching: find.text('How this is calculated'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Nothing here is estimated by AI'), findsOne);
  });

  test('goal direction and steadiness wording', () {
    expect(goalWeightDirection('fat_loss'), -1);
    expect(goalWeightDirection('muscle_gain'), 1);
    expect(goalWeightDirection('recomposition'), 0);
    expect(goalWeightDirection(null), 0);
    expect(trendSteadinessLabel(0.6), 'Steady trend');
    expect(trendSteadinessLabel(0.3), 'Some day-to-day variation');
    expect(trendSteadinessLabel(0.29), 'Too noisy to call yet');
  });
}
