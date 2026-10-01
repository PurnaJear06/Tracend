import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/nutrition_screen.dart';
import 'package:tracend/features/nutrition/widgets/meal_cards.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_sheets.dart';

ScheduledMeal _slot(String id, String label, String time, String status) =>
    ScheduledMeal(
      id: id,
      slotKey: id,
      label: label,
      time: time,
      foods: const [
        {'name': 'Rice', 'quantity': '150 g'},
        {'name': 'Chicken', 'quantity': '120 g'},
      ],
      status: status,
      optional: status == 'optional',
      reminderEnabled: false,
    );

MealEntry _meal(
  String id, {
  String type = 'lunch',
  String status = 'confirmed',
  int hour = 13,
  String? slot,
}) => MealEntry(
  id: id,
  type: type,
  status: status,
  source: 'manual',
  loggedAt: DateTime(2026, 10, 1, hour, 15),
  scheduleItemId: slot,
  items: status == 'draft'
      ? const []
      : const [
          MealItem(
            name: 'Chicken rice',
            calories: 612.4,
            protein: 41.2,
            carbohydrate: 70.6,
            fat: 14.1,
          ),
        ],
);

extension on MealEntry {
  MealEntry copyWithItems(List<MealItem> items) => MealEntry(
    id: id,
    type: type,
    status: status,
    source: source,
    loggedAt: loggedAt,
    scheduleItemId: scheduleItemId,
    items: items,
  );
}

void main() {
  group('buildNutritionTimeline', () {
    test('a meal logged from a slot replaces the planned row', () {
      final entries = buildNutritionTimeline(
        [
          _slot('pre', 'Pre-workout', '07:45', 'upcoming'),
          _slot('post', 'Post-workout', '10:00', 'due'),
        ],
        [_meal('m1', hour: 7, slot: 'pre')],
      );
      expect(entries, hasLength(2));
      expect(entries.first.title, 'Pre-workout');
      expect(entries.first.meal?.id, 'm1');
      expect(entries.last.isPlanned, isTrue);
    });

    test('unscheduled meals and drafts join in time order', () {
      final entries = buildNutritionTimeline(
        [_slot('post', 'Post-workout', '10:00', 'due')],
        [
          _meal('dinner', type: 'dinner', hour: 19),
          _meal('draft', status: 'draft', hour: 12),
          _meal('snack', type: 'snack', hour: 8),
        ],
      );
      expect(entries.map((e) => e.title), [
        'Snack',
        'Post-workout',
        'Lunch',
        'Dinner',
      ]);
      expect(entries[2].isDraft, isTrue);
    });

    test('a draft never fills a schedule slot', () {
      final entries = buildNutritionTimeline(
        [_slot('post', 'Post-workout', '10:00', 'due')],
        [_meal('draft', status: 'draft', slot: 'post')],
      );
      expect(entries, hasLength(2));
      expect(entries.where((e) => e.isPlanned), hasLength(1));
    });
  });

  test('MealEntry.fromRow reads embedded items, time, and slot', () {
    final meal = MealEntry.fromRow({
      'id': 'm1',
      'meal_type': 'dinner',
      'status': 'confirmed',
      'source': 'photo_analysis',
      'confirmed_at': '2026-10-01T13:05:00Z',
      'created_at': '2026-10-01T13:00:00Z',
      'nutrition_schedule_item_id': 'slot-1',
      'meal_items': [
        {
          'name_snapshot': 'Dal',
          'calories': 220,
          'protein_g': 12.5,
          'carbohydrate_g': 30,
          'fat_g': 6,
        },
        {
          'name_snapshot': 'Rice',
          'calories': 200,
          'protein_g': 4,
          'carbohydrate_g': 44,
          'fat_g': 0.5,
        },
      ],
    });
    expect(meal.items.map((i) => i.name), ['Dal', 'Rice']);
    expect(meal.calories, 420);
    expect(meal.protein, 16.5);
    expect(meal.scheduleItemId, 'slot-1');
    expect(meal.loggedAt, DateTime.utc(2026, 10, 1, 13, 5).toLocal());
  });

  test('a draft row without items parses with no foods', () {
    final meal = MealEntry.fromRow({
      'id': 'd1',
      'meal_type': 'lunch',
      'status': 'draft',
      'source': 'photo_analysis',
      'confirmed_at': null,
      'created_at': '2026-10-01T12:00:00Z',
      'nutrition_schedule_item_id': null,
      'meal_items': <Object>[],
    });
    expect(meal.items, isEmpty);
    expect(meal.calories, 0);
    expect(meal.loggedAt, isNotNull);
  });

  test('default meal type follows the time of day', () {
    expect(defaultMealType(DateTime(2026, 10, 1, 7)), 'breakfast');
    expect(defaultMealType(DateTime(2026, 10, 1, 10, 29)), 'breakfast');
    expect(defaultMealType(DateTime(2026, 10, 1, 10, 30)), 'lunch');
    expect(defaultMealType(DateTime(2026, 10, 1, 16)), 'snack');
    expect(defaultMealType(DateTime(2026, 10, 1, 17, 30)), 'dinner');
  });

  testWidgets('a full day fits 320pt at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: NutritionScreen(
            repository: _DayRepository(),
            coach: const FixtureCoachRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 30; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byKey(const ValueKey('log-a-meal')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Enter manually'), findsOneWidget);
  });

  testWidgets('every timeline state is announced in words', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: Scaffold(body: NutritionScreen(repository: _DayRepository())),
      ),
    );
    await tester.pumpAndSettle();
    for (final word in ['Logged', 'Needs review', 'Planned']) {
      expect(
        find.bySemanticsLabel(RegExp('(^|\\n)$word\\b', caseSensitive: false)),
        findsWidgets,
        reason: word,
      );
    }
    handle.dispose();
  });

  testWidgets('a split bar sizes macros by energy and speaks grams', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: MacroSplitBar(
              meal: _meal('m', hour: 12).copyWithItems(const [
                MealItem(
                  name: 'Mix',
                  calories: 400,
                  protein: 25,
                  carbohydrate: 25,
                  fat: 20,
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    final widths = [
      for (final box in tester.widgetList<Expanded>(find.byType(Expanded)))
        box.flex,
    ];
    // 100 kcal protein, 100 kcal carbs, 180 kcal fat.
    expect(widths, [263, 263, 474]);
    expect(
      find.bySemanticsLabel(
        'Protein 25 grams, carbohydrate 25 grams, fat 20 grams',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the timeline shows foods, totals, and states in words', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: Scaffold(body: NutritionScreen(repository: _DayRepository())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pre-workout · 612 kcal'), findsOneWidget);
    expect(find.text('Lunch · 612 kcal'), findsOneWidget);
    expect(
      find.text('logged  ·  Chicken rice', findRichText: true),
      findsNWidgets(2),
    );
    expect(find.byType(MacroSplitBar), findsNWidgets(2));
    expect(
      find.textContaining('needs review  ·', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('planned  ·  Rice 150 g · Chicken 120 g', findRichText: true),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('log-scheduled-dinner')), findsOneWidget);
  });
}

class _DayRepository extends FixtureNutritionRepository {
  @override
  Future<NutritionSchedule> loadSchedule(DateTime date) async =>
      NutritionSchedule(
        title: 'Plan',
        items: [
          _slot('pre', 'Pre-workout', '07:45', 'logged'),
          _slot('dinner', 'Dinner', '19:30', 'upcoming'),
        ],
      );

  @override
  Future<List<MealEntry>> loadMeals(DateTime date) async => [
    _meal('m1', type: 'breakfast', hour: 7, slot: 'pre'),
    _meal('m2', hour: 13),
    _meal('d1', status: 'draft', hour: 15),
  ];
}
