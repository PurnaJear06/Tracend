class RecoveryBreakdown {
  const RecoveryBreakdown({
    required this.hrvZ,
    required this.rhrZ,
    required this.sleepZ,
    required this.respRateZ,
    required this.prevStrainZ,
    this.missingComponents = const [],
  });
  final double hrvZ;
  final double rhrZ;
  final double sleepZ;
  final double respRateZ;
  final double prevStrainZ;

  /// Component keys that did not contribute to the recovery score because
  /// the value or its baseline was unavailable ('hrv_sdnn', 'resting_hr',
  /// 'sleep_minutes', 'resp_rate', 'prev_strain'). Absent on older payloads.
  final List<String> missingComponents;

  factory RecoveryBreakdown.fromJson(Map<String, dynamic> json) {
    return RecoveryBreakdown(
      hrvZ: (json['hrv_z'] as num).toDouble(),
      rhrZ: (json['rhr_z'] as num).toDouble(),
      sleepZ: (json['sleep_z'] as num).toDouble(),
      respRateZ: (json['resp_rate_z'] as num).toDouble(),
      prevStrainZ: (json['prev_strain_z'] as num).toDouble(),
      missingComponents: (json['missing_components'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecoveryBreakdown &&
      hrvZ == other.hrvZ &&
      rhrZ == other.rhrZ &&
      sleepZ == other.sleepZ &&
      respRateZ == other.respRateZ &&
      prevStrainZ == other.prevStrainZ &&
      _listEquals(missingComponents, other.missingComponents);

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    hrvZ,
    rhrZ,
    sleepZ,
    respRateZ,
    prevStrainZ,
    Object.hashAll(missingComponents),
  );
}

class SleepBreakdown {
  const SleepBreakdown({
    required this.durationScore,
    required this.efficiencyScore,
    required this.restorativeScore,
    required this.consistencyScore,
  });
  final double durationScore;
  final double efficiencyScore;
  final double restorativeScore;
  final double consistencyScore;

  factory SleepBreakdown.fromJson(Map<String, dynamic> json) {
    return SleepBreakdown(
      durationScore: (json['duration_score'] as num).toDouble(),
      efficiencyScore: (json['efficiency_score'] as num).toDouble(),
      restorativeScore: (json['restorative_score'] as num).toDouble(),
      consistencyScore: (json['consistency_score'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SleepBreakdown &&
      durationScore == other.durationScore &&
      efficiencyScore == other.efficiencyScore &&
      restorativeScore == other.restorativeScore &&
      consistencyScore == other.consistencyScore;

  @override
  int get hashCode => Object.hash(
    durationScore,
    efficiencyScore,
    restorativeScore,
    consistencyScore,
  );
}

class BaselineMetric {
  const BaselineMetric({
    required this.ewma,
    required this.spread,
    required this.nObs,
    required this.confidence,
    this.lastObsDate,
    this.ageDays,
  });
  final double ewma;
  final double spread;
  final int nObs;
  final String confidence;

  /// True date of the newest observation behind this baseline, and its
  /// age in days as of the brief's target date (0 = today). A baseline can
  /// be weeks old when the watch stops being worn overnight — these make
  /// the staleness visible instead of presenting an old value as current.
  /// Null when the metric was never observed. Absent on briefs < 1.5.
  final String? lastObsDate;
  final int? ageDays;

  factory BaselineMetric.fromJson(Map<String, dynamic> json) {
    return BaselineMetric(
      ewma: (json['ewma'] as num).toDouble(),
      spread: (json['spread'] as num).toDouble(),
      nObs: json['n_obs'] as int,
      confidence: json['confidence'] as String,
      lastObsDate: json['last_obs_date'] as String?,
      ageDays: (json['age_days'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BaselineMetric &&
      ewma == other.ewma &&
      spread == other.spread &&
      nObs == other.nObs &&
      confidence == other.confidence &&
      lastObsDate == other.lastObsDate &&
      ageDays == other.ageDays;

  @override
  int get hashCode =>
      Object.hash(ewma, spread, nObs, confidence, lastObsDate, ageDays);
}

/// Today's measured values, exactly as recorded — never derived. The
/// recovery driver rows pair each raw value with its z-score so "−1.2"
/// reads as "38 ms, 1.2 spreads below baseline" instead of a bare number
/// the owner can mistake for a broken unit. Absent on briefs < 1.4.
class TodayRaw {
  const TodayRaw({
    this.hrvMs,
    this.restingHrBpm,
    this.sleepMinutes,
    this.respRateBpm,
    this.dailyStrain,
  });
  final double? hrvMs;
  final double? restingHrBpm;
  final int? sleepMinutes;
  final double? respRateBpm;
  final double? dailyStrain;

  factory TodayRaw.fromJson(Map<String, dynamic> json) {
    return TodayRaw(
      hrvMs: (json['hrv_ms'] as num?)?.toDouble(),
      restingHrBpm: (json['resting_hr_bpm'] as num?)?.toDouble(),
      sleepMinutes: json['sleep_minutes'] as int?,
      respRateBpm: (json['resp_rate_bpm'] as num?)?.toDouble(),
      dailyStrain: (json['daily_strain'] as num?)?.toDouble(),
    );
  }
}

class ComputedBaselines {
  const ComputedBaselines({
    this.hrv,
    this.restingHr,
    this.sleepMinutes,
    this.weightKg,
    this.respRate,
  });
  final BaselineMetric? hrv;
  final BaselineMetric? restingHr;
  final BaselineMetric? sleepMinutes;
  final BaselineMetric? weightKg;
  final BaselineMetric? respRate;

  factory ComputedBaselines.fromJson(Map<String, dynamic> json) {
    BaselineMetric? parse(String key) {
      final raw = json[key];
      if (raw is! Map) return null;
      return BaselineMetric.fromJson(Map<String, dynamic>.from(raw));
    }

    return ComputedBaselines(
      hrv: parse('hrv_sdnn_ms'),
      restingHr: parse('resting_hr_bpm'),
      sleepMinutes: parse('sleep_minutes'),
      weightKg: parse('weight_kg'),
      respRate: parse('resp_rate_bpm'),
    );
  }
}

class ComputedScores {
  const ComputedScores({
    this.recovery,
    this.recoveryBreakdown,
    this.sleepQuality,
    this.sleepBreakdown,
    this.sleepDebtMinutes,
    this.dailyStrain,
    this.acwr,
    this.trainingMonotony,
    this.weightTrend7d,
    this.weightTrend28d,
    this.weightTrendR2,
    this.macroAdherencePct,
  });
  final int? recovery;
  final RecoveryBreakdown? recoveryBreakdown;
  final int? sleepQuality;
  final SleepBreakdown? sleepBreakdown;
  final int? sleepDebtMinutes;
  final double? dailyStrain;
  final double? acwr;
  final double? trainingMonotony;
  final double? weightTrend7d;
  final double? weightTrend28d;
  final double? weightTrendR2;
  final int? macroAdherencePct;

  factory ComputedScores.fromJson(Map<String, dynamic> json) {
    RecoveryBreakdown? parseBreakdown(String key) {
      final raw = json[key];
      if (raw is! Map) return null;
      return RecoveryBreakdown.fromJson(Map<String, dynamic>.from(raw));
    }

    SleepBreakdown? parseSleepBreakdown(String key) {
      final raw = json[key];
      if (raw is! Map) return null;
      return SleepBreakdown.fromJson(Map<String, dynamic>.from(raw));
    }

    return ComputedScores(
      recovery: json['recovery'] as int?,
      recoveryBreakdown: parseBreakdown('recovery_breakdown'),
      sleepQuality: json['sleep_quality'] as int?,
      sleepBreakdown: parseSleepBreakdown('sleep_breakdown'),
      sleepDebtMinutes: json['sleep_debt_minutes'] as int?,
      dailyStrain: (json['daily_strain'] as num?)?.toDouble(),
      acwr: (json['acwr'] as num?)?.toDouble(),
      trainingMonotony: (json['training_monotony'] as num?)?.toDouble(),
      weightTrend7d: (json['weight_trend_7d_kg_per_day'] as num?)?.toDouble(),
      weightTrend28d: (json['weight_trend_28d_kg_per_day'] as num?)?.toDouble(),
      weightTrendR2: (json['weight_trend_r2_28d'] as num?)?.toDouble(),
      macroAdherencePct: json['macro_adherence_pct'] as int?,
    );
  }
}

class ComputedMetrics {
  const ComputedMetrics({
    required this.scores,
    required this.baselines,
    required this.dataConfidence,
    this.todayRaw,
  });

  factory ComputedMetrics.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ComputedMetrics._empty();
    }
    final scoresRaw = json['scores'];
    final baselinesRaw = json['baselines'];
    final todayRawRaw = json['today_raw'];
    return ComputedMetrics(
      scores: scoresRaw is Map
          ? ComputedScores.fromJson(Map<String, dynamic>.from(scoresRaw))
          : const ComputedScores(),
      baselines: baselinesRaw is Map
          ? ComputedBaselines.fromJson(Map<String, dynamic>.from(baselinesRaw))
          : const ComputedBaselines(),
      dataConfidence: (json['data_confidence'] as String?) ?? 'cold_start',
      todayRaw: todayRawRaw is Map
          ? TodayRaw.fromJson(Map<String, dynamic>.from(todayRawRaw))
          : null,
    );
  }

  const ComputedMetrics._empty()
    : scores = const ComputedScores(),
      baselines = const ComputedBaselines(),
      dataConfidence = 'cold_start',
      todayRaw = null;

  final ComputedScores scores;
  final ComputedBaselines baselines;
  final String dataConfidence;
  final TodayRaw? todayRaw;
}
