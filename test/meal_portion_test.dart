import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_sheets.dart';

/// The Munch label case the server tests use
/// (supabase/functions/_shared/meal_vision/packaged_test.ts): the app must
/// recalculate the same portions from the stored per-gram values.
final Map<String, dynamic> _golden =
    jsonDecode(
          File(
            'supabase/functions/_shared/meal_vision/munch_label_golden.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

/// A `meal_analysis_candidates` row as the table returns the stored values.
Map<String, dynamic> _row(Map<String, dynamic> stored, {String id = 'c1'}) => {
  'id': id,
  'food_label': stored['name'],
  ...stored,
};

MealCandidate get _munch =>
    MealCandidate.fromRow(_row(_golden['stored'] as Map<String, dynamic>));

const _rice = MealCandidate(
  id: 'c2',
  name: 'Rice bowl',
  servingLabel: '1 bowl',
  calories: 520,
  protein: 24.5,
  carbohydrate: 72,
  fat: 14,
  confidence: 'medium',
  source: MealSource.estimate,
  assumptions: ['About 1 tsp of oil'],
  question: 'Was the rice fried?',
);

Future<void> _openSheet(
  WidgetTester tester,
  List<MealCandidate> candidates, {
  void Function(List<MealCandidate>?)? onConfirmed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final confirmed = await Navigator.of(context)
                  .push<List<MealCandidate>>(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        body: CandidateSheet(
                          candidates: candidates,
                          onDiscard: () async {},
                        ),
                      ),
                    ),
                  );
              onConfirmed?.call(confirmed);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('portion math', () {
    test('the stored row reads back with its per-gram values and sizes', () {
      final munch = _munch;
      expect(munch.source, MealSource.label);
      expect(munch.perGram!.kcal, 5.23);
      expect(munch.servingGrams, 18.7);
      expect(munch.packGrams, 37.4);
      expect(munch.portionGrams, 37.4);
      expect(munch.labelIssues, isEmpty);
      expect(munch.question, contains('whole bar'));
    });

    test('golden: one serving and the whole pack match the server', () {
      final munch = _munch;
      final options = portionOptions(
        servingGrams: munch.servingGrams,
        packGrams: munch.packGrams,
      );
      final expected = (_golden['portion_options'] as List)
          .cast<Map<String, dynamic>>();
      expect(options, hasLength(expected.length));
      for (var i = 0; i < options.length; i++) {
        final values = munch.perGram!.scale(options[i].grams);
        final want = expected[i]['nutrients'] as Map<String, dynamic>;
        expect(options[i].label, expected[i]['label']);
        expect(options[i].grams, expected[i]['grams']);
        expect(values.calories, want['kcal']);
        expect(values.protein, want['protein_g']);
        expect(values.carbohydrate, want['carbohydrate_g']);
        expect(values.fat, want['fat_g']);
      }
      // The whole bar, not the printed half-bar serving.
      expect(munch.perGram!.scale(37.4).calories, 195.6);
    });

    test('labels and the starting portion follow the stored grams', () {
      expect(portionLabel(PortionKind.grams, 125.25), '125.3 g');
      expect(portionLabel(PortionKind.pack, 40), 'Whole pack (40 g)');
      expect(
        initialPortionKind(
          portionGrams: 18.7,
          servingGrams: 18.7,
          packGrams: 37.4,
        ),
        PortionKind.serving,
      );
      expect(
        initialPortionKind(
          portionGrams: 100,
          servingGrams: null,
          packGrams: null,
        ),
        PortionKind.grams,
      );
      expect(portionOptions(servingGrams: 30, packGrams: 30), hasLength(1));
    });

    test('a row stored before the packaged columns reads as before', () {
      final legacy = MealCandidate.fromRow({
        'id': 'old',
        'food_label': 'Dal',
        'serving_label': '1 bowl',
        'calories': 180,
        'protein_g': 9,
        'carbohydrate_g': 24,
        'fat_g': 5,
        'confidence': 'low',
      });
      expect(legacy.source, isNull);
      expect(legacy.perGram, isNull);
      expect(legacy.assumptions, isEmpty);
      expect(legacy.question, '');
    });
  });

  group('review sheet', () {
    testWidgets('a label starts at the whole pack and recalculates portions', (
      tester,
    ) async {
      List<MealCandidate>? confirmed;
      await _openSheet(tester, [
        _munch,
      ], onConfirmed: (value) => confirmed = value);
      expect(find.text('From label'), findsOneWidget);
      expect(find.text('How much did you eat?'), findsOneWidget);
      expect(
        find.text('Whole pack (37.4 g) · 195.6 kcal · High confidence'),
        findsOneWidget,
      );

      await tester.tap(find.text('1 serving'));
      await tester.pumpAndSettle();
      expect(
        find.text('1 serving (18.7 g) · 97.8 kcal · High confidence'),
        findsOneWidget,
      );

      await tester.tap(find.text('Grams'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('portion-grams')), '50');
      await tester.pumpAndSettle();
      expect(find.text('50 g · 261.5 kcal · High confidence'), findsOneWidget);

      await tester.ensureVisible(find.text('Confirm selected foods'));
      await tester.tap(find.text('Confirm selected foods'));
      await tester.pumpAndSettle();
      final food = confirmed!.single;
      expect(food.servingLabel, '50 g');
      expect(food.calories, 261.5);
      expect(food.protein, 4.1);
      expect(food.carbohydrate, 28.8);
      expect(food.fat, 14.5);
    });

    testWidgets('too many grams are refused and leave the values alone', (
      tester,
    ) async {
      await _openSheet(tester, [_munch]);
      await tester.tap(find.text('Grams'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('portion-grams')),
        '9000',
      );
      await tester.pumpAndSettle();
      expect(find.text('Enter 1 to 5000 g'), findsOneWidget);
      expect(find.textContaining('9000 g ·'), findsNothing);
    });

    testWidgets('an estimate says so, shows the notes and has no chooser', (
      tester,
    ) async {
      await _openSheet(tester, [_rice]);
      expect(find.text('Estimated'), findsOneWidget);
      expect(find.text('From label'), findsNothing);
      expect(find.text('How much did you eat?'), findsNothing);
      expect(find.text('Assumed: About 1 tsp of oil'), findsOneWidget);
      expect(find.text('Question: Was the rice fried?'), findsOneWidget);
      expect(find.textContaining('These are estimates'), findsOneWidget);
    });

    testWidgets('a label that did not add up is unclear and says why', (
      tester,
    ) async {
      final unclear = MealCandidate.fromRow(
        _row({
          ...(_golden['stored'] as Map<String, dynamic>),
          'source': 'label_unverified',
          'confidence': 'low',
          'label_issues': ['energy_mismatch'],
        }),
      );
      await _openSheet(tester, [unclear]);
      expect(find.text('Label unclear'), findsOneWidget);
      expect(
        find.text('Check these numbers against the pack:'),
        findsOneWidget,
      );
      expect(
        find.text(
          "• The calories don't match the protein, carbs and fat on the label.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('a row from before sources has no badge', (tester) async {
      await _openSheet(tester, [
        const MealCandidate(
          id: 'old',
          name: 'Dal',
          servingLabel: '1 bowl',
          calories: 180,
          protein: 9,
          carbohydrate: 24,
          fat: 5,
          confidence: 'low',
        ),
      ]);
      for (final label in ['From label', 'Label unclear', 'Estimated']) {
        expect(find.text(label), findsNothing);
      }
    });
  });
}
