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
    test('the stored row reads back with its per-unit values and sizes', () {
      final munch = _munch;
      expect(munch.source, MealSource.label);
      expect(munch.unit, QuantityUnit.grams);
      expect(munch.perUnit!.kcal, 5.23);
      expect(munch.servingSize, 18.7);
      expect(munch.packSize, 37.4);
      expect(munch.portionSize, 37.4);
      expect(munch.labelIssues, isEmpty);
      expect(munch.question, contains('whole bar'));
    });

    test('golden: one serving and the whole pack match the server', () {
      final munch = _munch;
      final options = portionOptions(
        servingSize: munch.servingSize,
        packSize: munch.packSize,
        unit: munch.unit!,
      );
      final expected = (_golden['portion_options'] as List)
          .cast<Map<String, dynamic>>();
      expect(options, hasLength(expected.length));
      for (var i = 0; i < options.length; i++) {
        final values = munch.perUnit!.scale(options[i].size);
        final want = expected[i]['nutrients'] as Map<String, dynamic>;
        expect(options[i].label, expected[i]['label']);
        expect(options[i].size, expected[i]['size']);
        expect(values.calories, want['kcal']);
        expect(values.protein, want['protein_g']);
        expect(values.carbohydrate, want['carbohydrate_g']);
        expect(values.fat, want['fat_g']);
      }
      // The whole bar, not the printed half-bar serving.
      expect(munch.perUnit!.scale(37.4).calories, 195.6);
    });

    test('labels and the starting portion follow the stored portion', () {
      const g = QuantityUnit.grams;
      const ml = QuantityUnit.millilitres;
      expect(portionLabel(PortionKind.amount, 125.25, g), '125.3 g');
      expect(portionLabel(PortionKind.pack, 40, g), 'Whole pack (40 g)');
      expect(portionLabel(PortionKind.serving, 200, ml), '1 serving (200 ml)');
      expect(
        initialPortionKind(
          portionSize: 18.7,
          servingSize: 18.7,
          packSize: 37.4,
          unit: g,
        ),
        PortionKind.serving,
      );
      expect(
        initialPortionKind(
          portionSize: 100,
          servingSize: null,
          packSize: null,
          unit: g,
        ),
        PortionKind.amount,
      );
      // 100 ml is never a typed amount: no portion is chosen.
      expect(
        initialPortionKind(
          portionSize: 100,
          servingSize: null,
          packSize: null,
          unit: ml,
        ),
        isNull,
      );
      expect(
        portionOptions(servingSize: 30, packSize: 30, unit: g),
        hasLength(1),
      );
    });

    test('a portion one meal cannot hold is not storable, by any limit', () {
      const fatty = PerUnitNutrients(
        kcal: 7,
        protein: 0,
        carbohydrate: 0,
        fat: 0.8,
      );
      // 700 g: 4,900 kcal fits, but 560 g of fat does not.
      expect(fatty.scale(700).calories, lessThanOrEqualTo(5000));
      expect(fatty.scale(700).storable, isFalse);
      expect(fatty.scale(100).storable, isTrue);
    });

    test('the confirmation carries the chosen portion, or none', () {
      final munch = _munch;
      expect(munch.toConfirmationJson()['portion_size'], 37.4);
      expect(
        munch.copyWith(portionSize: 18.7).toConfirmationJson()['portion_size'],
        18.7,
      );
      expect(
        munch.copyWith(portionSize: null).toConfirmationJson()['portion_size'],
        isNull,
      );
      // Not passing it keeps it.
      expect(munch.copyWith(calories: 1).portionSize, 37.4);
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
      expect(legacy.perUnit, isNull);
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
      await tester.enterText(
        find.byKey(const ValueKey('portion-amount')),
        '50',
      );
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
      expect(food.portionSize, 50);
    });

    testWidgets('too many grams are refused and leave the values alone', (
      tester,
    ) async {
      await _openSheet(tester, [_munch]);
      await tester.tap(find.text('Grams'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('portion-amount')),
        '9000',
      );
      await tester.pumpAndSettle();
      expect(find.text('Enter 1 to 5000 g'), findsOneWidget);
      expect(find.textContaining('9000 g ·'), findsNothing);
    });

    testWidgets('a pack one meal cannot hold is disabled and says why', (
      tester,
    ) async {
      List<MealCandidate>? confirmed;
      final huge = MealCandidate.fromRow(
        _row({
          ...(_golden['stored'] as Map<String, dynamic>),
          'serving_label': '1 serving (18.7 g)',
          'calories': 97.8,
          'protein_g': 1.5,
          'carbohydrate_g': 10.8,
          'fat_g': 5.4,
          'servings_per_pack': 53.5,
          'pack_size': 1000,
          'portion_size': 18.7,
        }),
      );
      await _openSheet(tester, [
        huge,
      ], onConfirmed: (value) => confirmed = value);
      expect(
        find.text(
          'Whole pack (1000 g) is more than one meal can hold. Log part of '
          'it instead.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Whole pack'));
      await tester.pumpAndSettle();
      // Still the serving: the segment never moves to values it cannot hold.
      expect(
        find.text('1 serving (18.7 g) · 97.8 kcal · High confidence'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Confirm selected foods'));
      await tester.tap(find.text('Confirm selected foods'));
      await tester.pumpAndSettle();
      expect(confirmed!.single.calories, 97.8);
      expect(confirmed!.single.portionSize, 18.7);
    });

    testWidgets('typing a value clears the chosen portion', (tester) async {
      List<MealCandidate>? confirmed;
      await _openSheet(tester, [
        _munch,
      ], onConfirmed: (value) => confirmed = value);
      await tester.tap(find.text('Edit estimate'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Calories'),
        '300',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done editing'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirm selected foods'));
      await tester.tap(find.text('Confirm selected foods'));
      await tester.pumpAndSettle();
      expect(confirmed!.single.calories, 300);
      expect(confirmed!.single.portionSize, isNull);
      expect(confirmed!.single.toConfirmationJson()['portion_size'], isNull);
    });

    testWidgets(
      'a label printed per ml offers only its serving and pack, in ml',
      (tester) async {
        final milk = MealCandidate.fromRow(
          _row({
            ...(_golden['stored'] as Map<String, dynamic>),
            'name': 'Dairyfield Chocolate Milk',
            'serving_label': '1 serving (200 ml)',
            'calories': 150,
            'protein_g': 6.4,
            'carbohydrate_g': 21,
            'fat_g': 4.4,
            'confidence': 'low',
            'source': 'label_unverified',
            'quantity_unit': 'ml',
            'kcal_per_unit': 0.75,
            'protein_per_unit': 0.032,
            'carbohydrate_per_unit': 0.105,
            'fat_per_unit': 0.022,
            'serving_size': 200,
            'servings_per_pack': 1.25,
            'pack_size': 250,
            'portion_size': 200,
            'label_issues': ['volume_basis'],
          }),
        );
        await _openSheet(tester, [milk]);
        expect(find.text('1 serving'), findsOneWidget);
        expect(find.text('Whole pack'), findsOneWidget);
        expect(find.text('Grams'), findsNothing);
        await tester.tap(find.text('Whole pack'));
        await tester.pumpAndSettle();
        expect(
          find.text('Whole pack (250 ml) · 187.5 kcal · Low confidence'),
          findsOneWidget,
        );
        expect(find.textContaining(' g)'), findsNothing);
        expect(find.textContaining('per ml'), findsOneWidget);
      },
    );

    testWidgets(
      'a per-ml label with no printed serving or pack has no chooser',
      (tester) async {
        final milk = MealCandidate.fromRow(
          _row({
            ...(_golden['stored'] as Map<String, dynamic>),
            'serving_label': '100 ml',
            'source': 'label_unverified',
            'confidence': 'low',
            'quantity_unit': 'ml',
            'serving_size': null,
            'servings_per_pack': null,
            'pack_size': null,
            'portion_size': 100,
            'label_issues': ['volume_basis'],
          }),
        );
        await _openSheet(tester, [milk]);
        expect(find.text('How much did you eat?'), findsNothing);
        expect(find.text('Grams'), findsNothing);
      },
    );

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
      // The label guidance, not the plate copy.
      expect(
        find.textContaining('Compare the name and the numbers'),
        findsOneWidget,
      );
      expect(find.textContaining('These are estimates'), findsNothing);
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
