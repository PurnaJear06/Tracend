import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/formatting.dart';

/// "Needs your attention": Apple Health repairs and workout matches in one
/// group above the hero. Real candidates only; the RPCs are unchanged.
class AttentionGroup extends StatelessWidget {
  const AttentionGroup({
    required this.repairs,
    required this.reconciliations,
    required this.onRepair,
    required this.onRespond,
    required this.onShowDay,
    required this.selectedDate,
    this.busyReconciliationId,
    super.key,
  });

  final List<WorkoutRepairCandidate> repairs;
  final List<WorkoutReconciliation> reconciliations;
  final ValueChanged<WorkoutRepairCandidate> onRepair;
  final void Function(WorkoutReconciliation item, {required bool accept})
  onRespond;

  /// Selects the match's day in the strip.
  final ValueChanged<DateTime> onShowDay;
  final DateTime selectedDate;
  final String? busyReconciliationId;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final items = <Widget>[
      for (final repair in repairs)
        WorkoutRepairItem(candidate: repair, onReview: () => onRepair(repair)),
      for (final item in reconciliations)
        ReconciliationItem(
          item: item,
          busy: busyReconciliationId == item.id,
          isDifferentDay: !_sameDay(item.localDate, selectedDate),
          onAccept: () => onRespond(item, accept: true),
          onReject: () => onRespond(item, accept: false),
          onShowDay: () => onShowDay(item.localDate),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, TracendSpacing.xs),
          child: Semantics(
            header: true,
            child: Text(
              'Needs your attention',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(TracendRadii.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: colors.borderHairline,
                    ),
                  ),
                items[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _ItemFrame extends StatelessWidget {
  const _ItemFrame({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.title,
    required this.body,
    required this.actions,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String title;
  final List<Widget> body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(title, style: textTheme.titleMedium),
          const SizedBox(height: TracendSpacing.xxs),
          ...body,
          const SizedBox(height: TracendSpacing.sm),
          ...actions,
        ],
      ),
    );
  }
}

/// A completed workout whose recorded time disagrees with Apple Health.
class WorkoutRepairItem extends StatelessWidget {
  const WorkoutRepairItem({
    required this.candidate,
    required this.onReview,
    super.key,
  });

  final WorkoutRepairCandidate candidate;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) => _ItemFrame(
    icon: CupertinoIcons.exclamationmark_triangle_fill,
    iconColor: context.tracendColors.accentAmber,
    label: 'Workout record needs review',
    title: candidate.workoutName,
    body: [
      Text(
        '${friendlyDate(candidate.localDate)}. Apple Health recorded '
        '${(candidate.healthkitDurationSeconds / 60).round()} min; Tracend '
        'recorded ${(candidate.recordedDurationSeconds / 60).round()} min.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ],
    actions: [
      OutlinedButton(
        onPressed: onReview,
        child: const Text('Review and correct'),
      ),
    ],
  );
}

/// An Apple Health workout that may match a logged one.
class ReconciliationItem extends StatelessWidget {
  const ReconciliationItem({
    required this.item,
    required this.busy,
    required this.isDifferentDay,
    required this.onAccept,
    required this.onReject,
    required this.onShowDay,
    super.key,
  });

  final WorkoutReconciliation item;
  final bool busy;
  final bool isDifferentDay;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onShowDay;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final conflict = item.status == 'conflict';
    final activity = item.activityType.replaceAll('_', ' ').toLowerCase();
    return _ItemFrame(
      icon: conflict
          ? CupertinoIcons.exclamationmark_triangle_fill
          : CupertinoIcons.link,
      iconColor: conflict ? colors.accentAmber : colors.textSecondary,
      label: conflict ? 'Apple Health conflict' : 'Apple Health workout match',
      title: item.workoutName,
      body: [
        Text(
          '${friendlyDate(item.localDate)}, $activity, '
          '${(item.healthDurationSeconds / 60).round()} min. Apple Health '
          'confirms the activity; your sets stay as you logged them.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: TracendSpacing.xxs),
        Text(
          'Match confidence ${(item.confidence * 100).round()}%',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (isDifferentDay) ...[
          const SizedBox(height: TracendSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onShowDay,
              icon: const Icon(CupertinoIcons.calendar, size: 16),
              label: const Text('Switch to that day'),
            ),
          ),
        ],
      ],
      actions: [
        FilledButton(
          onPressed: busy ? null : onAccept,
          child: busy
              ? const TracendLoader(size: 22, semanticLabel: 'Saving')
              : const Text('Confirm match'),
        ),
        const SizedBox(height: TracendSpacing.xs),
        OutlinedButton(
          onPressed: busy ? null : onReject,
          child: const Text('Not the same workout'),
        ),
      ],
    );
  }
}
