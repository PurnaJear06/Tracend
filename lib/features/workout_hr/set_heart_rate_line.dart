import 'package:tracend/features/workout_hr/set_heart_rate_repository.dart';

/// The one small heart-rate line under an exercise in a finished workout's
/// summary: the peak of each set that has one, and how much of the sets and
/// their recovery minutes had readings. Null when no set of the exercise has
/// a heart rate. It informs only; heart rate never changes a load or a
/// prescription.
///
/// [completedSets] is how many sets the exercise completed. The report holds
/// only the sets that had readings, so the share tracked divides by this
/// count, and a set with no readings counts as 0 (one tracked set out of
/// four reads 25%, never 100%).
String? setHeartRateLine(
  SetHeartRateReport report,
  int exerciseOrder, {
  required int completedSets,
}) {
  final sets = report.forExercise(exerciseOrder);
  final peaks = [
    for (final set in sets)
      if (set.peakBpm != null) set.peakBpm!,
  ];
  if (peaks.isEmpty) return null;
  final all = completedSets < sets.length ? sets.length : completedSets;
  final coverage = sets.fold<double>(0, (sum, set) => sum + set.coverage) / all;
  return 'Heart rate peaks ${peaks.join(' · ')} bpm · '
      '${(coverage * 100).round()}% tracked';
}
