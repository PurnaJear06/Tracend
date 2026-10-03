import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/widgets/rpe_picker.dart';
import 'package:tracend/features/train/widgets/set_row.dart';
import 'package:tracend/shared/brand/tracend_mark.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// One exercise that set a new best in this workout.
@immutable
class WorkoutNewBest {
  const WorkoutNewBest({
    required this.exercise,
    required this.lifted,
    this.previous,
  });

  final String exercise;

  /// The best of this workout's new-best sets, "65 kg × 6".
  final String lifted;

  /// The best before today, when the history named one.
  final String? previous;
}

/// What the summary shows, all counted on the device from the logged sets.
@immutable
class WorkoutSummary {
  const WorkoutSummary({
    required this.workoutName,
    required this.date,
    required this.durationSeconds,
    required this.completedSets,
    required this.weightLiftedKg,
    required this.effort,
    this.newBests = const [],
  });

  final String workoutName;
  final DateTime date;
  final int durationSeconds;
  final int completedSets;

  /// From `weightLiftedKg`: completed sets with an added load, as logged.
  final num weightLiftedKg;

  /// The athlete's 1–10 answer to "How hard was this workout overall?".
  final int effort;
  final List<WorkoutNewBest> newBests;

  /// Whole minutes, at least one.
  int get minutes => durationSeconds < 60 ? 1 : (durationSeconds / 60).round();
}

/// "1,240" or "1,237.5".
String formatWeightLifted(num kg) {
  final tenths = (kg * 10).round();
  final whole = (tenths ~/ 10).toString();
  final grouped = whole.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
  return tenths % 10 == 0 ? grouped : '$grouped.${tenths % 10}';
}

/// The finished workout: a check, the time, sets and weight lifted counting
/// up, and any new bests stamped onto the card. Completes when it closes.
Future<void> showWorkoutSummarySheet(
  BuildContext context,
  WorkoutSummary summary,
) => showTracendSheet<void>(
  context,
  builder: (sheetContext) => WorkoutSummaryView(
    summary: summary,
    onDone: () => Navigator.of(sheetContext).pop(),
  ),
);

/// The body of the summary sheet.
class WorkoutSummaryView extends StatefulWidget {
  const WorkoutSummaryView({
    required this.summary,
    required this.onDone,
    super.key,
  });

  final WorkoutSummary summary;
  final VoidCallback onDone;

  @override
  State<WorkoutSummaryView> createState() => _WorkoutSummaryViewState();
}

class _WorkoutSummaryViewState extends State<WorkoutSummaryView>
    with SingleTickerProviderStateMixin {
  /// The whole entrance: check (0–600 ms), card (120–640 ms), numbers
  /// (300–1200 ms) and the new-best stamps (from 900 ms, 220 ms apart).
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: 1520 + 220 * widget.summary.newBests.length,
    ),
  );
  TracendMotionLevel? _level;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final level = TracendMotionScope.of(context);
    if (level == _level) return;
    _level = level;
    if (level == TracendMotionLevel.static) {
      _entrance.value = 1;
    } else {
      _entrance.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  double _phase(int startMs, int endMs, {Curve curve = Curves.linear}) {
    final total = _entrance.duration!.inMilliseconds;
    final t = ((_entrance.value * total - startMs) / (endMs - startMs)).clamp(
      0.0,
      1.0,
    );
    return curve.transform(t);
  }

  bool get _full => _level == TracendMotionLevel.full;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final summary = widget.summary;
    final friendly = friendlyDate(summary.date);
    final dateLabel = friendly == 'Today' || friendly == 'Yesterday'
        ? '$friendly, ${shortDate(summary.date)}'
        : friendly;
    final onCard = colors.actionOnPrimary;
    final muted = onCard.withValues(alpha: 0.68);

    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, _) {
        final check = _phase(0, 600, curve: TracendMotion.settle);
        final card = _phase(120, 640, curve: TracendMotion.settle);
        final count = _full
            ? _phase(300, 1200, curve: Curves.easeOutCubic)
            : 1.0;

        Widget stat(String label, String value, String? unit, String spoken) =>
            Semantics(
              label: '$label: $spoken',
              excludeSemantics: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 72),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: text.labelSmall?.copyWith(color: muted)),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        text: value,
                        children: [
                          if (unit != null)
                            TextSpan(
                              text: ' $unit',
                              style: text.labelLarge?.copyWith(color: muted),
                            ),
                        ],
                      ),
                      style: TracendTheme.numeric(
                        colors,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: onCard,
                      ).copyWith(height: 1, letterSpacing: -0.5),
                    ),
                  ],
                ),
              ),
            );

        final weight = summary.weightLiftedKg * count;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: TracendSpacing.xs),
            Center(
              child: Opacity(
                opacity: _full ? check.clamp(0.0, 1.0) : _phase(0, 240),
                child: Transform.scale(
                  scale: _full ? 0.6 + 0.4 * check : 1,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colors.stateStable,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.checkmark_alt,
                      size: 34,
                      color: colors.onStateGood,
                      semanticLabel: 'Saved',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: TracendSpacing.sm),
            Semantics(
              header: true,
              child: Text(
                'Workout complete',
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
            ),
            const SizedBox(height: TracendSpacing.lg),
            Opacity(
              opacity: _full ? card.clamp(0.0, 1.0) : _phase(0, 240),
              child: Transform.translate(
                offset: Offset(0, _full ? 24 * (1 - card) : 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.actionPrimary,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                dateLabel,
                                style: text.labelMedium?.copyWith(color: muted),
                              ),
                            ),
                            TracendMark(
                              size: 24,
                              letterColor: onCard,
                              semanticLabel: null,
                            ),
                          ],
                        ),
                        const SizedBox(height: TracendSpacing.xxs),
                        Text(
                          summary.workoutName,
                          style: text.headlineMedium?.copyWith(color: onCard),
                        ),
                        const SizedBox(height: TracendSpacing.gutter),
                        Wrap(
                          spacing: TracendSpacing.lg,
                          runSpacing: TracendSpacing.md,
                          children: [
                            stat(
                              'Time',
                              '${(summary.minutes * count).round()}',
                              'min',
                              '${summary.minutes} minutes',
                            ),
                            stat(
                              'Sets',
                              '${(summary.completedSets * count).round()}',
                              null,
                              '${summary.completedSets}',
                            ),
                            stat(
                              'Weight lifted',
                              formatWeightLifted(weight),
                              'kg',
                              '${formatWeightLifted(summary.weightLiftedKg)} '
                                  'kilograms',
                            ),
                          ],
                        ),
                        const SizedBox(height: TracendSpacing.sm),
                        Text(
                          'Counts sets with added weight, as you logged them.',
                          style: text.bodySmall?.copyWith(color: muted),
                        ),
                        for (var i = 0; i < summary.newBests.length; i++)
                          _stampRow(context, i, onCard, muted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: TracendSpacing.md),
            TracendGroupedList(
              children: [
                TracendListRow(
                  title: 'How hard it felt',
                  subtitle: 'Sets your training load',
                  trailing: Text(
                    '${summary.effort}, '
                    '${sessionEffortAnchor(summary.effort)}',
                    style: TracendTheme.numeric(
                      colors,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TracendSpacing.lg),
            FilledButton(onPressed: widget.onDone, child: const Text('Done')),
          ],
        );
      },
    );
  }

  Widget _stampRow(BuildContext context, int index, Color onCard, Color muted) {
    final best = widget.summary.newBests[index];
    final text = Theme.of(context).textTheme;
    final start = 900 + 220 * index;
    final t = _full
        ? _phase(start, start + 620, curve: Curves.easeOutBack)
        : _phase(0, 240);
    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? TracendSpacing.md : 10),
      child: Semantics(
        container: true,
        label:
            'New best: ${best.exercise}, ${best.lifted}'
            '${best.previous == null ? '' : '. Previous best ${best.previous}'}',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform(
                alignment: Alignment.center,
                transform: _full
                    ? (Matrix4.identity()
                        ..translateByDouble(0, -40 * (1 - t), 0, 1)
                        ..rotateZ(-0.05 - 0.25 * (1 - t))
                        ..scaleByDouble(
                          1 + 0.8 * (1 - t),
                          1 + 0.8 * (1 - t),
                          1,
                          1,
                        ))
                    : (Matrix4.identity()..rotateZ(-0.05)),
                child: const NewBestStamp(large: true),
              ),
            ),
            const SizedBox(width: TracendSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${best.exercise} ${best.lifted}',
                    style: text.titleSmall?.copyWith(color: onCard),
                  ),
                  if (best.previous != null)
                    Text(
                      'Previous best ${best.previous}',
                      style: text.bodySmall?.copyWith(color: muted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
