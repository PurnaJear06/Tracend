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
  List<WorkoutRepairCandidate> _repairCandidates = const [];
  List<WorkoutReconciliation> _reconciliations = const [];
  String? _reconciliationBusyId;
  int _weekday = DateTime.now().weekday;
  HealthkitCompletionCandidate? _healthkitCandidate;

  @override
  void initState() {
    super.initState();
    _source = widget.repository ?? FixtureWorkoutRepository();
    _hub = _load();
    _fetchHealthkitCandidate();
  }

  Future<TrainingHubData> _load() async {
    final source = _source;
    if (source is WorkoutRepairRepository) {
      _repairCandidates = await (source as WorkoutRepairRepository)
          .loadRepairCandidates();
    }
    if (source is WorkoutReconciliationRepository) {
      _reconciliations = await (source as WorkoutReconciliationRepository)
          .loadReconciliations();
    }
    if (source is TrainingHubRepository) {
      return (source as TrainingHubRepository).loadTrainingHub();
    }
    final workout = await source.loadTodayWorkout();
    return TrainingHubData(
      planTitle: 'Approved plan',
      workouts: [workout],
      recentSessions: const [],
      completedSessions: 0,
      plannedSessions: 0,
      progression: const [],
    );
  }

  Future<void> _confirmRepair(WorkoutRepairCandidate candidate) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct this workout record?'),
        content: Text(
          'Tracend saved ${(candidate.recordedDurationSeconds / 60).round()} minutes, while Apple Health recorded ${(candidate.healthkitDurationSeconds / 60).round()} minutes. Confirming preserves every logged set, changes untouched exercises from skipped to unknown, and audits the correction.${candidate.blankDuplicateSessionId == null ? '' : ' The empty duplicate session will also be abandoned.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm correction'),
          ),
        ],
      ),
    );
    if (accepted != true || _source is! WorkoutRepairRepository) return;
    await (_source as WorkoutRepairRepository).confirmRepair(candidate);
    if (!mounted) return;
    setState(() => _hub = _load());
  }

  Future<void> _respondToReconciliation(
    WorkoutReconciliation item, {
    required bool accept,
  }) async {
    setState(() => _reconciliationBusyId = item.id);
    try {
      await (_source as WorkoutReconciliationRepository)
          .respondToReconciliation(item.id, accept: accept);
      if (!mounted) return;
      setState(() {
        _reconciliations = _reconciliations
            .where((candidate) => candidate.id != item.id)
            .toList();
        _reconciliationBusyId = null;
        _hub = _load();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Workout match confirmed' : 'Match dismissed'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _reconciliationBusyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this match. Try again.')),
      );
    }
  }

  Future<void> _autoComplete(HealthkitCompletionCandidate candidate) async {
    try {
      await (_source as SupabaseWorkoutRepository).autoCompleteFromHealthKit(
        candidate.plannedWorkoutId,
        candidate.localDate.toIso8601String().substring(0, 10),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Workout marked complete from Apple Health')),
      );
      setState(() {
        _hub = _load();
        _healthkitCandidate = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save completion. Try again.'),
        ),
      );
    }
  }

  DateTime _dateForWeekday(int weekday) {
    final today = DateTime.now();
    final diff = (today.weekday - weekday + 7) % 7;
    return DateTime(today.year, today.month, today.day - diff);
  }

  Future<void> _fetchHealthkitCandidate() async {
    if (_source is! HealthkitCandidateRepository) return;
    final date = _dateForWeekday(_weekday);
    final candidate =
        await (_source as HealthkitCandidateRepository).getHealthkitCandidate(date);
    if (!mounted) return;
    setState(() => _healthkitCandidate = candidate);
  }

  void _selectWeekday(int day) {
    if (day == _weekday) return;
    setState(() {
      _weekday = day;
      _healthkitCandidate = null;
    });
    _fetchHealthkitCandidate();
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
      final sessionDate = _dateForWeekday(_weekday);
      final isCompleted = hub.isDayCompleted(sessionDate);
      return TracendScrollView(
        title: 'Train',
        subtitle: hub.planTitle,
        children: [
          _WeekdayStrip(
            workouts: hub.workouts,
            completedDays: hub.completedDays,
            dateForWeekday: _dateForWeekday,
            selected: _weekday,
            onSelected: _selectWeekday,
          ),
          const SizedBox(height: TracendSpacing.md),
          if (_repairCandidates.isNotEmpty) ...[
            _WorkoutRepairCard(
              candidate: _repairCandidates.first,
              onConfirm: () => _confirmRepair(_repairCandidates.first),
            ),
            const SizedBox(height: TracendSpacing.md),
          ],
          if (_reconciliations.isNotEmpty) ...[
            _ReconciliationCard(
              item: _reconciliations.first,
              busy: _reconciliationBusyId == _reconciliations.first.id,
              onAccept: () => _respondToReconciliation(
                _reconciliations.first,
                accept: true,
              ),
              onReject: () => _respondToReconciliation(
                _reconciliations.first,
                accept: false,
              ),
            ),
            const SizedBox(height: TracendSpacing.md),
          ],
          if (workout == null)
            const TracendCard(
              child: Text(
                'No approved workout is assigned to this day. Use recovery guidance or choose another day.',
              ),
            )
          else ...[
            if (_healthkitCandidate != null)
              _HealthkitCompleteCard(
                candidate: _healthkitCandidate!,
                onComplete: () =>
                    _autoComplete(_healthkitCandidate!),
                onManual: () => Navigator.of(context)
                    .push<bool>(
                      CupertinoPageRoute(
                        builder: (_) => WorkoutDetailScreen(
                          repository: _source,
                          workout: workout,
                          sessionDate: _healthkitCandidate!.localDate,
                        ),
                      ),
                    )
                    .then((completed) {
                      if (completed == true) {
      setState(() {
        _hub = _load();
        _healthkitCandidate = null;
      });
                      }
                    }),
              )
            else
              _WorkoutHero(
                workout: workout,
                source: _source,
                sessionDate: sessionDate,
                isCompleted: isCompleted,
                onWorkoutChanged: () => setState(() {
        _hub = _load();
        _healthkitCandidate = null;
      }),
              ),
            const SectionLabel('Prescription'),
            for (var index = 0; index < workout.exercises.length; index++) ...[
              _ExerciseRow(exercise: workout.exercises[index]),
              if (index < workout.exercises.length - 1)
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
                  for (final item in hub.progression)
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

class _WorkoutRepairCard extends StatelessWidget {
  const _WorkoutRepairCard({required this.candidate, required this.onConfirm});
  final WorkoutRepairCandidate candidate;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => TracendCard(
    raised: true,
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

class _ReconciliationCard extends StatelessWidget {
  const _ReconciliationCard({
    required this.item,
    required this.onAccept,
    required this.onReject,
    required this.busy,
  });
  final WorkoutReconciliation item;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) => TracendCard(
    raised: true,
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
          '${item.localDate.day}/${item.localDate.month} · ${item.activityType.replaceAll('_', ' ').toLowerCase()} · ${(item.healthDurationSeconds / 60).round()} min',
        ),
        const SizedBox(height: TracendSpacing.xs),
        Text(
          'Match confidence ${(item.confidence * 100).round()}%. Apple Health confirms the activity; Tracend remains the source for exercises and sets.',
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
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm match'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _WeekdayStrip extends StatelessWidget {
  const _WeekdayStrip({
    required this.workouts,
    required this.completedDays,
    required this.dateForWeekday,
    required this.selected,
    required this.onSelected,
  });
  final List<PlannedWorkout> workouts;
  final Set<DateTime> completedDays;
  final DateTime Function(int weekday) dateForWeekday;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final assigned = workouts
        .map((item) => item.weekday)
        .whereType<int>()
        .toSet();
    final stableColor = context.tracendColors.stateStable;
    return Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var day = 1; day <= 7; day++)
              Padding(
                padding: const EdgeInsets.only(right: TracendSpacing.xs),
                child: ChoiceChip(
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(labels[day - 1]),
                      if (assigned.contains(day))
                        Icon(
                          completedDays.any((d) =>
                              d.year == dateForWeekday(day).year &&
                              d.month == dateForWeekday(day).month &&
                              d.day == dateForWeekday(day).day)
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle_fill,
                          size: 5,
                          color: completedDays.any((d) =>
                              d.year == dateForWeekday(day).year &&
                              d.month == dateForWeekday(day).month &&
                              d.day == dateForWeekday(day).day)
                              ? stableColor
                              : null,
                        ),
                    ],
                  ),
                  selected: day == selected,
                  onSelected: (_) => onSelected(day),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutHero extends StatelessWidget {
  const _WorkoutHero({
    required this.workout,
    required this.source,
    this.sessionDate,
    this.isCompleted = false,
    this.onWorkoutChanged,
  });
  final PlannedWorkout workout;
  final WorkoutRepository source;
  final DateTime? sessionDate;
  final bool isCompleted;
  final VoidCallback? onWorkoutChanged;

  @override
  Widget build(BuildContext context) {
    final stableColor = context.tracendColors.stateStable;
    return TracendCard(
    radius: TracendRadii.decision,
    raised: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isCompleted)
          TracendPill(
            label: 'Completed',
            icon: CupertinoIcons.check_mark_circled_solid,
            color: stableColor,
          )
        else
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
          child: isCompleted
              ? OutlinedButton(
                  onPressed: () => Navigator.of(context)
                      .push<bool>(
                        CupertinoPageRoute(
                          builder: (_) => WorkoutDetailScreen(
                            repository: source,
                            workout: workout,
                            sessionDate: sessionDate,
                          ),
                        ),
                      )
                      .then((completed) {
                        if (completed == true) {
                          onWorkoutChanged?.call();
                        }
                      }),
                  child: const Text('View workout'),
                )
              : FilledButton(
                  onPressed: () => Navigator.of(context)
                      .push<bool>(
                        CupertinoPageRoute(
                          builder: (_) => WorkoutDetailScreen(
                            repository: source,
                            workout: workout,
                            sessionDate: sessionDate,
                          ),
                        ),
                      )
                      .then((completed) {
                        if (completed == true) {
                          onWorkoutChanged?.call();
                        }
                      }),
                  child: const Text('Start workout'),
                ),
        ),
      ],
    ),
  );
  }
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

class _HealthkitCompleteCard extends StatelessWidget {
  const _HealthkitCompleteCard({
    required this.candidate,
    required this.onComplete,
    required this.onManual,
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
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      dateLabel =
          'on ${months[candidate.localDate.month - 1]} ${candidate.localDate.day}';
    }
    return TracendCard(
    radius: TracendRadii.decision,
    raised: true,
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
