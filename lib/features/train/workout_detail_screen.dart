import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class WorkoutDetailScreen extends StatelessWidget {
  const WorkoutDetailScreen({this.repository, this.workout, super.key});
  final WorkoutRepository? repository;
  final PlannedWorkout? workout;

  @override
  Widget build(BuildContext context) {
    final currentWorkout = workout ?? PlannedWorkout.fixture;
    return Scaffold(
      appBar: AppBar(title: Text(currentWorkout.name)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            TracendSpacing.gutter,
            TracendSpacing.md,
            TracendSpacing.gutter,
            TracendSpacing.xxl,
          ),
          children: [
            TracendCard(
              radius: TracendRadii.decision,
              padding: const EdgeInsets.all(TracendSpacing.gutter),
              raised: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TracendPill(
                    label: 'Prescription',
                    icon: CupertinoIcons.doc_text_fill,
                  ),
                  const SizedBox(height: TracendSpacing.sm),
                  Text(
                    currentWorkout.objective,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: TracendSpacing.md),
                  MetricStrip(
                    items: [
                      MetricStripItem(
                        label: 'Duration',
                        value: '${currentWorkout.estimatedMinutes} min',
                        detail: 'planned',
                      ),
                      MetricStripItem(
                        label: 'Exercises',
                        value: '${currentWorkout.exercises.length}',
                        detail: 'ordered',
                      ),
                      MetricStripItem(
                        label: 'Sets',
                        value:
                            '${currentWorkout.exercises.fold<int>(0, (total, item) => total + item.setCount)}',
                        detail: 'working',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: TracendSpacing.lg),
            TracendCard(
              raised: true,
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < currentWorkout.exercises.length;
                    index++
                  ) ...[
                    _ExerciseRow(
                      order: currentWorkout.exercises[index].order
                          .toString()
                          .padLeft(2, '0'),
                      name: currentWorkout.exercises[index].name,
                      detail:
                          '${currentWorkout.exercises[index].setCount} × ${currentWorkout.exercises[index].repMin}–${currentWorkout.exercises[index].repMax} · RPE ${currentWorkout.exercises[index].targetRpe}',
                    ),
                    if (index < currentWorkout.exercises.length - 1)
                      const Divider(height: TracendSpacing.xl),
                  ],
                ],
              ),
            ),
            const SectionLabel('Execution mode'),
            const TracendCard(
              raised: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusChip(
                    label: 'Offline logging available',
                    icon: CupertinoIcons.arrow_2_circlepath,
                  ),
                  SizedBox(height: TracendSpacing.md),
                  Text(
                    'Sets autosave on this device. Sync resumes when a connection returns.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: TracendSpacing.lg),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push<void>(
                  CupertinoPageRoute(
                    builder: (_) => ActiveWorkoutScreen(
                      workout: currentWorkout,
                      repository: repository ?? FixtureWorkoutRepository(),
                    ),
                  ),
                );
              },
              icon: const Icon(CupertinoIcons.play_fill, size: 18),
              label: const Text('Begin first exercise'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.order,
    required this.name,
    required this.detail,
  });
  final String order;
  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(order, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleMedium),
              Text(detail, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const Icon(CupertinoIcons.chevron_right, size: 18),
      ],
    );
  }
}
