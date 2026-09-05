import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Train hero (Stitch `train.html`): approved workout headline, real
/// exercise/set/duration facts folded from the plan, coach insight line from
/// the latest `CoachDecision` (`loadLatest`), and the start/view action.
///
/// State table:
/// - full: name + objective + facts + primary action
/// - completed day: "Completed" pill + "View workout"
/// - null workout: caller renders the rest-day card instead
class WorkoutHero extends StatelessWidget {
  const WorkoutHero({
    required this.workout,
    required this.source,
    this.sessionDate,
    this.isCompleted = false,
    this.coachInsight,
    this.onWorkoutChanged,
    super.key,
  });

  final PlannedWorkout workout;
  final WorkoutRepository source;
  final DateTime? sessionDate;
  final bool isCompleted;

  /// Real `CoachDecision.trainingSummary` for the selected day. Null hides
  /// the insight line (never fabricated).
  final String? coachInsight;
  final VoidCallback? onWorkoutChanged;

  void _open(BuildContext context) {
    Navigator.of(context)
        .push<bool>(
          CupertinoPageRoute(
            builder: (_) => WorkoutDetailScreen(
              repository: source,
              workout: workout,
              sessionDate: sessionDate,
            ),
          ),
        )
        .then((completed) {
          if (completed == true) onWorkoutChanged?.call();
        });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final sets = workout.exercises.fold<int>(
      0,
      (sum, item) => sum + item.setCount,
    );
    return PremiumGradientCard(
      glow: true,
      glowColor: colors.stateStable,
      padding: const EdgeInsets.all(TracendSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCompleted)
            TracendPill(
              label: 'Completed',
              icon: CupertinoIcons.check_mark_circled_solid,
              color: colors.stateStable,
            )
          else
            const TracendPill(
              label: 'Approved plan',
              icon: CupertinoIcons.check_mark_circled_solid,
            ),
          const SizedBox(height: TracendSpacing.sm),
          Text(
            workout.name,
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(letterSpacing: -0.5),
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            workout.objective,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: TracendSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: TracendSpacing.sm,
              vertical: TracendSpacing.sm,
            ),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.borderHairline),
                bottom: BorderSide(color: colors.borderHairline),
              ),
            ),
            child: Row(
              children: [
                _Fact(label: 'EXERCISES', value: '${workout.exercises.length}'),
                _Divider(),
                _Fact(label: 'WORKING SETS', value: '$sets'),
                _Divider(),
                _Fact(
                  label: 'DURATION',
                  value: '~${workout.estimatedMinutes}m',
                ),
              ],
            ),
          ),
          if (coachInsight != null) ...[
            const SizedBox(height: TracendSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 3,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.actionPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: TracendSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COACH INSIGHT',
                        style: TracendTheme.labelCaps(
                          context,
                          color: colors.actionPrimary,
                        ),
                      ),
                      const SizedBox(height: TracendSpacing.xxs),
                      Text(
                        coachInsight!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: TracendSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: isCompleted
                ? OutlinedButton(
                    onPressed: () => _open(context),
                    child: const Text('View workout'),
                  )
                : FilledButton(
                    onPressed: () => _open(context),
                    child: const Text('Start workout'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: TracendTheme.labelCaps(context)),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontFamily: TracendFonts.monoFamily,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 32,
    color: context.tracendColors.borderHairline,
  );
}

/// Rest-day card shown when no workout is assigned to the selected day.
class RestDayCard extends StatelessWidget {
  const RestDayCard({super.key});

  @override
  Widget build(BuildContext context) => PremiumGradientCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rest day', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: TracendSpacing.xxs),
        const Text(
          'No approved workout is assigned to this day. Use recovery guidance or choose another day.',
        ),
      ],
    ),
  );
}
