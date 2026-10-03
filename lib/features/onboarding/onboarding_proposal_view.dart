import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/onboarding/health_activity.dart';
import 'package:tracend/features/onboarding/onboarding_flow.dart';
import 'package:tracend/features/onboarding/onboarding_repository.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// The starting plan as proposed: every training day with its exercises, the
/// nutrition targets and how they were calculated, what the plan assumes, and
/// where it came from. Nothing starts until the athlete approves it.
class OnboardingProposalView extends StatelessWidget {
  const OnboardingProposalView({
    required this.proposal,
    required this.saving,
    required this.onApprove,
    required this.onRequestRevision,
    required this.onReject,
    this.error,
    super.key,
  });

  final OnboardingProposal proposal;
  final bool saving;
  final String? error;
  final VoidCallback onApprove;
  final VoidCallback onRequestRevision;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final fromModel = proposal.origin == 'ai';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your starting plan', style: text.headlineMedium),
        const SizedBox(height: TracendSpacing.xs),
        Text(
          'Review it before it starts. You can ask for changes.',
          style: text.bodyLarge,
        ),
        const SizedBox(height: TracendSpacing.md),
        Wrap(
          spacing: TracendSpacing.xs,
          runSpacing: TracendSpacing.xs,
          children: [
            StatusChip(
              label: fromModel
                  ? 'Proposed by AI${proposal.model == null ? '' : ' (${proposal.model})'} · checked by Tracend'
                  : 'Built by Tracend\'s rules',
              icon: fromModel
                  ? CupertinoIcons.sparkles
                  : CupertinoIcons.checkmark_shield,
              tone: StatusTone.neutral,
            ),
            StatusChip(
              label: '${_confidence(proposal.confidence)} confidence',
              icon: CupertinoIcons.doc_text_search,
              tone: proposal.confidence == 'low'
                  ? StatusTone.caution
                  : StatusTone.neutral,
            ),
          ],
        ),
        if (proposal.assessment.isNotEmpty) ...[
          const SizedBox(height: TracendSpacing.md),
          Text(proposal.assessment, style: text.bodyLarge),
        ],
        const SectionLabel('Training'),
        Text(
          '${proposal.title} · ${proposal.blockWeeks} weeks · '
          '${proposal.workouts.length} ${proposal.workouts.length == 1 ? 'day' : 'days'} a week',
          style: text.titleMedium,
        ),
        if (proposal.calculation?.priorityMinimums case final focus?
            when focus.isNotEmpty) ...[
          const SizedBox(height: TracendSpacing.xxs),
          Text(focusLine(focus), style: text.bodyMedium),
        ],
        const SizedBox(height: TracendSpacing.sm),
        for (final workout in proposal.workouts) ...[
          _WorkoutCard(workout: workout),
          const SizedBox(height: TracendSpacing.sm),
        ],
        if (proposal.progression.isNotEmpty)
          Text('Progression: ${proposal.progression}', style: text.bodyMedium),
        const SectionLabel('Nutrition'),
        TracendCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${proposal.calories} kcal a day', style: text.titleLarge),
              const SizedBox(height: TracendSpacing.xs),
              Text(
                '${proposal.proteinG} g protein · ${proposal.carbohydrateG} g carbs · ${proposal.fatG} g fat',
              ),
              if (proposal.calculation != null) ...[
                const Divider(height: TracendSpacing.xl),
                Text('How this was calculated', style: text.labelLarge),
                const SizedBox(height: TracendSpacing.xs),
                Text(
                  _calculation(proposal.calculation!),
                  style: text.bodySmall,
                ),
              ],
              if (proposal.nutritionRationale.isNotEmpty) ...[
                const SizedBox(height: TracendSpacing.xs),
                Text(proposal.nutritionRationale, style: text.bodyMedium),
              ],
            ],
          ),
        ),
        if (proposal.keptFromCurrentPlan.isNotEmpty) ...[
          const SectionLabel('Kept from your plan'),
          _Bullets(proposal.keptFromCurrentPlan),
        ],
        if (proposal.changedFromCurrentPlan.isNotEmpty) ...[
          const SectionLabel('Changed from your plan'),
          _Bullets(proposal.changedFromCurrentPlan),
        ],
        const SectionLabel('Why this plan'),
        Text(proposal.rationale),
        const SectionLabel('Expected benefit'),
        Text(proposal.benefit),
        const SectionLabel('Downside and uncertainty'),
        Text(proposal.downside),
        if (proposal.assumptions.isNotEmpty) ...[
          const SectionLabel('Assumptions'),
          _Bullets(proposal.assumptions),
        ],
        if (proposal.missingInformation.isNotEmpty) ...[
          const SectionLabel('Not known yet'),
          _Bullets(proposal.missingInformation),
        ],
        if (error != null) ...[
          const SizedBox(height: TracendSpacing.md),
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: text.bodyMedium?.copyWith(
                color: context.tracendColors.stateDanger,
              ),
            ),
          ),
        ],
        const SizedBox(height: TracendSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: saving ? null : onApprove,
            child: const Text('Approve plan'),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: saving ? null : onRequestRevision,
            child: const Text('Request changes'),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: saving ? null : onReject,
            child: const Text('Reject proposal'),
          ),
        ),
      ],
    );
  }

  /// RPE in plain words: reps left in reserve, 10 − RPE (RPE 7.5 → about
  /// 2–3 reps left).
  static String effortText(num rpe) {
    final left = 10 - rpe;
    final reps = left % 1 == 0
        ? '${left.toInt()} ${left == 1 ? 'rep' : 'reps'} left'
        : '${left.floor()}–${left.ceil()} reps left';
    final shown = rpe % 1 == 0 ? '${rpe.toInt()}' : '$rpe';
    return 'RPE $shown (about $reps)';
  }

  static String _confidence(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  static String _range(List<int> values) => values.isEmpty
      ? '—'
      : values.length == 1 || values.first == values.last
      ? '${values.first}'
      : '${values.first}–${values.last}';

  static String _calculation(ProposalCalculation calc) {
    final floor = calc.floorApplied
        ? ' The range starts at Tracend\'s minimum for you, so weigh-ins will show whether it needs to move.'
        : '';
    final ceiling = calc.ceilingApplied && calc.ceilingKcal != null
        ? ' Your estimate is above ${calc.ceilingKcal} kcal, the most Tracend sets, so the range is capped there.'
        : '';
    final health = calc.health == null
        ? ''
        : '\n\n${appleHealthLine(calc.health!)}';
    final history = calc.history == null
        ? ''
        : '\n${usualMonthsLine(calc.history!)}';
    return 'Resting energy ${_range(calc.bmrKcal)} kcal × activity ${calc.activityFactor} '
        'plus training ≈ ${_range(calc.tdeeKcal)} kcal to maintain. '
        'For your goal Tracend allows ${_range(calc.calorieRangeKcal)} kcal.$floor$ceiling$health$history';
  }

  /// "Focus: chest 10+ sets a week · shoulders 9+ sets a week."
  static String focusLine(List<({String muscle, int sets})> focus) =>
      'Focus: ${focus.map((item) => '${item.muscle} ${item.sets}+ sets a week').join(' · ')}.';

  /// "Your usual months (11): strength 3.4 times a week · sleep 7 h 5 min."
  static String usualMonthsLine(ProposalHealthHistory history) {
    final parts = [
      if (history.usualStrengthPerWeek case final strength?)
        'strength ${_number(strength)} ${strength == 1 ? 'time' : 'times'} a week',
      if (history.usualSleepMinutes case final sleep?)
        'sleep ${sleep ~/ 60} h ${sleep % 60} min',
    ];
    return parts.isEmpty
        ? 'Apple Health has ${history.months} earlier ${history.months == 1 ? 'month' : 'months'}, not enough to show your usual.'
        : 'Your usual months (${history.months}): ${parts.join(' · ')}.';
  }

  /// "Apple Health, last 28 days: about 9,100 steps a day · 3 workouts a
  /// week · sleep 6 h 50 min · weight down 0.3 kg a week."
  static String appleHealthLine(ProposalHealth health) {
    final parts = [
      if (health.stepsPerDay case final steps?)
        'about ${roundedSteps(steps)} steps a day',
      if (health.workoutsPerWeek case final workouts?)
        '${_number(workouts)} ${workouts == 1 ? 'workout' : 'workouts'} a week',
      if (health.sleepMinutesPerNight case final sleep?)
        'sleep ${sleep ~/ 60} h ${sleep % 60} min',
      if (health.weightTrendKgPerWeek case final trend?)
        trend.abs() < 0.05
            ? 'weight steady'
            : 'weight ${trend < 0 ? 'down' : 'up'} ${_number(trend.abs())} kg a week',
    ];
    return parts.isEmpty
        ? 'Apple Health: ${health.daysWithData} of ${health.windowDays} days had data, not enough to average.'
        : 'Apple Health, last ${health.windowDays} days: ${parts.join(' · ')}.';
  }

  static String _number(num value) =>
      value % 1 == 0 ? '${value.toInt()}' : value.toStringAsFixed(1);
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.workout});

  final ProposalWorkout workout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final day = workout.weekday >= 1 && workout.weekday <= 7
        ? onboardingWeekdayLabels[workout.weekday - 1]
        : '';
    return TracendCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$day · ${workout.name}', style: text.titleMedium),
          Text(
            'About ${workout.estimatedMinutes} min · ${workout.objective}',
            style: text.bodySmall,
          ),
          const SizedBox(height: TracendSpacing.xs),
          for (final exercise in workout.exercises)
            Padding(
              padding: const EdgeInsets.only(top: TracendSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exercise.name),
                  Text(
                    '${exercise.sets} × ${exercise.repMin == exercise.repMax ? exercise.repMin : '${exercise.repMin}–${exercise.repMax}'}'
                    ' · ${OnboardingProposalView.effortText(exercise.targetRpe)} · ${_rest(exercise.restSeconds)}',
                    style: text.bodySmall,
                  ),
                  if (exercise.startLoadKg case final load?)
                    Text(
                      'Start at ${OnboardingProposalView._number(load)} kg',
                      style: text.bodySmall?.copyWith(
                        color: context.tracendColors.actionPrimary,
                      ),
                    ),
                  if (exercise.notes.isNotEmpty)
                    Text(exercise.notes, style: text.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _rest(int seconds) => seconds % 60 == 0
      ? '${seconds ~/ 60} min rest'
      : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} rest';
}

class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: TracendSpacing.xs),
          child: Text('• $item'),
        ),
    ],
  );
}
