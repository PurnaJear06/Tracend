/// The heart-rate profile (coaching platform chunk C3): resting heart rate, an
/// estimated maximum, zones and recovery after sets. Deterministic arithmetic
/// over stored summaries; heart rate informs and never sets a load or a
/// prescription (program decision D9). Sleeping heart rate is not an input
/// (D10, shadow mode).
///
/// The TypeScript twin is
/// `supabase/functions/_shared/training/heart_rate/profile.ts`; both read the
/// cases in `profile_cases.json`, so they cannot drift apart.
library;

import 'package:flutter/foundation.dart';

/// Tanaka, Monahan and Seals (2001), "Age-predicted maximal heart rate
/// revisited", J Am Coll Cardiol 37(1):153-156: 208 - 0.7 x age. Their sample
/// covered 18 to 81 years with a residual of about 10 bpm; the formula is used
/// for 16 to 90.
const tanakaIntercept = 208;
const tanakaSlope = 0.7;
const formulaMinAge = 16;
const formulaMaxAge = 90;
const tanakaResidualBpm = 10;

/// An observed peak replaces the formula only when it comes from a Watch
/// workout, has enough readings and coverage, and is plausible: at least 120
/// bpm and at most the formula plus two residuals (210 with no age).
const peakMinimumBpm = 120;
const peakCeilingWithoutAgeBpm = 210;
const peakMinimumSamples = 8;
const peakMinimumCoverage = 0.6;

/// Zones from heart-rate reserve (Karvonen, Kentala and Mustala 1957,
/// Ann Med Exp Biol Fenn 35:307): resting + fraction x (maximum - resting).
/// Five bands in 10-point steps from 50% to 100% of reserve, the five-zone
/// layout common to heart-rate watches; the intensity anchors agree with the
/// ACSM Guidelines (moderate 40-59% of reserve, vigorous 60-89%, near-maximal
/// 90% and above). Below 50% is no zone.
const zoneLabels = ['Easy', 'Aerobic', 'Tempo', 'Hard', 'Maximum'];
const zoneCutFractions = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0];
const minimumReserveBpm = 20;

/// Resting heart rate: the median of the last 14 days, from at least 3 days.
const restingWindowDays = 14;
const restingMinimumDays = 3;
const restingMinBpm = 30;
const restingMaxBpm = 120;

/// Recovery after sets: the drop in the minute after a set, the last 28 days
/// against the 28 before. A trend of the athlete against themselves; there is
/// no threshold for a set of lifting. A set counts when it has the drop,
/// covered at least 60% and ended at least 20 bpm above resting (100 bpm when
/// resting is unknown).
const recoveryWindowDays = 28;
const recoveryMinimumSets = 6;
const recoveryMinimumCoverage = 0.6;
const recoveryElevationBpm = 20;
const recoveryElevationWithoutRestingBpm = 100;
const recoveryTrendBpm = 3;

/// One set's summary as `get_my_heart_rate_inputs_v1` returns it.
@immutable
class HeartRateSetRow {
  const HeartRateSetRow({
    required this.localDate,
    required this.coverage,
    required this.sampleCount,
    required this.source,
    this.startBpm,
    this.peakBpm,
    this.endBpm,
    this.drop30sBpm,
    this.drop60sBpm,
  });

  static HeartRateSetRow? tryParse(Object? value) {
    if (value is! Map) return null;
    final date = value['local_date'];
    final coverage = value['coverage'];
    final samples = value['sample_count'];
    final source = value['source'];
    if (date is! String ||
        _parseDay(date) == null ||
        coverage is! num ||
        samples is! num ||
        (source != 'watch_workout' && source != 'background')) {
      return null;
    }
    return HeartRateSetRow(
      localDate: date,
      coverage: coverage.toDouble(),
      sampleCount: samples.toInt(),
      source: source as String,
      startBpm: _number(value['start_bpm']),
      peakBpm: _number(value['peak_bpm']),
      endBpm: _number(value['end_bpm']),
      drop30sBpm: _number(value['drop_30s_bpm']),
      drop60sBpm: _number(value['drop_60s_bpm']),
    );
  }

  final String localDate;
  final double? startBpm;
  final double? peakBpm;
  final double? endBpm;
  final double? drop30sBpm;
  final double? drop60sBpm;
  final double coverage;
  final int sampleCount;

  /// `watch_workout` or `background`.
  final String source;
}

/// The stored values the profile is worked out from.
@immutable
class HeartRateInputs {
  const HeartRateInputs({
    required this.asOf,
    required this.birthYear,
    required this.resting,
    required this.sets,
    required this.peakCandidates,
  });

  /// Reads the RPC payload; null when it is not an inputs object. Malformed
  /// rows are dropped, never repaired.
  static HeartRateInputs? tryParse(Object? value) {
    if (value is! Map) return null;
    final asOf = value['as_of'];
    if (asOf is! String || _parseDay(asOf) == null) return null;
    List<T> rows<T>(Object? list, T? Function(Object?) read) => [
      for (final item in list is List ? list : const <Object?>[])
        if (read(item) case final T parsed) parsed,
    ];
    return HeartRateInputs(
      asOf: asOf,
      birthYear: _number(value['birth_year'])?.toInt(),
      resting: rows(value['resting'], (item) {
        if (item is! Map) return null;
        final date = item['local_date'];
        final bpm = _number(item['bpm']);
        if (date is! String || _parseDay(date) == null || bpm == null) {
          return null;
        }
        return RestingHeartRateDay(localDate: date, bpm: bpm);
      }),
      sets: rows(value['sets'], HeartRateSetRow.tryParse),
      peakCandidates: rows(value['peak_candidates'], HeartRateSetRow.tryParse),
    );
  }

  final String asOf;
  final int? birthYear;
  final List<RestingHeartRateDay> resting;

  /// Sets of the last 60 days, for the recovery trend.
  final List<HeartRateSetRow> sets;

  /// The sets with the highest peaks of the last 365 days.
  final List<HeartRateSetRow> peakCandidates;
}

@immutable
class RestingHeartRateDay {
  const RestingHeartRateDay({required this.localDate, required this.bpm});

  final String localDate;
  final double bpm;
}

enum MaxHeartRateBasis { observed, ageFormula, missing }

enum ZonesMissing { noResting, noMax, narrowReserve }

enum RecoveryState { improving, steady, slower, notEnoughData }

@immutable
class HeartRateZone {
  const HeartRateZone({
    required this.zone,
    required this.label,
    required this.lowBpm,
    required this.highBpm,
  });

  final int zone;
  final String label;
  final int lowBpm;
  final int highBpm;
}

@immutable
class HeartRateProfile {
  const HeartRateProfile({
    required this.asOf,
    required this.ageYears,
    required this.restingBpm,
    required this.restingDays,
    required this.maxBpm,
    required this.maxBasis,
    required this.formulaBpm,
    required this.observedBpm,
    required this.observedOn,
    required this.zones,
    required this.zonesMissing,
    required this.recoveryState,
    required this.recentDrop60sBpm,
    required this.priorDrop60sBpm,
    required this.recoveryChangeBpm,
    required this.recentSets,
    required this.priorSets,
  });

  final String asOf;
  final int? ageYears;
  final int? restingBpm;
  final int restingDays;
  final int? maxBpm;
  final MaxHeartRateBasis maxBasis;
  final int? formulaBpm;
  final int? observedBpm;
  final String? observedOn;
  final List<HeartRateZone> zones;
  final ZonesMissing? zonesMissing;
  final RecoveryState recoveryState;
  final double? recentDrop60sBpm;
  final double? priorDrop60sBpm;
  final double? recoveryChangeBpm;
  final int recentSets;
  final int priorSets;

  /// The same shape the TypeScript twin returns (`profile_cases.json`).
  Map<String, Object?> toJson() => {
    'schema_version': '1.0',
    'as_of': asOf,
    'age_years': ageYears,
    'resting': {'bpm': restingBpm, 'days': restingDays},
    'max': {
      'bpm': maxBpm,
      'basis': switch (maxBasis) {
        MaxHeartRateBasis.observed => 'observed',
        MaxHeartRateBasis.ageFormula => 'age_formula',
        MaxHeartRateBasis.missing => 'missing',
      },
      'formula_bpm': formulaBpm,
      'observed_bpm': observedBpm,
      'observed_on': observedOn,
    },
    'zones': [
      for (final zone in zones)
        {
          'zone': zone.zone,
          'label': zone.label,
          'low_bpm': zone.lowBpm,
          'high_bpm': zone.highBpm,
        },
    ],
    'zones_missing': switch (zonesMissing) {
      ZonesMissing.noResting => 'no_resting',
      ZonesMissing.noMax => 'no_max',
      ZonesMissing.narrowReserve => 'narrow_reserve',
      null => null,
    },
    'recovery': {
      'state': switch (recoveryState) {
        RecoveryState.improving => 'improving',
        RecoveryState.steady => 'steady',
        RecoveryState.slower => 'slower',
        RecoveryState.notEnoughData => 'not_enough_data',
      },
      'recent_drop_60s_bpm': recentDrop60sBpm,
      'prior_drop_60s_bpm': priorDrop60sBpm,
      'change_bpm': recoveryChangeBpm,
      'recent_sets': recentSets,
      'prior_sets': priorSets,
    },
  };
}

double? _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

DateTime? _parseDay(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  return DateTime.tryParse('${value}T00:00:00Z');
}

int _daysBetween(String from, String to) =>
    _parseDay(to)!.difference(_parseDay(from)!).inDays;

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

double _oneDecimal(double value) => (value * 10).round() / 10;

/// Age in whole years on [asOf], or null when there is no birth year or the
/// age is outside the ages the formula covers.
int? profileAgeYears(int? birthYear, String asOf) {
  if (birthYear == null) return null;
  final age = int.parse(asOf.substring(0, 4)) - birthYear;
  return age >= formulaMinAge && age <= formulaMaxAge ? age : null;
}

/// Tanaka et al. (2001): 208 - 0.7 x age, to a whole beat.
int tanakaMaxHeartRate(int age) =>
    (tanakaIntercept - tanakaSlope * age).round();

/// Whether a set's peak can stand as the observed maximum.
bool isTrustedPeak(HeartRateSetRow row, int? formulaBpm) {
  final peak = row.peakBpm;
  if (peak == null || row.source != 'watch_workout') return false;
  if (row.sampleCount < peakMinimumSamples ||
      row.coverage < peakMinimumCoverage) {
    return false;
  }
  final ceiling = formulaBpm == null
      ? peakCeilingWithoutAgeBpm
      : formulaBpm + 2 * tanakaResidualBpm;
  return peak >= peakMinimumBpm && peak <= ceiling;
}

/// Karvonen zones; empty when the reserve is too narrow.
List<HeartRateZone> heartRateZones(int resting, int max) {
  final reserve = max - resting;
  if (reserve < minimumReserveBpm) return const [];
  final cuts = [
    for (final fraction in zoneCutFractions)
      (resting + fraction * reserve).round(),
  ];
  return [
    for (var i = 0; i < zoneLabels.length; i++)
      HeartRateZone(
        zone: i + 1,
        label: zoneLabels[i],
        lowBpm: cuts[i],
        highBpm: i == zoneLabels.length - 1 ? cuts[i + 1] : cuts[i + 1] - 1,
      ),
  ];
}

/// The profile from the stored inputs; anything missing stays missing and
/// nothing is invented.
HeartRateProfile buildHeartRateProfile(HeartRateInputs inputs) {
  final age = profileAgeYears(inputs.birthYear, inputs.asOf);
  final formula = age == null ? null : tanakaMaxHeartRate(age);

  final restingValues = [
    for (final row in inputs.resting)
      if (_daysBetween(row.localDate, inputs.asOf) >= 0 &&
          _daysBetween(row.localDate, inputs.asOf) < restingWindowDays &&
          row.bpm >= restingMinBpm &&
          row.bpm <= restingMaxBpm)
        row.bpm,
  ];
  final resting = restingValues.length >= restingMinimumDays
      ? _median(restingValues).round()
      : null;

  HeartRateSetRow? observed;
  for (final row in inputs.peakCandidates) {
    if (!isTrustedPeak(row, formula)) continue;
    if (observed == null || row.peakBpm! > observed.peakBpm!) observed = row;
  }
  final observedBpm = observed?.peakBpm?.round();
  final useObserved =
      observedBpm != null && (formula == null || observedBpm > formula);
  final maxBpm = useObserved ? observedBpm : formula;
  final basis = useObserved
      ? MaxHeartRateBasis.observed
      : formula != null
      ? MaxHeartRateBasis.ageFormula
      : MaxHeartRateBasis.missing;

  final zonesMissing = resting == null
      ? ZonesMissing.noResting
      : maxBpm == null
      ? ZonesMissing.noMax
      : maxBpm - resting < minimumReserveBpm
      ? ZonesMissing.narrowReserve
      : null;

  final floor = resting == null
      ? recoveryElevationWithoutRestingBpm
      : resting + recoveryElevationBpm;
  final recent = <double>[];
  final prior = <double>[];
  for (final row in inputs.sets) {
    final drop = row.drop60sBpm;
    final end = row.endBpm;
    if (drop == null ||
        end == null ||
        row.coverage < recoveryMinimumCoverage ||
        end < floor) {
      continue;
    }
    final age = _daysBetween(row.localDate, inputs.asOf);
    if (age >= 0 && age < recoveryWindowDays) {
      recent.add(drop);
    } else if (age >= recoveryWindowDays && age < 2 * recoveryWindowDays) {
      prior.add(drop);
    }
  }
  final recentDrop = recent.length >= recoveryMinimumSets
      ? _oneDecimal(_median(recent))
      : null;
  final priorDrop = prior.length >= recoveryMinimumSets
      ? _oneDecimal(_median(prior))
      : null;
  final change = recentDrop != null && priorDrop != null
      ? _oneDecimal(recentDrop - priorDrop)
      : null;
  final state = change == null
      ? RecoveryState.notEnoughData
      : change >= recoveryTrendBpm
      ? RecoveryState.improving
      : change <= -recoveryTrendBpm
      ? RecoveryState.slower
      : RecoveryState.steady;

  return HeartRateProfile(
    asOf: inputs.asOf,
    ageYears: age,
    restingBpm: resting,
    restingDays: restingValues.length,
    maxBpm: maxBpm,
    maxBasis: basis,
    formulaBpm: formula,
    observedBpm: observedBpm,
    observedOn: observed?.localDate,
    zones: zonesMissing == null ? heartRateZones(resting!, maxBpm!) : const [],
    zonesMissing: zonesMissing,
    recoveryState: state,
    recentDrop60sBpm: recentDrop,
    priorDrop60sBpm: priorDrop,
    recoveryChangeBpm: change,
    recentSets: recent.length,
    priorSets: prior.length,
  );
}
