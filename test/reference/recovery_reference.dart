/// Reference implementation of the Tracend recovery / sleep / training-load
/// scoring math, written from `docs/ALGORITHMS.md` — NOT from the SQL.
///
/// Pass 5 of the post-review optimization ladder
/// (docs/plans/2026-09-04-optimization-plan.md): the SQL pipeline in
/// `compute_user_baselines` / `compute_daily_metrics` (migration
/// 20260907160000) is the production calculator; this file is an
/// independent re-derivation of the same documented formulas in Dart.
/// Shared oracle fixtures (`fixtures/*.json`) run through BOTH sides and
/// the outputs must agree — that parity test is the drift alarm for every
/// scoring change since Pass 2.
///
/// The file is pure Dart (no Flutter imports) so it can be consumed by
/// plain `dart test` and stays outside the app's dependency graph.
library;

import 'dart:convert';
import 'dart:math' as math;

// ─── Shared constants (pinned once; mirrored in the pgTAP parity test) ───

/// Logistic steepness for the recovery score (ALGORITHMS.md §1).
const double kLogisticK = 1.6;

/// Composite weights (ALGORITHMS.md §1). Sum = 1.0.
const double kWeightHrv = 0.55;
const double kWeightRhr = 0.20;
const double kWeightSleep = 0.15;
const double kWeightResp = 0.05;
const double kWeightPrevStrain = 0.05;

/// Sleep sub-score weights (ALGORITHMS.md §3).
const double kSleepWeightDuration = 0.50;
const double kSleepWeightEfficiency = 0.20;
const double kSleepWeightRestorative = 0.20;
const double kSleepWeightConsistency = 0.10;

/// Cold-start population floor for sleep need (ALGORITHMS.md §3).
const double kSleepNeedFloorMinutes = 480;

/// Plausibility bands at fold and today-value (ALGORITHMS.md §2). An
/// out-of-band observation is REJECTED (never clamped into the baseline);
/// an out-of-band today-value is reported missing, never z-scored.
class PlausibilityBand {
  const PlausibilityBand(this.min, this.max);
  final double min;
  final double max;
  bool contains(double? v) => v != null && v >= min && v <= max;
}

const PlausibilityBand kBandHrvMs = PlausibilityBand(5, 250);
const PlausibilityBand kBandRhrBpm = PlausibilityBand(30, 120);
const PlausibilityBand kBandSleepMinutes = PlausibilityBand(1, 960);
const PlausibilityBand kBandWeightKg = PlausibilityBand(30, 300);
const PlausibilityBand kBandRespBpm = PlausibilityBand(8, 25);

/// Per-metric spread floors (Pass 3, `baseline_floor_spread`). The spread
/// EWMA result and the static Winsor bound scale are floored at this value.
const double kFloorSpreadHrvLn = 0.05; // ln(ms) domain
const double kFloorSpreadRhrBpm = 2.0;
const double kFloorSpreadSleepMinutes = 15.0;
const double kFloorSpreadWeightKg = 0.5;
const double kFloorSpreadRespBpm = 0.5;

/// EWMA center half-lives (ALGORITHMS.md §2): 3-day while the fold is on
/// observations 2–8, 14-day from observation
/// `kStableFromObservation` (the 9th) on. The first observation seeds.
const double kHalfLifeDaysEarly = 3;
const double kHalfLifeDaysStable = 14;
const int kStableFromObservation = 9;

/// Spread-EWMA coefficients (SQL literal): a 21-day half-life over
/// per-observation |deviation|, expressed with the SQL's rounded
/// complements 0.9670 / 0.0330 rather than the unrounded
/// 1 − 0.5^(1/21) ≈ 0.0327.
const double kSpreadEwmaKeep = 0.9670;
const double kSpreadEwmaStep = 0.0330;

/// Winsorization multipliers on the (floored, for the spread pass) MAD
/// scale: ±3× clamps, ±5× rejects.
const double kWinsorClampSigmas = 3.0;
const double kWinsorRejectSigmas = 5.0;

/// MAD-to-sigma consistency constant (Hunter 1986).
const double kMadSigma = 1.4826;

/// Strain cap per session — sessions longer than 3 h are excluded from
/// every strain window (2026-08-22 cap; the July-22 403-strain outlier).
const int kStrainSessionCapSeconds = 10800;

/// Z-usability gate: a component joins the composite only when the
/// baseline has `spread > 0` AND `n_observations >= 3`.
const int kMinBaselineObservations = 3;

/// ACWR needs ≥ 14 strain days in the 28-day chronic window.
const int kAcwrMinChronicDays = 14;

/// Monotony needs ≥ 4 strain days in the acute week and stddev > 0.
const int kMonotonyMinAcuteDays = 4;

/// Duration score uses the personal sleep EWMA only at ≥ 7 nights.
const int kSleepBaselineMinNights = 7;

/// prev-strain z needs 7-day avg > 0 AND 28-day stddev > 0.
const double kStrainZMinPrev7Avg = 0;

/// The 7-day average sleep the debt metric targets (ALGORITHMS.md §3).
const double kSleepDebtTargetMinutes = 480;

// ─── Input model ─────────────────────────────────────────────────────────

/// One night/day of HealthKit-sourced observations as the fixture JSON
/// carries them. `null` = not measured that day.
class HealthDay {
  HealthDay({
    required this.date,
    this.hrvMs,
    this.restingHrBpm,
    this.sleepMinutes,
    this.sleepAwakeMinutes,
    this.sleepDeepMinutes,
    this.sleepRemMinutes,
    this.respRateBpm,
    this.weightKg,
  });

  factory HealthDay.fromJson(Map<String, dynamic> json) {
    double? asDouble(String key) => (json[key] as num?)?.toDouble();
    return HealthDay(
      date: _localDay(json['date'] as String),
      hrvMs: asDouble('hrv_ms'),
      restingHrBpm: asDouble('resting_hr_bpm'),
      sleepMinutes: asDouble('sleep_minutes'),
      sleepAwakeMinutes: asDouble('sleep_awake_minutes'),
      sleepDeepMinutes: asDouble('sleep_deep_minutes'),
      sleepRemMinutes: asDouble('sleep_rem_minutes'),
      respRateBpm: asDouble('resp_rate_bpm'),
      weightKg: asDouble('weight_kg'),
    );
  }

  final DateTime date;
  final double? hrvMs;
  final double? restingHrBpm;
  final double? sleepMinutes;
  final double? sleepAwakeMinutes;
  final double? sleepDeepMinutes;
  final double? sleepRemMinutes;
  final double? respRateBpm;
  final double? weightKg;
}

/// One completed training session (sRPE load model, ALGORITHMS.md §4).
class WorkoutSession {
  WorkoutSession({
    required this.date,
    required this.effort,
    required this.durationSeconds,
  });

  factory WorkoutSession.fromJson(Map<String, dynamic> json) {
    return WorkoutSession(
      date: _localDay(json['date'] as String),
      effort: (json['effort'] as num).toDouble(),
      durationSeconds: json['duration_seconds'] as int,
    );
  }

  final DateTime date;
  final double effort;
  final int durationSeconds;

  double get strain => effort * durationSeconds / 600.0;
}

/// A full fixture scenario.
class ReferenceScenario {
  ReferenceScenario({
    required this.name,
    required this.targetDate,
    required this.healthDays,
    this.sessions = const [],
    this.weightDays = const [],
  });

  factory ReferenceScenario.fromJson(Map<String, dynamic> json) {
    final target = _localDay(json['target_date'] as String);
    final health = (json['health_days'] as List)
        .map((raw) => HealthDay.fromJson(raw as Map<String, dynamic>))
        .toList();
    final sessions = (json['sessions'] as List? ?? [])
        .map((raw) => WorkoutSession.fromJson(raw as Map<String, dynamic>))
        .toList();
    final weights = (json['weight_days'] as List? ?? [])
        .map(
          (raw) => WeightEntry.fromJson(raw as Map<String, dynamic>),
        )
        .toList();
    return ReferenceScenario(
      name: json['name'] as String,
      targetDate: target,
      healthDays: health,
      sessions: sessions,
      weightDays: weights,
    );
  }

  final String name;
  final DateTime targetDate;

  /// All HealthKit summary days (history + today), any order.
  final List<HealthDay> healthDays;

  /// Completed workout sessions, any order.
  final List<WorkoutSession> sessions;

  /// Manual body measurements (the weight band source), any order.
  final List<WeightEntry> weightDays;
}

/// One manual weight observation (body_measurements).
class WeightEntry {
  WeightEntry({required this.date, required this.weightKg});

  factory WeightEntry.fromJson(Map<String, dynamic> json) {
    return WeightEntry(
      date: _localDay(json['date'] as String),
      weightKg: (json['weight_kg'] as num).toDouble(),
    );
  }

  final DateTime date;
  final double weightKg;
}

/// Parse a `YYYY-MM-DD` string as a local calendar day (midnight, no UTC
/// marker) so day arithmetic never crosses a timezone boundary.
DateTime _localDay(String iso) {
  final parsed = DateTime.parse(iso);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

// ─── Baseline fold ───────────────────────────────────────────────────────

/// The two numbers a z-score needs, per metric.
class Baseline {
  Baseline({
    required this.center,
    required this.spread,
    required this.nObservations,
    required this.lastObservationDate,
    required this.confidence,
  });

  final double center;
  final double spread;
  final int nObservations;
  final DateTime? lastObservationDate;
  final String confidence;

  bool get usable => spread > 0 && nObservations >= kMinBaselineObservations;
}

/// Fold one metric's history into a baseline, reproducing both SQL passes:
///
/// 1. `compute_winsorized_ewma` — the stored CENTER: unfloored MAD bounds,
///    `MAD = 0 → last observation` shortcut live.
/// 2. The fold loop — the stored SPREAD: floored bounds, 21-day spread
///    EWMA, floored at every step.
///
/// Sub-3-observation histories take the cold-start branch (floor spread,
/// first value as center, `cold_start` confidence) exactly as the SQL does.
Baseline foldBaseline({
  required List<({DateTime date, double value})> observations,
  required double floorSpread,
}) {
  final sorted = [...observations]
    ..sort((a, b) => a.date.compareTo(b.date));
  final values = sorted.map((o) => o.value).toList();

  // Cold start: fewer than 3 observations never fold.
  if (values.length < kMinBaselineObservations) {
    return Baseline(
      center: values.isEmpty ? 0 : values.first,
      spread: floorSpread,
      nObservations: values.length,
      lastObservationDate:
          sorted.isEmpty ? null : sorted[sorted.length - 1].date,
      confidence: 'cold_start',
    );
  }

  final median = _percentile50(values);
  final mad = _percentile50([for (final v in values) (v - median).abs()]);
  final staticSpread = kMadSigma * mad;

  // Pass 1 — stored center (unfloored bounds, MAD=0 shortcut).
  final center = _winsorizedEwma(values, staticSpread);

  // Pass 2 — stored spread (floored bounds, 21-day EWMA, floored).
  final spread = _spreadEwma(values, staticSpread, floorSpread);

  final n = values.length;
  return Baseline(
    center: center,
    spread: spread,
    nObservations: n,
    lastObservationDate: sorted[sorted.length - 1].date,
    confidence: n >= 14
        ? 'high'
        : n >= 7
        ? 'medium'
        : 'low',
  );
}

/// Pass 1 — the stored center, mirroring `compute_winsorized_ewma`:
/// unfloored ±3σ clamp / ±5σ reject around the raw MAD scale. When MAD = 0
/// the SQL returns the LAST observation (not the EWMA).
double _winsorizedEwma(List<double> values, double staticSpread) {
  if (staticSpread == 0) return values[values.length - 1];

  final median = _percentile50(values);
  final lower = median - kWinsorClampSigmas * staticSpread;
  final upper = median + kWinsorClampSigmas * staticSpread;
  final hardLower = median - kWinsorRejectSigmas * staticSpread;
  final hardUpper = median + kWinsorRejectSigmas * staticSpread;

  var ewma = values[0];
  for (var i = 1; i < values.length; i++) {
    final v = values[i];
    if (v < hardLower || v > hardUpper) continue;
    final winsorized = v.clamp(lower, upper);
    final halfLife = i + 1 < kStableFromObservation ? kHalfLifeDaysEarly : kHalfLifeDaysStable;
    final lambda = 1 - math.pow(0.5, 1 / halfLife);
    ewma = lambda * winsorized + (1 - lambda) * ewma;
  }
  return ewma;
}

/// Pass 2 — the stored spread, mirroring the Pass-3 fold loop: floored
/// bounds for the reject test, `max(floor, 0.9670·spread + 0.0330·|dev|)`
/// EWMA, floored at every step. Note the deviation uses the RAW value
/// (the value the center pass would clamp), not the winsorized one.
double _spreadEwma(
  List<double> values,
  double staticSpread,
  double floorSpread,
) {
  final median = _percentile50(values);
  final flooredStatic = math.max(floorSpread, staticSpread);
  final hardLower = median - kWinsorRejectSigmas * flooredStatic;
  final hardUpper = median + kWinsorRejectSigmas * flooredStatic;

  var ewma = values[0];
  var spread = flooredStatic;
  for (var i = 1; i < values.length; i++) {
    final v = values[i];
    if (v < hardLower || v > hardUpper) continue;
    final halfLife = i + 1 < kStableFromObservation ? kHalfLifeDaysEarly : kHalfLifeDaysStable;
    final lambda = 1 - math.pow(0.5, 1 / halfLife);
    final winsorized = v.clamp(
      median - kWinsorClampSigmas * flooredStatic,
      median + kWinsorClampSigmas * flooredStatic,
    );
    ewma = lambda * winsorized + (1 - lambda) * ewma;
    spread = math.max(
      floorSpread,
      kSpreadEwmaKeep * spread + kSpreadEwmaStep * (v - ewma).abs(),
    );
  }
  return spread;
}

double _percentile50(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

// ─── Daily metrics ───────────────────────────────────────────────────────

/// Everything the daily compute produces that the fixtures pin.
class RecoveryDay {
  RecoveryDay({
    required this.recovery,
    required this.missingComponents,
    required this.zHrv,
    required this.zRhr,
    required this.zSleep,
    required this.zResp,
    required this.zPrevStrain,
    required this.sleepQuality,
    required this.sleepBreakdown,
    required this.sleepBreakdownMissing,
    required this.sleepDebtMinutes,
    required this.dailyStrain,
    required this.acwr,
    required this.monotony,
    required this.dataConfidence,
    required this.baselines,
  });

  final double? recovery;
  final List<String> missingComponents;
  final double zHrv;
  final double zRhr;
  final double zSleep;
  final double zResp;
  final double zPrevStrain;

  /// The 0–100 composite (null when no sub-score was computable).
  final double? sleepQuality;

  /// The four sub-scores (null = that sub-input was missing). The full
  /// breakdown object exists only when all four are non-null (shipped-client
  /// parser contract).
  final SleepBreakdown? sleepBreakdown;
  final List<String>? sleepBreakdownMissing;
  final int? sleepDebtMinutes;
  final double dailyStrain;
  final double? acwr;
  final double? monotony;
  final String dataConfidence;
  final Map<String, Baseline> baselines;
}

/// The four sleep sub-scores (ALGORITHMS.md §3).
class SleepBreakdown {
  SleepBreakdown({
    required this.duration,
    required this.efficiency,
    required this.restorative,
    required this.consistency,
  });

  final double duration;
  final double efficiency;
  final double restorative;
  final double consistency;
}

/// Result of running one scenario through the reference.
class ReferenceResult {
  ReferenceResult({
    required this.day,
    required this.durationScoreFloorUsed,
  });

  /// The computed day (recovery, scores, baselines).
  final RecoveryDay day;

  /// True when duration_score used the 480-min population floor rather
  /// than the personal sleep EWMA (cold start diagnostic).
  final bool durationScoreFloorUsed;
}

/// Compute one scenario's day, from ALGORITHMS.md §1–§4.
ReferenceResult computeReferenceDay(ReferenceScenario scenario) {
  final target = DateTime(
    scenario.targetDate.year,
    scenario.targetDate.month,
    scenario.targetDate.day,
  );
  final missing = <String>[];
  final byDate = <DateTime, HealthDay>{};
  for (final d in scenario.healthDays) {
    byDate[DateTime(d.date.year, d.date.month, d.date.day)] = d;
  }
  final today = byDate[target];
  // The fold uses the full history INCLUDING today (SQL: local_date <=
  // target_date).
  final history = scenario.healthDays
      .where((d) => !d.date.isAfter(target))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  // Baselines fold from the full history INCLUDING today (the SQL folds
  // `local_date <= target_date`, today included).
  List<({DateTime date, double value})> foldObservations(
    double? Function(HealthDay) pick,
    PlausibilityBand band,
  ) {
    return [
      for (final d in history)
        if (band.contains(pick(d))) (date: d.date, value: pick(d)!),
    ];
  }

  final hrvFold = foldObservations((d) => d.hrvMs, kBandHrvMs)
      .map((o) => (date: o.date, value: math.log(o.value)))
      .toList();
  final rhrFold = foldObservations((d) => d.restingHrBpm, kBandRhrBpm);
  final sleepFold = foldObservations((d) => d.sleepMinutes, kBandSleepMinutes);
  final respFold = foldObservations((d) => d.respRateBpm, kBandRespBpm);

  // Weight: manual entries take priority over HealthKit days on the same
  // date (the SQL's UNION with a NOT IN exclusion).
  final manualDates = {
    for (final w in scenario.weightDays)
      DateTime(w.date.year, w.date.month, w.date.day),
  };
  final weightFold = [
    ...scenario.weightDays
        .where((w) => kBandWeightKg.contains(w.weightKg))
        .map((w) => (
              date: DateTime(w.date.year, w.date.month, w.date.day),
              value: w.weightKg,
            )),
    ...scenario.healthDays
        .where(
          (d) =>
              kBandWeightKg.contains(d.weightKg) &&
              !manualDates.contains(
                DateTime(d.date.year, d.date.month, d.date.day),
              ),
        )
        .map(
          (d) => (
            date: DateTime(d.date.year, d.date.month, d.date.day),
            value: d.weightKg!,
          ),
        ),
  ]..sort((a, b) => a.date.compareTo(b.date));

  final baselines = <String, Baseline>{};
  baselines['hrv_sdnn_ms'] = foldBaseline(
    observations: hrvFold,
    floorSpread: kFloorSpreadHrvLn,
  );
  baselines['resting_hr_bpm'] = foldBaseline(
    observations: rhrFold,
    floorSpread: kFloorSpreadRhrBpm,
  );
  baselines['sleep_minutes'] = foldBaseline(
    observations: sleepFold,
    floorSpread: kFloorSpreadSleepMinutes,
  );
  baselines['weight_kg'] = foldBaseline(
    observations: weightFold,
    floorSpread: kFloorSpreadWeightKg,
  );
  baselines['resp_rate_bpm'] = foldBaseline(
    observations: respFold,
    floorSpread: kFloorSpreadRespBpm,
  );

  // ── Recovery composite ──
  var composite = 0.0;
  var weightTotal = 0.0;
  var zHrv = 0.0;
  var zRhr = 0.0;
  var zSleep = 0.0;
  var zResp = 0.0;
  var zStrain = 0.0;

  // HRV (ln domain today).
  final hrvToday = today?.hrvMs;
  final hrvBaseline = baselines['hrv_sdnn_ms']!;
  if (kBandHrvMs.contains(hrvToday) && hrvBaseline.usable) {
    zHrv = (math.log(hrvToday!) - hrvBaseline.center) / hrvBaseline.spread;
    composite += kWeightHrv * zHrv;
    weightTotal += kWeightHrv;
  } else {
    missing.add('hrv_sdnn');
  }

  // RHR (negated).
  final rhrToday = today?.restingHrBpm;
  final rhrBaseline = baselines['resting_hr_bpm']!;
  if (kBandRhrBpm.contains(rhrToday) && rhrBaseline.usable) {
    zRhr = -(rhrToday! - rhrBaseline.center) / rhrBaseline.spread;
    composite += kWeightRhr * zRhr;
    weightTotal += kWeightRhr;
  } else {
    missing.add('resting_hr');
  }

  // Sleep.
  final sleepToday = today?.sleepMinutes;
  final sleepBaseline = baselines['sleep_minutes']!;
  if (kBandSleepMinutes.contains(sleepToday) && sleepBaseline.usable) {
    zSleep = (sleepToday! - sleepBaseline.center) / sleepBaseline.spread;
    composite += kWeightSleep * zSleep;
    weightTotal += kWeightSleep;
  } else {
    missing.add('sleep_minutes');
  }

  // Resp rate (negated).
  final respToday = today?.respRateBpm;
  final respBaseline = baselines['resp_rate_bpm']!;
  if (kBandRespBpm.contains(respToday) && respBaseline.usable) {
    zResp = -(respToday! - respBaseline.center) / respBaseline.spread;
    composite += kWeightResp * zResp;
    weightTotal += kWeightResp;
  } else {
    missing.add('resp_rate');
  }

  // Daily + prior strain.
  final cappedSessions = scenario.sessions
      .where((s) => s.durationSeconds <= kStrainSessionCapSeconds)
      .toList();
  double strainOn(DateTime day) => cappedSessions
      .where(
        (s) =>
            DateTime(s.date.year, s.date.month, s.date.day)
                .isAtSameMomentAs(day),
      )
      .fold(0, (total, s) => total + s.strain);

  final dailyStrain = strainOn(target);
  // SQL windows: prev7 = days with a session in [target-7, target-1]
  // (average over logged days only, no zero-fill); the 28-day set =
  // distinct logged days in [target-28, target-1].
  final prev7Logged = <double>[];
  for (var i = 7; i >= 1; i--) {
    final day = target.subtract(Duration(days: i));
    final s = strainOn(day);
    if (s > 0) prev7Logged.add(s);
  }
  final prev7Avg = prev7Logged.isEmpty
      ? null
      : prev7Logged.reduce((a, b) => a + b) / prev7Logged.length;

  final last28Logged = <double>[];
  for (var i = 28; i >= 1; i--) {
    final day = target.subtract(Duration(days: i));
    final s = strainOn(day);
    if (s > 0) last28Logged.add(s);
  }

  if (prev7Avg != null && prev7Avg > kStrainZMinPrev7Avg) {
    final dayStrains = last28Logged;
    final avg28 = dayStrains.isEmpty
        ? null
        : dayStrains.reduce((a, b) => a + b) / dayStrains.length;
    final stddev28 = avg28 == null
        ? null
        : _stddevSamp(dayStrains);
    if (stddev28 != null && stddev28 > 0 && avg28 != null) {
      zStrain = (prev7Avg - avg28) / stddev28;
      composite -= kWeightPrevStrain * zStrain;
      weightTotal += kWeightPrevStrain;
    } else {
      missing.add('prev_strain');
    }
  } else {
    missing.add('prev_strain');
  }

  double? recovery;
  if (weightTotal > 0) {
    final compositeZ = composite / weightTotal;
    recovery = 100 / (1 + math.exp(-kLogisticK * compositeZ));
  }

  // ── Sleep quality ──
  double? sleepQuality;
  SleepBreakdown? sleepBreakdown;
  List<String>? sleepMissing;
  int? sleepDebt;
  var floorUsed = false;

  if (kBandSleepMinutes.contains(sleepToday)) {
    final tonight = sleepToday!;
    final sleepMissingList = <String>[];
    double? efficiency;
    double? restorative;
    double? consistency;

    if (today?.sleepAwakeMinutes != null) {
      efficiency = (tonight - today!.sleepAwakeMinutes!) / tonight * 100;
    } else {
      sleepMissingList.add('efficiency');
    }
    if (today?.sleepDeepMinutes != null && today?.sleepRemMinutes != null) {
      restorative =
          (today!.sleepDeepMinutes! + today.sleepRemMinutes!) / tonight * 100;
    } else {
      sleepMissingList.add('restorative');
    }

    double durationScore;
    final sleepBaselineForDuration = baselines['sleep_minutes']!;
    if (sleepBaselineForDuration.nObservations >= kSleepBaselineMinNights &&
        sleepBaselineForDuration.center > 0) {
      durationScore = (tonight / sleepBaselineForDuration.center * 100)
          .clamp(0, 100);
    } else {
      floorUsed = true;
      durationScore = (tonight / kSleepNeedFloorMinutes * 100).clamp(0, 100);
    }

    // SQL: sleep nights with a non-null sleep_minutes in
    // [target - 6, target] — no plausibility filter on the window.
    final last7Nights = [
      for (final d in history)
        if (d.sleepMinutes != null && !d.date.isAfter(target))
          if (target.difference(d.date).inDays <= 6) d.sleepMinutes!,
    ];
    if (last7Nights.length >= 2) {
      final mean = last7Nights.reduce((a, b) => a + b) / last7Nights.length;
      if (mean > 0) {
        final sd = _stddevSamp(last7Nights);
        if (sd != null) {
          consistency = math.max(0, 100 - (sd / mean) * 50);
        }
      }
    }
    if (consistency == null) sleepMissingList.add('consistency');

    var sleepComposite = 0.0;
    var sleepWeightTotal = 0.0;
    void add(double? score, double weight) {
      if (score != null) {
        sleepComposite += weight * score;
        sleepWeightTotal += weight;
      }
    }

    add(durationScore, kSleepWeightDuration);
    add(efficiency, kSleepWeightEfficiency);
    add(restorative, kSleepWeightRestorative);
    add(consistency, kSleepWeightConsistency);

    if (sleepWeightTotal > 0) {
      // SQL order: round the composite to an integer, then clamp 0..100.
      sleepQuality = _roundHalfAway(sleepComposite / sleepWeightTotal)
          .clamp(0, 100);
    }
    if (sleepQuality != null &&
        efficiency != null &&
        restorative != null &&
        consistency != null) {
      sleepBreakdown = SleepBreakdown(
        duration: durationScore,
        efficiency: efficiency,
        restorative: restorative,
        consistency: consistency,
      );
    }
    sleepMissing = sleepQuality == null ? null : List.of(sleepMissingList);

    if (last7Nights.isNotEmpty) {
      final avg7 = last7Nights.reduce((a, b) => a + b) / last7Nights.length;
      // SQL: 480 - round(avg7); the debt result stays an integer.
      sleepDebt =
          (kSleepDebtTargetMinutes - _roundHalfAway(avg7)).round();
    }
  }

  // ── ACWR / monotony (calendar windows, zero-filled) ──
  double? acwr;
  double? monotony;
  {
    final last28Strains = [
      for (var i = 27; i >= 0; i--)
        strainOn(target.subtract(Duration(days: i))),
    ];
    final avg28 = last28Strains.reduce((a, b) => a + b) / 28;
    final avg7 = last28Strains.sublist(21).reduce((a, b) => a + b) / 7;
    final chronicDays = last28Strains.where((s) => s > 0).length;
    final acuteDays = last28Strains.sublist(21).where((s) => s > 0).length;
    final sd7 = _stddevSamp(last28Strains.sublist(21));
    if (chronicDays >= kAcwrMinChronicDays && avg28 > 0) {
      acwr = avg7 / avg28;
    }
    if (acuteDays >= kMonotonyMinAcuteDays && sd7 != null && sd7 > 0) {
      monotony = avg7 / sd7;
    }
  }

  // ── Data confidence ──
  final healthMissing = missing.where((m) => m != 'prev_strain').length;
  final hasTodaySummary = scenario.healthDays.any(
    (d) =>
        DateTime(d.date.year, d.date.month, d.date.day).isAtSameMomentAs(
            target),
  );
  var confidence = 'high';
  if (!hasTodaySummary || healthMissing >= 3) {
    confidence = 'low';
  } else if (healthMissing > 0) {
    confidence = 'medium';
  }

  return ReferenceResult(
    day: RecoveryDay(
      recovery: recovery,
      missingComponents: missing,
      zHrv: zHrv,
      zRhr: zRhr,
      zSleep: zSleep,
      zResp: zResp,
      zPrevStrain: zStrain,
      sleepQuality: sleepQuality,
      sleepBreakdown: sleepBreakdown,
      sleepBreakdownMissing: sleepMissing,
      sleepDebtMinutes: sleepDebt,
      dailyStrain: dailyStrain,
      acwr: acwr,
      monotony: monotony,
      dataConfidence: confidence,
      baselines: baselines,
    ),
    durationScoreFloorUsed: floorUsed,
  );
}

double? _stddevSamp(List<double> values) {
  if (values.length < 2) return null;
  final mean = values.reduce((a, b) => a + b) / values.length;
  final sumSq = values.fold<double>(
    0,
    (total, v) => total + (v - mean) * (v - mean),
  );
  return math.sqrt(sumSq / (values.length - 1));
}

/// Postgres `round(numeric)` semantics: half away from zero.
double _roundHalfAway(double v) => v.roundToDouble();

// ─── Fixture loading ─────────────────────────────────────────────────────

/// Parse one fixture file's JSON into a scenario.
ReferenceScenario loadScenario(String fixtureJson) {
  final parsed = jsonDecode(fixtureJson);
  if (parsed is! Map<String, dynamic>) {
    throw FormatException('Fixture must be a JSON object');
  }
  return ReferenceScenario.fromJson(parsed);
}
