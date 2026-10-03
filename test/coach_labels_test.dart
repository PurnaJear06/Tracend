import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/coach/coach_labels.dart';

void main() {
  group('provider display names', () {
    test('a known provider reads by its name', () {
      expect(aiAnswerLabel('deepseek'), 'AI answer · DeepSeek');
      expect(aiAnswerLabel('groq'), 'AI answer · Qwen');
      expect(aiAnswerLabel('gemini'), 'AI answer · Gemini');
      expect(aiProviderDisplayName('DeepSeek'), 'DeepSeek');
    });

    test('an unlisted or missing provider never shows its raw id', () {
      expect(aiProviderDisplayName('acme-llm'), isNull);
      expect(aiAnswerLabel('acme-llm'), 'AI answer');
      expect(aiAnswerLabel(null), 'AI answer');
    });
  });

  group('data gaps', () {
    test('every code the server produces reads as words', () {
      const codes = {
        'recovery_check_in': 'Morning check-in',
        'recovery_check_ins': 'Morning check-ins',
        'check_in': 'Morning check-in',
        'health_context': 'Recent Apple Health data',
        'resting_hr': 'Resting heart rate',
        'hrv_sdnn': 'Heart rate variability',
        'sleep_minutes': 'Sleep duration',
        'resp_rate': 'Respiratory rate',
        'prev_strain': 'Previous day’s training load',
        'restorative': 'Restorative sleep',
        'efficiency': 'Sleep efficiency',
        'consistency': 'Sleep consistency',
        'confirmed_nutrition': 'Confirmed meals',
        'nutrition_data': 'Confirmed meals',
        'active_training_plan': 'Active training plan',
        'current_plan': 'Current training plan',
        'training_history': 'Training history',
        'workout_execution': 'Logged workouts',
        'body_measurements': 'Body measurements',
      };
      for (final MapEntry(:key, :value) in codes.entries) {
        expect(coachGapLabel(key), value, reason: key);
      }
    });

    test('an unlisted code reads as words; a sentence stays as written', () {
      expect(coachGapLabel('weekly_volume'), 'Weekly volume');
      expect(
        coachGapLabel('Respiratory rate was not measured'),
        'Respiratory rate was not measured',
      );
    });
  });

  test('evidence sources and reasoning steps read as words', () {
    expect(
      coachEvidenceSourceLabel('feature_snapshot'),
      'Calculated from your health data',
    );
    expect(
      coachEvidenceSourceLabel('policy_evaluation'),
      'Tracend safety rules',
    );
    expect(coachEvidenceSourceLabel('coach_context'), 'Your coaching context');
    expect(coachReasoningStepLabel('training_age'), 'Training experience');
    expect(coachReasoningStepLabel('recovery_status'), 'Recovery');
    expect(coachReasoningStepLabel('sleep_debt'), 'Sleep debt');
  });

  test('context dates read as words, never ISO', () {
    final now = DateTime(2026, 10, 3, 9);
    expect(coachLatestLabel('2026-10-03', now: now), 'latest today');
    expect(coachLatestLabel('2026-10-02', now: now), 'latest yesterday');
    expect(coachLatestLabel('2026-07-10', now: now), 'latest Fri 10 Jul');
    expect(coachLatestLabel('2025-12-30', now: now), 'latest Tue 30 Dec 2025');
  });
}
