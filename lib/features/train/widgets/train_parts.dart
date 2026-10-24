import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/widgets/muscle_map.dart';
import 'package:tracend/features/train/workout_logic.dart';
import 'package:tracend/features/train/workout_repository.dart';

/// Small pieces the Train screen and its sheets share.

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Thursday".
String weekdayName(DateTime date) => _weekdayNames[date.weekday - 1];

/// "Thursday 2 October".
String longDate(DateTime date) =>
    '${weekdayName(date)} ${date.day} ${_monthNames[date.month - 1]}';

/// "2 October".
String dayMonth(DateTime date) => '${date.day} ${_monthNames[date.month - 1]}';

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "72.5" or "70": a load as logged, without a trailing ".0".
String formatKg(num kg) {
  final value = kg.toDouble();
  if (value == value.roundToDouble()) return value.round().toString();
  final text = value.toStringAsFixed(2);
  return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// "90 s", "2 min" or "2 min 30 s".
String restText(int seconds) {
  if (seconds < 120) return '$seconds s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return rest == 0 ? '$minutes min' : '$minutes min $rest s';
}

/// "8" or "8 to 10".
String repRange(PlannedExercise exercise) => exercise.repMin == exercise.repMax
    ? '${exercise.repMin}'
    : '${exercise.repMin} to ${exercise.repMax}';

/// Whether [exercise]'s load is machine help, by the server's rule.
bool isAssistedPlanned(PlannedExercise exercise) =>
    isAssistedExercise(slug: exercise.exerciseSlug, name: exercise.name);

/// "62.5 kg × 5", "11 reps" for an exercise logged without a load, and, for
/// an [assisted] exercise (the load is machine help), "20 kg help × 8" or
/// "Unassisted × 8" as the workout screen words it.
String nextTargetText(NextTarget target, {bool assisted = false}) {
  final load = target.loadKg;
  if (load == null) return '${target.reps} reps';
  if (assisted) {
    return load == 0
        ? 'Unassisted × ${target.reps}'
        : '${formatKg(load)} kg help × ${target.reps}';
  }
  return '${formatKg(load)} kg × ${target.reps}';
}

/// Why the target is what it is, in the athlete's words. Null for a reason
/// code this build does not know: the target still shows, unexplained.
String? nextTargetWhy(NextTarget target, {bool assisted = false}) {
  final lowered = target.action == NextTargetAction.lower;
  final text = switch (target.reason) {
    'top_of_range' =>
      assisted
          ? 'Every set reached the top of the range last time. Use less help '
                'and start the reps again.'
          : 'Every set reached the top of the range last time. Add weight and '
                'start the reps again.',
    'within_range' =>
      assisted
          ? 'Add one rep to your weakest set before using less help.'
          : 'Add one rep to your weakest set before adding weight.',
    'top_no_step' =>
      'You are at the top of the range. Try a harder variation to keep '
          'progressing.',
    'incomplete' =>
      'You finished fewer sets than planned. Repeat last time first.',
    'effort' => 'Last time was close to your limit. Repeat the weight.',
    'below_range' =>
      lowered
          ? (assisted
                ? 'Reps stayed below the range twice, so you get a step more '
                      'help.'
                : 'Reps stayed below the range twice, so the weight comes '
                      'down a step.')
          : 'Reps dropped below the range. Aim for the bottom of the range '
                'at this weight.',
    'stall' =>
      lowered
          ? (assisted
                ? 'Three sessions without progress at this help, so you get a '
                      'step more help.'
                : 'Three sessions without progress at this weight, so it '
                      'comes down a step.')
          : 'Three sessions without progress at this weight. Repeat it.',
    'away' =>
      lowered
          ? (assisted
                ? 'You have been away a while, so you get a step more help.'
                : 'You have been away a while, so the weight comes down a '
                      'step.')
          : 'You have been away a while. Repeat your last result.',
    'skipped' => 'You skipped this last time. Repeat your last result.',
    'pain' =>
      'Pain was flagged last time. Repeat your last result and keep it '
          'comfortable.',
    'day_adjustment' =>
      "You chose to keep last time's weight today. Tomorrow's target comes "
          'from how you train.',
    _ => null,
  };
  if (text == null || !target.lowConfidence) return text;
  return '$text Reps left were not logged, so check it feels right.';
}

/// "3 × 8 to 10 at 72.5 kg", or without a load when the plan sets none. With
/// a next target from the sets logged: "3 × 8 to 10 · next 75 kg × 8".
String exerciseLine(PlannedExercise exercise) {
  final base = '${exercise.setCount} × ${repRange(exercise)}';
  final next = exercise.nextTarget;
  if (next != null) {
    final assisted = isAssistedPlanned(exercise);
    // A held target is today's choice, not the next progression step.
    final word = exercise.loadHeld ? 'hold' : 'next';
    return '$base · $word ${nextTargetText(next, assisted: assisted)}';
  }
  final load = exercise.targetLoadKg;
  return load == null ? base : '$base at ${formatKg(load)} kg';
}

int totalSets(PlannedWorkout workout) =>
    workout.exercises.fold<int>(0, (sum, item) => sum + item.setCount);

/// What today's accepted same-day adjustment did to [workout]: "Lighter
/// today: 12 of 15 sets" or "Weights held today". Null when it did nothing.
String? dayAdjustmentNote(PlannedWorkout workout) {
  final planned = workout.exercises.fold<int>(
    0,
    (sum, item) => sum + (item.plannedSetCount ?? item.setCount),
  );
  final now = totalSets(workout);
  if (now < planned) return 'Lighter today: $now of $planned sets';
  return workout.exercises.any((item) => item.loadHeld)
      ? 'Weights held today'
      : null;
}

/// "6 exercises, about 48 min".
String workoutMeta(PlannedWorkout workout) {
  final count = workout.exercises.length;
  return '$count ${count == 1 ? 'exercise' : 'exercises'}, about '
      '${workout.estimatedMinutes} min';
}

/// The muscle map palette for the current theme.
MuscleMapPalette musclePalette(BuildContext context) {
  final colors = context.tracendColors;
  final base = Theme.of(context).brightness == Brightness.dark
      ? MuscleMapPalette.dark
      : MuscleMapPalette.light;
  return MuscleMapPalette(
    base: colors.mapBase,
    off: colors.mapOff,
    mainStart: base.mainStart,
    mainEnd: base.mainEnd,
    hatch: base.hatch,
    shadow: base.shadow,
    glowOpacity: base.glowOpacity,
    shading: base.shading,
  );
}

/// Archivo for titles inside cards and sheets.
TextStyle trainDisplay(
  BuildContext context, {
  double size = 30,
  FontWeight weight = FontWeight.w800,
  Color? color,
}) => TextStyle(
  fontFamily: TracendFonts.displayFamily,
  fontSize: size,
  height: 1.05,
  letterSpacing: -0.02 * size,
  fontWeight: weight,
  color: color ?? context.tracendColors.textPrimary,
);

/// A note with a leading icon tile, a small label and a sentence: advice,
/// a plan tip, a first-time hint.
class TrainNote extends StatelessWidget {
  const TrainNote({
    required this.icon,
    required this.text,
    this.label,
    this.raised = false,
    super.key,
  });

  final IconData icon;
  final String? label;
  final String text;

  /// A raised fill for a note that sits on a surface rather than a sheet.
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: raised ? colors.surfaceRaised : colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: raised ? colors.surface : colors.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: colors.textPrimary),
          ),
          const SizedBox(width: TracendSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null) ...[
                  Text(
                    label!,
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(text, style: textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small readout tile: a label above a big number.
class TrainStatTile extends StatelessWidget {
  const TrainStatTile({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(TracendSpacing.sm),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              value,
              style: TextStyle(
                fontFamily: TracendFonts.numericFamily,
                fontSize: 22,
                height: 1.1,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiles side by side, or stacked when the text is large or the space is
/// narrow, so a number never clips.
class TrainStatRow extends StatelessWidget {
  const TrainStatRow({required this.tiles, super.key});

  final List<TrainStatTile> tiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final perTile = constraints.maxWidth / tiles.length;
      if (scale > 1.35 || perTile < 96) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(height: TracendSpacing.xs),
              tiles[i],
            ],
          ],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: TracendSpacing.xs),
              Expanded(child: tiles[i]),
            ],
          ],
        ),
      );
    },
  );
}

/// A small numbered tile that leads an exercise row.
class ExerciseIndexTile extends StatelessWidget {
  const ExerciseIndexTile({required this.number, super.key});

  final int number;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Text(
          '$number',
          style: TextStyle(
            fontFamily: TracendFonts.displayFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Beta diagnostics: the raw reason in small secondary text, under the
/// plain message, so a tester can report it.
class BetaDiagnostic extends StatelessWidget {
  const BetaDiagnostic(this.error, {super.key});

  final Object error;

  static String describe(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 160 ? '${text.substring(0, 157)}...' : text;
  }

  @override
  Widget build(BuildContext context) => SelectableText(
    describe(error),
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 11,
      color: context.tracendColors.textSecondary,
    ),
  );
}
