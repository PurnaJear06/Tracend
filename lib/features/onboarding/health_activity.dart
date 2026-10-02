import 'package:tracend/features/health/health_models.dart';

/// What onboarding shows from the athlete's Apple Health history before the
/// plan is built: average steps and the latest weight. The athlete still
/// answers every question; these only inform the answer.
class OnboardingHealthFacts {
  const OnboardingHealthFacts({
    required this.daysWithData,
    required this.metrics,
    this.stepsPerDay,
    this.latestWeightKg,
    this.latestWeightDate,
  });

  /// Days in the last four weeks with any Apple Health value.
  final int daysWithData;
  final Set<HealthMetric> metrics;

  /// Average daily steps over the last four complete weeks, when at least
  /// [onboardingMinimumStepDays] days have steps.
  final int? stepsPerDay;

  /// The newest weight from the last [onboardingWeightMaxAgeDays] days.
  final double? latestWeightKg;
  final DateTime? latestWeightDate;

  bool get hasData => daysWithData > 0;
}

/// The same thresholds as the server's onboarding summary
/// (supabase/functions/_shared/onboarding/health_summary.ts).
const onboardingHealthWindowDays = 28;
const onboardingMinimumStepDays = 7;
const onboardingWeightMaxAgeDays = 14;

OnboardingHealthFacts onboardingHealthFacts(
  HealthHistory history,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final first = today.subtract(
    const Duration(days: onboardingHealthWindowDays),
  );
  // Today is still going, so its steps are left out.
  final window = history.days.where((day) {
    final date = DateTime(day.date.year, day.date.month, day.date.day);
    return !date.isBefore(first) && date.isBefore(today);
  }).toList();
  final steps = [
    for (final day in window)
      if ((day.steps ?? 0) > 0) day.steps!,
  ];
  final weighed = [
    for (final day in history.days)
      if ((day.weightKg ?? 0) > 0 &&
          !DateTime(day.date.year, day.date.month, day.date.day).isBefore(
            today.subtract(const Duration(days: onboardingWeightMaxAgeDays)),
          ))
        day,
  ]..sort((a, b) => a.date.compareTo(b.date));
  return OnboardingHealthFacts(
    daysWithData: window.where((day) => day.presentMetrics.isNotEmpty).length,
    metrics: {for (final day in window) ...day.presentMetrics},
    stepsPerDay: steps.length >= onboardingMinimumStepDays
        ? (steps.reduce((a, b) => a + b) / steps.length).round()
        : null,
    latestWeightKg: weighed.isEmpty ? null : weighed.last.weightKg,
    latestWeightDate: weighed.isEmpty ? null : weighed.last.date,
  );
}

/// The daily-activity answer average steps point to. Steps never suggest
/// physical labour. The server uses the same bands for its notes
/// (`activityFromSteps` in health_summary.ts; ALGORITHMS §9).
String activityFromSteps(int stepsPerDay) {
  if (stepsPerDay < 5000) return 'mostly_sitting';
  if (stepsPerDay < 7500) return 'some_standing';
  return 'mostly_standing';
}

/// 9132 → "9,100": steps rounded to the nearest hundred.
String roundedSteps(int steps) {
  final hundreds = ((steps / 100).round() * 100).toString();
  final buffer = StringBuffer();
  for (var index = 0; index < hundreds.length; index++) {
    if (index > 0 && (hundreds.length - index) % 3 == 0) buffer.write(',');
    buffer.write(hundreds[index]);
  }
  return buffer.toString();
}
