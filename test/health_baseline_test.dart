import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/health/health_baseline.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/onboarding/onboarding_repository.dart';
import 'package:tracend/features/train/workout_repository.dart';

void main() {
  final now = DateTime(2026, 10, 3, 9);
  var id = 0;

  RawHealthSample workout(DateTime start, String type, {int minutes = 60}) =>
      RawHealthSample(
        metric: HealthMetric.workouts,
        value: 1,
        start: start,
        end: start.add(Duration(minutes: minutes)),
        sampleId: 'workout-${id++}',
        sourceId: 'watch',
        workoutActivityType: type,
      );

  RawHealthSample night(DateTime morning, int minutes) => RawHealthSample(
    metric: HealthMetric.sleep,
    value: minutes.toDouble(),
    start: morning.subtract(Duration(minutes: minutes)),
    end: morning,
    sampleId: 'sleep-${id++}',
    sourceId: 'watch',
    sleepStage: SleepStage.asleep,
  );

  RawHealthSample weighIn(DateTime at, double kg) => RawHealthSample(
    metric: HealthMetric.weight,
    value: kg,
    start: at,
    end: at,
    sampleId: 'weight-${id++}',
    sourceId: 'scale',
  );

  test('the history reads the 11 completed months, never this one', () {
    expect(healthHistoryStart(now), DateTime(2025, 11));
    final months = healthMonthTotals([
      workout(DateTime(2025, 10, 20, 7), 'TRADITIONAL_STRENGTH_TRAINING'),
      workout(DateTime(2026, 9, 2, 7), 'TRADITIONAL_STRENGTH_TRAINING'),
      workout(DateTime(2026, 9, 3, 7), 'RUNNING', minutes: 30),
      workout(DateTime(2026, 10, 1, 7), 'TRADITIONAL_STRENGTH_TRAINING'),
    ], now);
    expect(months, hasLength(1));
    final september = months.single;
    expect(september.month, DateTime(2026, 9));
    expect(september.workouts, 2);
    expect(september.strengthWorkouts, 1);
    expect(september.workoutMinutes, 90);
    expect(september.toJson()['month'], '2026-09-01');
    expect(september.toJson()['first_data_date'], '2026-09-02');
    expect(september.toJson()['last_data_date'], '2026-09-03');
  });

  test('sleep and weight are averaged with their coverage', () {
    final months = healthMonthTotals([
      for (var day = 1; day <= 22; day++)
        night(DateTime(2026, 8, day, 7), day.isEven ? 420 : 400),
      weighIn(DateTime(2026, 8, 5, 7), 80.2),
      weighIn(DateTime(2026, 8, 19, 7), 79.6),
    ], now);
    final august = months.single;
    expect(august.sleepNights, 22);
    expect(august.sleepMinutesAvg, 410);
    expect(august.weightDays, 2);
    expect(august.weightKgAvg, 79.9);
    expect(august.dataDays, 22);
  });

  test('usual vs recent: a median from the first month with a workout', () {
    final samples = [
      for (final month in [7, 8, 9])
        for (var day = 1; day <= 16; day++)
          workout(
            DateTime(2026, month, day, 7),
            'TRADITIONAL_STRENGTH_TRAINING',
          ),
      // The last 28 complete days: four strength sessions.
      for (final day in [6, 13, 20, 27])
        workout(DateTime(2026, 9, day, 18), 'FUNCTIONAL_STRENGTH_TRAINING'),
    ];
    final months = healthMonthTotals(samples, now);
    final baseline = healthBaseline(months, samples, now);
    // July 16/4.43, August 16/4.43, September 20/4.29: median 3.6.
    expect(baseline.usualStrengthPerWeek, 3.6);
    // Sept 5 – Oct 2: the four, plus the sessions on the 5th–16th.
    expect(baseline.recentStrengthPerWeek, 4);
    expect(baseline.usualSleepMinutes, isNull);
    expect(baseline.hasUsual, isTrue);
  });

  test('no workouts at all is "none found", not zero', () {
    final baseline = healthBaseline(const [], const [], now);
    expect(baseline.usualStrengthPerWeek, isNull);
    expect(baseline.recentStrengthPerWeek, isNull);
    expect(baseline.hasUsual, isFalse);
  });

  test('a planned exercise carries its starting load from the hub', () {
    final workout = PlannedWorkout.fromHubJson({
      'id': 'w-1',
      'name': 'Upper',
      'objective': 'Press',
      'estimated_minutes': 50,
      'exercises': [
        {
          'order': 1,
          'name': 'Barbell bench press',
          'set_count': 4,
          'rep_min': 5,
          'rep_max': 8,
          'target_rpe': 8,
          'target_load_kg': 82.5,
        },
        {
          'order': 2,
          'name': 'Cable fly',
          'set_count': 3,
          'rep_min': 10,
          'rep_max': 15,
        },
      ],
    });
    expect(workout.exercises.first.targetLoadKg, 82.5);
    expect(workout.exercises.last.targetLoadKg, isNull);
  });

  test('questions parse safely; a reply without a hash is no reply', () {
    final questions = OnboardingQuestions.fromJson({
      'schema_version': '1.0',
      'questions_hash': 'a' * 64,
      'questions': [
        {
          'category': 'split_history',
          'question': 'Which split?',
          'choices': ['Full body', 'Upper/lower'],
        },
        {'category': 'stalled_lift'},
      ],
    })!;
    expect(questions.questions, hasLength(1));
    expect(questions.questions.single.choices, ['Full body', 'Upper/lower']);
    expect(OnboardingQuestions.fromJson({'questions': []}), isNull);
  });
}
