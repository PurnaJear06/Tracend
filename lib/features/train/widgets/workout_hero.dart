import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/train_view_models.dart';
import 'package:tracend/features/train/widgets/muscle_map.dart';
import 'package:tracend/features/train/widgets/train_parts.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_segmented_control.dart';

/// Where the selected day's workout stands.
enum HeroDayState {
  /// Today or a coming day: ready to start.
  planned,

  /// A past day with nothing logged; it can still be logged.
  notLogged,

  /// A completed session exists for the day.
  done,
}

/// The selected day's workout: a kicker, the name, "N exercises, about M
/// min", the worked muscles as chips and on a turnable map, and one action.
/// Apple Health's completion prompt replaces the Start button when it has a
/// matching workout. The title area opens the workout overview; the map
/// opens the muscles sheet.
class WorkoutHero extends StatelessWidget {
  const WorkoutHero({
    required this.workout,
    required this.date,
    required this.today,
    required this.state,
    required this.side,
    required this.onSideChanged,
    required this.onOpenOverview,
    required this.onStart,
    required this.onViewSummary,
    required this.onOpenMuscles,
    this.doneSession,
    this.healthkitCandidate,
    this.onHealthkitComplete,
    this.onHealthkitManual,
    this.healthkitBusy = false,
    super.key,
  });

  final PlannedWorkout workout;
  final DateTime date;
  final DateTime today;
  final HeroDayState state;

  /// The day's completed session from the hub, when it is listed.
  final TrainingSessionSummary? doneSession;

  final BodySide side;
  final ValueChanged<BodySide> onSideChanged;
  final VoidCallback onOpenOverview;
  final VoidCallback onStart;
  final VoidCallback onViewSummary;
  final VoidCallback onOpenMuscles;

  final HealthkitCompletionCandidate? healthkitCandidate;
  final VoidCallback? onHealthkitComplete;
  final VoidCallback? onHealthkitManual;
  final bool healthkitBusy;

  static const mapWidth = 128.0;

  bool get _isToday => sameDay(date, today);

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final sets = muscleMapCoversWorkout(workout.exercises)
        ? muscleSetsFor(workout.exercises)
        : const <MuscleSets>[];
    final candidate = state == HeroDayState.done ? null : healthkitCandidate;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(TracendRadii.card),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final sideBySide =
              sets.isNotEmpty && constraints.maxWidth >= 300 && scale <= 1.35;
          final heading = _Heading(
            titleSize: sideBySide ? 27 : 30,
            workout: workout,
            kicker: _kicker(context, candidate),
            meta: _meta(),
            onTap: onOpenOverview,
          );
          final muscles = sets.isEmpty
              ? null
              : _Muscles(
                  sets: sets,
                  side: side,
                  onSideChanged: onSideChanged,
                  onOpenMuscles: onOpenMuscles,
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sideBySide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          heading,
                          const SizedBox(height: 14),
                          _MuscleChips(sets: sets),
                        ],
                      ),
                    ),
                    const SizedBox(width: TracendSpacing.xs),
                    muscles!.figure(context, width: mapWidth),
                  ],
                )
              else ...[
                heading,
                if (muscles != null) ...[
                  const SizedBox(height: 14),
                  _MuscleChips(sets: sets),
                  const SizedBox(height: TracendSpacing.sm),
                  Center(child: muscles.figure(context, width: 168)),
                ] else if (workout.exercises.isNotEmpty) ...[
                  const SizedBox(height: TracendSpacing.sm),
                  const _MapPending(),
                ],
              ],
              if (state == HeroDayState.done &&
                  doneSession?.completionSource ==
                      CompletionSource.healthkit) ...[
                const SizedBox(height: TracendSpacing.sm),
                Text(
                  'Auto-completed from Apple Health',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: TracendSpacing.md),
              if (candidate != null)
                _HealthkitPrompt(
                  candidate: candidate,
                  today: today,
                  busy: healthkitBusy,
                  onComplete: onHealthkitComplete,
                  onManual: onHealthkitManual,
                )
              else if (state == HeroDayState.done)
                OutlinedButton(
                  onPressed: onViewSummary,
                  child: const Text('View summary'),
                )
              else
                FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(CupertinoIcons.play_fill, size: 18),
                  label: Text(
                    state == HeroDayState.notLogged
                        ? 'Log this workout'
                        : 'Start workout',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  _Kicker _kicker(
    BuildContext context,
    HealthkitCompletionCandidate? candidate,
  ) {
    final colors = context.tracendColors;
    if (candidate != null) {
      return _Kicker(
        icon: CupertinoIcons.heart_fill,
        text: 'Apple Health detected workout',
        color: colors.textSecondary,
      );
    }
    return switch (state) {
      HeroDayState.done => _Kicker(
        icon: CupertinoIcons.checkmark_circle_fill,
        text: _isToday ? 'Done today' : 'Done on ${weekdayName(date)}',
        color: colors.stateStable,
      ),
      HeroDayState.notLogged => _Kicker(
        icon: CupertinoIcons.calendar,
        text: '${weekdayName(date)}, not logged',
        color: colors.textSecondary,
      ),
      HeroDayState.planned when _isToday => _Kicker(
        icon: CupertinoIcons.bolt_fill,
        text: 'Today',
        color: colors.accentSignalInk,
      ),
      HeroDayState.planned => _Kicker(
        text: weekdayName(date),
        color: colors.textSecondary,
      ),
    };
  }

  String _meta() {
    final minutes = doneSession?.durationSeconds;
    if (state == HeroDayState.done && minutes != null) {
      final count = workout.exercises.length;
      return '${(minutes / 60).round()} min, $count '
          '${count == 1 ? 'exercise' : 'exercises'}';
    }
    return workoutMeta(workout);
  }
}

class _Kicker {
  const _Kicker({required this.text, required this.color, this.icon});

  final IconData? icon;
  final String text;
  final Color color;
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.titleSize,
    required this.workout,
    required this.kicker,
    required this.meta,
    required this.onTap,
  });

  final double titleSize;
  final PlannedWorkout workout;
  final _Kicker kicker;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      semanticLabel:
          '${kicker.text}. ${workout.name}, $meta. Opens the workout '
          'overview.',
      borderRadius: BorderRadius.circular(TracendRadii.control),
      pressedScale: 0.98,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (kicker.icon != null) ...[
                Icon(kicker.icon, size: 15, color: kicker.color),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  kicker.text,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: kicker.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(workout.name, style: trainDisplay(context, size: titleSize)),
          const SizedBox(height: TracendSpacing.xxs),
          Text(meta, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Shown when too few of the workout's sets come from catalog-linked
/// exercises ([muscleMapCoversWorkout]; plans approved before the catalog):
/// a partial map would misdescribe the session, so it is left out rather
/// than guessed, and this says when it arrives.
class _MapPending extends StatelessWidget {
  const _MapPending();

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Row(
      children: [
        Icon(
          Icons.accessibility_new_rounded,
          size: 16,
          color: colors.textTertiary,
        ),
        const SizedBox(width: TracendSpacing.xs),
        Expanded(
          child: Text(
            'Muscle map appears with your next plan.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _MuscleChips extends StatelessWidget {
  const _MuscleChips({required this.sets});

  final List<MuscleSets> sets;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Muscles worked',
          style: textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: TracendSpacing.xs),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in sets)
              Container(
                constraints: const BoxConstraints(minHeight: 28),
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  borderRadius: BorderRadius.circular(TracendRadii.pill),
                ),
                child: Text(
                  entry.group.label,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Muscles {
  const _Muscles({
    required this.sets,
    required this.side,
    required this.onSideChanged,
    required this.onOpenMuscles,
  });

  final List<MuscleSets> sets;
  final BodySide side;
  final ValueChanged<BodySide> onSideChanged;
  final VoidCallback onOpenMuscles;

  Widget figure(BuildContext context, {required double width}) => SizedBox(
    width: width,
    child: Column(
      children: [
        MuscleMap(
          muscles: muscleTones(sets),
          side: side,
          palette: musclePalette(context),
          onSideChanged: onSideChanged,
          onTap: onOpenMuscles,
          width: width - 12,
        ),
        const SizedBox(height: TracendSpacing.xs),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: TracendSegmentedControl<BodySide>(
            segments: const [
              (BodySide.front, 'Front'),
              (BodySide.back, 'Back'),
            ],
            selected: side,
            onChanged: onSideChanged,
          ),
        ),
      ],
    ),
  );
}

class _HealthkitPrompt extends StatelessWidget {
  const _HealthkitPrompt({
    required this.candidate,
    required this.today,
    required this.busy,
    required this.onComplete,
    required this.onManual,
  });

  final HealthkitCompletionCandidate candidate;
  final DateTime today;
  final bool busy;
  final VoidCallback? onComplete;
  final VoidCallback? onManual;

  String get _when {
    final date = candidate.localDate;
    if (sameDay(date, today)) return 'today';
    if (sameDay(date, today.subtract(const Duration(days: 1)))) {
      return 'yesterday';
    }
    return 'on ${dayMonth(date)}';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Apple Health recorded a ${candidate.workoutMinutes} min workout '
        '$_when. Did you complete ${candidate.plannedWorkoutName}?',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: TracendSpacing.sm),
      FilledButton(
        onPressed: busy ? null : onComplete,
        child: const Text('Yes, mark complete'),
      ),
      const SizedBox(height: TracendSpacing.xs),
      OutlinedButton(
        onPressed: busy ? null : onManual,
        child: const Text('Log manually'),
      ),
    ],
  );
}

/// A day without a planned workout. A coming rest day names the next
/// workout of the week and jumps to it.
class RestDayHero extends StatelessWidget {
  const RestDayHero({
    required this.date,
    required this.today,
    this.nextWorkout,
    this.nextDate,
    this.onJump,
    super.key,
  });

  final DateTime date;
  final DateTime today;
  final PlannedWorkout? nextWorkout;
  final DateTime? nextDate;
  final VoidCallback? onJump;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final past = date.isBefore(DateTime(today.year, today.month, today.day));
    final next = nextWorkout;
    final nextDay = nextDate;
    final note = past
        ? 'You took the day off. Recovery is part of the plan.'
        : next == null || nextDay == null
        ? 'Easy walking is fine. No more workouts are planned this week.'
        : 'Easy walking is fine. Your next workout is ${next.name} on '
              '${weekdayName(nextDay)}.';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(TracendRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.moon, size: 15, color: colors.textSecondary),
              const SizedBox(width: 6),
              Text(
                sameDay(date, today) ? 'Today' : weekdayName(date),
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(
            header: true,
            child: Text('Rest day', style: trainDisplay(context)),
          ),
          const SizedBox(height: TracendSpacing.sm),
          Text(note, style: textTheme.bodyMedium),
          if (!past && next != null && nextDay != null && onJump != null) ...[
            const SizedBox(height: TracendSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onJump,
                iconAlignment: IconAlignment.end,
                icon: const Icon(CupertinoIcons.arrow_right, size: 17),
                label: Text('See ${weekdayName(nextDay)}’s workout'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
