import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/goals/goal_target.dart';

Map<String, dynamic> _loadFixtureJson(String name) {
  final file = File('test/contract/fixtures/$name');
  if (!file.existsSync()) {
    throw FileSystemException('Contract fixture not found: $name');
  }
  final parsed = json.decode(file.readAsStringSync());
  if (parsed is! Map<String, dynamic>) {
    throw FormatException('Contract fixture "$name" must be a JSON object');
  }
  return parsed;
}

void main() {
  group(
    'Goal target contract — get_goal_target_v1 / set_goal_target_v1 1.0',
    () {
      // The key lists are the contract: add keys, never remove or rename them.
      // The same lists are asserted against the database in
      // supabase/tests/database/goal_targets_test.sql.
      const responseKeys = [
        'goal_type',
        'has_goal',
        'has_target',
        'min_target_weight_kg',
        'schema_version',
        'target',
      ];
      const targetKeys = [
        'body_fat_pct_max',
        'body_fat_pct_min',
        'date',
        'physique',
        'physique_note',
        'set_at',
        'weight_kg',
      ];

      for (final name in const [
        'goal_target_v1_0.json',
        'goal_target_none_v1_0.json',
      ]) {
        test('$name carries exactly the contract keys', () {
          final fixture = _loadFixtureJson(name);
          expect(fixture['schema_version'], '1.0');
          expect(fixture.keys.toList()..sort(), responseKeys);
          expect(
            (fixture['target'] as Map<String, dynamic>).keys.toList()..sort(),
            targetKeys,
          );
        });
      }

      test('a set target parses into its parts', () {
        final state = GoalTargetState.fromJson(
          _loadFixtureJson('goal_target_v1_0.json'),
        )!;
        expect(state.hasGoal, isTrue);
        expect(state.hasTarget, isTrue);
        expect(state.goalType, 'fat_loss');
        expect(state.minTargetWeightKg, 59.9);
        expect(state.target.weightKg, 72);
        expect(state.target.physique, 'visible_abs');
        expect(state.target.physiqueNote, 'for summer');
        expect(state.target.date, DateTime(2027, 2, 14));
        expect(
          state.target.summary,
          '72 kg · Visible abs (for summer) · by 14 Feb 2027',
        );
      });

      test('a goal without a target asks for one', () {
        final state = GoalTargetState.fromJson(
          _loadFixtureJson('goal_target_none_v1_0.json'),
        )!;
        expect(state.hasGoal, isTrue);
        expect(state.hasTarget, isFalse);
        expect(state.target.isSet, isFalse);
      });

      test('a payload from another major version is not read', () {
        final fixture = _loadFixtureJson('goal_target_v1_0.json');
        expect(
          GoalTargetState.fromJson({...fixture, 'schema_version': '2.0'}),
          isNull,
        );
        expect(GoalTargetState.fromJson(null), isNull);
      });

      test('a date alone is not a target', () {
        expect(GoalTarget(date: DateTime(2027, 2, 14)).isSet, isFalse);
      });
    },
  );
}
