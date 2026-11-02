import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/today/widgets/fuel_rail_card.dart';

/// The schedule a new athlete gets when their first plan is approved
/// (20261102224851_starter_meal_schedule.sql): the app reads it like any other
/// schedule, and Today's rail has meals to spread the protein over instead of
/// "No meal plan is set for today."
Map<String, dynamic> _fixture() =>
    json.decode(
          File(
            'test/contract/fixtures/nutrition_schedule_starter_v1_0.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Future<NutritionSchedule> _load() async {
  final client = SupabaseClient(
    'https://tracend-test.supabase.co',
    'publishable-test',
    httpClient: MockClient((request) async {
      expect(request.url.path, '/rest/v1/rpc/get_my_nutrition_schedule');
      return http.Response(
        jsonEncode(_fixture()),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  return SupabaseNutritionRepository(
    client,
  ).loadSchedule(DateTime(2026, 11, 3));
}

void main() {
  test('get_my_nutrition_schedule 1.0 carries exactly the contract keys', () {
    final fixture = _fixture();
    expect(fixture.keys.toList()..sort(), [
      'items',
      'local_date',
      'schema_version',
      'version',
    ]);
    final first = (fixture['items'] as List).first as Map<String, dynamic>;
    expect(first.keys.toList()..sort(), [
      'foods',
      'id',
      'label',
      'local_time',
      'optional',
      'order',
      'reminder_enabled',
      'slot_key',
      'status',
      'window_minutes',
    ]);
  });

  test('the starting schedule reads as four planned meals', () async {
    final schedule = await _load();

    expect(schedule.title, 'Starting meal schedule');
    expect(schedule.items.map((item) => item.slotKey), [
      'breakfast',
      'lunch',
      'snack',
      'dinner',
    ]);
    expect(schedule.items.map((item) => item.time), [
      '08:00',
      '13:00',
      '16:30',
      '19:30',
    ]);
    expect(schedule.items.map((item) => item.optional), [
      false,
      false,
      true,
      false,
    ]);
  });

  test('its next meal is breakfast, with the split amounts', () async {
    final next = (await _load()).nextMeal!;

    expect(next.label, 'Breakfast');
    expect(next.foods.single['quantity'], 'about 530 kcal and 35 g protein');
    expect(next.reminderEnabled, isFalse);
  });

  test('Today has a plan to spread the protein over', () async {
    final day = FuelDay.from(
      proteinEaten: 0,
      proteinTarget: 150,
      schedule: await _load(),
      loggedMeals: const [],
      now: DateTime(2026, 11, 3, 7, 30),
    );

    expect(day.planLoaded, isTrue);
    expect(day.hasPlan, isTrue);
    expect(day.mealsLeft, 4);
    expect(day.perMeal, 37.5);
  });

  testWidgets('the Fuel rail says how many meals are left, not that there '
      'is no plan', (tester) async {
    final day = FuelDay.from(
      proteinEaten: 0,
      proteinTarget: 150,
      schedule: await _load(),
      loggedMeals: const [],
      now: DateTime(2026, 11, 3, 7, 30),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [TracendColors.dark],
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: FuelRailCard(
              consumed: null,
              targets: const NutritionTargets(
                calories: 2100,
                protein: 150,
                carbohydrate: 235,
                fat: 65,
              ),
              day: day,
              onLog: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('4 meals left, about 38 g each'), findsOneWidget);
    expect(find.text('No meal plan is set for today.'), findsNothing);
  });
}
