import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/today/computed_metrics.dart';

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

void main() {
  group('Daily Brief contract — get_my_daily_brief v1.1', () {
    const fixture = 'daily_brief_v1_1.json';

    test('fixture is valid JSON and top-level shape', () {
      final json = _loadFixtureJson(fixture);

      expect(json['schema_version'], '1.1');
      expect(json['local_date'], isA<String>());
      expect(json['today_workout'], isA<Map>());
      expect(json['check_in'], isA<Map>());
      expect(json['health'], isA<Map>());
      expect(json['computed'], isA<Map>());
    });

    test('computed.scores includes recovery breakdown with all z-scores', () {
      final json = _loadFixtureJson(fixture);
      final computed = Map<String, dynamic>.from(json['computed'] as Map);
      final scores = Map<String, dynamic>.from(computed['scores'] as Map);
      final breakdown =
          Map<String, dynamic>.from(scores['recovery_breakdown'] as Map);

      expect(breakdown['hrv_z'], isA<num>());
      expect(breakdown['rhr_z'], isA<num>());
      expect(breakdown['sleep_z'], isA<num>());
      expect(breakdown['resp_rate_z'], isA<num>());
      expect(breakdown['prev_strain_z'], isA<num>());
    });

    test('computed.scores includes sleep breakdown', () {
      final json = _loadFixtureJson(fixture);
      final computed = Map<String, dynamic>.from(json['computed'] as Map);
      final scores = Map<String, dynamic>.from(computed['scores'] as Map);
      final sleepBreakdown =
          Map<String, dynamic>.from(scores['sleep_breakdown'] as Map);

      expect(sleepBreakdown['duration_score'], isA<num>());
      expect(sleepBreakdown['efficiency_score'], isA<num>());
      expect(sleepBreakdown['restorative_score'], isA<num>());
      expect(sleepBreakdown['consistency_score'], isA<num>());
    });

    test('computed.scores includes sleep_debt_minutes', () {
      final json = _loadFixtureJson(fixture);
      final computed = Map<String, dynamic>.from(json['computed'] as Map);
      final scores = Map<String, dynamic>.from(computed['scores'] as Map);

      expect(scores['sleep_debt_minutes'], isA<num>());
    });

    test('computed.baselines includes resp_rate_bpm metric', () {
      final json = _loadFixtureJson(fixture);
      final computed = Map<String, dynamic>.from(json['computed'] as Map);
      final baselines =
          Map<String, dynamic>.from(computed['baselines'] as Map);

      expect(baselines['resp_rate_bpm'], isA<Map>());
      final respRate =
          Map<String, dynamic>.from(baselines['resp_rate_bpm'] as Map);
      expect(respRate['ewma'], isA<num>());
      expect(respRate['confidence'], isA<String>());
    });

    test('computed includes data_confidence', () {
      final json = _loadFixtureJson(fixture);
      final computed = Map<String, dynamic>.from(json['computed'] as Map);

      expect(computed['data_confidence'], isA<String>());
    });

    test('recovery score in valid range', () {
      final json = _loadFixtureJson(fixture);
      final computed = Map<String, dynamic>.from(json['computed'] as Map);
      final scores = Map<String, dynamic>.from(computed['scores'] as Map);
      final recovery = scores['recovery'] as num;

      expect(recovery, greaterThanOrEqualTo(0));
      expect(recovery, lessThanOrEqualTo(100));
    });

    test('sleep quality score in valid range', () {
      final json = _loadFixtureJson(fixture);
      final computed = Map<String, dynamic>.from(json['computed'] as Map);
      final scores = Map<String, dynamic>.from(computed['scores'] as Map);

      if (scores['sleep_quality'] != null) {
        final sq = scores['sleep_quality'] as num;
        expect(sq, greaterThanOrEqualTo(0));
        expect(sq, lessThanOrEqualTo(100));
      }
    });

    test('computed maps into ComputedMetrics model', () {
      final json = _loadFixtureJson(fixture);
      final computedRaw = Map<String, dynamic>.from(json['computed'] as Map);
      final m = ComputedMetrics.fromJson(computedRaw);

      expect(m.dataConfidence, 'medium');
      expect(m.scores.recovery, 72);
      expect(m.scores.sleepQuality, 85);
      expect(m.scores.acwr, 1.15);
      expect(m.scores.recoveryBreakdown, isA<RecoveryBreakdown>());
      expect(m.scores.sleepBreakdown, isA<SleepBreakdown>());
      expect(m.baselines.hrv, isA<BaselineMetric>());
      expect(m.baselines.restingHr, isA<BaselineMetric>());
    });

    test('check_in fields parseable', () {
      final json = _loadFixtureJson(fixture);
      final checkIn = Map<String, dynamic>.from(json['check_in'] as Map);

      if (checkIn['sleep_quality'] != null) {
        expect(checkIn['sleep_quality'], isA<num>());
      }
      if (checkIn['energy'] != null) {
        expect(checkIn['energy'], isA<num>());
      }
      if (checkIn['available_to_train'] != null) {
        expect(checkIn['available_to_train'], isA<bool>());
      }
    });
  });

  group('Daily Computed Metrics contract', () {
    const fixture = 'daily_computed_metrics.json';

    test('fixture matches table schema', () {
      final json = _loadFixtureJson(fixture);

      expect(json['id'], isA<String>());
      expect(json['user_id'], isA<String>());
      expect(json['local_date'], isA<String>());
      expect(() => DateTime.parse(json['local_date'] as String),
          returnsNormally);
      expect(json['recovery_score'], isA<num>());
      expect(json['data_confidence'], isA<String>());
      expect(json['scores_jsonb'], isA<Map>());
      expect(json['baseline_snapshot_jsonb'], isA<Map>());
      expect(json['eligibility_jsonb'], isA<Map>());
      expect(json['schema_version'], '2.0');
    });

    test('recovery_score in valid range', () {
      final json = _loadFixtureJson(fixture);
      final rs = json['recovery_score'] as num;
      expect(rs, greaterThanOrEqualTo(0));
      expect(rs, lessThanOrEqualTo(100));
    });

    test('data_confidence is valid enum value', () {
      final json = _loadFixtureJson(fixture);
      expect(
        json['data_confidence'],
        anyOf('cold_start', 'low', 'medium', 'high'),
      );
    });

    test('eligibility_jsonb has valid shape', () {
      final json = _loadFixtureJson(fixture);
      final eligibility =
          Map<String, dynamic>.from(json['eligibility_jsonb'] as Map);

      expect(eligibility['eligibility_version'], 'eligibility-v1');
      expect(
          Map<String, dynamic>.from(eligibility['training_change'] as Map)['eligible'],
          isA<bool>());
      expect(
          Map<String, dynamic>.from(eligibility['nutrition_change'] as Map)['eligible'],
          isA<bool>());
    });

    test('baseline_snapshot_jsonb includes five metrics', () {
      final json = _loadFixtureJson(fixture);
      final baselines =
          Map<String, dynamic>.from(json['baseline_snapshot_jsonb'] as Map);

      expect(baselines.length, 5);
      expect(baselines['hrv_sdnn_ms'], isA<Map>());
      expect(baselines['resting_hr_bpm'], isA<Map>());
      expect(baselines['sleep_minutes'], isA<Map>());
      expect(baselines['weight_kg'], isA<Map>());
      expect(baselines['resp_rate_bpm'], isA<Map>());
    });

    test('scores_jsonb includes new Phase 2 fields', () {
      final json = _loadFixtureJson(fixture);
      final scores =
          Map<String, dynamic>.from(json['scores_jsonb'] as Map);

      expect(scores['recovery'], isA<num>());
      expect(scores['recovery_breakdown'], isA<Map>());
      expect(scores['sleep_quality'], isA<num>());
      expect(scores['sleep_breakdown'], isA<Map>());
      expect(scores['sleep_debt_minutes'], isA<num>());
    });
  });
}
