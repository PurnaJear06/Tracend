import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/train/workout_repository.dart';

String _readFixture(String name) {
  final file = File('test/contract/fixtures/$name');
  if (!file.existsSync()) {
    throw FileSystemException('Contract fixture not found: $name');
  }
  return file.readAsStringSync();
}

Map<String, dynamic> _loadFixtureJson(String name) {
  final raw = _readFixture(name);
  final parsed = json.decode(raw);
  if (parsed is! Map<String, dynamic>) {
    throw FormatException('Contract fixture "$name" must be a JSON object');
  }
  return parsed;
}

extension on List<dynamic> {
  List<Map<String, dynamic>> toMapList() =>
      map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>)).toList();
}

void main() {
  group('Training Hub contract — get_my_training_hub v1.3', () {
    const fixture = 'training_hub_v1_3.json';

    test('fixture is valid JSON and top-level shape', () {
      final json = _loadFixtureJson(fixture);

      expect(json['schema_version'], '1.3');
      expect(json['active_plan'], isA<Map>());
      expect(json['workouts'], isA<List>());
      expect(json['recent_sessions'], isA<List>());
      expect(json['adherence'], isA<Map>());
      expect(json['progression'], isA<List>());
      expect(json['completed_day_set'], isA<List>());
    });

    test('active_plan is parseable', () {
      final json = _loadFixtureJson(fixture);
      final active = Map<String, dynamic>.from(json['active_plan'] as Map);

      expect(active['title'], isA<String>());
      expect(active['start_date'], isA<String>());
    });

    test('workouts list is parseable (matches PlannedWorkout.fromHubJson)', () {
      final json = _loadFixtureJson(fixture);
      final workouts = (json['workouts'] as List).toMapList();

      expect(workouts, isNotEmpty);

      for (final row in workouts) {
        // These fields match the parsing in PlannedWorkout.fromHubJson
        expect(row['id'], isA<String>());
        expect(row['name'], isA<String>());
        expect(row['objective'], isA<String>());
        expect(row['estimated_minutes'], isA<num>());
        expect(row['exercises'], isA<List>());

        for (final item in (row['exercises'] as List).toMapList()) {
          // Matches PlannedExercise parsing
          expect(item['order'], isA<num>());
          expect(item['name'], isA<String>());
          expect(item['set_count'], isA<num>());
          expect(item['rep_min'], isA<num>());
          expect(item['rep_max'], isA<num>());

          // weekday, warm_up, cooldown_cardio are optional on PlannedWorkout
          if (row.containsKey('weekday')) expect(row['weekday'], isA<num>());
        }
      }
    });

    test('recent_sessions are parseable', () {
      final json = _loadFixtureJson(fixture);
      final sessions = (json['recent_sessions'] as List).toMapList();

      expect(sessions, isNotEmpty);

      for (final row in sessions) {
        // Matches TrainingSessionSummary parsing
        expect(row['name'], isA<String>());
        expect(row['local_date'], isA<String>());
        // local_date must be parseable as DateTime
        expect(
          () => DateTime.parse(row['local_date'] as String),
          returnsNormally,
        );
      }
    });

    test('adherence metrics are parseable', () {
      final json = _loadFixtureJson(fixture);
      final adherence = Map<String, dynamic>.from(json['adherence'] as Map);

      expect(adherence['completed_sessions'], isA<num>());
      expect(adherence['planned_sessions'], isA<num>());
    });

    test('progression list is parseable', () {
      final json = _loadFixtureJson(fixture);
      final progression = (json['progression'] as List).toMapList();

      expect(progression, isNotEmpty);

      for (final row in progression) {
        // Matches ExerciseProgression parsing
        expect(row['exercise'], isA<String>());
        expect(row['sessions'], isA<num>());
      }
    });

    test('completed_day_set contains parseable date strings', () {
      final json = _loadFixtureJson(fixture);
      final completedDays = json['completed_day_set'] as List;

      for (final day in completedDays) {
        expect(day, isA<String>());
        expect(() => DateTime.parse(day as String), returnsNormally);
      }
    });
  });

  group('Training Hub contract — get_my_training_hub v1.4', () {
    const fixture = 'training_hub_v1_4.json';

    test('fixture is valid JSON and top-level shape', () {
      final json = _loadFixtureJson(fixture);

      expect(json['schema_version'], '1.4');
      expect(json['active_plan'], isA<Map>());
      expect(json['workouts'], isA<List>());
      expect(json['recent_sessions'], isA<List>());
      expect(json['adherence'], isA<Map>());
      expect(json['progression'], isA<List>());
      expect(json['completed_day_set'], isA<List>());
    });

    test('computed metrics field is present and parseable', () {
      final json = _loadFixtureJson(fixture);

      final computed = Map<String, dynamic>.from(json['computed'] as Map);
      expect(computed, isNotNull);

      if (computed['acwr'] != null) {
        expect(computed['acwr'], isA<num>());
      }
      if (computed['training_monotony'] != null) {
        expect(computed['training_monotony'], isA<num>());
      }
      if (computed['today_strain'] != null) {
        expect(computed['today_strain'], isA<num>());
      }
      if (computed['recovery_score'] != null) {
        expect(computed['recovery_score'], isA<num>());
        expect(computed['recovery_score'], greaterThanOrEqualTo(0));
        expect(computed['recovery_score'], lessThanOrEqualTo(100));
      }
      if (computed['recovery_breakdown'] != null) {
        final breakdown = Map<String, dynamic>.from(
          computed['recovery_breakdown'] as Map,
        );
        expect(breakdown['hrv_z'], isA<num>());
        expect(breakdown['resp_rate_z'], isA<num>());
        expect(breakdown['prev_strain_z'], isA<num>());
      }
      if (computed['sleep_quality'] != null) {
        expect(computed['sleep_quality'], isA<num>());
      }
      if (computed['sleep_debt_minutes'] != null) {
        expect(computed['sleep_debt_minutes'], isA<num>());
      }
    });

    test('v1.4 retains all v1.3 fields', () {
      final json = _loadFixtureJson(fixture);
      final workouts = (json['workouts'] as List).toMapList();
      expect(workouts, isNotEmpty);
      for (final row in workouts) {
        expect(row['id'], isA<String>());
        expect(row['name'], isA<String>());
        expect(row['objective'], isA<String>());
        expect(row['exercises'], isA<List>());
      }
    });

    test('recent_sessions carry workout_id for detail wiring', () {
      final json = _loadFixtureJson(fixture);
      final sessions = (json['recent_sessions'] as List).toMapList();
      expect(sessions, isNotEmpty);
      for (final row in sessions) {
        expect(row['name'], isA<String>());
        expect(row['local_date'], isA<String>());
        // Matches TrainingSessionSummary parsing (nullable on older payloads)
        if (row.containsKey('workout_id')) {
          expect(row['workout_id'], isA<String>());
        }
      }
    });

    test('completed_day_set contains parseable date strings', () {
      final json = _loadFixtureJson(fixture);
      final completedDays = json['completed_day_set'] as List;
      for (final day in completedDays) {
        expect(day, isA<String>());
        expect(() => DateTime.parse(day as String), returnsNormally);
      }
    });
  });

  group('Training Hub contract — get_my_training_hub v1.5', () {
    const fixture = 'training_hub_v1_5.json';

    test('v1.5 adds a nullable starting load to every exercise', () {
      final json = _loadFixtureJson(fixture);
      expect(json['schema_version'], '1.5');
      final workouts = (json['workouts'] as List).toMapList();
      final exercises = (workouts.first['exercises'] as List).toMapList();
      expect(exercises.first['target_load_kg'], 82.5);
      final parsed = PlannedWorkout.fromHubJson(workouts.first);
      expect(parsed.exercises.first.targetLoadKg, 82.5);
      for (final exercise in exercises.skip(1)) {
        expect(exercise['target_load_kg'], anyOf(isNull, isA<num>()));
      }
    });
  });

  group('Training Hub contract — get_my_training_hub v1.6', () {
    const fixture = 'training_hub_v1_6.json';

    test('v1.6 keeps every v1.5 field, so installed builds still parse it', () {
      final json = _loadFixtureJson(fixture);
      expect(json['schema_version'], '1.6');
      final workouts = (json['workouts'] as List).toMapList();
      final parsed = PlannedWorkout.fromHubJson(workouts.first);
      expect(parsed.exercises.first.targetLoadKg, 72.5);
      expect(json['recent_sessions'], isA<List>());
      expect(json['completed_day_set'], isA<List>());
    });

    test('the plan reports its dates and progression rule', () {
      final plan = _loadFixtureJson(fixture)['active_plan'] as Map;
      expect(
        () => DateTime.parse(plan['effective_date'] as String),
        returnsNormally,
      );
      expect(
        () => DateTime.parse(plan['approved_on'] as String),
        returnsNormally,
      );
      expect(plan['progression_rule'], anyOf(isNull, isA<String>()));
    });

    test('exercises report a nullable slug and their catalog muscles', () {
      final json = _loadFixtureJson(fixture);
      final workouts = (json['workouts'] as List).toMapList();
      const muscles = {
        'quads',
        'glutes',
        'hamstrings',
        'chest',
        'back',
        'shoulders',
        'biceps',
        'triceps',
        'core',
        'calves',
      };
      for (final workout in workouts) {
        for (final exercise in (workout['exercises'] as List).toMapList()) {
          expect(exercise['exercise_slug'], anyOf(isNull, isA<String>()));
          final list = exercise['primary_muscles'] as List;
          expect(list.every(muscles.contains), isTrue);
          if (exercise['exercise_slug'] == null) expect(list, isEmpty);
        }
      }
    });

    test('recent sessions report completion and effort sources', () {
      final sessions = (_loadFixtureJson(fixture)['recent_sessions'] as List)
          .toMapList();
      for (final row in sessions) {
        expect(row['completion_source'], anyOf(isNull, 'manual', 'healthkit'));
        expect(
          row['effort_source'],
          anyOf(isNull, 'athlete', 'legacy_default', 'healthkit_default'),
        );
      }
    });

    test('daily_load has 28 consecutive days ending on local_today', () {
      final json = _loadFixtureJson(fixture);
      final days = (json['daily_load'] as List).toMapList();
      expect(days, hasLength(28));
      expect(days.last['local_date'], json['local_today']);
      for (var i = 1; i < days.length; i++) {
        final previous = DateTime.parse(days[i - 1]['local_date'] as String);
        final current = DateTime.parse(days[i]['local_date'] as String);
        expect(current.difference(previous).inDays, 1);
      }
      for (final day in days) {
        final recorded = day['recorded'] as bool;
        final level = day['level'];
        expect(level, anyOf(isNull, 'rest', 'easy', 'moderate', 'hard'));
        expect(day['reference'], anyOf('personal', 'fixed'));
        if (!recorded) expect(level, 'rest');
        // A day without athlete-reported effort never gets an intensity.
        if (recorded && day['effort_reported'] != true) expect(level, isNull);
      }
    });
  });

  group('Exercise history contract — get_my_exercise_history v1.0', () {
    const fixture = 'exercise_history_v1_0.json';

    test('each exercise has a kind, last session, best set and top sets', () {
      final json = _loadFixtureJson(fixture);
      expect(json['schema_version'], '1.0');
      expect(json['sessions_limit'], inInclusiveRange(1, 12));
      for (final row in (json['exercises'] as List).toMapList()) {
        expect(row['key'], isA<String>());
        expect(row['kind'], anyOf(isNull, 'load', 'reps', 'assistance'));
        expect(row['top_sets'], isA<List>());
        if (row['kind'] == null) {
          expect(row['last_session'], isNull);
          expect(row['best_set'], isNull);
          expect(row['top_sets'], isEmpty);
          continue;
        }
        final best = row['best_set'] as Map;
        expect(best['kind'], row['kind']);
        expect(best['repetitions'], isA<int>());
        if (row['kind'] == 'reps') expect(best['load_kg'], isNull);
        // Assistance is help from the machine: less is better, so the best
        // set has the least assistance of any ranked set.
        if (row['kind'] == 'assistance') {
          final tops = (row['top_sets'] as List).toMapList();
          for (final top in tops) {
            expect((best['load_kg'] as num) <= (top['load_kg'] as num), isTrue);
          }
        }
        final last = row['last_session'] as Map;
        expect(
          () => DateTime.parse(last['local_date'] as String),
          returnsNormally,
        );
        expect(last['sets'], isNotEmpty);
      }
    });
  });
}
