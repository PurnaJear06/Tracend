import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/today/computed_metrics.dart';

void main() {
  group('ComputedMetrics.fromJson', () {
    final fullJson = const <String, dynamic>{
      'scores': <String, dynamic>{
        'recovery': 72,
        'recovery_breakdown': <String, dynamic>{
          'hrv_z': 0.517,
          'rhr_z': 0.455,
          'sleep_z': 0.798,
          'resp_rate_z': 0.500,
          'prev_strain_z': 0.300,
        },
        'sleep_quality': 85,
        'sleep_breakdown': <String, dynamic>{
          'duration_score': 86.4,
          'efficiency_score': 92.8,
          'restorative_score': 43.4,
          'consistency_score': 95.6,
        },
        'sleep_debt_minutes': -65,
        'daily_strain': 42.0,
        'acwr': 1.15,
        'training_monotony': 1.8,
        'weight_trend_7d_kg_per_day': -0.0714,
        'weight_trend_28d_kg_per_day': -0.0357,
        'weight_trend_r2_28d': 0.85,
        'macro_adherence_pct': 95,
      },
      'baselines': <String, dynamic>{
        'hrv_sdnn_ms': <String, dynamic>{
          'ewma': 49.45,
          'spread': 3.0,
          'n_obs': 6,
          'confidence': 'low',
        },
        'resting_hr_bpm': <String, dynamic>{
          'ewma': 55.5,
          'spread': 1.1,
          'n_obs': 6,
          'confidence': 'low',
        },
        'sleep_minutes': <String, dynamic>{
          'ewma': 406.7,
          'spread': 10.4,
          'n_obs': 6,
          'confidence': 'low',
        },
        'weight_kg': <String, dynamic>{
          'ewma': 77.5,
          'spread': 0.4,
          'n_obs': 5,
          'confidence': 'low',
        },
        'resp_rate_bpm': <String, dynamic>{
          'ewma': 14.3,
          'spread': 0.6,
          'n_obs': 4,
          'confidence': 'low',
        },
      },
      'data_confidence': 'medium',
    };

    test('parses full fixture with all scores', () {
      final m = ComputedMetrics.fromJson(fullJson);

      expect(m.scores.recovery, 72);
      expect(m.scores.sleepQuality, 85);
      expect(m.scores.sleepDebtMinutes, -65);
      expect(m.scores.dailyStrain, 42.0);
      expect(m.scores.acwr, 1.15);
      expect(m.scores.trainingMonotony, 1.8);
      expect(m.scores.weightTrend7d, -0.0714);
      expect(m.scores.weightTrend28d, -0.0357);
      expect(m.scores.weightTrendR2, 0.85);
      expect(m.scores.macroAdherencePct, 95);
      expect(m.dataConfidence, 'medium');
    });

    test('parses recovery breakdown', () {
      final m = ComputedMetrics.fromJson(fullJson);
      final b = m.scores.recoveryBreakdown!;

      expect(b.hrvZ, 0.517);
      expect(b.rhrZ, 0.455);
      expect(b.sleepZ, 0.798);
      expect(b.respRateZ, 0.500);
      expect(b.prevStrainZ, 0.300);
    });

    test('parses sleep breakdown', () {
      final m = ComputedMetrics.fromJson(fullJson);
      final b = m.scores.sleepBreakdown!;

      expect(b.durationScore, 86.4);
      expect(b.efficiencyScore, 92.8);
      expect(b.restorativeScore, 43.4);
      expect(b.consistencyScore, 95.6);
    });

    test('parses baselines for all five metrics', () {
      final m = ComputedMetrics.fromJson(fullJson);

      expect(m.baselines.hrv!.ewma, 49.45);
      expect(m.baselines.hrv!.nObs, 6);
      expect(m.baselines.hrv!.confidence, 'low');

      expect(m.baselines.restingHr!.ewma, 55.5);
      expect(m.baselines.sleepMinutes!.ewma, 406.7);
      expect(m.baselines.weightKg!.ewma, 77.5);
      expect(m.baselines.respRate!.ewma, 14.3);
    });

    test('null recovery breakdown returns null', () {
      final m = ComputedMetrics.fromJson({
        'scores': <String, dynamic>{'recovery': 50},
        'baselines': <String, dynamic>{},
        'data_confidence': 'low',
      });

      expect(m.scores.recovery, 50);
      expect(m.scores.recoveryBreakdown, isNull);
      expect(m.scores.sleepQuality, isNull);
    });

    test('cold start with empty computed returns safe defaults', () {
      final m = ComputedMetrics.fromJson({
        'scores': <String, dynamic>{},
        'baselines': <String, dynamic>{},
        'data_confidence': 'cold_start',
      });

      expect(m.scores.recovery, isNull);
      expect(m.scores.sleepQuality, isNull);
      expect(m.scores.acwr, isNull);
      expect(m.baselines.hrv, isNull);
      expect(m.baselines.restingHr, isNull);
      expect(m.dataConfidence, 'cold_start');
    });

    test('null scores becomes empty and returns nulls', () {
      final m = ComputedMetrics.fromJson(<String, dynamic>{
        'baselines': <String, dynamic>{},
        'data_confidence': 'low',
      });

      expect(m.scores.recovery, isNull);
      expect(m.scores.sleepQuality, isNull);
      expect(m.scores.dailyStrain, isNull);
      expect(m.dataConfidence, 'low');
    });

    test('partial baselines parse only available metrics', () {
      final m = ComputedMetrics.fromJson({
        'scores': <String, dynamic>{},
        'baselines': <String, dynamic>{
          'hrv_sdnn_ms': <String, dynamic>{
            'ewma': 42.0,
            'spread': 5.0,
            'n_obs': 3,
            'confidence': 'low',
          },
        },
        'data_confidence': 'low',
      });

      expect(m.baselines.hrv!.ewma, 42.0);
      expect(m.baselines.restingHr, isNull);
      expect(m.baselines.sleepMinutes, isNull);
      expect(m.baselines.weightKg, isNull);
      expect(m.baselines.respRate, isNull);
    });

    test('null computed yields safe empty metrics', () {
      final m = ComputedMetrics.fromJson(null);

      expect(m.scores.recovery, isNull);
      expect(m.scores.recoveryBreakdown, isNull);
      expect(m.baselines.hrv, isNull);
      expect(m.dataConfidence, 'cold_start');
    });
  });

  group('RecoveryBreakdown', () {
    test('drivers are accessible as typed fields', () {
      final b = RecoveryBreakdown(
        hrvZ: 0.8,
        rhrZ: -0.2,
        sleepZ: 1.1,
        respRateZ: 0.0,
        prevStrainZ: -0.5,
      );

      expect(b.hrvZ, 0.8);
      expect(b.rhrZ, -0.2);
      expect(b.sleepZ, 1.1);
      expect(b.respRateZ, 0.0);
      expect(b.prevStrainZ, -0.5);
    });

    test('equality works for value comparison', () {
      final a = RecoveryBreakdown(
        hrvZ: 1.0,
        rhrZ: 0.5,
        sleepZ: 0.3,
        respRateZ: 0.1,
        prevStrainZ: 0.7,
      );
      final b = RecoveryBreakdown(
        hrvZ: 1.0,
        rhrZ: 0.5,
        sleepZ: 0.3,
        respRateZ: 0.1,
        prevStrainZ: 0.7,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('BaselineMetric', () {
    test('equality works for value comparison', () {
      final a = BaselineMetric(
        ewma: 50.0,
        spread: 3.0,
        nObs: 6,
        confidence: 'low',
      );
      final b = BaselineMetric(
        ewma: 50.0,
        spread: 3.0,
        nObs: 6,
        confidence: 'low',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
