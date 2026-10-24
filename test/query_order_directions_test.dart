import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/train/workout_repository.dart';

/// postgrest-dart sorts descending unless `ascending: true` is passed. These
/// tests pin the `order` each repository read sends, so a direction cannot
/// flip unnoticed. (The Coach thread read is pinned in
/// coach_chat_errors_test.dart.)
class _Recorder {
  /// The `order` query parameter of each GET, by table path.
  final orders = <String, String?>{};

  late final client = SupabaseClient(
    'https://tracend-test.supabase.co',
    'publishable-test',
    httpClient: MockClient((request) async {
      // postgrest-dart appends `.nullslast`; the direction is what matters.
      orders[request.url.path] = request.url.queryParameters['order']
          ?.replaceAll('.nullslast', '');
      return http.Response(
        jsonEncode(
          request.headers['Accept']?.contains('vnd.pgrst.object') == true
              ? {'goal_type': 'build_muscle'}
              : <Object>[],
        ),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}

void main() {
  late _Recorder server;

  setUp(() => server = _Recorder());

  group('progress reads', () {
    test('the active goal is the top priority, priority 1 first', () async {
      await SupabaseProgressRepository(server.client).loadActiveGoal();
      expect(server.orders['/rest/v1/user_goals'], 'priority.asc');
    });

    test('measurements load oldest-first, ties by creation time', () async {
      await SupabaseProgressRepository(server.client).loadMeasurements();
      expect(
        server.orders['/rest/v1/body_measurements'],
        'measured_on.asc,created_at.asc',
      );
    });

    test('photo sets load newest-first with a stable id tie-break', () async {
      await SupabaseProgressRepository(server.client).loadPhotoSets();
      expect(
        server.orders['/rest/v1/progress_photo_sets'],
        'captured_on.desc,created_at.desc,id.asc',
      );
    });
  });

  group('nutrition reads', () {
    test('the day\'s meals load in the order they were logged', () async {
      await SupabaseNutritionRepository(
        server.client,
      ).loadMeals(DateTime(2026, 10, 24));
      expect(server.orders['/rest/v1/meals'], 'created_at.asc');
    });

    test(
      'meal candidates load in the order the analysis ranked them',
      () async {
        await SupabaseNutritionRepository(server.client).loadCandidates('m1');
        expect(
          server.orders['/rest/v1/meal_analysis_candidates'],
          'candidate_order.asc',
        );
      },
    );
  });

  test(
    'today\'s workout is the first one the plan orders for the day',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final repository = SupabaseWorkoutRepository(
        server.client,
        SharedPreferencesAsync(),
      );
      await expectLater(
        repository.loadTodayWorkout(),
        throwsA(isA<FormatException>()),
      );
      expect(server.orders['/rest/v1/planned_workouts'], 'workout_order.asc');
    },
  );
}
