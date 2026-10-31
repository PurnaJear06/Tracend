import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';

Map<String, dynamic> _fixture(String name) =>
    json.decode(File('test/contract/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('Nutrition contract — get_my_daily_nutrition 1.0', () {
    // The key list is the contract: add keys, never remove or rename them.
    test('daily_nutrition_v1_0.json carries exactly the contract keys', () {
      expect(_fixture('daily_nutrition_v1_0.json').keys.toList()..sort(), [
        'calories',
        'carbohydrate_g',
        'confirmed_meals',
        'fat_g',
        'local_date',
        'protein_g',
        'schema_version',
      ]);
    });

    test('the totals parse into a summary', () {
      final summary = NutritionSummary.fromJson(
        _fixture('daily_nutrition_v1_0.json'),
      );
      expect(summary.calories, 1840);
      expect(summary.protein, 132.5);
      expect(summary.carbohydrate, 190);
      expect(summary.fat, 58);
      expect(summary.confirmedMeals, 3);
    });

    test('an answer from before the version existed still reads', () {
      final fixture = _fixture('daily_nutrition_v1_0.json')
        ..remove('schema_version');
      expect(NutritionSummary.fromJson(fixture).confirmedMeals, 3);
    });

    test('another major version is not read', () {
      expect(
        () => NutritionSummary.fromJson({
          ..._fixture('daily_nutrition_v1_0.json'),
          'schema_version': '2.0',
        }),
        throwsFormatException,
      );
      expect(() => NutritionSummary.fromJson(null), throwsFormatException);
    });
  });

  group('Nutrition contract — create_meal_photo_draft 1.0', () {
    test('meal_photo_draft_v1_0.json carries exactly the contract keys', () {
      expect(_fixture('meal_photo_draft_v1_0.json').keys.toList()..sort(), [
        'meal_id',
        'media_id',
        'object_path',
        'replayed',
        'schema_version',
      ]);
    });

    test('the draft names its meal', () {
      expect(
        mealIdFromDraft(_fixture('meal_photo_draft_v1_0.json')),
        '3f1c2a4e-6b7d-4c8e-9a1b-2d3e4f5a6b7c',
      );
    });

    test('a replay carries only the meal and still reads', () {
      expect(
        mealIdFromDraft({
          'schema_version': '1.0',
          'meal_id': 'meal-1',
          'replayed': true,
        }),
        'meal-1',
      );
    });

    test('another major version or no meal is not read', () {
      expect(
        () => mealIdFromDraft({'schema_version': '2.0', 'meal_id': 'meal-1'}),
        throwsFormatException,
      );
      expect(() => mealIdFromDraft({'replayed': true}), throwsFormatException);
    });
  });
}
