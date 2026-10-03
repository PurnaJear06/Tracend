import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/muscle_groups.dart';
import 'package:tracend/features/train/train_view_models.dart';
import 'package:tracend/features/train/widgets/muscle_map.dart';
import 'package:tracend/features/train/widgets/train_parts.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// Opens the muscles sheet for [workout]: front and back side by side, then
/// one row per worked muscle with its sets and exercises. A row and its
/// muscle select each other.
Future<void> showMusclesSheet(
  BuildContext context, {
  required PlannedWorkout workout,
}) => showTracendSheet<void>(
  context,
  title: 'Muscles worked',
  subtitle: workout.name,
  builder: (_) => MusclesSheetBody(workout: workout),
);

class MusclesSheetBody extends StatefulWidget {
  const MusclesSheetBody({required this.workout, super.key});

  final PlannedWorkout workout;

  static const footnote =
      'Muscles come from the exercise catalog or Tracend’s reviewed '
      'exercise list. An exercise on neither counts toward none.';

  @override
  State<MusclesSheetBody> createState() => _MusclesSheetBodyState();
}

class _MusclesSheetBodyState extends State<MusclesSheetBody> {
  MuscleGroup? _selected;

  void _select(MuscleGroup group) {
    TracendHaptics.selection();
    setState(() => _selected = _selected == group ? null : group);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final exercises = widget.workout.exercises;
    final sets = muscleSetsFor(exercises);
    final linked = exercises
        .where((exercise) => exercise.primaryMuscles.isNotEmpty)
        .length;
    if (sets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: TracendSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Not enough data yet', style: textTheme.titleSmall),
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              'None of this workout’s exercises has known muscles yet, so '
              'no muscles are shown.',
              style: textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: TracendSpacing.xs),
        LayoutBuilder(
          builder: (context, constraints) {
            final figure = ((constraints.maxWidth - 24) / 2).clamp(80.0, 132.0);
            return Center(
              child: MuscleMapPair(
                muscles: muscleTones(sets),
                palette: musclePalette(context),
                selected: _selected,
                onMuscleTap: (group) {
                  if (sets.any((entry) => entry.group == group)) {
                    _select(group);
                  }
                },
                figureWidth: figure,
                spacing: 24,
              ),
            );
          },
        ),
        const SizedBox(height: TracendSpacing.md),
        Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(TracendRadii.card),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < sets.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 14),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: colors.borderHairline,
                    ),
                  ),
                _MuscleRow(
                  entry: sets[i],
                  exercises: [
                    for (final exercise in exercises)
                      if (exercise.primaryMuscles.contains(sets[i].group))
                        exercise.name,
                  ],
                  selected: _selected == sets[i].group,
                  onTap: () => _select(sets[i].group),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: TracendSpacing.sm),
        Text(
          '${MusclesSheetBody.footnote} $linked of ${exercises.length} '
          'exercises have muscles.',
          style: textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _MuscleRow extends StatelessWidget {
  const _MuscleRow({
    required this.entry,
    required this.exercises,
    required this.selected,
    required this.onTap,
  });

  final MuscleSets entry;
  final List<String> exercises;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final tone = entry.tone == MuscleTone.main ? 'Main' : 'Also worked';
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${entry.group.label}, ${entry.sets} sets, $tone. '
          '${exercises.join(', ')}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        highlightColor: colors.surfaceRaised,
        child: AnimatedContainer(
          duration: TracendMotionScope.fade(context, TracendMotion.quick),
          color: selected ? colors.accentSignalTint : Colors.transparent,
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: entry.tone == MuscleTone.main
                      ? colors.accentSignal
                      : colors.accentSignal.withValues(alpha: 0.45),
                  border: Border.all(color: colors.accentSignalRing),
                ),
              ),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.group.label, style: textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(exercises.join(', '), style: textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: TracendSpacing.sm),
              Text(
                '${entry.sets} ${entry.sets == 1 ? 'set' : 'sets'}',
                style: TextStyle(
                  fontFamily: TracendFonts.numericFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
