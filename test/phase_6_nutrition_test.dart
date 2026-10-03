import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/nutrition_screen.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

import 'widgets/haptics_recorder.dart';

void main() {
  testWidgets('Nutrition shows confirmed-only totals and timeline', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_NutritionRepository()));
    await tester.pumpAndSettle();
    expect(find.text('From confirmed meals'), findsOneWidget);
    expect(find.text('FROM CONFIRMED MEALS'), findsNothing);
    expect(find.text('540'), findsOneWidget);
    expect(find.textContaining('/ 2200 kcal'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Breakfast · 540 kcal'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Breakfast · 540 kcal'), findsOneWidget);
    expect(
      find.text('Logged  ·  Oats · Greek yogurt', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('confirmed'), findsNothing);
    expect(find.text('breakfast'), findsNothing);
  });

  testWidgets('Nutrition can reopen persisted meals from a previous day', (
    tester,
  ) async {
    final repository = _NutritionRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final key = ValueKey(
      'date-pill-${yesterday.year.toString().padLeft(4, '0')}-'
      '${yesterday.month.toString().padLeft(2, '0')}-'
      '${yesterday.day.toString().padLeft(2, '0')}',
    );
    if (find.byKey(key).evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('date-strip-previous')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    expect(repository.loadedDates.length, greaterThanOrEqualTo(2));
    expect(repository.loadedDates.last.day, yesterday.day);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Today’s meals'.toUpperCase()), findsNothing);
  });

  testWidgets('Manual meal validates fields before confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_NutritionRepository()));
    await tester.pumpAndSettle();
    await _openLogMeal(tester);
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
    await _tapReviewSampleAnalysis(tester);
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
    await _tapReviewSampleAnalysis(tester);
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
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(reviewButton);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Needs review', findRichText: true),
      findsOneWidget,
    );
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
    await _tapReviewSampleAnalysis(tester);
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

  testWidgets('Meal deletion asks in an action sheet, then confirms', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final haptics = recordHaptics(tester);
    final repository = _NutritionRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    final menu = find.byKey(const ValueKey('meal-menu-meal-1'));
    await tester.scrollUntilVisible(
      menu,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('Breakfast · 540 kcal'), findsNWidgets(2));
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoActionSheet),
        matching: find.text('Delete meal'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('Delete this meal?'), findsOneWidget);
    expect(repository.deletedMealId, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.deletedMealId, isNull);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoActionSheet),
        matching: find.text('Delete meal'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoAlertDialog),
        matching: find.text('Delete meal'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.deletedMealId, 'meal-1');
    expect(find.text('Meal deleted'), findsOneWidget);
    expect(haptics, isNot(contains('HapticFeedbackType.successNotification')));
  });

  testWidgets('A confirmed meal plays the success haptic and a toast', (
    tester,
  ) async {
    final haptics = recordHaptics(tester);
    final repository = _NutritionRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await _tapReviewSampleAnalysis(tester);
    expect(haptics, isNot(contains('HapticFeedbackType.successNotification')));
    await tester.ensureVisible(find.text('Confirm selected foods'));
    await tester.tap(find.text('Confirm selected foods'));
    await tester.pumpAndSettle();
    expect(repository.confirmed, isTrue);
    expect(haptics, contains('HapticFeedbackType.successNotification'));
    expect(find.text('Meal logged'), findsOneWidget);
  });

  testWidgets('Log a meal opens as a titled sheet with grouped methods', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_NutritionRepository()));
    await tester.pumpAndSettle();
    await _openLogMeal(tester);
    expect(find.byType(TracendSheetHeader), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TracendSheetHeader),
        matching: find.text('Log a meal'),
      ),
      findsOneWidget,
    );
    expect(find.byType(TracendGroupedList), findsOneWidget);
    expect(find.text('Enter manually'), findsOneWidget);
    await tester.tap(find.byType(TracendSheetCloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(TracendSheetHeader), findsNothing);
  });

  testWidgets('Candidate review fits 320pt at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_app(_NutritionRepository()));
    await tester.pumpAndSettle();
    await _tapReviewSampleAnalysis(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Edit estimate'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Confirm selected foods'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Candidates read their confidence in sentence case', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_NutritionRepository()));
    await tester.pumpAndSettle();
    await _tapReviewSampleAnalysis(tester);
    expect(find.textContaining('Medium confidence'), findsOneWidget);
    expect(find.textContaining('medium confidence'), findsNothing);
  });

  testWidgets('Pull to refresh reloads the day', (tester) async {
    final repository = _NutritionRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    final loads = repository.loadedDates.length;
    await tester.fling(find.text('Nutrition'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(repository.loadedDates.length, greaterThan(loads));
  });

  testWidgets('Choosing a day plays the selection haptic', (tester) async {
    final haptics = recordHaptics(tester);
    await tester.pumpWidget(_app(_NutritionRepository()));
    await tester.pumpAndSettle();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final key = ValueKey(
      'date-pill-${yesterday.year.toString().padLeft(4, '0')}-'
      '${yesterday.month.toString().padLeft(2, '0')}-'
      '${yesterday.day.toString().padLeft(2, '0')}',
    );
    if (find.byKey(key).evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('date-strip-previous')));
      await tester.pumpAndSettle();
      haptics.clear();
    }
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    expect(haptics, ['HapticFeedbackType.selectionClick']);
  });
}

Widget _app(NutritionRepository repository) => MaterialApp(
  theme: TracendTheme.light,
  home: Scaffold(body: NutritionScreen(repository: repository)),
);

Future<void> _openLogMeal(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('log-a-meal'));
  await tester.scrollUntilVisible(
    button,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _tapReviewSampleAnalysis(WidgetTester tester) async {
  await _openLogMeal(tester);
  await tester.tap(find.text('Review sample analysis'));
  await tester.pumpAndSettle();
}

class _NutritionRepository implements NutritionRepository {
  _NutritionRepository({this.includeDraft = false});
  final bool includeDraft;
  static bool _confirmed = false;
  bool get confirmed => _confirmed;
  List<MealCandidate> confirmedCandidates = const [];
  String? confirmedMealId;
  String? deletedMealId;
  final List<DateTime> loadedDates = [];
  @override
  Future<NutritionTargets?> loadTargets() async => const NutritionTargets(
    calories: 2200,
    protein: 150,
    carbohydrate: 240,
    fat: 70,
  );
  @override
  Future<NutritionSummary> loadSummary(DateTime date) async {
    loadedDates.add(date);
    return const NutritionSummary(
      calories: 540,
      protein: 35,
      carbohydrate: 62,
      fat: 18,
      confirmedMeals: 1,
    );
  }

  @override
  Future<List<MealEntry>> loadMeals(DateTime date) async => [
    MealEntry(
      id: 'meal-1',
      type: 'breakfast',
      status: 'confirmed',
      source: 'manual',
      loggedAt: DateTime(date.year, date.month, date.day, 8, 5),
      items: const [
        MealItem(
          name: 'Oats',
          calories: 380,
          protein: 15,
          carbohydrate: 58,
          fat: 9,
        ),
        MealItem(
          name: 'Greek yogurt',
          calories: 160,
          protein: 20,
          carbohydrate: 4,
          fat: 9,
        ),
      ],
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
