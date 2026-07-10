import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class TrainScreen extends StatefulWidget {
  const TrainScreen({this.repository, super.key});
  final WorkoutRepository? repository;

  @override
  State<TrainScreen> createState() => _TrainScreenState();
}

class _TrainScreenState extends State<TrainScreen> {
  late final WorkoutRepository _source;
  late Future<TrainingHubData> _hub;
  int _weekday = DateTime.now().weekday;

  @override
  void initState() {
    super.initState();
    _source = widget.repository ?? FixtureWorkoutRepository();
    _hub = _load();
  }

  Future<TrainingHubData> _load() {
    final source = _source;
    if (source is TrainingHubRepository) {
      return (source as TrainingHubRepository).loadTrainingHub();
    }
    return source.loadTodayWorkout().then(
      (workout) => TrainingHubData(
        planTitle: 'Approved plan',
        workouts: [workout],
        recentSessions: const [],
        completedSessions: 0,
        plannedSessions: 0,
        progression: const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TrainingHubData>(
    future: _hub,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const TracendScrollView(
          title: 'Train',
          subtitle: 'Loading your approved plan',
          children: [LinearProgressIndicator(minHeight: 3)],
        );
      }
      if (snapshot.hasError || snapshot.data == null) {
        return TracendScrollView(
          title: 'Train',
          subtitle: 'Approved plan unavailable',
          children: [
            TracendCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your training plan could not be loaded. No fixture workout was substituted.',
                  ),
                  const SizedBox(height: TracendSpacing.sm),
                  OutlinedButton(
                    onPressed: () => setState(() => _hub = _load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ],
        );
      }
      final hub = snapshot.data!;
      final workout = hub.workoutForWeekday(_weekday);
      return TracendScrollView(
        title: 'Train',
        subtitle: hub.planTitle,
        children: [
          _WeekdayStrip(
            workouts: hub.workouts,
            selected: _weekday,
            onSelected: (value) => setState(() => _weekday = value),
          ),
          if (workout == null)
            const TracendCard(
              child: Text(
                'No approved workout is assigned to this day. Use recovery guidance or choose another day.',
              ),
            )
          else ...[
            _WorkoutHero(workout: workout, source: _source),
            const SectionLabel('Prescription'),
            for (final exercise in workout.exercises) ...[
              _ExerciseRow(exercise: exercise),
              const SizedBox(height: TracendSpacing.sm),
            ],
            if (workout.warmUp.isNotEmpty ||
                workout.cooldownCardio.isNotEmpty) ...[
              const SectionLabel('Warm-up and cardio'),
              TracendCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (workout.warmUp.isNotEmpty) ...[
                      Text(
                        'Warm-up',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: TracendSpacing.xxs),
                      Text(workout.warmUp),
                    ],
                    if (workout.cooldownCardio.isNotEmpty) ...[
                      const SizedBox(height: TracendSpacing.sm),
                      Text(
                        'Cooldown / cardio',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: TracendSpacing.xxs),
                      Text(workout.cooldownCardio),
                    ],
                  ],
                ),
              ),
            ],
          ],
          const SectionLabel('Execution evidence'),
          _AdherenceCard(hub: hub),
          if (hub.progression.isNotEmpty) ...[
            const SizedBox(height: TracendSpacing.sm),
            TracendCard(
              child: Column(
                children: [
                  for (final item in hub.progression.take(5))
                    _ProgressionRow(item: item),
                ],
              ),
            ),
          ] else
            const TracendCard(
              child: Text(
                'Progression appears after at least two completed sessions contain comparable logged sets. Planned values are never charted.',
              ),
            ),
          if (hub.recentSessions.isNotEmpty) ...[
            const SectionLabel('Recent sessions'),
            TracendCard(
              child: Column(
                children: [
                  for (final session in hub.recentSessions.take(6))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        CupertinoIcons.check_mark_circled_solid,
                      ),
                      title: Text(session.name),
                      subtitle: Text(
                        '${session.date.day}/${session.date.month}/${session.date.year}',
                      ),
                      trailing: session.durationSeconds == null
                          ? null
                          : Text(
                              '${(session.durationSeconds! / 60).round()} min',
                            ),
                    ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _WeekdayStrip extends StatelessWidget {
  const _WeekdayStrip({
    required this.workouts,
    required this.selected,
    required this.onSelected,
  });
  final List<PlannedWorkout> workouts;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final assigned = workouts
        .map((item) => item.weekday)
        .whereType<int>()
        .toSet();
    return Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var day = 1; day <= 7; day++)
              Padding(
                padding: const EdgeInsets.only(right: TracendSpacing.xs),
                child: Semantics(
                  selected: day == selected,
                  button: true,
                  label: 'Select weekday $day',
                  child: ChoiceChip(
                    label: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(labels[day - 1]),
                        if (assigned.contains(day))
                          const Icon(CupertinoIcons.circle_fill, size: 5),
                      ],
                    ),
                    selected: day == selected,
                    onSelected: (_) => onSelected(day),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutHero extends StatelessWidget {
  const _WorkoutHero({required this.workout, required this.source});
  final PlannedWorkout workout;
  final WorkoutRepository source;

  @override
  Widget build(BuildContext context) => TracendCard(
    radius: TracendRadii.decision,
    raised: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TracendPill(
          label: 'Approved plan',
          icon: CupertinoIcons.check_mark_circled_solid,
        ),
        const SizedBox(height: TracendSpacing.sm),
        Text(workout.name, style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: TracendSpacing.xs),
        Text(workout.objective, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: TracendSpacing.md),
        Wrap(
          spacing: TracendSpacing.lg,
          runSpacing: TracendSpacing.sm,
          children: [
            _Fact(label: 'Duration', value: '${workout.estimatedMinutes} min'),
            _Fact(label: 'Exercises', value: '${workout.exercises.length}'),
            _Fact(
              label: 'Working sets',
              value:
                  '${workout.exercises.fold<int>(0, (sum, item) => sum + item.setCount)}',
            ),
          ],
        ),
        const SizedBox(height: TracendSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).push<void>(
              CupertinoPageRoute(
                builder: (_) =>
                    WorkoutDetailScreen(repository: source, workout: workout),
              ),
            ),
            child: const Text('Start workout'),
          ),
        ),
      ],
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 92,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: TracendSpacing.xxs),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise});
  final PlannedExercise exercise;
  @override
  Widget build(BuildContext context) => TracendCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${exercise.order}'.padLeft(2, '0'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(width: TracendSpacing.sm),
            Expanded(
              child: Text(
                exercise.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: TracendSpacing.sm),
        Wrap(
          spacing: TracendSpacing.md,
          runSpacing: TracendSpacing.xs,
          children: [
            Text(
              '${exercise.setCount} × ${exercise.repMin}–${exercise.repMax} reps',
            ),
            Text('RPE ${exercise.targetRpe}'),
            Text('${exercise.restSeconds}s rest'),
          ],
        ),
        if (exercise.notes.isNotEmpty) ...[
          const SizedBox(height: TracendSpacing.xs),
          Text(exercise.notes, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    ),
  );
}

class _AdherenceCard extends StatelessWidget {
  const _AdherenceCard({required this.hub});
  final TrainingHubData hub;
  @override
  Widget build(BuildContext context) {
    final ratio = hub.plannedSessions == 0
        ? 0.0
        : (hub.completedSessions / hub.plannedSessions).clamp(0, 1).toDouble();
    return TracendCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${hub.completedSessions} of ${hub.plannedSessions} planned sessions completed',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: TracendSpacing.sm),
          LinearProgressIndicator(value: ratio, minHeight: 7),
        ],
      ),
    );
  }
}

class _ProgressionRow extends StatelessWidget {
  const _ProgressionRow({required this.item});
  final ExerciseProgression item;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(item.exercise),
    subtitle: Text('${item.sessions} comparable sessions'),
    trailing: Text(
      item.bestLoadKg == null
          ? '${item.bestRepetitions ?? '—'} reps'
          : '${item.bestLoadKg} kg',
    ),
  );
}
