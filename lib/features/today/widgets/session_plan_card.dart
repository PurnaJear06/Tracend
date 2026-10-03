import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/pressable.dart';

/// Today's workout as the screen's training card: the brief's
/// `today_workout` name in display type, its real time, exercise and set
/// counts as pills, and a lime "View workout" action. When the brief has
/// one, a display-only training load line from the real ACWR
/// (`ComputedScores.acwr`; hidden when null, never fabricated) closes it.
///
/// State table:
/// - workout: the card and its action open the workout ([onOpen])
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
    final colors = context.tracendColors;
    final workout = this.workout;
    final acwr = this.acwr;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(TracendRadii.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (workout == null)
            _RestDay(onOpenWeek: onOpenWeek)
          else
            _WorkoutBody(workout: workout, onOpen: onOpen),
          if (acwr != null) ...[
            Divider(height: 1, thickness: 1, color: colors.borderHairline),
            _LoadRow(acwr: acwr),
          ],
        ],
      ),
    );
  }
}

class _WorkoutBody extends StatelessWidget {
  const _WorkoutBody({required this.workout, required this.onOpen});

  final Map<String, dynamic> workout;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final name = workout['name'] as String? ?? 'Training session';
    final detail = workoutSummary(workout);
    final exercises = workout['exercises'] as List? ?? const [];
    final sets = exercises.fold<int>(
      0,
      (sum, item) =>
          sum +
          ((item is Map ? item['set_count'] as num? : null)?.toInt() ?? 0),
    );
    final minutes = (workout['estimated_minutes'] as num?)?.toInt();
    return Pressable(
      onTap: onOpen,
      pressedScale: 0.985,
      semanticLabel: "Today's workout: $name. $detail. Opens the workout.",
      borderRadius: BorderRadius.circular(TracendRadii.card),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TracendSpacing.gutter,
          TracendSpacing.gutter,
          TracendSpacing.gutter,
          TracendSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's workout",
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.accentSignalInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        style: textTheme.headlineMedium?.copyWith(
                          fontSize: 26,
                          height: 1.08,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: TracendSpacing.sm),
                ExcludeSemantics(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: colors.accentSignal,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.fitness_center_rounded,
                      size: 26,
                      color: colors.onAccentSignal,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TracendSpacing.md),
            ExcludeSemantics(
              child: Wrap(
                spacing: TracendSpacing.xs,
                runSpacing: TracendSpacing.xs,
                children: [
                  if (minutes != null)
                    _StatPill(
                      icon: CupertinoIcons.timer,
                      value: '$minutes',
                      unit: 'min',
                    ),
                  if (exercises.isNotEmpty)
                    _StatPill(
                      icon: CupertinoIcons.list_bullet,
                      value: '${exercises.length}',
                      unit: exercises.length == 1 ? 'exercise' : 'exercises',
                    ),
                  if (sets > 0)
                    _StatPill(
                      icon: CupertinoIcons.square_stack_3d_up_fill,
                      value: '$sets',
                      unit: sets == 1 ? 'set' : 'sets',
                    ),
                ],
              ),
            ),
            const SizedBox(height: TracendSpacing.md),
            FilledButton.icon(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: colors.accentSignal,
                foregroundColor: colors.onAccentSignal,
              ),
              icon: const Icon(CupertinoIcons.play_fill, size: 18),
              label: const Text('View workout'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One stat on the workout card: "55 min", "7 sets".
class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.value,
    required this.unit,
  });

  final IconData icon;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(TracendRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.textSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontFamily: TracendFonts.numericFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final onOpenWeek = this.onOpenWeek;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.gutter,
        TracendSpacing.gutter,
        TracendSpacing.gutter,
        TracendSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's workout",
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Rest day',
                      style: textTheme.headlineMedium?.copyWith(fontSize: 26),
                    ),
                    const SizedBox(height: TracendSpacing.xxs),
                    Text(
                      'Your approved plan has no workout today.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: TracendSpacing.sm),
              ExcludeSemantics(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colors.surfaceRaised,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.moon_stars_fill,
                    size: 24,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (onOpenWeek != null) ...[
            const SizedBox(height: TracendSpacing.md),
            OutlinedButton(
              onPressed: onOpenWeek,
              child: const Text('See your week'),
            ),
          ],
        ],
      ),
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
