class RecoveryBreakdown {
  const RecoveryBreakdown({
    required this.hrvZ,
    required this.rhrZ,
    required this.sleepZ,
    required this.respRateZ,
    required this.prevStrainZ,
  });
  final double hrvZ;
  final double rhrZ;
  final double sleepZ;
  final double respRateZ;
  final double prevStrainZ;

  factory RecoveryBreakdown.fromJson(Map<String, dynamic> json) {
    return RecoveryBreakdown(
      hrvZ: (json['hrv_z'] as num).toDouble(),
      rhrZ: (json['rhr_z'] as num).toDouble(),
      sleepZ: (json['sleep_z'] as num).toDouble(),
      respRateZ: (json['resp_rate_z'] as num).toDouble(),
      prevStrainZ: (json['prev_strain_z'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecoveryBreakdown &&
      hrvZ == other.hrvZ &&
      rhrZ == other.rhrZ &&
      sleepZ == other.sleepZ &&
      respRateZ == other.respRateZ &&
      prevStrainZ == other.prevStrainZ;

  @override
  int get hashCode => Object.hash(hrvZ, rhrZ, sleepZ, respRateZ, prevStrainZ);
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
  });
  final double ewma;
  final double spread;
  final int nObs;
  final String confidence;

  factory BaselineMetric.fromJson(Map<String, dynamic> json) {
    return BaselineMetric(
      ewma: (json['ewma'] as num).toDouble(),
      spread: (json['spread'] as num).toDouble(),
      nObs: json['n_obs'] as int,
      confidence: json['confidence'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BaselineMetric &&
      ewma == other.ewma &&
      spread == other.spread &&
      nObs == other.nObs &&
      confidence == other.confidence;

  @override
  int get hashCode => Object.hash(ewma, spread, nObs, confidence);
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
  });

  factory ComputedMetrics.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ComputedMetrics._empty();
    }
    final scoresRaw = json['scores'];
    final baselinesRaw = json['baselines'];
    return ComputedMetrics(
      scores: scoresRaw is Map
          ? ComputedScores.fromJson(Map<String, dynamic>.from(scoresRaw))
          : const ComputedScores(),
      baselines: baselinesRaw is Map
          ? ComputedBaselines.fromJson(Map<String, dynamic>.from(baselinesRaw))
          : const ComputedBaselines(),
      dataConfidence: (json['data_confidence'] as String?) ?? 'cold_start',
    );
  }

  const ComputedMetrics._empty()
    : scores = const ComputedScores(),
      baselines = const ComputedBaselines(),
      dataConfidence = 'cold_start';

  final ComputedScores scores;
  final ComputedBaselines baselines;
  final String dataConfidence;
}
