import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(File('test/contract/fixtures/$name.json').readAsStringSync())
      as Map,
);

List<Map<String, dynamic>> _maps(Object? list) => [
  for (final item in list! as List) Map<String, dynamic>.from(item as Map),
];

// The 1.0 keys of get_my_day_adjustment_v1 plus the two schema 1.1 adds.
const _keys = [
  'answered_at',
  'available',
  'band',
  'cardio',
  'changes',
  'confidence',
  'exercise_joint_options',
  'explanation',
  'joint_states',
  'kind',
  'local_date',
  'missing',
  'options',
  'origin',
  'planned_workout_id',
  'previous_answer',
  'rules_version',
  'safety_route',
  'schema_version',
  'sets_total_from',
  'sets_total_to',
  'signals',
  'status',
  'triggers',
  'unavailable_reason',
  'workout_name',
];

const _changeKeys = [
  'exercise_order',
  'load_kg_from',
  'load_kg_to',
  'load_note',
  'name',
  'planned_exercise_id',
  'reps_from',
  'reps_to',
  'rpe_to',
  'sets_from',
  'sets_to',
];

// An exercise a joint touches carries these as well: all of them, or none.
const _jointKeys = [
  'joint',
  'joint_action',
  'joint_state',
  'range_note_code',
  'range_note_codes',
  'swap_to_name',
  'swap_to_slug',
];

const _kinds = [
  'hold_load',
  'reduce_sets',
  'swap_to_easy_cardio',
  'joint_adjust',
];

const _routes = ['pain_referral', 'urgent', 'clinician_today', 'clinician'];

const _redFlags = [
  'bladder_bowel_saddle',
  'cannot_bear_or_move',
  'chest_or_breath',
  'dislocated_or_cannot_lift',
  'fever_unwell',
  'locks_gives_way',
  'night_pain',
  'numb_weak_limb',
  'pop_or_sudden',
  'rapid_swelling',
];

void _checkChange(Map<String, dynamic> change) {
  final keys = change.keys.toList()..sort();
  final hasJoint = change.containsKey('joint_action');
  expect(
    keys,
    hasJoint ? ([..._changeKeys, ..._jointKeys]..sort()) : _changeKeys,
  );
  expect(
    change['sets_to'] as int,
    lessThanOrEqualTo(change['sets_from'] as int),
  );
  if (!hasJoint) return;
  expect(change['joint_action'], isIn(['swap', 'limit', 'drop']));
  expect(change['joint'], isIn(['knee', 'back', 'shoulder']));
  expect(change['joint_state'], isIn(['held', 'limited', 'watch']));
  expect(change['swap_to_slug'] != null, change['joint_action'] == 'swap');
  expect(change['swap_to_name'] != null, change['joint_action'] == 'swap');
  expect(change['range_note_code'] != null, change['joint_action'] == 'limit');
  expect(change['range_note_codes'] != null, change['joint_action'] == 'limit');
  if (change['joint_action'] == 'limit') {
    expect(change['range_note_codes'], contains(change['range_note_code']));
  }
  if (change['joint_action'] == 'drop') expect(change['sets_to'], 0);
}

void main() {
  final fixtures = {
    'joint': _fixture('day_adjustment_v1_1_joint'),
    'redFlag': _fixture('day_adjustment_v1_1_red_flag'),
  };

  group('get_my_day_adjustment_v1 1.1 (the pain check and joint rules)', () {
    for (final entry in fixtures.entries) {
      final json = entry.value;
      group(entry.key, () {
        test('carries its schema version and complete key list', () {
          expect(json.keys.toList()..sort(), _keys);
          expect(json['schema_version'], '1.1');
          expect(json['rules_version'], 'readiness-v1');
        });

        test('every change and option has its complete key list', () {
          for (final change in _maps(json['changes'])) {
            _checkChange(change);
          }
          for (final option in _maps(json['options'])) {
            expect(option.keys.toList()..sort(), [
              'cardio',
              'changes',
              'explanation',
              'kind',
              'sets_total_to',
            ]);
            expect(option['kind'], isIn(_kinds));
            expect(
              option['cardio'] != null,
              option['kind'] == 'swap_to_easy_cardio',
            );
            for (final change in _maps(option['changes'])) {
              _checkChange(change);
            }
          }
        });

        test('the joint states and swap options have their keys', () {
          for (final state in _maps(json['joint_states'])) {
            expect(state.keys.toList()..sort(), [
              'area',
              'hold_outcome',
              'persistent',
              'severity',
              'since',
              'state',
            ]);
            expect(state['area'], isIn(['knee', 'back', 'shoulder', 'other']));
            expect(state['state'], isIn(['held', 'limited', 'watch']));
            expect(
              state['hold_outcome'],
              state['state'] == 'held'
                  ? isIn(['urgent', 'clinician_today', 'clinician'])
                  : isNull,
            );
            expect(state['severity'] as int, inInclusiveRange(0, 10));
          }
          for (final exercise in _maps(json['exercise_joint_options'])) {
            expect(exercise.keys.toList()..sort(), [
              'exercise_order',
              'joint_options',
              'name',
              'planned_exercise_id',
            ]);
            final options = Map<String, dynamic>.from(
              exercise['joint_options'] as Map,
            );
            expect(options.keys.toList()..sort(), ['back', 'knee', 'shoulder']);
            for (final swap in options.values) {
              if (swap == null) continue;
              expect((swap as Map).keys.toList()..sort(), ['name', 'slug']);
            }
          }
        });
      });
    }

    test('a joint adjustment carries only joint changes and no cardio', () {
      final joint = fixtures['joint']!;
      expect(joint['kind'], 'joint_adjust');
      expect(joint['status'], 'proposed');
      expect(joint['cardio'], isNull);
      expect(joint['safety_route'], isNull);
      for (final change in _maps(joint['changes'])) {
        expect(change['joint_action'], isNotNull);
      }
      expect(
        _maps(joint['options']).map((option) => option['kind']),
        contains('joint_adjust'),
      );
      expect(
        joint['sets_total_to'] as int,
        lessThanOrEqualTo(joint['sets_total_from'] as int),
      );
    });

    test('a red-flag day carries its route, its flags and no change', () {
      final flag = fixtures['redFlag']!;
      expect(flag['safety_route'], isIn(_routes));
      expect(flag['safety_route'], 'clinician_today');
      expect(flag['band'], 'red');
      expect(flag['kind'], 'none');
      expect(flag['status'], 'none');
      expect(flag['changes'], isEmpty);
      expect(flag['options'], isEmpty);
      for (final trigger in flag['triggers'] as List) {
        final text = trigger as String;
        expect(text.startsWith('red_flag:'), isTrue);
        expect(text.substring('red_flag:'.length), isIn(_redFlags));
      }
    });

    test(
      '1.1 only adds keys to 1.0: its payload minus the added keys is a 1.0 payload',
      () {
        final older = _fixture('day_adjustment_v1_0_safety');
        final flag = fixtures['redFlag']!;
        final added = {'exercise_joint_options', 'joint_states'};
        expect(
          flag.keys.where((key) => !added.contains(key)).toSet(),
          older.keys.toSet(),
        );
      },
    );
  });

  group('record_pain_check_v1 1.0', () {
    final pain = _fixture('pain_check_v1_0');

    test('has its complete key list', () {
      expect(pain.keys.toList()..sort(), [
        'area_state',
        'id',
        'outcome',
        'schema_version',
      ]);
      expect(pain['schema_version'], '1.0');
    });

    test('names the outcome and the state of the area', () {
      expect(
        pain['outcome'],
        isIn([
          'urgent',
          'clinician_today',
          'clinician',
          'modify',
          'watch',
          'clear',
        ]),
      );
      expect(pain['area_state'], isIn(['held', 'limited', 'watch', 'none']));
      expect(pain['id'], isA<String>());
    });
  });
}
