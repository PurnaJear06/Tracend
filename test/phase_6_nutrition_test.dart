import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/nutrition_screen.dart';

void main() {
  testWidgets('Nutrition shows confirmed-only totals and timeline', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_NutritionRepository()));
    await tester.pumpAndSettle();
    expect(find.text('Confirmed meals only'), findsOneWidget);
    expect(find.text('540 kcal'), findsOneWidget);
    expect(find.text('breakfast'), findsOneWidget);
    expect(find.text('Enter manually'), findsOneWidget);
  });

  testWidgets('Manual meal validates fields before confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_NutritionRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter manually'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Confirm meal'));
    await tester.tap(find.text('Confirm meal'));
    await tester.pump();
    expect(find.text('Required'), findsNWidgets(2));
    expect(find.text('Enter a valid number'), findsNWidgets(4));
  });

  testWidgets('Fixture candidates require explicit confirmation', (
    tester,
  ) async {
    final repository = _NutritionRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review sample analysis'));
    await tester.pumpAndSettle();
    expect(find.text('Rice bowl'), findsOneWidget);
    expect(find.text('Confirm selected foods'), findsOneWidget);
    expect(repository.confirmed, isFalse);
    await tester.ensureVisible(find.text('Confirm selected foods'));
    await tester.tap(find.text('Confirm selected foods'));
    await tester.pumpAndSettle();
    expect(repository.confirmed, isTrue);
  });

  testWidgets('Fixture candidates can be corrected before confirmation', (
    tester,
  ) async {
    final repository = _NutritionRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review sample analysis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit estimate'));
    await tester.pumpAndSettle();
    final foodName = find.widgetWithText(TextFormField, 'Food name');
    await tester.enterText(foodName, 'Chicken rice bowl');
    await tester.ensureVisible(find.text('Confirm selected foods'));
    await tester.tap(find.text('Confirm selected foods'));
    await tester.pumpAndSettle();
    expect(repository.confirmedCandidates.single.name, 'Chicken rice bowl');
  });

  testWidgets('Existing draft exposes a visible resume editing action', (
    tester,
  ) async {
    final repository = _NutritionRepository(includeDraft: true);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    final reviewButton = find.byKey(const ValueKey('review-meal-draft-1'));
    await tester.scrollUntilVisible(
      reviewButton,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Review & edit draft'), findsOneWidget);
    await tester.tap(reviewButton);
    await tester.pumpAndSettle();
    expect(find.text('Edit estimate'), findsOneWidget);
    await tester.ensureVisible(find.text('Confirm selected foods'));
    await tester.tap(find.text('Confirm selected foods'));
    await tester.pumpAndSettle();
    expect(repository.confirmedMealId, 'draft-1');
  });

  testWidgets('Candidate form dismisses the keyboard outside a field', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_NutritionRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review sample analysis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit estimate'));
    await tester.pumpAndSettle();
    final foodName = find.widgetWithText(TextFormField, 'Food name');
    await tester.tap(foodName);
    await tester.pump();
    final editable = tester.widget<EditableText>(
      find.descendant(of: foodName, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    await tester.tap(find.text('Review candidates'));
    await tester.pump();
    expect(editable.focusNode.hasFocus, isFalse);
  });

  testWidgets('Meal deletion requires confirmation', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _NutritionRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    final deleteButton = find.byKey(const ValueKey('delete-meal-meal-1'));
    await tester.scrollUntilVisible(
      deleteButton,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    expect(find.text('Delete this meal?'), findsOneWidget);
    expect(repository.deletedMealId, isNull);
    await tester.tap(find.text('Delete meal'));
    await tester.pumpAndSettle();
    expect(repository.deletedMealId, 'meal-1');
  });
}

Widget _app(NutritionRepository repository) => MaterialApp(
  theme: TracendTheme.light,
  home: Scaffold(body: NutritionScreen(repository: repository)),
);

class _NutritionRepository implements NutritionRepository {
  _NutritionRepository({this.includeDraft = false});
  final bool includeDraft;
  static bool _confirmed = false;
  bool get confirmed => _confirmed;
  List<MealCandidate> confirmedCandidates = const [];
  String? confirmedMealId;
  String? deletedMealId;
  @override
  Future<NutritionTargets?> loadTargets() async => const NutritionTargets(
    calories: 2200,
    protein: 150,
    carbohydrate: 240,
    fat: 70,
  );
  @override
  Future<NutritionSummary> loadSummary(DateTime date) async =>
      const NutritionSummary(
        calories: 540,
        protein: 35,
        carbohydrate: 62,
        fat: 18,
        confirmedMeals: 1,
      );
  @override
  Future<List<MealEntry>> loadMeals(DateTime date) async => [
    const MealEntry(
      id: 'meal-1',
      type: 'breakfast',
      status: 'confirmed',
      source: 'manual',
    ),
    if (includeDraft)
      const MealEntry(
        id: 'draft-1',
        type: 'lunch',
        status: 'draft',
        source: 'fixture_analysis',
      ),
  ];
  @override
  Future<void> saveManualMeal({
    required DateTime date,
    required String mealType,
    required ManualFoodInput food,
  }) async {}
  @override
  Future<String> createFixtureMeal({
    required DateTime date,
    required String mealType,
  }) async => 'fixture-1';
  @override
  Future<List<MealCandidate>> loadCandidates(String mealId) async => const [
    MealCandidate(
      id: 'candidate-1',
      name: 'Rice bowl',
      servingLabel: '1 bowl',
      calories: 520,
      protein: 24,
      carbohydrate: 72,
      fat: 14,
      confidence: 'medium',
    ),
  ];
  @override
  Future<void> confirmCandidates(
    String mealId,
    List<MealCandidate> candidates,
  ) async {
    _confirmed = true;
    confirmedMealId = mealId;
    confirmedCandidates = candidates;
  }

  @override
  Future<void> deleteMeal(String mealId) async => deletedMealId = mealId;
}
