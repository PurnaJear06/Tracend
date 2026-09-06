import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// One planned movement for the merged exercise list, carrying both the
/// prescription facts and the optional recorded effort for one row.
class ExerciseListEntry {
  const ExerciseListEntry({required this.exercise, this.recordedRpe});

  final PlannedExercise exercise;

  /// Average RPE recorded across the movement's logged sets. Null when the
  /// session has no recorded RPE for this movement (no marker is drawn).
  final double? recordedRpe;
}

/// Today's exercises (2026-09-04 Train redesign): the prescription stats and
/// the planned/recorded effort bar merged into one row per movement — one
/// list where the old page showed the same exercises twice (PrescriptionCard
/// + IntensityBar). Rows keep the honest binding: stats from
/// `planned_exercises`, bar fill = target RPE, marker = recorded set RPE
/// (never the hardcoded `session_effort = 8` written on save). Warm-up and
/// cooldown guidance fold in below when the plan carries them.
class ExerciseListCard extends StatelessWidget {
  const ExerciseListCard({
    required this.entries,
    this.warmUp = '',
    this.cooldownCardio = '',
    super.key,
  });

  final List<ExerciseListEntry> entries;
  final String warmUp;
  final String cooldownCardio;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final hasRecorded = entries.any((entry) => entry.recordedRpe != null);
    return PremiumGradientCard(
      padding: const EdgeInsets.symmetric(
        horizontal: TracendSpacing.md,
        vertical: TracendSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            _ExerciseRow(entry: entries[index]),
            if (index < entries.length - 1)
              Divider(height: TracendSpacing.lg, color: colors.borderHairline),
          ],
          if (hasRecorded || entries.isNotEmpty) ...[
            const SizedBox(height: TracendSpacing.sm),
            Row(
              children: [
                _LegendDot(
                  color: colors.actionPrimary.withValues(alpha: 0.55),
                  label: 'Planned effort',
                ),
                if (hasRecorded) ...[
                  const SizedBox(width: TracendSpacing.sm),
                  _LegendDot(color: colors.stateStable, label: 'Recorded'),
                ],
              ],
            ),
          ],
          if (warmUp.isNotEmpty || cooldownCardio.isNotEmpty) ...[
            Divider(height: TracendSpacing.lg, color: colors.borderHairline),
            if (warmUp.isNotEmpty) ...[
              Text('Warm-up', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: TracendSpacing.xxs),
              Text(
                warmUp,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ],
            if (cooldownCardio.isNotEmpty) ...[
              if (warmUp.isNotEmpty) const SizedBox(height: TracendSpacing.sm),
              Text(
                'Cooldown / cardio',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: TracendSpacing.xxs),
              Text(
                cooldownCardio,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.entry});
  final ExerciseListEntry entry;

  static String _formatRpe(num value) =>
      value is int ? '$value' : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final exercise = entry.exercise;
    final target = (exercise.targetRpe.toDouble() / 10).clamp(0.0, 1.0);
    final recorded = entry.recordedRpe == null
        ? null
        : (entry.recordedRpe! / 10).clamp(0.0, 1.0);
    return Semantics(
      label:
          '${exercise.name}, ${exercise.setCount} sets of '
          '${exercise.repMin} to ${exercise.repMax} reps at RPE '
          '${_formatRpe(exercise.targetRpe)}, rest '
          '${exercise.restSeconds} seconds'
          '${entry.recordedRpe == null ? '' : ', recorded RPE ${entry.recordedRpe!.toStringAsFixed(1)}'}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${exercise.order}'.padLeft(2, '0'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontFamily: TracendFonts.monoFamily,
                  fontSize: 11,
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: TracendSpacing.xxs),
                  Wrap(
                    spacing: TracendSpacing.md,
                    runSpacing: TracendSpacing.xxs,
                    children: [
                      _ExerciseStat(
                        text:
                            '${exercise.setCount} × ${exercise.repMin}–${exercise.repMax}',
                      ),
                      _ExerciseStat(
                        text: 'RPE ${_formatRpe(exercise.targetRpe)}',
                      ),
                      if (entry.recordedRpe != null)
                        _ExerciseStat(
                          text: 'logged ${_formatRpe(entry.recordedRpe!)}',
                          color: colors.stateStable,
                        ),
                      _ExerciseStat(text: '${exercise.restSeconds}s rest'),
                    ],
                  ),
                  const SizedBox(height: TracendSpacing.xs),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      return SizedBox(
                        height: 8,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: colors.borderSubtle.withValues(
                                  alpha: 0.4,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: target,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: colors.actionPrimary.withValues(
                                    alpha: 0.55,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            if (recorded != null)
                              Positioned(
                                left: (recorded * width).clamp(0.0, width - 4),
                                top: -2,
                                bottom: -2,
                                child: Container(
                                  width: 4,
                                  decoration: BoxDecoration(
                                    color: colors.stateStable,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (exercise.notes.isNotEmpty) ...[
                    const SizedBox(height: TracendSpacing.xxs),
                    Text(
                      exercise.notes,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseStat extends StatelessWidget {
  const _ExerciseStat({required this.text, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      fontFamily: TracendFonts.monoFamily,
      fontSize: 11,
      color: color ?? context.tracendColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
      const SizedBox(width: TracendSpacing.xxs),
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: 10,
          color: context.tracendColors.textSecondary,
        ),
      ),
    ],
  );
}

/// Execution (2026-09-04 Train redesign): the two side-by-side evidence
/// cards — adherence and progression — merged into one card with one row per
/// fact. Display-only: values are facts, not navigation (no chevrons, no
/// dead affordances). Empty progression keeps its honest teaching copy.
class ExecutionCard extends StatelessWidget {
  const ExecutionCard({
    required this.completedSessions,
    required this.plannedSessions,
    required this.progression,
    super.key,
  });

  final int completedSessions;
  final int plannedSessions;
  final List<ExerciseProgression> progression;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final ratio = plannedSessions == 0
        ? 0.0
        : (completedSessions / plannedSessions).clamp(0, 1).toDouble();
    return PremiumGradientCard(
      padding: const EdgeInsets.symmetric(
        horizontal: TracendSpacing.md,
        vertical: TracendSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: TracendSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Sessions completed this cycle',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  '$completedSessions of $plannedSessions',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontFamily: TracendFonts.monoFamily,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: TracendSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 5,
                    width: 88,
                    child: Stack(
                      children: [
                        Container(
                          color: colors.borderSubtle.withValues(alpha: 0.4),
                        ),
                        FractionallySizedBox(
                          widthFactor: ratio,
                          child: Container(color: colors.stateStable),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: TracendSpacing.lg, color: colors.borderHairline),
          if (progression.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: TracendSpacing.sm),
              child: Text(
                'Progression appears after at least two completed sessions '
                'contain comparable logged sets. Planned values are never '
                'charted.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            )
          else
            for (var index = 0; index < progression.length; index++) ...[
              _ProgressionRow(item: progression[index]),
              if (index < progression.length - 1)
                Divider(
                  height: TracendSpacing.lg,
                  color: colors.borderHairline,
                ),
            ],
        ],
      ),
    );
  }
}

class _ProgressionRow extends StatelessWidget {
  const _ProgressionRow({required this.item});
  final ExerciseProgression item;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.exercise,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: TracendSpacing.xxs),
                Text(
                  '${item.sessions} comparable sessions',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            item.bestLoadKg == null
                ? '${item.bestRepetitions ?? '—'} reps'
                : '${item.bestLoadKg} kg',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontFamily: TracendFonts.monoFamily,
              color: colors.stateStable,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
