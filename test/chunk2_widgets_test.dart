import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_insight_card.dart';
import 'package:tracend/shared/widgets/date_pill_strip.dart';
import 'package:tracend/shared/widgets/intensity_bar.dart';
import 'package:tracend/shared/widgets/targets_grid.dart';

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

CoachDecision _decision() => CoachDecision(
  id: 'decision-1',
  localDate: '2026-08-23',
  trainingAction: 'Proceed',
  trainingSummary: 'Training stays as planned.',
  nutritionAction: 'Keep intake unchanged',
  nutritionSummary: 'Prioritize protein across your remaining meals.',
  finalDecision: 'Keep the approved plan.',
  reason: 'Evidence supports the current plan.',
  confidence: 'high',
  evidence: const [],
  missingData: const [],
  riskFlags: const [],
  createdAt: DateTime(2026, 8, 23),
);

void main() {
  group('DatePillStrip', () {
    testWidgets('renders seven day pills for the current week', (tester) async {
      final selected = DateTime(2026, 8, 19);
      await tester.pumpWidget(
        _wrap(DatePillStrip(selectedDate: selected, onSelectedDate: (_) {})),
      );
      for (var day = 17; day <= 23; day++) {
        expect(find.byKey(ValueKey('date-pill-2026-08-$day')), findsOneWidget);
      }
    });

    testWidgets('tapping a pill reports the normalized date', (tester) async {
      DateTime? picked;
      await tester.pumpWidget(
        _wrap(
          DatePillStrip(
            selectedDate: DateTime(2026, 8, 19),
            onSelectedDate: (date) => picked = date,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('date-pill-2026-08-21')));
      expect(picked, DateTime(2026, 8, 21));
    });

    testWidgets('chevrons appear only when callbacks are provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          DatePillStrip(
            selectedDate: DateTime(2026, 8, 19),
            onSelectedDate: (_) {},
          ),
        ),
      );
      expect(find.byKey(const ValueKey('date-strip-previous')), findsNothing);
      expect(find.byKey(const ValueKey('date-strip-next')), findsNothing);

      await tester.pumpWidget(
        _wrap(
          DatePillStrip(
            selectedDate: DateTime(2026, 8, 19),
            onSelectedDate: (_) {},
            onPreviousWeek: () {},
            onNextWeek: () {},
          ),
        ),
      );
      expect(find.byKey(const ValueKey('date-strip-previous')), findsOneWidget);
      expect(find.byKey(const ValueKey('date-strip-next')), findsOneWidget);
    });

    testWidgets('disabled pill does not fire selection', (tester) async {
      DateTime? picked;
      await tester.pumpWidget(
        _wrap(
          DatePillStrip(
            selectedDate: DateTime(2026, 8, 19),
            onSelectedDate: (date) => picked = date,
            isDateEnabled: (date) => date.day != 21,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('date-pill-2026-08-21')));
      expect(picked, isNull);
      await tester.tap(find.byKey(const ValueKey('date-pill-2026-08-20')));
      expect(picked, DateTime(2026, 8, 20));
    });

    test('mondayOf normalizes to the week start', () {
      expect(mondayOf(DateTime(2026, 8, 19)), DateTime(2026, 8, 17));
      expect(mondayOf(DateTime(2026, 8, 17)), DateTime(2026, 8, 17));
      expect(mondayOf(DateTime(2026, 8, 23)), DateTime(2026, 8, 17));
    });
  });

  group('IntensityBar', () {
    testWidgets('shows honest cold start when there are no entries', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const IntensityBar(entries: [])));
      expect(find.text('Log a session to see intensity'), findsOneWidget);
      expect(find.text('Planned RPE'), findsNothing);
    });

    testWidgets('renders planned RPE bars for every entry', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const IntensityBar(
            entries: [
              IntensityBarEntry(name: 'Squat', targetRpe: 8),
              IntensityBarEntry(name: 'Press', targetRpe: 7.5),
            ],
          ),
        ),
      );
      expect(find.text('Squat'), findsOneWidget);
      expect(find.text('Press'), findsOneWidget);
      expect(find.textContaining('RPE 8'), findsOneWidget);
      expect(find.textContaining('RPE 7.5'), findsOneWidget);
    });

    testWidgets('shows recorded RPE marker text when present', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const IntensityBar(
            entries: [
              IntensityBarEntry(name: 'Squat', targetRpe: 8, recordedRpe: 9.0),
            ],
          ),
        ),
      );
      expect(find.textContaining('logged 9.0'), findsOneWidget);
    });

    testWidgets('shows strain context line only when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const IntensityBar(
            entries: [IntensityBarEntry(name: 'Squat', targetRpe: 8)],
            dailyStrain: 42.3,
          ),
        ),
      );
      expect(find.textContaining('STRAIN 42.3'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(
          const IntensityBar(
            entries: [IntensityBarEntry(name: 'Squat', targetRpe: 8)],
          ),
        ),
      );
      expect(find.textContaining('STRAIN'), findsNothing);
    });
  });

  group('TargetsGrid', () {
    testWidgets('shows consumed vs target with remaining protein', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TargetsGrid(
            summary: NutritionSummary(
              calories: 1620,
              protein: 108,
              carbohydrate: 172,
              fat: 48,
              confirmedMeals: 3,
            ),
            targets: NutritionTargets(
              calories: 2200,
              protein: 160,
              carbohydrate: 240,
              fat: 70,
            ),
          ),
        ),
      );
      expect(find.text('1620'), findsOneWidget);
      expect(find.text('/ 2200 kcal'), findsOneWidget);
      expect(find.text('108'), findsOneWidget);
      expect(find.text('52g left'), findsOneWidget);
      expect(find.text('172'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
      expect(find.text('74%'), findsOneWidget);
    });

    testWidgets('no targets shows honest note, no fabricated bars', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TargetsGrid(
            summary: NutritionSummary(
              calories: 540,
              protein: 35,
              carbohydrate: 62,
              fat: 18,
              confirmedMeals: 1,
            ),
            targets: null,
          ),
        ),
      );
      expect(find.text('540 kcal logged'), findsOneWidget);
      expect(find.text('No active nutrition target is set.'), findsOneWidget);
      expect(find.text('PROTEIN'), findsNothing);
    });

    testWidgets('cold start shows targets with zero consumed', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TargetsGrid(
            summary: null,
            targets: NutritionTargets(
              calories: 2200,
              protein: 160,
              carbohydrate: 240,
              fat: 70,
            ),
          ),
        ),
      );
      expect(find.text('0'), findsWidgets);
      expect(find.text('/ 2200 kcal'), findsOneWidget);
      expect(find.text('160g left'), findsOneWidget);
    });
  });

  group('NutritionInsightCard', () {
    testWidgets('shows real decision fields and confidence', (tester) async {
      await tester.pumpWidget(
        _wrap(NutritionInsightCard(decision: _decision())),
      );
      expect(find.text('Keep intake unchanged'), findsOneWidget);
      expect(
        find.text('Prioritize protein across your remaining meals.'),
        findsOneWidget,
      );
      expect(find.text('Confidence: high'), findsOneWidget);
    });
  });
}
