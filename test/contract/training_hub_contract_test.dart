import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

    test('workouts list is parseable (matches _workoutFromJson)', () {
      final json = _loadFixtureJson(fixture);
      final workouts = (json['workouts'] as List).toMapList();

      expect(workouts, isNotEmpty);

      for (final row in workouts) {
        // These fields match the parsing in SupabaseWorkoutRepository._workoutFromJson
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
        expect(() => DateTime.parse(row['local_date'] as String), returnsNormally);
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
}
