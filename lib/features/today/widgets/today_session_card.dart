import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// Today's session as something you can see: the workout's name, a strip
/// of blocks (one per prescribed set, grouped by exercise) that fill in as
/// sets are logged in Train, and the coach's note for today.
///
/// Today mirrors logging and never changes it: the blocks are exactly what
/// Train prescribes, and the coach's note is advice in its own words. "Open
/// in Train" (and the card itself) opens the workout.
///
/// States:
/// - workout, not started: name, "5 exercises · 14 sets · about 48 min"
/// - in progress: "6 of 14 sets logged"
/// - completed: "Done · 14 sets logged"
/// - rest day: "Rest day", and the next planned day when the week has one
/// - coach note: today's adjustment, else today's training summary; a
///   decision from another day is not shown; with AI coaching off it says
///   so; without a decision it says how to get one
class TodaySessionCard extends StatelessWidget {
  const TodaySessionCard({
    required this.brief,
    required this.decision,
    required this.aiAllowed,
    required this.onOpen,
    super.key,
  });

  final DailyBrief brief;

  /// The latest coach decision; shown only when it is today's.
  final CoachDecision? decision;
  final bool aiAllowed;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final workout = brief.workout;
    final note = _CoachNote(
      decision: decision?.localDate == brief.localDate ? decision : null,
      aiAllowed: aiAllowed,
    );
    if (workout == null) {
      return _Frame(
        kicker: "Today's session",
        title: 'Rest day',
        semanticLabel: 'Rest day',
        onOpen: null,
        children: [
          Text(
            _nextPlanned(brief) ?? 'Nothing is planned today.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.tracendColors.textSecondary,
            ),
          ),
          const SizedBox(height: TracendSpacing.sm),
          note,
        ],
      );
    }

    final exercises = [
      for (final item in (workout['exercises'] as List? ?? const []))
        if (item is Map)
          (
            order: (item['order'] as num?)?.toInt() ?? 0,
            name: item['name'] as String? ?? 'Exercise',
            sets: ((item['set_count'] as num?)?.toInt() ?? 0).clamp(0, 12),
          ),
    ];
    final session = brief.todaySession;
    final total = exercises.fold<int>(0, (sum, e) => sum + e.sets);
    final logged = exercises.fold<int>(
      0,
      (sum, e) =>
          sum + (session?.completedSets[e.order] ?? 0).clamp(0, e.sets).toInt(),
    );
    final name = workout['name'] as String? ?? 'Workout';
    final status = session == null
        ? workoutSummary(workout)
        : session.completed
        ? 'Done · $logged ${logged == 1 ? 'set' : 'sets'} logged'
        : '$logged of $total sets logged';

    return _Frame(
      kicker: "Today's session",
      title: name,
      semanticLabel: '$name. $status',
      onOpen: onOpen,
      children: [
        Text(
          status,
          style: TracendTheme.numeric(
            context.tracendColors,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: context.tracendColors.textSecondary,
          ),
        ),
        if (total > 0) ...[
          const SizedBox(height: TracendSpacing.sm),
          _SetStrip(
            exercises: [
              for (final e in exercises)
                if (e.sets > 0)
                  (
                    name: e.name,
                    sets: e.sets,
                    done: (session?.completedSets[e.order] ?? 0)
                        .clamp(0, e.sets)
                        .toInt(),
                  ),
            ],
          ),
        ],
        const SizedBox(height: TracendSpacing.sm),
        note,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: onOpen,
            iconAlignment: IconAlignment.end,
            icon: const Icon(CupertinoIcons.chevron_right, size: 14),
            label: const Text('Open in Train'),
          ),
        ),
      ],
    );
  }

  /// "Next: Friday" from the week, or null when nothing else is planned.
  static String? _nextPlanned(DailyBrief brief) {
    final today = DateTime.tryParse(brief.localDate);
    if (today == null) return null;
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    for (final day in brief.week) {
      if (day.planned && day.date.isAfter(today)) {
        return 'Recovery is part of the plan. Next session: '
            '${names[day.date.weekday - 1]}.';
      }
    }
    return null;
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.kicker,
    required this.title,
    required this.semanticLabel,
    required this.onOpen,
    required this.children,
  });

  final String kicker;
  final String title;
  final String semanticLabel;
  final VoidCallback? onOpen;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final header = Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kicker,
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.md,
        TracendSpacing.md,
        TracendSpacing.md,
        TracendSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(TracendRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onOpen == null)
            header
          else
            Pressable(
              onTap: onOpen,
              pressedScale: 0.99,
              borderRadius: BorderRadius.circular(TracendRadii.control),
              child: header,
            ),
          const SizedBox(height: 2),
          ...children,
          if (onOpen == null) const SizedBox(height: TracendSpacing.sm),
        ],
      ),
    );
  }
}

/// One block per prescribed set, grouped by exercise; a logged set is lime.
/// Exercise names sit under their group when they fit.
class _SetStrip extends StatelessWidget {
  const _SetStrip({required this.exercises});

  final List<({String name, int sets, int done})> exercises;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final duration = TracendMotionScope.fade(context, TracendMotion.standard);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var e = 0; e < exercises.length; e++) ...[
                if (e > 0) const SizedBox(width: 5),
                Expanded(
                  flex: exercises[e].sets,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var s = 0; s < exercises[e].sets; s++) ...[
                        if (s > 0) const SizedBox(width: 2),
                        Expanded(
                          child: AnimatedContainer(
                            duration: duration,
                            decoration: BoxDecoration(
                              color: s < exercises[e].done
                                  ? colors.accentSignalRing
                                  : colors.surfaceRaised,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var e = 0; e < exercises.length; e++) ...[
              if (e > 0) const SizedBox(width: 5),
              Expanded(
                flex: exercises[e].sets,
                child: Text(
                  exercises[e].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The coach's note for today, in a lime-tinted panel.
class _CoachNote extends StatelessWidget {
  const _CoachNote({required this.decision, required this.aiAllowed});

  final CoachDecision? decision;
  final bool aiAllowed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final decision = this.decision;
    final String text;
    if (!aiAllowed) {
      text =
          'AI coaching is off, so no daily decision is generated. Turn it on '
          'in Account.';
    } else if (decision == null) {
      text = 'Tap Sync to generate an evidence-backed daily decision.';
    } else {
      text = decision.trainingAdjustments.isNotEmpty
          ? decision.trainingAdjustments.first
          : decision.trainingSummary;
    }
    return Container(
      padding: const EdgeInsets.all(TracendSpacing.sm),
      decoration: BoxDecoration(
        color: decision == null
            ? colors.surfaceRaised
            : colors.accentSignalTint,
        borderRadius: BorderRadius.circular(TracendRadii.control + 4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.slider_horizontal_3,
            size: 17,
            color: decision == null
                ? colors.textSecondary
                : colors.accentSignalInk,
          ),
          const SizedBox(width: TracendSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (decision != null)
                  Text(
                    'Coach · ${_confidence(decision.confidence)}',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.accentSignalInk,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  text,
                  style: textTheme.bodyMedium?.copyWith(
                    color: decision == null
                        ? colors.textSecondary
                        : colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _confidence(String value) => switch (value) {
    'high' => 'high confidence',
    'medium' => 'medium confidence',
    'low' => 'low confidence',
    _ => 'advice',
  };
}

/// "2 exercises · 7 sets · about 60 min" from the real workout map; any
/// part the plan does not carry is left out rather than guessed.
String workoutSummary(Map<String, dynamic> workout) {
  final exercises = workout['exercises'] as List? ?? const [];
  final sets = exercises.fold<int>(
    0,
    (sum, item) =>
        sum + ((item is Map ? item['set_count'] as num? : null)?.toInt() ?? 0),
  );
  final minutes = (workout['estimated_minutes'] as num?)?.toInt();
  return [
    if (exercises.isNotEmpty)
      '${exercises.length} ${exercises.length == 1 ? 'exercise' : 'exercises'}',
    if (sets > 0) '$sets ${sets == 1 ? 'set' : 'sets'}',
    if (minutes != null) 'about $minutes min',
  ].join(' · ');
}
