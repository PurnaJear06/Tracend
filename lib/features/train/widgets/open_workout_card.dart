import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/open_workout.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// A workout left open on this phone, offered back on Train and Today
/// whatever day it is logged under: "Legs B · Fri 30 Oct · 2 sets logged"
/// with Resume. When more than one is open, the newest leads and the others
/// are listed under it, each with its own Resume.
class OpenWorkoutCard extends StatelessWidget {
  const OpenWorkoutCard({
    required this.workouts,
    required this.onResume,
    this.nameFor,
    this.now,
    super.key,
  }) : assert(workouts.length > 0);

  /// The open workouts, newest first.
  final List<OpenWorkout> workouts;
  final ValueChanged<OpenWorkout> onResume;

  /// Names a workout whose draft kept no name, from the plan.
  final String? Function(OpenWorkout workout)? nameFor;

  /// The clock, for the year in the date; tests set it.
  final DateTime? now;

  /// "Legs B · Fri 30 Oct · 2 sets logged".
  static String line(OpenWorkout workout, String name, {DateTime? now}) {
    final sets = workout.doneSets == 1 ? 'set' : 'sets';
    return '$name · ${dayAndDate(workout.date, now: now)} · '
        '${workout.doneSets} $sets logged';
  }

  String _line(OpenWorkout workout) =>
      line(workout, workout.nameOr(nameFor?.call(workout)), now: now);

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final newest = workouts.first;
    final others = workouts.skip(1).toList();
    return TracendCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.play_circle_fill,
                size: 16,
                color: colors.accentSignalInk,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Workout in progress',
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_line(newest), style: text.titleMedium),
          const SizedBox(height: TracendSpacing.sm),
          FilledButton.icon(
            key: ValueKey('open-workout-resume-${newest.workoutId}'),
            onPressed: () => onResume(newest),
            icon: const Icon(CupertinoIcons.play_fill, size: 18),
            label: const Text('Resume'),
          ),
          if (others.isNotEmpty) ...[
            const SizedBox(height: TracendSpacing.sm),
            Text(
              'Also in progress',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            for (final other in others)
              Padding(
                padding: const EdgeInsets.only(top: TracendSpacing.xxs),
                child: Row(
                  children: [
                    Expanded(child: Text(_line(other), style: text.bodyMedium)),
                    TextButton(
                      key: ValueKey('open-workout-resume-${other.workoutId}'),
                      onPressed: () => onResume(other),
                      child: Text(
                        'Resume',
                        semanticsLabel: 'Resume ${_line(other)}',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
