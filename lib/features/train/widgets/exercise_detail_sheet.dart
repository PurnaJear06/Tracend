import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/exercise_history.dart';
import 'package:tracend/features/train/widgets/train_parts.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// Opens the exercise sheet: today's target, last time, your best, the
/// heaviest set of each logged session and the plan's tip.
Future<void> showExerciseDetailSheet(
  BuildContext context, {
  required PlannedWorkout workout,
  required PlannedExercise exercise,
  required WorkoutRepository repository,
  String? progressionRule,
}) {
  final index = workout.exercises.indexOf(exercise);
  return showTracendSheet<void>(
    context,
    title: exercise.name,
    subtitle:
        '${workout.name}, exercise ${index + 1} of ${workout.exercises.length}',
    builder: (_) => ExerciseDetailBody(
      exercise: exercise,
      history: repository.loadExerciseHistory([exercise.historyKey]),
      progressionRule: progressionRule,
    ),
  );
}

/// The sheet's body; [history] is the pending history request.
class ExerciseDetailBody extends StatelessWidget {
  const ExerciseDetailBody({
    required this.exercise,
    required this.history,
    this.progressionRule,
    super.key,
  });

  final PlannedExercise exercise;
  final Future<ExerciseHistoryResult> history;
  final String? progressionRule;

  static const firstTime =
      'First time. Pick a weight you can lift for every rep with good form.';
  static const offline = 'Last time loads when you’re online.';

  @override
  Widget build(BuildContext context) {
    final load = exercise.targetLoadKg;
    final notes = exercise.notes.trim();
    final rule = progressionRule?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: TracendSpacing.xs),
        TrainStatRow(
          tiles: [
            if (load != null)
              TrainStatTile(label: 'Today', value: '${formatKg(load)} kg'),
            TrainStatTile(
              label: 'Sets × reps',
              value: '${exercise.setCount} × ${_compactReps(exercise)}',
            ),
            TrainStatTile(label: 'Rest', value: restText(exercise.restSeconds)),
          ],
        ),
        const SizedBox(height: TracendSpacing.xs),
        Text(
          'Aim for about ${_repsLeft(exercise.targetRpe)} on each set.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        FutureBuilder<ExerciseHistoryResult>(
          future: history,
          builder: (context, snapshot) {
            final Widget child;
            if (snapshot.connectionState != ConnectionState.done) {
              child = const _HistoryLoading(key: ValueKey('loading'));
            } else if (snapshot.hasError) {
              child = _HistoryError(
                key: const ValueKey('error'),
                error: snapshot.error!,
              );
            } else {
              child = _HistoryView(
                key: const ValueKey('history'),
                result: snapshot.data!,
                exercise: exercise,
              );
            }
            return AnimatedSwitcher(
              duration: TracendMotionScope.fade(
                context,
                TracendMotion.standard,
              ),
              child: child,
            );
          },
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 14),
          TrainNote(
            icon: CupertinoIcons.lightbulb,
            label: 'From your plan',
            text: notes,
          ),
        ] else if (rule != null && rule.isNotEmpty) ...[
          const SizedBox(height: 14),
          TrainNote(
            icon: CupertinoIcons.arrow_up_right,
            label: 'Plan rule',
            text: rule,
          ),
        ],
      ],
    );
  }

  static String _compactReps(PlannedExercise exercise) =>
      exercise.repMin == exercise.repMax
      ? '${exercise.repMin}'
      : '${exercise.repMin}–${exercise.repMax}';

  /// The plan's target effort as reps left in reserve.
  static String _repsLeft(num rpe) {
    final left = (10 - rpe).round();
    if (left <= 0) return 'no reps left';
    if (left == 1) return '1 rep left';
    if (left >= 5) return '5 or more reps left';
    return '$left reps left';
  }
}

class _HistoryLoading extends StatelessWidget {
  const _HistoryLoading({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: TracendSpacing.md),
    child: Row(
      children: [
        const TracendLoader(semanticLabel: 'Loading your history'),
        const SizedBox(width: TracendSpacing.sm),
        Expanded(
          child: ExcludeSemantics(
            child: Text(
              'Loading your history',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    ),
  );
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const TrainNote(
        icon: CupertinoIcons.exclamationmark_circle,
        text: 'Your history for this exercise could not load.',
      ),
      const SizedBox(height: TracendSpacing.xxs),
      BetaDiagnostic(error),
    ],
  );
}

class _HistoryView extends StatelessWidget {
  const _HistoryView({required this.result, required this.exercise, super.key});

  final ExerciseHistoryResult result;
  final PlannedExercise exercise;

  @override
  Widget build(BuildContext context) {
    final history = result[exercise.historyKey];
    if (history == null) {
      return const TrainNote(
        icon: CupertinoIcons.wifi_slash,
        text: ExerciseDetailBody.offline,
      );
    }
    if (history.isFirstLog) {
      return const TrainNote(
        icon: CupertinoIcons.sparkles,
        text: ExerciseDetailBody.firstTime,
        raised: true,
      );
    }
    final last = history.lastSession;
    final best = history.bestSet;
    final kind = history.kind ?? best?.kind;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TracendGroupedList(
          children: [
            if (last != null)
              _row(
                largeText: largeText,
                title: 'Last time',
                value: lastSessionText(last.sets),
                detail: last.localDate == null
                    ? null
                    : friendlyDate(last.localDate!),
              ),
            if (best != null)
              _row(
                largeText: largeText,
                title: 'Your best',
                value: bestSetText(best),
                detail: switch (best.kind) {
                  ExerciseHistoryKind.load => 'Heaviest set you have logged',
                  ExerciseHistoryKind.reps => 'Most reps you have logged',
                  ExerciseHistoryKind.assistance =>
                    'Least help you have needed',
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        TopSetChart(topSets: history.topSets, kind: kind),
        if (result.fromCache) ...[
          const SizedBox(height: TracendSpacing.xs),
          Text(
            'Saved on this phone. It updates when you’re online.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// A history row. Large text moves the value under the title so neither is
/// squeezed.
TracendListRow _row({
  required bool largeText,
  required String title,
  required String value,
  String? detail,
}) => TracendListRow(
  title: title,
  subtitle: largeText ? [value, ?detail].join('\n') : detail,
  trailing: largeText ? null : _Value(value),
);

class _Value extends StatelessWidget {
  const _Value(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width * 0.45,
    ),
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontFamily: TracendFonts.numericFamily,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: context.tracendColors.textPrimary,
      ),
    ),
  );
}

/// "70 kg × 8, 8, 7" when every set used one load, "60 kg × 8, 62.5 kg × 6"
/// when the load changed, and "12, 10 reps" without loads.
String lastSessionText(List<HistorySet> sets) {
  final logged = sets.where((set) => set.repetitions != null).toList();
  if (logged.isEmpty) return 'No sets logged';
  final loads = logged.map((set) => set.loadKg).toSet();
  if (loads.length == 1 && loads.single == null) {
    return '${logged.map((set) => set.repetitions).join(', ')} reps';
  }
  if (loads.length == 1) {
    return '${formatKg(loads.single!)} kg × '
        '${logged.map((set) => set.repetitions).join(', ')}';
  }
  return logged
      .map(
        (set) => set.loadKg == null
            ? '${set.repetitions} reps'
            : '${formatKg(set.loadKg!)} kg × ${set.repetitions}',
      )
      .join(', ');
}

/// "72.5 kg × 6", "12 reps" or "20 kg help × 8".
String bestSetText(ExerciseBestSet best) {
  final reps = best.repetitions;
  final load = best.loadKg;
  return switch (best.kind) {
    ExerciseHistoryKind.reps => reps == null ? 'Not logged' : '$reps reps',
    ExerciseHistoryKind.load =>
      load == null
          ? (reps == null ? 'Not logged' : '$reps reps')
          : '${formatKg(load)} kg${reps == null ? '' : ' × $reps'}',
    ExerciseHistoryKind.assistance =>
      load == null || load == 0
          ? (reps == null ? 'Unassisted' : 'Unassisted × $reps')
          : '${formatKg(load)} kg help${reps == null ? '' : ' × $reps'}',
  };
}

/// The best set of each logged session, oldest to newest. Only logged sets
/// are drawn; planned values never are. Fewer than two sessions with a value
/// reads "Not enough data yet".
class TopSetChart extends StatelessWidget {
  const TopSetChart({required this.topSets, required this.kind, super.key});

  final List<ExerciseTopSet> topSets;
  final ExerciseHistoryKind? kind;

  static const notEnough = 'Not enough data yet';

  bool get _byReps => kind == ExerciseHistoryKind.reps;

  List<({DateTime date, double value})> get points => [
    for (final top in topSets.reversed)
      if (top.localDate != null &&
          (_byReps ? top.repetitions != null : top.loadKg != null))
        (
          date: top.localDate!,
          value: _byReps ? top.repetitions!.toDouble() : top.loadKg!.toDouble(),
        ),
  ];

  String get _caption => switch (kind) {
    ExerciseHistoryKind.reps => 'Most reps per session.',
    ExerciseHistoryKind.assistance =>
      'Machine help per session, in kg. Less help is stronger.',
    _ => 'Heaviest set per session, in kg.',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final data = points;
    if (data.length < 2) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(TracendRadii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notEnough, style: textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              'Your progress chart appears after two logged sessions.',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    final unit = _byReps ? 'reps' : 'kg';
    final speech = data
        .map((p) => '${shortDate(p.date)} ${formatKg(p.value)} $unit')
        .join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(8, 12, 12, 6),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(TracendRadii.card),
          ),
          child: Semantics(
            label: '$_caption $speech',
            excludeSemantics: true,
            child: SizedBox(
              height: 140,
              child: CustomPaint(
                painter: _TopSetPainter(
                  points: data,
                  line: colors.textPrimary,
                  latest: colors.accentSignalRing,
                  grid: colors.borderHairline,
                  label: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  textScaler: MediaQuery.textScalerOf(
                    context,
                  ).clamp(maxScaleFactor: 1.3),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: TracendSpacing.xs),
        Text(
          '$_caption Only logged sets are shown.',
          style: textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _TopSetPainter extends CustomPainter {
  _TopSetPainter({
    required this.points,
    required this.line,
    required this.latest,
    required this.grid,
    required this.label,
    required this.textScaler,
  });

  final List<({DateTime date, double value})> points;
  final Color line;
  final Color latest;
  final Color grid;
  final TextStyle label;
  final TextScaler textScaler;

  TextPainter _text(String text) => TextPainter(
    text: TextSpan(text: text, style: label),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final values = points.map((p) => p.value);
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final step = _niceStep((high - low).abs());
    final bottom = ((low - step / 2) / step).floor() * step;
    final top = ((high + step / 2) / step).ceil() * step;
    final ticks = [for (var v = bottom; v <= top + 1e-9; v += step) v];

    final tickLabels = [for (final v in ticks) _text(formatKg(v))];
    final left =
        tickLabels.map((t) => t.width).reduce(math.max) + 8; // label gap
    final dateLabels = [for (final p in points) _text(shortDate(p.date))];
    final labelHeight = dateLabels.first.height;
    final plotTop = 6.0;
    final plotBottom = size.height - labelHeight - 8;
    final plotLeft = left + 4;
    final plotRight = size.width - 8;
    double x(int i) =>
        plotLeft + (plotRight - plotLeft) * i / (points.length - 1);
    double y(double v) =>
        plotBottom - (v - bottom) / (top - bottom) * (plotBottom - plotTop);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i < ticks.length; i++) {
      final ty = y(ticks[i]);
      canvas.drawLine(Offset(plotLeft, ty), Offset(plotRight, ty), gridPaint);
      final t = tickLabels[i];
      t.paint(canvas, Offset(left - 4 - t.width, ty - t.height / 2));
    }

    final path = Path()..moveTo(x(0), y(points.first.value));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(x(i), y(points[i].value));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Date labels: first, last, and those in between that fit.
    var lastRight = double.negativeInfinity;
    for (var i = 0; i < points.length; i++) {
      final isLast = i == points.length - 1;
      final center = Offset(x(i), y(points[i].value));
      canvas.drawCircle(
        center,
        isLast ? 5 : 3.5,
        Paint()..color = isLast ? latest : line,
      );
      final t = dateLabels[i];
      var dx = x(i) - t.width / 2;
      dx = dx.clamp(0, size.width - t.width);
      final mustShow = i == 0 || isLast;
      if (!mustShow && dx < lastRight + 6) continue;
      if (!isLast && i > 0) {
        final lastLabel = dateLabels.last;
        final lastStart = (x(points.length - 1) - lastLabel.width / 2).clamp(
          0,
          size.width - lastLabel.width,
        );
        if (dx + t.width + 6 > lastStart) continue;
      }
      t.paint(canvas, Offset(dx, plotBottom + 8));
      lastRight = dx + t.width;
    }
  }

  static double _niceStep(double range) {
    if (range <= 0) return 2.5;
    final raw = range / 3;
    for (final candidate in [1.0, 2.5, 5.0, 10.0, 20.0, 25.0, 50.0]) {
      if (raw <= candidate) return candidate;
    }
    return 100;
  }

  @override
  bool shouldRepaint(_TopSetPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.line != line ||
      oldDelegate.latest != latest ||
      oldDelegate.grid != grid ||
      oldDelegate.textScaler != textScaler;
}
