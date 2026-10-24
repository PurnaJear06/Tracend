import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/unfinished_workout.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// A workout the athlete logged sets in and left without finishing, offered
/// back so it is never lost and never finished for them. "Save workout" asks
/// how hard it was and puts it in their history on its own day; "Discard"
/// keeps it out for good.
class UnfinishedWorkoutCard extends StatelessWidget {
  const UnfinishedWorkoutCard({
    required this.workout,
    required this.busy,
    required this.onSave,
    required this.onDiscard,
    this.now,
    super.key,
  });

  final UnfinishedWorkout workout;

  /// An answer is being sent: both buttons wait.
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  /// The clock, for the year in the date; tests set it.
  final DateTime? now;

  /// "You didn't finish Legs B on Fri 23 Oct · 23 sets logged".
  String get message {
    final sets = workout.loggedSets == 1 ? 'set' : 'sets';
    return "You didn't finish ${workout.name} on "
        '${dayAndDate(workout.localDate, now: now)} · '
        '${workout.loggedSets} $sets logged';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    return TracendCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.exclamationmark_circle_fill,
                size: 16,
                color: colors.accentAmber,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Workout not finished',
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(message, style: text.titleMedium),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            'Save it by ${dayAndDate(workout.saveBy, now: now)}, or discard '
            'it. Until you answer, it does not count as a workout.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: TracendSpacing.sm),
          FilledButton(
            onPressed: busy ? null : onSave,
            child: busy
                ? const TracendLoader(size: 22, semanticLabel: 'Saving')
                : const Text('Save workout'),
          ),
          const SizedBox(height: TracendSpacing.xs),
          OutlinedButton(
            onPressed: busy ? null : onDiscard,
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }
}
