import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Weekly review action card: honest queued/ready/failed/create states.
class WeeklyReviewActionCard extends StatelessWidget {
  const WeeklyReviewActionCard({
    required this.weeklyReview,
    required this.weeklyReviewJob,
    required this.onTap,
    super.key,
  });

  final WeeklyProgressReview? weeklyReview;
  final WeeklyReviewJob? weeklyReviewJob;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = weeklyReview != null
        ? 'Weekly review ready'
        : weeklyReviewJob?.isPending == true
        ? 'Weekly review is preparing'
        : weeklyReviewJob?.status == 'failed'
        ? 'Weekly review needs another try'
        : 'Create your weekly review';
    final detail = weeklyReview != null
        ? '${_weekLabel(weeklyReview!.week)} · deterministic evidence · no AI estimation'
        : weeklyReviewJob?.isPending == true
        ? 'Your evidence is queued privately. The approved plan remains available while it processes.'
        : 'Summarize training, recovery, nutrition and progress without changing your plan.';
    final action = weeklyReview != null
        ? 'Open weekly review'
        : weeklyReviewJob?.isPending == true
        ? 'Refresh status'
        : 'Generate review';
    return TracendCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.calendar,
            color: context.tracendColors.actionPrimary,
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(detail, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }

  static String _weekLabel(DateTime week) =>
      'Week of ${week.day}/${week.month}/${week.year}';
}

/// Deterministic seven-part weekly review sheet.
class WeeklyReviewSheet extends StatelessWidget {
  const WeeklyReviewSheet({required this.review, super.key});

  final WeeklyProgressReview review;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly review',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'A deterministic editorial review of confirmed evidence. Missing inputs remain visible.',
            ),
            const SizedBox(height: 20),
            _ReviewSection('1 · Outcome', _outcome(review.outcomeCode)),
            _ReviewSection(
              '2 · Execution and adherence',
              '${review.completedWorkouts} of ${review.plannedSessions} planned workouts completed (${review.adherencePercent}%). ${review.completedSets} working sets were confirmed.',
            ),
            _ReviewSection(
              '3 · Recovery context',
              '${review.checkInDays} check-in days · ${review.healthDays} Apple Health days. Average energy ${_metric(review.averageEnergy)} and soreness ${_metric(review.averageSoreness)}.',
            ),
            _ReviewSection(
              '4 · Training and nutrition evidence',
              '${review.confirmedNutritionDays} days include confirmed nutrition. ${review.measurementDays} measurement days were recorded.',
            ),
            const _ReviewSection(
              '5 · What remains unchanged',
              'Your approved training plan and nutrition targets remain active. No persistent plan change is implied by this review.',
            ),
            _ReviewSection(
              '6 · Missing evidence',
              review.missingData.isEmpty
                  ? 'No required evidence category is completely missing.'
                  : review.missingData.map(_missingLabel).join(' · '),
            ),
            _ReviewSection(
              '7 · Next-week focus',
              _nextFocus(review.nextFocusCode),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, !review.acknowledged),
                child: Text(review.acknowledged ? 'Done' : 'Mark reviewed'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static String _metric(double? value) =>
      value == null ? 'not recorded' : '${value.toStringAsFixed(1)} of 5';

  static String _outcome(String code) => switch (code) {
    'week_observed' =>
      'The week has enough execution and recovery evidence to review.',
    'training_logged_recovery_missing' =>
      'Training was logged, but recovery evidence is incomplete.',
    _ => 'More execution evidence is needed before drawing a weekly pattern.',
  };

  static String _nextFocus(String code) => switch (code) {
    'complete_next_planned_workout' => 'Complete the next planned workout.',
    'record_recovery_check_in' => 'Record recovery after your next session.',
    'confirm_nutrition' => 'Confirm nutrition on the days you track meals.',
    _ => 'Continue the approved plan and keep the evidence comparable.',
  };

  static String _missingLabel(String code) => switch (code) {
    'active_training_plan' => 'Active training plan',
    'recovery_check_ins' => 'Recovery check-ins',
    'confirmed_nutrition' => 'Confirmed nutrition',
    'health_context' => 'Apple Health context',
    _ => 'Additional evidence',
  };
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection(this.title, this.body);
  final String title, body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(body),
      ],
    ),
  );
}
