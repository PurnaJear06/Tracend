import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_loading_indicator.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// "Workout record needs review" card (duration mismatch between Tracend and
/// Apple Health). Real candidate data only.
class WorkoutRepairCard extends StatelessWidget {
  const WorkoutRepairCard({
    required this.candidate,
    required this.onConfirm,
    super.key,
  });
  final WorkoutRepairCandidate candidate;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => PremiumGradientCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StatusChip(
          label: 'Workout record needs review',
          icon: CupertinoIcons.exclamationmark_triangle,
        ),
        const SizedBox(height: TracendSpacing.sm),
        Text(
          candidate.workoutName,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: TracendSpacing.xs),
        Text(
          'Apple Health recorded ${(candidate.healthkitDurationSeconds / 60).round()} minutes. Tracend recorded ${(candidate.recordedDurationSeconds / 60).round()} minutes while you were entering sets.',
        ),
        const SizedBox(height: TracendSpacing.md),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onConfirm,
            child: const Text('Review and correct'),
          ),
        ),
      ],
    ),
  );
}

/// Apple Health match/conflict card. Real reconciliation data only.
class ReconciliationCard extends StatelessWidget {
  const ReconciliationCard({
    required this.item,
    required this.onAccept,
    required this.onReject,
    required this.busy,
    required this.isDifferentDay,
    super.key,
  });
  final WorkoutReconciliation item;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final bool busy;
  final bool isDifferentDay;

  String _dateLabel(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = DateTime.now();
    if (date.year == today.year &&
        date.month == today.month &&
        date.day == today.day) {
      return 'Today';
    }
    final yesterday = today.subtract(const Duration(days: 1));
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }
    return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) => PremiumGradientCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusChip(
          label: item.status == 'conflict'
              ? 'Apple Health conflict'
              : 'Apple Health workout match',
          icon: item.status == 'conflict'
              ? CupertinoIcons.exclamationmark_triangle
              : CupertinoIcons.link,
        ),
        const SizedBox(height: TracendSpacing.sm),
        Text(item.workoutName, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: TracendSpacing.xs),
        Text(
          '${_dateLabel(item.localDate)} · ${item.activityType.replaceAll('_', ' ').toLowerCase()} · ${(item.healthDurationSeconds / 60).round()} min',
        ),
        const SizedBox(height: TracendSpacing.xs),
        Text(
          'Match confidence ${(item.confidence * 100).round()}%. Apple Health confirms the activity; Tracend remains the source for exercises and sets.',
        ),
        if (isDifferentDay)
          Padding(
            padding: const EdgeInsets.only(top: TracendSpacing.xs),
            child: Text(
              'This match is for ${_dateLabel(item.localDate)}. Switch to that day to see the workout.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
        const SizedBox(height: TracendSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onReject,
                child: const Text('Not the same workout'),
              ),
            ),
            const SizedBox(width: TracendSpacing.sm),
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : onAccept,
                child: busy
                    ? const TracendLoadingIndicator(size: 18)
                    : const Text('Confirm match'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Apple Health detected-workout prompt. Real candidate data only.
class HealthkitCompleteCard extends StatelessWidget {
  const HealthkitCompleteCard({
    required this.candidate,
    required this.onComplete,
    required this.onManual,
    super.key,
  });
  final HealthkitCompletionCandidate candidate;
  final VoidCallback onComplete;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    String dateLabel;
    if (candidate.localDate.year == today.year &&
        candidate.localDate.month == today.month &&
        candidate.localDate.day == today.day) {
      dateLabel = 'today';
    } else if (candidate.localDate.year == yesterday.year &&
        candidate.localDate.month == yesterday.month &&
        candidate.localDate.day == yesterday.day) {
      dateLabel = 'yesterday';
    } else {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      dateLabel =
          'on ${months[candidate.localDate.month - 1]} ${candidate.localDate.day}';
    }
    return PremiumGradientCard(
      glow: true,
      glowColor: context.tracendColors.stateStable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatusChip(
            label: 'Apple Health detected workout',
            icon: CupertinoIcons.heart_fill,
          ),
          const SizedBox(height: TracendSpacing.sm),
          Text(
            candidate.plannedWorkoutName,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            'Apple Health recorded a ${candidate.workoutMinutes} min workout $dateLabel. '
            'Did you complete ${candidate.plannedWorkoutName}?',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: TracendSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onManual,
                  child: const Text('Log manually'),
                ),
              ),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: onComplete,
                  child: const Text('Yes, mark complete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
