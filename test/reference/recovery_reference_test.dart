// Pass 5 reference self-tests: every oracle fixture runs through the
// Dart reference (test/reference/recovery_reference.dart) and the
// result is pinned to the documented constants and the hand-computed
// anchors from the pgTAP suites. The pgTAP parity test
// (supabase/tests/database/reference_parity_test.sql) runs the SAME
// fixtures through the production SQL — reference pins here and SQL
// pins there must agree.
//
// This file is pure Dart — run with `dart test test/reference/` or via
// `flutter test` (it has no Flutter imports either way).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'recovery_reference.dart';

/// Allowance between the reference and SQL floating-point paths.
const double kEpsilon = 0.01;

String _fixtureJson(String name) {
  final file = File('test/reference/fixtures/$name.json');
  if (!file.existsSync()) {
    throw FileSystemException('Reference fixture not found: $name');
  }
  return file.readAsStringSync();
}

ReferenceScenario _scenario(String name) {
  final parsed = jsonDecode(_fixtureJson(name));
  if (parsed is! Map<String, dynamic>) {
    throw FormatException('Fixture "$name" must be a JSON object');
  }
  return ReferenceScenario.fromJson(parsed);
}

void main() {
  group('Recovery reference — documented constants', () {
    test('composite weights sum to 1.0', () {
      expect(
        kWeightHrv + kWeightRhr + kWeightSleep + kWeightResp +
            kWeightPrevStrain,
        moreOrLessEquals(1.0, epsilon: 1e-9),
      );
    });

    test('sleep weights sum to 1.0', () {
      expect(
        kSleepWeightDuration + kSleepWeightEfficiency +
            kSleepWeightRestorative + kSleepWeightConsistency,
        moreOrLessEquals(1.0, epsilon: 1e-9),
      );
    });
  });

  group('Recovery reference — oracle fixtures', () {
    test('zero data → recovery null, all five missing, low confidence', () {
      final result = computeReferenceDay(_scenario('zero_data'));
      final day = result.day;
      expect(day.recovery, isNull);
      expect(day.missingComponents, containsAll([
        'hrv_sdnn',
        'resting_hr',
        'sleep_minutes',
        'resp_rate',
        'prev_strain',
      ]));
      expect(day.dataConfidence, 'low');
    });

    test('owner strain-only day → recovery 62 (composite +0.294, no offset)',
        () {
      final result = computeReferenceDay(_scenario('owner_day_strain_only'));
      final day = result.day;
      // prev7 = 10, avg28 = 11.5, sd28 = sqrt(26) ≈ 5.099
      // z = (10 − 11.5)/5.099 ≈ −0.294; composite = +0.294 → 62.
      expect(day.zPrevStrain, moreOrLessEquals(-0.294, epsilon: 0.001));
      expect(day.recovery, moreOrLessEquals(62, epsilon: 0.5));
      expect(day.missingComponents, containsAll([
        'hrv_sdnn',
        'resting_hr',
        'sleep_minutes',
        'resp_rate',
      ]));
      expect(
        day.missingComponents,
        isNot(contains('prev_strain')),
      );
      expect(day.dataConfidence, 'low');
    });

    test('HRV history + today 62ms → positive z, high recovery', () {
      final result = computeReferenceDay(_scenario('hrv_only_history'));
      final day = result.day;
      expect(day.zHrv, greaterThan(0));
      expect(day.recovery, greaterThan(80));
      expect(day.missingComponents, containsAll([
        'resting_hr',
        'sleep_minutes',
        'resp_rate',
        'prev_strain',
      ]));
    });

    test('HRV today with cold baseline → missing, recovery null', () {
      final result =
          computeReferenceDay(_scenario('hrv_cold_start_today_only'));
      final day = result.day;
      expect(day.recovery, isNull);
      expect(day.missingComponents, contains('hrv_sdnn'));
      expect(
        day.baselines['hrv_sdnn_ms']!.confidence,
        'cold_start',
      );
    });

    test('full data day → all four health z-scores non-zero, high confidence',
        () {
      final result = computeReferenceDay(_scenario('full_data_day'));
      final day = result.day;
      expect(day.zHrv, isNot(0));
      expect(day.zRhr, isNot(0));
      expect(day.zSleep, isNot(0));
      expect(day.zResp, isNot(0));
      expect(day.recovery, isNotNull);
      expect(day.recovery, inInclusiveRange(0, 100));
      expect(day.dataConfidence, 'high');
      expect(day.sleepQuality, isNotNull);
      expect(day.sleepBreakdown, isNotNull);
      expect(day.sleepBreakdownMissing, isEmpty);
      // The fixture seeds 5 history nights + today = 6 sleep nights, below
      // the 7-night gate → duration uses the 480 population floor
      // (SQL: n_obs >= 7 on the sleep baseline). 415/480 ≈ 86.5.
      expect(result.durationScoreFloorUsed, isTrue);
      expect(day.sleepBreakdown!.duration, moreOrLessEquals(86.5, epsilon: 0.5));
    });

    test('long sleep + resp → duration from sleep EWMA, not resp baseline',
        () {
      final result = computeReferenceDay(_scenario('long_sleep_resp_day'));
      final day = result.day;
      expect(result.durationScoreFloorUsed, isFalse);
      // ~522-min EWMA baseline: 500/522*100 ≈ 95.8 — under 100.
      expect(day.sleepBreakdown!.duration, lessThan(100));
      expect(day.sleepQuality, isNotNull);
      expect(day.zResp, isNot(0));
    });

    test('short 300-min night → duration ≈ 57.6 against ~522 baseline', () {
      final result = computeReferenceDay(_scenario('short_night_duration'));
      final day = result.day;
      // 300 / 522 * 100 ≈ 57.47 — the time-invariant form gave ~92.
      expect(day.sleepBreakdown!.duration, moreOrLessEquals(57.5, epsilon: 0.5));
      expect(day.sleepQuality, lessThan(70));
      expect(day.sleepDebtMinutes, isNotNull);
    });

    test('sleep subs partial → efficiency+restorative missing, renorm', () {
      final result = computeReferenceDay(_scenario('sleep_subs_partial'));
      final day = result.day;
      expect(
        day.sleepBreakdownMissing,
        allOf(contains('efficiency'), contains('restorative')),
      );
      expect(day.sleepBreakdown, isNull);
      expect(day.sleepQuality, isNotNull);
      expect(day.sleepQuality, inInclusiveRange(0, 100));
      // Composite = (duration + 0.10*consistency)/0.60 renormalized.
      // duration ~ 411/445*100 ≈ 92.4 (floor not used: 7 nights).
      expect(result.durationScoreFloorUsed, isFalse);
    });

    test('six nights → duration uses 480 population floor (411/480 = 85.6)',
        () {
      final result =
          computeReferenceDay(_scenario('sleep_cold_floor_six_nights'));
      // 6 nights < 7 → 480 floor: 411/480*100 = 85.6 (the pgTAP pin).
      expect(result.durationScoreFloorUsed, isTrue);
      expect(
        result.day.sleepBreakdown!.duration,
        moreOrLessEquals(85.6, epsilon: 0.05),
      );
    });

    test('HRV x3-scaled history → identical ln-domain z to the base history',
        () {
      final base = computeReferenceDay(_scenario('hrv_only_history'));
      final scaled = computeReferenceDay(_scenario('hrv_x3_scale_invariant'));
      expect(
        scaled.day.zHrv,
        moreOrLessEquals(base.day.zHrv, epsilon: 1e-6),
      );
    });

    test('out-of-band today (400ms HRV) → missing, never z-scored', () {
      final result = computeReferenceDay(_scenario('out_of_band_today'));
      final day = result.day;
      expect(day.missingComponents, contains('hrv_sdnn'));
      expect(day.zHrv, 0.0);
      expect(day.recovery, isNull);
      expect(day.dataConfidence, 'low');
    });

    test('out-of-band history (400ms night) → rejected from the fold', () {
      final result = computeReferenceDay(_scenario('plausibility_rejections'));
      // 7 nights seeded, one (400ms) out of band → fold counts 6.
      expect(result.day.baselines['hrv_sdnn_ms']!.nObservations, 6);
    });

    test('ACWR/monotony windows → pinned 1.95 / 2.27 (user-D shape)', () {
      final result = computeReferenceDay(_scenario('acwr_monotony_windows'));
      final day = result.day;
      // 15 strain days (8 at 24, 7 at 36), today rest. Zero-filled acute
      // week: avg7 = 216/7 = 30.86; chronic avg28 = 444/28 = 15.86
      // → ACWR = 1.95 (pgTAP math_honesty pin 10).
      expect(day.acwr, moreOrLessEquals(1.95, epsilon: kEpsilon));
      // Acute week {36×6, 0}: mean 30.86, sd_samp 13.61 → 2.27.
      expect(day.monotony, moreOrLessEquals(2.27, epsilon: kEpsilon));
    });
  });
}
