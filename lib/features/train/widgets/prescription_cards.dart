import 'package:flutter/cupertino.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// "6 workouts in 4 weeks": the History row's value.
String historyLabel(List<TrainingSessionSummary> sessions) {
  final count = sessions.length;
  return '$count ${count == 1 ? 'workout' : 'workouts'} in 4 weeks';
}

/// Opens the training history: completed sessions, newest first, with
/// friendly dates. A row opens its summary only when its planned workout is
/// known; otherwise it is not shown as tappable.
Future<void> showTrainingHistorySheet(
  BuildContext context, {
  required List<TrainingSessionSummary> sessions,
  required PlannedWorkout? Function(String workoutId) workoutForId,
  required void Function(PlannedWorkout workout, TrainingSessionSummary session)
  onOpenSession,
}) => showTracendSheet<void>(
  context,
  title: 'History',
  subtitle: 'Your completed workouts, last 4 weeks',
  builder: (sheetContext) => TrainingHistoryList(
    sessions: sessions,
    workoutForId: workoutForId,
    onOpenSession: (workout, session) {
      Navigator.of(sheetContext).pop();
      onOpenSession(workout, session);
    },
  ),
);

class TrainingHistoryList extends StatelessWidget {
  const TrainingHistoryList({
    required this.sessions,
    required this.workoutForId,
    required this.onOpenSession,
    super.key,
  });

  final List<TrainingSessionSummary> sessions;
  final PlannedWorkout? Function(String workoutId) workoutForId;
  final void Function(PlannedWorkout workout, TrainingSessionSummary session)
  onOpenSession;

  TracendListRow _row(TrainingSessionSummary session, TracendColors colors) {
    final workout = session.workoutId == null
        ? null
        : workoutForId(session.workoutId!);
    final minutes = session.durationSeconds == null
        ? null
        : (session.durationSeconds! / 60).round();
    final details = [
      friendlyDate(session.date),
      if (minutes != null) '$minutes min',
      if (session.completionSource == CompletionSource.healthkit)
        'from Apple Health',
    ].join(', ');
    return TracendListRow(
      leading: TracendRowIcon(
        icon: CupertinoIcons.checkmark_alt,
        color: colors.stateStable,
      ),
      title: session.name,
      subtitle: details,
      onTap: workout == null ? null : () => onOpenSession(workout, session),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final ordered = [...sessions]..sort((a, b) => b.date.compareTo(a.date));
    return Padding(
      padding: const EdgeInsets.only(top: TracendSpacing.xs),
      child: TracendGroupedList(
        children: [for (final session in ordered) _row(session, colors)],
      ),
    );
  }
}
