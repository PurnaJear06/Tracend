import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/exercise_history.dart';
import 'package:tracend/features/train/widgets/exercise_detail_sheet.dart';
import 'package:tracend/features/train/widgets/exercise_list_card.dart';
import 'package:tracend/features/train/widgets/train_parts.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// What the workout overview sheet asks the screen to do.
enum WorkoutOverviewAction { start, viewSummary }

/// Opens the workout overview: objective, warm-up, exercises and cooldown,
/// with Start workout, or View summary once the day is done. Completes with
/// the chosen action, or null when dismissed.
Future<WorkoutOverviewAction?> showWorkoutOverviewSheet(
  BuildContext context, {
  required PlannedWorkout workout,
  required bool isCompleted,
  required ValueChanged<PlannedExercise> onExerciseTap,
}) => showTracendSheet<WorkoutOverviewAction>(
  context,
  title: workout.name,
  subtitle: workoutMeta(workout),
  builder: (sheetContext) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WorkoutOverviewBody(workout: workout, onExerciseTap: onExerciseTap),
      const SizedBox(height: TracendSpacing.lg),
      if (isCompleted)
        OutlinedButton(
          onPressed: () =>
              Navigator.of(sheetContext).pop(WorkoutOverviewAction.viewSummary),
          child: const Text('View summary'),
        )
      else
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(sheetContext).pop(WorkoutOverviewAction.start),
          icon: const Icon(CupertinoIcons.play_fill, size: 18),
          label: const Text('Start workout'),
        ),
    ],
  ),
);

/// Objective, warm-up, the exercise list and the cooldown.
class WorkoutOverviewBody extends StatelessWidget {
  const WorkoutOverviewBody({
    required this.workout,
    required this.onExerciseTap,
    super.key,
  });

  final PlannedWorkout workout;
  final ValueChanged<PlannedExercise> onExerciseTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final objective = workout.objective.trim();
    final warmUp = workout.warmUp.trim();
    final cooldown = workout.cooldownCardio.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (objective.isNotEmpty) ...[
          const SizedBox(height: TracendSpacing.xs),
          Text(objective, style: textTheme.bodyLarge),
        ],
        if (warmUp.isNotEmpty) ...[
          const _Heading('Warm-up'),
          TrainNote(icon: CupertinoIcons.flame, text: warmUp),
        ],
        _Heading('Exercises', value: '${totalSets(workout)} sets'),
        ExerciseListCard(workout: workout, onExerciseTap: onExerciseTap),
        if (cooldown.isNotEmpty) ...[
          const _Heading('Cooldown and cardio'),
          TrainNote(icon: CupertinoIcons.wind, text: cooldown),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.value});

  final String text;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: textTheme.titleLarge),
            ),
          ),
          if (value != null) Text(value!, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// One exercise as logged in a completed session.
@immutable
class LoggedExercise {
  const LoggedExercise({
    required this.order,
    required this.name,
    required this.status,
    required this.sets,
  });

  final int order;
  final String name;
  final String? status;

  /// Completed sets only.
  final List<HistorySet> sets;
}

/// A completed session as `get_my_workout_session` returns it. Every field
/// is optional: a missing value reads as unknown, never as zero.
@immutable
class LoggedSession {
  const LoggedSession({
    required this.state,
    required this.exercises,
    this.durationSeconds,
    this.effort,
    this.effortSource,
    this.completionSource,
  });

  final String? state;
  final int? durationSeconds;
  final num? effort;
  final EffortSource? effortSource;
  final CompletionSource? completionSource;
  final List<LoggedExercise> exercises;

  bool get completed => state == 'completed';

  int get completedSets =>
      exercises.fold<int>(0, (sum, item) => sum + item.sets.length);

  /// Only an effort the athlete gave is shown; app defaults are not.
  num? get athleteEffort =>
      effortSource == EffortSource.athlete ? effort : null;

  static LoggedSession? parse(
    Map<String, dynamic>? json,
    PlannedWorkout workout,
  ) {
    if (json == null) return null;
    final rows = json['exercises'];
    final exercises = <LoggedExercise>[];
    for (final item in rows is List ? rows : const []) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final order = (row['order'] as num?)?.toInt() ?? 0;
      String? planned;
      for (final exercise in workout.exercises) {
        if (exercise.order == order) planned = exercise.name;
      }
      final sets = row['sets'];
      exercises.add(
        LoggedExercise(
          order: order,
          name: row['performed_name'] as String? ?? planned ?? 'Exercise',
          status: row['status'] as String?,
          sets: [
            for (final set in sets is List ? sets : const [])
              if (set is Map && set['completed'] != false)
                HistorySet.fromJson(Map<String, dynamic>.from(set)),
          ],
        ),
      );
    }
    exercises.sort((a, b) => a.order.compareTo(b.order));
    return LoggedSession(
      state: json['state'] as String?,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      effort: json['session_effort'] as num?,
      effortSource: EffortSource.fromKey(json['session_effort_source']),
      completionSource: CompletionSource.fromKey(json['completion_source']),
      exercises: exercises,
    );
  }
}

/// Opens the summary of the workout done on [date], read from the server.
Future<void> showWorkoutSummarySheet(
  BuildContext context, {
  required PlannedWorkout workout,
  required WorkoutRepository repository,
  required DateTime date,
}) => showTracendSheet<void>(
  context,
  title: workout.name,
  subtitle: 'Done on ${longDate(date)}',
  builder: (_) => WorkoutSummaryBody(
    workout: workout,
    session: repository.loadSession(workout, localDate: date),
  ),
);

class WorkoutSummaryBody extends StatelessWidget {
  const WorkoutSummaryBody({
    required this.workout,
    required this.session,
    super.key,
  });

  final PlannedWorkout workout;
  final Future<Map<String, dynamic>?> session;

  static const healthkitNote =
      'Auto-completed from Apple Health. Sets were not logged in Tracend.';

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: session,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: TracendSpacing.lg),
          child: Center(
            child: TracendLoader(semanticLabel: 'Loading your summary'),
          ),
        );
      }
      if (snapshot.hasError) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: TracendSpacing.xs),
            const TrainNote(
              icon: CupertinoIcons.exclamationmark_circle,
              text:
                  'This summary could not load. Pull to refresh Train and '
                  'try again.',
            ),
            const SizedBox(height: TracendSpacing.xxs),
            BetaDiagnostic(snapshot.error!),
          ],
        );
      }
      final logged = LoggedSession.parse(snapshot.data, workout);
      if (logged == null) {
        return const Padding(
          padding: EdgeInsets.only(top: TracendSpacing.xs),
          child: TrainNote(
            icon: CupertinoIcons.doc_text,
            text: 'No logged session was found for this day.',
          ),
        );
      }
      return _SummaryContent(workout: workout, logged: logged);
    },
  );
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({required this.workout, required this.logged});

  final PlannedWorkout workout;
  final LoggedSession logged;

  @override
  Widget build(BuildContext context) {
    final duration = logged.durationSeconds;
    final effort = logged.athleteEffort;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: TracendSpacing.xs),
        if (logged.completionSource == CompletionSource.healthkit) ...[
          const TrainNote(
            icon: CupertinoIcons.heart_fill,
            text: WorkoutSummaryBody.healthkitNote,
          ),
          const SizedBox(height: TracendSpacing.sm),
        ],
        TrainStatRow(
          tiles: [
            TrainStatTile(
              label: 'Time',
              value: duration == null ? '–' : '${(duration / 60).round()} min',
            ),
            TrainStatTile(
              label: 'Sets',
              value: '${logged.completedSets} of ${totalSets(workout)}',
            ),
            TrainStatTile(
              label: 'Effort',
              value: effort == null ? 'Not rated' : '$effort of 10',
            ),
          ],
        ),
        if (logged.exercises.isNotEmpty) ...[
          const _Heading('What you logged'),
          TracendGroupedList(
            children: [
              for (final exercise in logged.exercises)
                TracendListRow(
                  title: exercise.name,
                  subtitle: exercise.sets.isEmpty
                      ? (exercise.status == 'skipped'
                            ? 'Skipped'
                            : 'No sets logged')
                      : lastSessionText(exercise.sets),
                ),
            ],
          ),
        ],
        const SizedBox(height: TracendSpacing.sm),
        Text(
          'Only what you logged is shown.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Opens the workout logging screen as a full-screen cover. Completes true
/// when the workout was finished.
Future<bool> startWorkout(
  BuildContext context, {
  required PlannedWorkout workout,
  required WorkoutRepository repository,
  DateTime? sessionDate,
}) async {
  unawaited(TracendHaptics.heavy());
  final completed = await Navigator.of(context).push<bool>(
    CupertinoPageRoute(
      fullscreenDialog: true,
      builder: (_) => ActiveWorkoutScreen(
        workout: workout,
        repository: repository,
        sessionDate: sessionDate,
      ),
    ),
  );
  return completed == true;
}

/// The workout overview as a pushed page, for entry points outside Train
/// (Today's "Start session"). It pops true once the workout is finished.
/// A day that is already done shows View summary instead of Start.
class WorkoutDetailScreen extends StatefulWidget {
  const WorkoutDetailScreen({
    this.repository,
    this.workout,
    this.sessionDate,
    super.key,
  });
  final WorkoutRepository? repository;
  final PlannedWorkout? workout;
  final DateTime? sessionDate;

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  late final WorkoutRepository _repository =
      widget.repository ?? FixtureWorkoutRepository();
  late final PlannedWorkout _workout = widget.workout ?? PlannedWorkout.fixture;
  late final DateTime _date = widget.sessionDate ?? DateTime.now();
  late final Future<bool> _completed = _loadCompleted();

  Future<bool> _loadCompleted() async {
    try {
      final session = await _repository.loadSession(_workout, localDate: _date);
      final logged = LoggedSession.parse(session, _workout);
      return logged != null &&
          logged.completed &&
          sameDay(_sessionDay(session), _date);
    } catch (error) {
      debugPrint('Non-critical error: workout state: $error');
      return false;
    }
  }

  static DateTime _sessionDay(Map<String, dynamic>? session) {
    final raw = session?['local_date'];
    return (raw is String ? DateTime.tryParse(raw) : null) ?? DateTime(0);
  }

  Future<void> _start() async {
    final navigator = Navigator.of(context);
    final completed = await startWorkout(
      context,
      workout: _workout,
      repository: _repository,
      sessionDate: widget.sessionDate,
    );
    if (completed && mounted) navigator.pop(true);
  }

  void _openExercise(PlannedExercise exercise) => showExerciseDetailSheet(
    context,
    workout: _workout,
    exercise: exercise,
    repository: _repository,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Scaffold(
      appBar: AppBar(title: Text(_workout.name)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            TracendSpacing.gutter,
            TracendSpacing.xs,
            TracendSpacing.gutter,
            TracendSpacing.xxl,
          ),
          children: [
            Text(
              workoutMeta(_workout),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            WorkoutOverviewBody(
              workout: _workout,
              onExerciseTap: _openExercise,
            ),
            const SizedBox(height: TracendSpacing.lg),
            FutureBuilder<bool>(
              future: _completed,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(height: 52);
                }
                if (snapshot.data == true) {
                  return OutlinedButton(
                    onPressed: () => showWorkoutSummarySheet(
                      context,
                      workout: _workout,
                      repository: _repository,
                      date: _date,
                    ),
                    child: const Text('View summary'),
                  );
                }
                return FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(CupertinoIcons.play_fill, size: 18),
                  label: const Text('Start workout'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
