import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/workout_hr/heart_rate_profile.dart';
import 'package:tracend/features/workout_hr/sleeping_heart_rate.dart';

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(File('test/contract/fixtures/$name.json').readAsStringSync())
      as Map,
);

const _setKeys = {
  'local_date',
  'start_bpm',
  'peak_bpm',
  'end_bpm',
  'drop_30s_bpm',
  'drop_60s_bpm',
  'coverage',
  'sample_count',
  'source',
};

void main() {
  group('get_my_heart_rate_inputs_v1 1.0', () {
    final json = _fixture('heart_rate_inputs_v1_0');

    test('carries its schema version and complete top-level keys', () {
      expect(json.keys.toSet(), {
        'schema_version',
        'as_of',
        'birth_year',
        'resting',
        'sets',
        'peak_candidates',
      });
      expect(json['schema_version'], '1.0');
    });

    test('has no sleeping heart rate (shadow mode)', () {
      expect(json.keys.any((key) => key.contains('sleep')), isFalse);
    });

    test('each row carries the complete key list', () {
      for (final row in json['sets'] as List) {
        expect((row as Map).keys.toSet(), _setKeys);
      }
      for (final row in json['peak_candidates'] as List) {
        expect((row as Map).keys.toSet(), _setKeys);
      }
      for (final row in json['resting'] as List) {
        expect((row as Map).keys.toSet(), {'local_date', 'bpm'});
      }
    });

    test('reads into inputs, keeping empty values empty', () {
      final inputs = HeartRateInputs.tryParse(json)!;
      expect(inputs.asOf, '2026-10-17');
      expect(inputs.birthYear, 1990);
      expect(inputs.resting.map((day) => day.bpm), [60.0, 58.0]);
      expect(inputs.sets, hasLength(2));
      expect(inputs.sets.first.drop60sBpm, 27);
      expect(inputs.sets.last.peakBpm, isNull);
      expect(inputs.peakCandidates, hasLength(1));
    });

    test('works out a profile whose missing parts stay missing', () {
      final profile = buildHeartRateProfile(HeartRateInputs.tryParse(json)!);
      expect(profile.ageYears, 36);
      expect(profile.restingBpm, isNull);
      expect(profile.zonesMissing, ZonesMissing.noResting);
      expect(profile.maxBpm, 183);
      expect(profile.recoveryState, RecoveryState.notEnoughData);
    });
  });

  group('persist_sleeping_heart_rate_v1 1.0', () {
    test('carries its schema version and complete key list', () {
      final json = _fixture('persist_sleeping_heart_rate_v1_0');
      expect(json.keys.toSet(), {'schema_version', 'saved', 'skipped'});
      expect(json['schema_version'], '1.0');
    });

    test('a night is sent with exactly the keys the save reads', () {
      const night = SleepingHeartRateNight(
        localDate: '2026-10-16',
        medianBpm: 52,
        lowestBpm: 46,
        sampleCount: 84,
        asleepMinutes: 430,
        coverage: 0.8123,
      );
      expect(night.toJson().keys.toSet(), {
        'local_date',
        'median_bpm',
        'lowest_bpm',
        'sample_count',
        'asleep_minutes',
        'coverage',
      });
      expect(night.toJson()['coverage'], 0.812);
    });
  });
}
