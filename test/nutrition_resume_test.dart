import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/nutrition_screen.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_sheets.dart';
import 'package:tracend/shared/widgets/date_pill_strip.dart';

/// Meals across a night and a quick tap through the days: the screen follows
/// today unless the athlete picked a day, and a reply for a day that is no
/// longer shown never reaches the screen.
class _Meals extends FixtureNutritionRepository {
  _Meals();

  final requested = <DateTime>[];

  /// While set for a day, that day's meals wait for it.
  final gates = <int, Completer<List<MealEntry>>>{};

  @override
  Future<List<MealEntry>> loadMeals(DateTime date) {
    requested.add(date);
    final gate = gates[date.day];
    return gate == null ? super.loadMeals(date) : gate.future;
  }
}

MealEntry _meal(String name) => MealEntry(
  id: name,
  type: 'lunch',
  status: 'confirmed',
  source: 'manual',
  loggedAt: DateTime(2026, 10, 1, 13),
  items: [
    MealItem(name: name, calories: 500, protein: 30, carbohydrate: 50, fat: 10),
  ],
);

void main() {
  late DateTime now;
  late _Meals repository;

  setUp(() {
    now = DateTime(2026, 10, 2, 22);
    repository = _Meals();
  });

  Future<void> pumpMeals(WidgetTester tester, {bool active = true}) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: NutritionScreen(
            repository: repository,
            clock: () => now,
            active: active,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  DateTime shownDay(WidgetTester tester) =>
      tester.widget<DatePillStrip>(find.byType(DatePillStrip)).selectedDate;

  testWidgets('resuming on a new day moves Meals to today and loads it', (
    tester,
  ) async {
    await pumpMeals(tester);
    expect(shownDay(tester).day, 2);
    repository.requested.clear();

    now = DateTime(2026, 10, 3, 8);
    await resume(tester);

    expect(shownDay(tester).day, 3);
    expect(repository.requested.map((d) => d.day), [3]);
  });

  testWidgets('a day the athlete picked stays put across midnight', (
    tester,
  ) async {
    await pumpMeals(tester);
    await tester.tap(find.byKey(const ValueKey('date-pill-2026-10-01')));
    await tester.pumpAndSettle();
    expect(shownDay(tester).day, 1);
    repository.requested.clear();

    now = DateTime(2026, 10, 3, 8);
    await resume(tester);

    expect(shownDay(tester).day, 1);
    // The picked day's data is old by a day: it loads again, as itself.
    expect(repository.requested.map((d) => d.day), [1]);
  });

  testWidgets('picking today again follows today after midnight', (
    tester,
  ) async {
    await pumpMeals(tester);
    await tester.tap(find.byKey(const ValueKey('date-pill-2026-10-01')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('date-pill-2026-10-02')));
    await tester.pumpAndSettle();

    now = DateTime(2026, 10, 3, 8);
    await resume(tester);

    expect(shownDay(tester).day, 3);
  });

  testWidgets('the same day, a few minutes later, is not reloaded', (
    tester,
  ) async {
    await pumpMeals(tester);
    repository.requested.clear();
    now = now.add(const Duration(minutes: 5));
    await resume(tester);
    expect(repository.requested, isEmpty);

    now = now.add(const Duration(minutes: 6));
    await resume(tester);
    expect(repository.requested, hasLength(1));
  });

  testWidgets('opening the tab again reloads data older than a minute', (
    tester,
  ) async {
    await pumpMeals(tester, active: false);
    repository.requested.clear();
    now = now.add(const Duration(minutes: 2));
    await pumpMeals(tester);
    expect(repository.requested, hasLength(1));
  });

  testWidgets('a reply for a day no longer shown is dropped', (tester) async {
    await pumpMeals(tester);
    // Tuesday's meals are slow; Wednesday's are not.
    repository.gates[1] = Completer<List<MealEntry>>();
    await tester.tap(find.byKey(const ValueKey('date-pill-2026-10-01')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('date-pill-2026-10-02')));
    await tester.pumpAndSettle();
    expect(shownDay(tester).day, 2);

    // The slow reply for the first day lands last.
    repository.gates[1]!.complete([_meal('Yesterday curry')]);
    await tester.pumpAndSettle();

    expect(find.text('Yesterday curry'), findsNothing);
    expect(find.textContaining('Yesterday curry'), findsNothing);
  });

  testWidgets('the manual meal sheet opens on the meal of the app\'s clock', (
    tester,
  ) async {
    // An hour whose meal differs from the wall clock's, so only the app's
    // clock can give the right answer.
    now = DateTime(
      2026,
      10,
      2,
      defaultMealType(DateTime.now()) == 'breakfast' ? 20 : 8,
    );
    await pumpMeals(tester);

    await tester.tap(find.text('Log meal').first);
    await tester.pumpAndSettle();

    final sheet = tester.widget<ManualMealSheet>(find.byType(ManualMealSheet));
    expect(sheet.initialMealType, defaultMealType(now));
    expect(sheet.initialMealType, isNot(defaultMealType(DateTime.now())));
  });
}
