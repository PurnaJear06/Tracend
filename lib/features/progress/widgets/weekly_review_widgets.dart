import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Weekly review action card: honest create / preparing / failed / ready
/// states, one action each.
class WeeklyReviewActionCard extends StatelessWidget {
  const WeeklyReviewActionCard({
    required this.weeklyReview,
    required this.weeklyReviewJob,
    required this.onTap,
    this.now,
    super.key,
  });

  final WeeklyProgressReview? weeklyReview;
  final WeeklyReviewJob? weeklyReviewJob;
  final VoidCallback onTap;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    final review = weeklyReview;
    final pending = weeklyReviewJob?.isPending == true;
    final failed = weeklyReviewJob?.status == 'failed';
    final title = review != null
        ? 'Weekly review ready'
        : pending
        ? 'Weekly review is preparing'
        : failed
        ? 'Weekly review needs another try'
        : 'Create your weekly review';
    final detail = review != null
        ? 'Week of ${shortDate(review.week, now: now)} · calculated from your logs, '
              'no AI'
        : pending
        ? 'Usually ready in a few minutes. Your plan stays as it is.'
        : failed
        ? 'It could not be prepared. Try again.'
        : 'A short summary of your training, recovery, food and body '
              'changes. It never changes your plan.';
    final action = review != null
        ? 'Open weekly review'
        : pending
        ? 'Refresh status'
        : 'Generate review';
    final accent = review != null && !review.acknowledged
        ? colors.stateStable
        : failed
        ? colors.stateAttention
        : colors.actionPrimary;
    final icon = review != null
        ? CupertinoIcons.doc_text_fill
        : pending
        ? CupertinoIcons.hourglass
        : CupertinoIcons.calendar;
    return PremiumGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(TracendRadii.control),
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.titleMedium),
                    const SizedBox(height: TracendSpacing.xxs),
                    Text(detail, style: theme.bodyMedium),
                  ],
                ),
              ),
              if (review != null && !review.acknowledged) ...[
                const SizedBox(width: TracendSpacing.xs),
                TracendPill(label: 'New', color: accent, compact: true),
              ],
            ],
          ),
          const SizedBox(height: TracendSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: review != null
                ? FilledButton(onPressed: onTap, child: Text(action))
                : OutlinedButton(onPressed: onTap, child: Text(action)),
          ),
        ],
      ),
    );
  }
}

/// Weekly review sheet. Sections keep the order UX_FLOWS requires: outcome,
/// execution, recovery, evidence, unchanged items, missing data, next focus.
class WeeklyReviewSheet extends StatelessWidget {
  const WeeklyReviewSheet({required this.review, this.now, super.key});

  final WeeklyProgressReview review;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => SafeArea(
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            TracendSpacing.gutter,
            0,
            TracendSpacing.gutter,
            TracendSpacing.lg,
          ),
          children: [
            Text('Weekly review', style: theme.headlineSmall),
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              'Week of ${shortDate(review.week, now: now)}',
              style: theme.bodyMedium,
            ),
            const SizedBox(height: TracendSpacing.sm),
            Text(
              'Calculated from your logs · no AI. Missing data is shown, '
              'not guessed.',
              style: theme.bodySmall,
            ),
            const SizedBox(height: TracendSpacing.lg),
            _ReviewSection(
              icon: CupertinoIcons.flag_fill,
              title: 'Outcome',
              body: _outcome(review.outcomeCode),
            ),
            _ReviewSection(
              icon: CupertinoIcons.bolt_fill,
              title: 'Workouts',
              child: Row(
                children: [
                  _StatTile(
                    value:
                        '${review.completedWorkouts} of ${review.plannedSessions}',
                    label: 'planned workouts',
                  ),
                  const SizedBox(width: TracendSpacing.xs),
                  _StatTile(
                    value: '${review.adherencePercent}%',
                    label: 'on plan',
                  ),
                  const SizedBox(width: TracendSpacing.xs),
                  _StatTile(
                    value: '${review.completedSets}',
                    label: 'working sets',
                  ),
                ],
              ),
            ),
            _ReviewSection(
              icon: CupertinoIcons.heart_fill,
              title: 'Recovery',
              body:
                  '${_days(review.checkInDays, 'check-in')} and '
                  '${_days(review.healthDays, 'Apple Health day')}. Energy '
                  '${_metric(review.averageEnergy)}, soreness '
                  '${_metric(review.averageSoreness)}.',
            ),
            _ReviewSection(
              icon: CupertinoIcons.chart_bar_fill,
              title: 'Food and body',
              body:
                  'Meals logged on ${_days(review.confirmedNutritionDays, 'day')}. '
                  'Weighed in on ${_days(review.measurementDays, 'day')}.',
            ),
            const _ReviewSection(
              icon: CupertinoIcons.lock_fill,
              title: 'What stays the same',
              body:
                  'Your training plan and nutrition targets stay as they are. '
                  'This review never changes them.',
            ),
            _ReviewSection(
              icon: CupertinoIcons.question_circle_fill,
              title: 'Missing data',
              body: review.missingData.isEmpty
                  ? 'Nothing important is missing.'
                  : review.missingData.map(_missingLabel).join(' · '),
            ),
            _ReviewSection(
              icon: CupertinoIcons.arrow_right_circle_fill,
              title: 'Next week',
              body: _nextFocus(review.nextFocusCode),
            ),
            const SizedBox(height: TracendSpacing.xs),
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
    );
  }

  static String _days(int count, String noun) =>
      '$count ${count == 1 ? noun : '${noun}s'}';

  static String _metric(double? value) =>
      value == null ? 'not recorded' : '${value.toStringAsFixed(1)}/5';

  static String _outcome(String code) => switch (code) {
    'week_observed' => 'You logged enough this week for a full review.',
    'training_logged_recovery_missing' =>
      'Your training is logged, but recovery check-ins are missing.',
    _ => 'Log a few more workouts before a weekly pattern shows.',
  };

  static String _nextFocus(String code) => switch (code) {
    'complete_next_planned_workout' => 'Complete your next planned workout.',
    'record_recovery_check_in' =>
      'Check in on recovery after your next session.',
    'confirm_nutrition' => 'Log your meals on the days you track food.',
    _ => 'Keep following your plan and logging the same way.',
  };

  static String _missingLabel(String code) => switch (code) {
    'active_training_plan' => 'Active training plan',
    'recovery_check_ins' => 'Recovery check-ins',
    'confirmed_nutrition' => 'Logged meals',
    'health_context' => 'Apple Health data',
    _ => 'Other data',
  };
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.icon,
    required this.title,
    this.body,
    this.child,
  });
  final IconData icon;
  final String title;
  final String? body;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: TracendSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: colors.textSecondary),
          ),
          const SizedBox(width: TracendSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: TracendSpacing.xxs),
                if (body != null) Text(body!),
                ?child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(TracendRadii.control),
        ),
        child: Padding(
          padding: const EdgeInsets.all(TracendSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(label, style: TracendTheme.labelCaps(context)),
            ],
          ),
        ),
      ),
    );
  }
}
