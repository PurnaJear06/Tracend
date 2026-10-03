import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/pressable.dart';

/// Today's workout, as rows in one grouped list: the brief's `today_workout`
/// (name, exercise and set counts folded from the real `exercises` array,
/// and the estimated time) and, when the brief has one, a display-only
/// training load row from the real ACWR (`ComputedScores.acwr`; hidden when
/// null, never fabricated).
///
/// State table:
/// - workout: a tappable row that opens the workout ([onOpen])
/// - no workout: "Rest day" with an enabled secondary action to see the
///   week ([onOpenWeek]; left out when not wired)
/// - ACWR present: "Training load: about normal" with the ratio as detail
class SessionPlanCard extends StatelessWidget {
  const SessionPlanCard({
    required this.workout,
    required this.onOpen,
    this.acwr,
    this.onOpenWeek,
    super.key,
  });

  final Map<String, dynamic>? workout;
  final VoidCallback onOpen;

  /// Acute:chronic workload ratio from computed scores. Null hides the row.
  final double? acwr;

  /// Opens the week in Train from the rest-day state.
  final VoidCallback? onOpenWeek;

  @override
  Widget build(BuildContext context) {
    final workout = this.workout;
    final acwr = this.acwr;
    return TracendGroupedList(
      children: [
        if (workout == null)
          _RestDay(onOpenWeek: onOpenWeek)
        else
          _WorkoutRow(workout: workout, onOpen: onOpen),
        if (acwr != null) _LoadRow(acwr: acwr),
      ],
    );
  }
}

class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({required this.workout, required this.onOpen});

  final Map<String, dynamic> workout;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final name = workout['name'] as String? ?? 'Training session';
    final detail = workoutSummary(workout);
    return Pressable(
      onTap: onOpen,
      pressedScale: 0.98,
      semanticLabel: "Today's workout: $name. $detail. Opens the workout.",
      borderRadius: BorderRadius.circular(TracendRadii.card),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 76),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TracendListRow.horizontalPadding,
            vertical: TracendSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.accentSignalTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CupertinoIcons.bolt_fill,
                  size: 20,
                  color: colors.accentSignalInk,
                ),
              ),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's workout",
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(name, style: textTheme.titleMedium),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: TracendSpacing.xs),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "2 exercises · 7 sets · about 60 min" from the real workout map; any
/// part the plan does not carry is left out rather than guessed.
String workoutSummary(Map<String, dynamic> workout) {
  final exercises = workout['exercises'] as List? ?? const [];
  final sets = exercises.fold<int>(
    0,
    (sum, item) =>
        sum + ((item is Map ? item['set_count'] as num? : null)?.toInt() ?? 0),
  );
  final minutes = (workout['estimated_minutes'] as num?)?.toInt();
  return [
    if (exercises.isNotEmpty)
      '${exercises.length} ${exercises.length == 1 ? 'exercise' : 'exercises'}',
    if (sets > 0) '$sets ${sets == 1 ? 'set' : 'sets'}',
    if (minutes != null) 'about $minutes min',
  ].join(' · ');
}

class _RestDay extends StatelessWidget {
  const _RestDay({required this.onOpenWeek});

  final VoidCallback? onOpenWeek;

  @override
  Widget build(BuildContext context) {
    final onOpenWeek = this.onOpenWeek;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TracendListRow(
          leading: TracendRowIcon(icon: CupertinoIcons.moon_fill),
          title: 'Rest day',
          subtitle: 'Your approved plan has no workout today.',
        ),
        if (onOpenWeek != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TracendListRow.horizontalPadding,
              0,
              TracendListRow.horizontalPadding,
              TracendSpacing.sm,
            ),
            child: OutlinedButton(
              onPressed: onOpenWeek,
              child: const Text('See your week'),
            ),
          ),
      ],
    );
  }
}

/// Display-only training load row from the real ACWR, with the app-wide
/// bands (ALGORITHMS.md "ACWR Bands", `LoadBand.forAcwr`): under 0.8 lighter
/// than usual, 0.8–1.3 about normal, above 1.3 heavier than usual, and above
/// 1.5 much heavier.
class _LoadRow extends StatelessWidget {
  const _LoadRow({required this.acwr});

  final double acwr;

  @override
  Widget build(BuildContext context) {
    final words = trainingLoadWords(acwr);
    final ratio = acwr.toStringAsFixed(2);
    return TracendListRow(
      leading: const TracendRowIcon(icon: CupertinoIcons.speedometer),
      title: 'Training load: $words',
      subtitle: 'Last 7 days against your 4-week average · ratio $ratio',
      semanticLabel: 'Training load: $words. Ratio $ratio.',
    );
  }
}

/// Plain words for an ACWR value.
String trainingLoadWords(double acwr) {
  if (acwr < 0.8) return 'lighter than usual';
  if (acwr <= 1.3) return 'about normal';
  if (acwr <= 1.5) return 'heavier than usual';
  return 'much heavier than usual';
}
