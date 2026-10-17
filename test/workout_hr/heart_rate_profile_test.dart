import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/workout_hr/heart_rate_profile.dart';

const _casesPath =
    'supabase/functions/_shared/training/heart_rate/profile_cases.json';

List<Map<String, dynamic>> _cases() => [
  for (final item in jsonDecode(File(_casesPath).readAsStringSync()) as List)
    Map<String, dynamic>.from(item as Map),
];

HeartRateSetRow _set({
  String date = '2026-10-10',
  double? peak = 150,
  double? end = 140,
  double? drop60 = 24,
  double coverage = 0.9,
  int samples = 20,
  String source = 'watch_workout',
}) => HeartRateSetRow(
  localDate: date,
  startBpm: 110,
  peakBpm: peak,
  endBpm: end,
  drop30sBpm: 12,
  drop60sBpm: drop60,
  coverage: coverage,
  sampleCount: samples,
  source: source,
);

void main() {
  test('every shared case gives the profile the TypeScript twin expects', () {
    final cases = _cases();
    expect(cases.length, greaterThanOrEqualTo(15));
    for (final given in cases) {
      final inputs = HeartRateInputs.tryParse(given['inputs']);
      expect(inputs, isNotNull, reason: given['name'] as String);
      expect(
        jsonDecode(jsonEncode(buildHeartRateProfile(inputs!).toJson())),
        given['expected'],
        reason: given['name'] as String,
      );
    }
  });

  test('Tanaka 2001 is 208 - 0.7 x age and only for the ages it covers', () {
    expect(tanakaMaxHeartRate(20), 194);
    expect(tanakaMaxHeartRate(36), 183);
    expect(tanakaMaxHeartRate(50), 173);
    expect(profileAgeYears(1990, '2026-10-17'), 36);
    expect(profileAgeYears(null, '2026-10-17'), isNull);
    expect(profileAgeYears(2011, '2026-10-17'), isNull);
    expect(profileAgeYears(2010, '2026-10-17'), 16);
    expect(profileAgeYears(1936, '2026-10-17'), 90);
    expect(profileAgeYears(1935, '2026-10-17'), isNull);
  });

  test('Karvonen zones are resting plus 50 to 100 percent of the reserve', () {
    expect(
      [
        for (final zone in heartRateZones(60, 180))
          [zone.zone, zone.lowBpm, zone.highBpm],
      ],
      [
        [1, 120, 131],
        [2, 132, 143],
        [3, 144, 155],
        [4, 156, 167],
        [5, 168, 180],
      ],
    );
    expect(heartRateZones(60, 70), isEmpty);
  });

  test('a peak needs a Watch workout, readings, coverage and a sane value', () {
    final row = _set(peak: 190);
    expect(isTrustedPeak(row, 183), isTrue);
    expect(isTrustedPeak(_set(peak: 203), 183), isTrue);
    expect(isTrustedPeak(_set(peak: 204), 183), isFalse);
    expect(isTrustedPeak(_set(peak: 119), null), isFalse);
    expect(isTrustedPeak(_set(peak: 190, samples: 7), 183), isFalse);
    expect(isTrustedPeak(_set(peak: 190, coverage: 0.59), 183), isFalse);
    expect(isTrustedPeak(_set(peak: 190, source: 'background'), 183), isFalse);
    expect(isTrustedPeak(_set(peak: null), 183), isFalse);
  });

  test('parsing drops malformed rows and ignores unknown keys', () {
    final inputs = HeartRateInputs.tryParse({
      'as_of': '2026-10-17',
      'birth_year': 1990,
      'resting': [
        {'local_date': '2026-10-16', 'bpm': 58},
        {'local_date': 'bad', 'bpm': 58},
        5,
      ],
      'sets': [
        {
          'local_date': '2026-10-10',
          'coverage': 0.9,
          'sample_count': 20,
          'source': 'watch_workout',
          'drop_60s_bpm': null,
        },
        {
          'local_date': '2026-10-10',
          'coverage': '1',
          'sample_count': 20,
          'source': 'watch_workout',
        },
        {
          'local_date': '2026-10-10',
          'coverage': 1,
          'sample_count': 20,
          'source': 'phone',
        },
      ],
      'peak_candidates': 'none',
      'sleeping_heart_rate': [
        {'local_date': '2026-10-16', 'median_bpm': 40},
      ],
    })!;
    expect(inputs.resting, hasLength(1));
    expect(inputs.sets, hasLength(1));
    expect(inputs.sets.single.drop60sBpm, isNull);
    expect(inputs.peakCandidates, isEmpty);
    expect(HeartRateInputs.tryParse(null), isNull);
    expect(HeartRateInputs.tryParse({'as_of': 'yesterday'}), isNull);
  });
}
