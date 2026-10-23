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

const _keys = [
  'answered_at',
  'available',
  'band',
  'cardio',
  'changes',
  'confidence',
  'explanation',
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

const _kinds = ['hold_load', 'reduce_sets', 'swap_to_easy_cardio'];

void main() {
  final fixtures = {
    'none': _fixture('day_adjustment_v1_0_none'),
    'hold': _fixture('day_adjustment_v1_0_hold'),
    'reduce': _fixture('day_adjustment_v1_0_reduce'),
    'cardio': _fixture('day_adjustment_v1_0_cardio'),
    'safety': _fixture('day_adjustment_v1_0_safety'),
    'safetyStarted': _fixture('day_adjustment_v1_0_safety_started'),
    'reasked': _fixture('day_adjustment_v1_0_reasked'),
    'unknown': _fixture('day_adjustment_v1_0_unknown'),
    'answered': _fixture('respond_to_day_adjustment_v1_0'),
  };

  group('get_my_day_adjustment_v1 and respond_to_day_adjustment_v1 1.0', () {
    for (final entry in fixtures.entries) {
      final json = entry.value;
      group(entry.key, () {
        test('carries its schema version and complete key list', () {
          expect(json.keys.toList()..sort(), _keys);
          expect(json['schema_version'], '1.0');
          expect(json['rules_version'], 'readiness-v1');
        });

        test('every change and option has its complete key list', () {
          for (final change in _maps(json['changes'])) {
            expect(change.keys.toList()..sort(), _changeKeys);
            expect(
              change['sets_to'] as int,
              lessThanOrEqualTo(change['sets_from'] as int),
            );
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
              expect(change.keys.toList()..sort(), _changeKeys);
            }
          }
          expect((json['signals'] as Map).keys.toList()..sort(), [
            'recovery_confidence',
            'recovery_low',
            'recovery_mode',
            'recovery_score',
            'sleep_minutes',
          ]);
        });

        test('the kind, status and totals agree', () {
          final kind = json['kind'] as String;
          expect(kind, isIn(['none', ..._kinds]));
          expect(
            json['status'],
            isIn(['none', 'proposed', 'accepted', 'declined']),
          );
          expect(kind == 'none', json['status'] == 'none');
          expect(
            json['cardio'] != null,
            kind == 'swap_to_easy_cardio',
            reason: 'a cardio dose belongs to the easy-cardio kind only',
          );
          expect(
            json['sets_total_to'] as int,
            lessThanOrEqualTo(json['sets_total_from'] as int),
          );
          expect(json['band'], isIn(['green', 'amber', 'red', 'unknown']));
          expect(json['available'], json['unavailable_reason'] == null);
          if (json['safety_route'] != null) {
            expect(kind, 'none');
            expect(json['changes'], isEmpty);
            expect(json['options'], isEmpty);
          }
        });
      });
    }

    test('the proposed kinds say what they change', () {
      final hold = fixtures['hold']!;
      expect(hold['kind'], 'hold_load');
      expect(
        _maps(hold['changes']).first['load_note'],
        "Keep last time's 60 kg",
      );
      expect(hold['sets_total_to'], hold['sets_total_from']);
      final reduce = fixtures['reduce']!;
      expect(reduce['kind'], 'reduce_sets');
      expect([reduce['sets_total_from'], reduce['sets_total_to']], [9, 7]);
      final cardio = fixtures['cardio']!;
      expect(cardio['kind'], 'swap_to_easy_cardio');
      expect((cardio['cardio'] as Map)['vigorous_allowed'], isFalse);
      expect(cardio['sets_total_to'], 0);
    });

    test('a safety day carries its route and no training change', () {
      final safety = fixtures['safety']!;
      expect(safety['safety_route'], 'pain_referral');
      expect(safety['triggers'], ['pain_severe']);
    });

    test('a safety route stands over a started session', () {
      final started = fixtures['safetyStarted']!;
      expect(started['safety_route'], 'pain_referral');
      expect(started['unavailable_reason'], 'session_started');
      expect(started['kind'], 'none');
      expect(started['status'], 'none');
    });

    test('an answer that no longer stands says why', () {
      final previous = Map<String, dynamic>.from(
        fixtures['reasked']!['previous_answer'] as Map,
      );
      expect(previous.keys.toList()..sort(), [
        'answered_at',
        'kind',
        'reason',
        'status',
      ]);
      expect(previous['reason'], isIn(['check_in', 'new_data']));
      expect(previous['kind'], isIn(_kinds));
    });

    test('without a check-in the band is unknown and nothing is proposed', () {
      final unknown = fixtures['unknown']!;
      expect(unknown['band'], 'unknown');
      expect(unknown['confidence'], isNull);
      expect(unknown['kind'], 'none');
      expect((unknown['signals'] as Map)['recovery_low'], isTrue);
    });

    test('an answered adjustment names its origin and the time', () {
      final answered = fixtures['answered']!;
      expect(answered['status'], 'accepted');
      expect(answered['origin'], isIn(['proposed', 'chosen']));
      expect(DateTime.parse(answered['answered_at'] as String).year, 2026);
    });
  });
}
