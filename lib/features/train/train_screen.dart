import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/train/train_view_models.dart';
import 'package:tracend/features/train/widgets/action_cards.dart';
import 'package:tracend/features/train/widgets/exercise_detail_sheet.dart';
import 'package:tracend/features/train/widgets/exercise_list_card.dart';
import 'package:tracend/features/train/widgets/muscle_map.dart';
import 'package:tracend/features/train/widgets/muscles_sheet.dart';
import 'package:tracend/features/train/widgets/prescription_cards.dart';
import 'package:tracend/features/train/widgets/readiness_line.dart';
import 'package:tracend/features/train/widgets/train_parts.dart';
import 'package:tracend/features/train/widgets/training_load_sheet.dart';
import 'package:tracend/features/train/widgets/week_rail_card.dart';
import 'package:tracend/features/train/widgets/week_summary_card.dart';
import 'package:tracend/features/train/widgets/workout_hero.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_skeleton.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// The Train tab: the week as day boxes, today's readiness in one line, the
/// selected day's workout and exercises, then this week's count, training
/// load and history (UX_FLOWS.md, Train).
class TrainScreen extends StatefulWidget {
  const TrainScreen({
    this.repository,
    this.brief,
    this.coach = const FixtureCoachRepository(),
    this.health,
    this.onOpenAccount,
    this.now,
    super.key,
  });
  final WorkoutRepository? repository;
  final DailyBriefRepository? brief;
  final CoachRepository coach;

  /// Apple Health's connection state. Without it, the state is read from
  /// whether today's brief carries health data.
  final HealthRepository? health;

  /// Opens Account, where Apple Health is connected.
  final VoidCallback? onOpenAccount;

  /// The clock, for tests; the hub's `local_today` wins once loaded.
  final DateTime Function()? now;

  @override
  State<TrainScreen> createState() => _TrainScreenState();
}

/// Today's recovery state for the readiness line.
class _Readiness {
  const _Readiness({required this.line, this.computed, this.verdict});

  final ReadinessLine line;
  final ComputedMetrics? computed;
  final String? verdict;
}

class _TrainScreenState extends State<TrainScreen> {
  /// Weeks the strip can page back; the hub carries 28 days.
  static const _weeksBack = 3;

  late final WorkoutRepository _source =
      widget.repository ?? FixtureWorkoutRepository();

  TrainingHubData? _hub;
  Object? _hubError;
  bool _hubLoading = true;

  late Future<_Readiness> _readiness;

  List<WorkoutRepairCandidate> _repairs = const [];
  List<WorkoutReconciliation> _reconciliations = const [];
  final Set<String> _respondedReconciliationIds = {};
  final Set<String> _respondedRepairSessionIds = {};
  String? _busyReconciliationId;

  late DateTime _selected;
  late DateTime _weekStart;
  bool _forward = true;

  HealthkitCompletionCandidate? _candidate;
  bool _healthkitBusy = false;

  BodySide _side = BodySide.front;

  DateTime _clock() => (widget.now ?? DateTime.now)();

  DateTime get _today => normalizedDate(_hub?.localToday ?? _clock());

  DateTime get _currentWeek => mondayOf(_today);

  @override
  void initState() {
    super.initState();
    _selected = normalizedDate(_clock());
    _weekStart = mondayOf(_selected);
    // The readiness line is built only once the hub is in, so a failed
    // brief must not surface as an unhandled error before then.
    _readiness = _loadReadiness()..ignore();
    _loadHub();
    _fetchCandidate();
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> _loadHub() async {
    if (mounted) setState(() => _hubLoading = true);
    final source = _source;
    List<WorkoutRepairCandidate>? repairs;
    List<WorkoutReconciliation>? reconciliations;
    if (source is WorkoutRepairRepository) {
      try {
        repairs =
            (await (source as WorkoutRepairRepository).loadRepairCandidates())
                .where((c) => !_respondedRepairSessionIds.contains(c.sessionId))
                .toList();
      } catch (error) {
        debugPrint('Non-critical error: repair candidates: $error');
      }
    }
    if (source is WorkoutReconciliationRepository) {
      try {
        reconciliations =
            (await (source as WorkoutReconciliationRepository)
                    .loadReconciliations())
                .where((r) => !_respondedReconciliationIds.contains(r.id))
                .toList();
      } catch (error) {
        debugPrint('Non-critical error: workout matches: $error');
      }
    }
    try {
      final hub = await _loadHubData();
      if (!mounted) return;
      final hadHub = _hub != null;
      setState(() {
        _hub = hub;
        _hubError = null;
        _hubLoading = false;
        if (repairs != null) _repairs = repairs;
        if (reconciliations != null) _reconciliations = reconciliations;
        if (!hadHub && hub.localToday != null) {
          _selected = normalizedDate(hub.localToday!);
          _weekStart = mondayOf(_selected);
        }
      });
    } catch (error) {
      debugPrint('Train: training hub failed: $error');
      if (!mounted) return;
      setState(() {
        _hubError = error;
        _hubLoading = false;
        if (repairs != null) _repairs = repairs;
        if (reconciliations != null) _reconciliations = reconciliations;
      });
    }
  }

  Future<TrainingHubData> _loadHubData() async {
    final source = _source;
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

  Future<_Readiness> _loadReadiness() async {
    final repository = widget.brief ?? const FixtureDailyBriefRepository();
    final today = normalizedDate(_clock());
    final brief = await repository.load(today);
    final computed = brief.computed;
    bool connected =
        brief.health != null ||
        computed?.baselines.hrv != null ||
        computed?.baselines.restingHr != null ||
        computed?.baselines.sleepMinutes != null;
    final health = widget.health;
    if (health != null) {
      try {
        final status = await health.loadStatus();
        connected = ReadinessLine.isHealthConnected(status.state);
      } catch (error) {
        debugPrint('Non-critical error: health status: $error');
      }
    }
    String? verdict;
    try {
      final decision = await widget.coach.loadLatest();
      if (decision != null && decision.localDate == DayBoxesStrip.iso(today)) {
        verdict = decision.finalDecision;
      }
    } catch (error) {
      debugPrint('Non-critical error: coach decision: $error');
    }
    return _Readiness(
      line: ReadinessLine.from(
        healthConnected: connected,
        recoveryScore: computed?.scores.recovery,
      ),
      computed: computed,
      verdict: verdict,
    );
  }

  Future<void> _fetchCandidate() async {
    final source = _source;
    if (source is! HealthkitCandidateRepository) return;
    final requested = _selected;
    try {
      final candidate = await (source as HealthkitCandidateRepository)
          .getHealthkitCandidate(requested);
      if (!mounted || !sameDay(requested, _selected)) return;
      setState(() => _candidate = candidate);
    } catch (error) {
      debugPrint('Non-critical error: Apple Health candidate: $error');
    }
  }

  Future<void> _refresh() async {
    final readiness = _loadReadiness()..ignore();
    setState(() {
      _readiness = readiness;
    });
    await Future.wait<void>([
      _loadHub(),
      _fetchCandidate(),
      readiness.then((_) {}, onError: (_) {}),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Day and week
  // ---------------------------------------------------------------------------

  void _select(DateTime date) {
    final day = normalizedDate(date);
    if (sameDay(day, _selected)) return;
    setState(() {
      _forward = day.isAfter(_selected);
      _selected = day;
      _weekStart = mondayOf(day);
      _candidate = null;
    });
    _fetchCandidate();
  }

  bool _canShift(int weeks) {
    final target = _weekStart.add(Duration(days: 7 * weeks));
    final earliest = _currentWeek.subtract(
      const Duration(days: 7 * _weeksBack),
    );
    return !target.isAfter(_currentWeek) && !target.isBefore(earliest);
  }

  void _shiftWeek(int weeks) {
    if (!_canShift(weeks)) return;
    TracendHaptics.selection();
    final target = _weekStart.add(Duration(days: 7 * weeks));
    _select(
      sameDay(target, _currentWeek)
          ? _today
          : target.add(Duration(days: _selected.weekday - 1)),
    );
  }

  bool _reachable(DateTime date) {
    final week = mondayOf(date);
    final earliest = _currentWeek.subtract(
      const Duration(days: 7 * _weeksBack),
    );
    return !week.isAfter(_currentWeek) && !week.isBefore(earliest);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _start(PlannedWorkout workout, DateTime date) async {
    final completed = await startWorkout(
      context,
      workout: workout,
      repository: _source,
      sessionDate: date,
    );
    if (completed && mounted) {
      setState(() => _candidate = null);
      await _refresh();
    }
  }

  void _openExercise(PlannedWorkout workout, PlannedExercise exercise) =>
      showExerciseDetailSheet(
        context,
        workout: workout,
        exercise: exercise,
        repository: _source,
        progressionRule: _hub?.plan?.progressionRule,
      );

  void _viewSummary(PlannedWorkout workout, DateTime date) =>
      showWorkoutSummarySheet(
        context,
        workout: workout,
        repository: _source,
        date: date,
      );

  Future<void> _openOverview(
    PlannedWorkout workout,
    DateTime date, {
    required bool done,
  }) async {
    final action = await showWorkoutOverviewSheet(
      context,
      workout: workout,
      isCompleted: done,
      onExerciseTap: (exercise) => _openExercise(workout, exercise),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case WorkoutOverviewAction.start:
        await _start(workout, date);
      case WorkoutOverviewAction.viewSummary:
        _viewSummary(workout, date);
    }
  }

  Future<void> _autoComplete(HealthkitCompletionCandidate candidate) async {
    final source = _source;
    if (source is! SupabaseWorkoutRepository) return;
    setState(() => _healthkitBusy = true);
    try {
      await source.autoCompleteFromHealthKit(
        candidate.plannedWorkoutId,
        DayBoxesStrip.iso(candidate.localDate),
      );
      if (!mounted) return;
      unawaited(TracendHaptics.success());
      TracendToast.show(context, 'Workout marked complete from Apple Health');
      setState(() {
        _candidate = null;
        _healthkitBusy = false;
      });
      await _loadHub();
    } catch (error) {
      debugPrint('Train: Apple Health completion failed: $error');
      if (!mounted) return;
      setState(() => _healthkitBusy = false);
      TracendToast.show(
        context,
        'Could not save completion. Try again.',
        icon: CupertinoIcons.exclamationmark_circle,
      );
    }
  }

  Future<void> _confirmRepair(WorkoutRepairCandidate candidate) async {
    final source = _source;
    if (source is! WorkoutRepairRepository) return;
    final accepted = await showTracendConfirm(
      context,
      title: 'Correct this workout record?',
      message:
          'Tracend saved ${(candidate.recordedDurationSeconds / 60).round()} '
          'min; Apple Health recorded '
          '${(candidate.healthkitDurationSeconds / 60).round()} min. '
          'Correcting keeps every logged set, marks untouched exercises as '
          'unknown instead of skipped, and records the change.'
          '${candidate.blankDuplicateSessionId == null ? '' : ' The empty duplicate session is also removed.'}',
      confirmLabel: 'Confirm correction',
      cancelLabel: 'Not now',
    );
    if (!accepted || !mounted) return;
    try {
      await (source as WorkoutRepairRepository).confirmRepair(candidate);
      if (!mounted) return;
      unawaited(TracendHaptics.success());
      TracendToast.show(context, 'Workout record corrected');
      setState(() {
        _respondedRepairSessionIds.add(candidate.sessionId);
        _repairs = _repairs
            .where((c) => c.sessionId != candidate.sessionId)
            .toList();
      });
      await _loadHub();
    } catch (error) {
      debugPrint('Train: workout repair failed: $error');
      if (!mounted) return;
      TracendToast.show(
        context,
        'Could not correct this record. Try again.',
        icon: CupertinoIcons.exclamationmark_circle,
      );
    }
  }

  Future<void> _respond(
    WorkoutReconciliation item, {
    required bool accept,
  }) async {
    final source = _source;
    if (source is! WorkoutReconciliationRepository) return;
    setState(() => _busyReconciliationId = item.id);
    try {
      await (source as WorkoutReconciliationRepository).respondToReconciliation(
        item.id,
        accept: accept,
      );
      if (!mounted) return;
      TracendToast.show(
        context,
        accept ? 'Workout match confirmed' : 'Match dismissed',
      );
      setState(() {
        _respondedReconciliationIds.add(item.id);
        _reconciliations = _reconciliations
            .where((candidate) => candidate.id != item.id)
            .toList();
        _busyReconciliationId = null;
      });
      if (accept && _reachable(item.localDate)) _select(item.localDate);
      await _loadHub();
    } catch (error) {
      debugPrint('Train: workout match response failed: $error');
      if (!mounted) return;
      setState(() => _busyReconciliationId = null);
      TracendToast.show(
        context,
        'Could not save this match. Try again.',
        icon: CupertinoIcons.exclamationmark_circle,
      );
    }
  }

  void _showPlan(ActivePlanSummary plan, PlanWeek week) {
    showTracendSheet<void>(
      context,
      title: plan.title,
      subtitle: [
        if (plan.blockWeeks != null) '${plan.blockWeeks} weeks',
        if (plan.sessionsPerWeek != null)
          '${plan.sessionsPerWeek} workouts a week',
      ].join(', '),
      builder: (_) => _PlanSheetBody(plan: plan, week: week),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) =>
      Material(type: MaterialType.transparency, child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    final hub = _hub;
    if (hub == null) {
      return TracendScrollView(
        title: 'Train',
        subtitle: longDate(_today),
        onRefresh: _hubLoading ? null : _refresh,
        children: [
          if (_hubLoading || _hubError == null)
            const _TrainSkeleton()
          else
            _LoadError(error: _hubError!, onRetry: _loadHub),
        ],
      );
    }
    final planWeek = hub.plan == null
        ? null
        : PlanWeek.from(
            effectiveDate: hub.plan!.effectiveDate,
            localToday: hub.localToday,
            blockWeeks: hub.plan!.blockWeeks,
          );
    final pill = planWeek == null
        ? null
        : _PlanPill(
            label: planWeek.label,
            onTap: () => _showPlan(hub.plan!, planWeek),
          );
    // At large text the pill moves under the title so the title never
    // squeezes beside it.
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return TracendScrollView(
      title: 'Train',
      subtitle: longDate(_today),
      trailing: largeText ? null : pill,
      onRefresh: _refresh,
      children: [
        if (largeText && pill != null) ...[
          Align(alignment: Alignment.centerLeft, child: pill),
          const SizedBox(height: TracendSpacing.xs),
        ],
        if (_hubError != null) ...[
          _StaleNote(error: _hubError!),
          const SizedBox(height: TracendSpacing.sm),
        ],
        if (hub.plan == null && hub.workouts.isEmpty)
          _NoPlan(onRetry: _refresh)
        else
          ..._planContent(hub),
      ],
    );
  }

  List<Widget> _planContent(TrainingHubData hub) {
    final load = TrainingLoadSheetModel.from(
      dailyLoad: hub.dailyLoad,
      acwr: hub.load?.acwr,
      monotony: hub.load?.trainingMonotony,
      localToday: hub.localToday,
    );
    final week = [
      for (var i = 0; i < 7; i++) _weekStart.add(Duration(days: i)),
    ];
    final doneThisWeek = week.where(hub.isDayCompleted).length;
    final assigned = hub.workouts.any((w) => w.weekday != null);
    final plannedThisWeek = assigned
        ? week.where((d) => hub.workoutForWeekday(d.weekday) != null).length
        : hub.plan?.sessionsPerWeek ?? hub.workouts.length;
    final attention = _repairs.isNotEmpty || _reconciliations.isNotEmpty;
    return [
      if (!sameDay(_weekStart, _currentWeek))
        _WeekCaption(
          weekStart: _weekStart,
          onThisWeek: () {
            TracendHaptics.selection();
            _select(_today);
          },
        ),
      DayBoxesStrip(
        weekStart: _weekStart,
        selectedDate: _selected,
        today: _today,
        statusFor: (date) => hub.isDayCompleted(date)
            ? DayBoxStatus.done
            : hub.workoutForWeekday(date.weekday) != null
            ? DayBoxStatus.planned
            : DayBoxStatus.rest,
        workoutNameFor: (date) => hub.workoutForWeekday(date.weekday)?.name,
        onSelected: _select,
        onPreviousWeek: _canShift(-1) ? () => _shiftWeek(-1) : null,
        onNextWeek: _canShift(1) ? () => _shiftWeek(1) : null,
      ),
      const SizedBox(height: 14),
      _ReadinessSlot(
        readiness: _readiness,
        load: load,
        onOpenAccount: widget.onOpenAccount,
      ),
      const SizedBox(height: TracendSpacing.sm),
      if (attention) ...[
        AttentionGroup(
          repairs: _repairs,
          reconciliations: _reconciliations,
          busyReconciliationId: _busyReconciliationId,
          selectedDate: _selected,
          onRepair: _confirmRepair,
          onRespond: _respond,
          onShowDay: (date) {
            if (!_reachable(date)) return;
            TracendHaptics.selection();
            _select(date);
          },
        ),
        const SizedBox(height: TracendSpacing.sm),
      ],
      _DaySwitcher(
        dayKey: DayBoxesStrip.iso(_selected),
        forward: _forward,
        child: _dayContent(hub),
      ),
      const SectionLabel('This week'),
      WeekSummaryCard(
        done: doneThisWeek,
        planned: plannedThisWeek,
        loadLabel: load.rowLabel,
        onLoadTap: () => showTrainingLoadSheet(context, model: load),
        historyLabel: hub.recentSessions.isEmpty
            ? null
            : historyLabel(hub.recentSessions),
        onHistoryTap: hub.recentSessions.isEmpty
            ? null
            : () => showTrainingHistorySheet(
                context,
                sessions: hub.recentSessions,
                workoutForId: (id) {
                  for (final workout in hub.workouts) {
                    if (workout.id == id) return workout;
                  }
                  return null;
                },
                onOpenSession: (workout, session) =>
                    _viewSummary(workout, normalizedDate(session.date)),
              ),
      ),
    ];
  }

  Widget _dayContent(TrainingHubData hub) {
    final date = _selected;
    final today = _today;
    final workout = hub.workoutForWeekday(date.weekday);
    if (workout == null) {
      DateTime? nextDate;
      PlannedWorkout? next;
      for (
        var d = date.add(const Duration(days: 1));
        d.weekday != DateTime.monday;
        d = d.add(const Duration(days: 1))
      ) {
        final candidate = hub.workoutForWeekday(d.weekday);
        if (candidate != null && !hub.isDayCompleted(d)) {
          next = candidate;
          nextDate = d;
          break;
        }
      }
      return RestDayHero(
        date: date,
        today: today,
        nextWorkout: next,
        nextDate: nextDate,
        onJump: nextDate == null ? null : () => _select(nextDate!),
      );
    }
    final done = hub.isDayCompleted(date);
    final state = done
        ? HeroDayState.done
        : date.isBefore(today)
        ? HeroDayState.notLogged
        : HeroDayState.planned;
    TrainingSessionSummary? doneSession;
    if (done) {
      for (final session in hub.recentSessions) {
        if (sameDay(session.date, date) &&
            (session.workoutId == null || session.workoutId == workout.id)) {
          doneSession = session;
          break;
        }
      }
    }
    final candidate = _candidate;
    final canAutoComplete = _source is SupabaseWorkoutRepository;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkoutHero(
          workout: workout,
          date: date,
          today: today,
          state: state,
          doneSession: doneSession,
          side: _side,
          onSideChanged: (side) => setState(() => _side = side),
          onOpenOverview: () => _openOverview(workout, date, done: done),
          onStart: () => _start(workout, date),
          onViewSummary: () => _viewSummary(workout, date),
          onOpenMuscles: () => showMusclesSheet(context, workout: workout),
          healthkitCandidate: candidate,
          healthkitBusy: _healthkitBusy,
          onHealthkitComplete: candidate == null || !canAutoComplete
              ? null
              : () => _autoComplete(candidate),
          onHealthkitManual: candidate == null
              ? null
              : () => _start(workout, normalizedDate(candidate.localDate)),
        ),
        Builder(
          builder: (context) => SectionLabel(
            'Exercises',
            // The shared label does not wrap its value; at the largest
            // sizes the count would squeeze the title.
            value: MediaQuery.textScalerOf(context).scale(1) > 1.5
                ? null
                : '${totalSets(workout)} sets',
          ),
        ),
        ExerciseListCard(
          workout: workout,
          onExerciseTap: (exercise) => _openExercise(workout, exercise),
        ),
      ],
    );
  }
}

/// Slides the selected day's content in from the side it came from, or
/// crossfades under Reduce Motion.
class _DaySwitcher extends StatelessWidget {
  const _DaySwitcher({
    required this.dayKey,
    required this.forward,
    required this.child,
  });

  final String dayKey;
  final bool forward;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final level = TracendMotionScope.of(context);
    final key = ValueKey(dayKey);
    return AnimatedSwitcher(
      duration: switch (level) {
        TracendMotionLevel.full => const Duration(milliseconds: 320),
        TracendMotionLevel.reduced => TracendMotion.standard,
        TracendMotionLevel.static => Duration.zero,
      },
      switchInCurve: TracendMotion.curve,
      switchOutCurve: TracendMotion.curve,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        children: [
          for (final old in previous)
            Positioned(top: 0, left: 0, right: 0, child: old),
          ?current,
        ],
      ),
      transitionBuilder: (child, animation) {
        final fade = FadeTransition(opacity: animation, child: child);
        if (level != TracendMotionLevel.full || child.key != key) return fade;
        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(forward ? 0.07 : -0.07, 0),
            end: Offset.zero,
          ).animate(animation),
          child: fade,
        );
      },
      child: KeyedSubtree(key: key, child: child),
    );
  }
}

class _ReadinessSlot extends StatelessWidget {
  const _ReadinessSlot({
    required this.readiness,
    required this.load,
    this.onOpenAccount,
  });

  final Future<_Readiness> readiness;
  final TrainingLoadSheetModel load;
  final VoidCallback? onOpenAccount;

  @override
  Widget build(BuildContext context) => FutureBuilder<_Readiness>(
    future: readiness,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const ExcludeSemantics(
          child: TracendSkeleton.block(height: 58, radius: 14),
        );
      }
      if (snapshot.hasError) {
        final colors = context.tracendColors;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recovery could not load. Pull down to try again.',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              BetaDiagnostic(snapshot.error!),
            ],
          ),
        );
      }
      final data = snapshot.data!;
      return ReadinessLineRow(
        line: data.line,
        verdict: data.verdict,
        onTap: () => showReadinessSheet(
          context,
          line: data.line,
          computed: data.computed,
          load: load,
          onOpenAccount: onOpenAccount,
        ),
      );
    },
  );
}

class _PlanPill extends StatelessWidget {
  const _PlanPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Pressable(
      onTap: onTap,
      semanticLabel: '$label. Opens your plan.',
      borderRadius: BorderRadius.circular(TracendRadii.pill),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          widthFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(TracendRadii.pill),
            ),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 13,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanSheetBody extends StatelessWidget {
  const _PlanSheetBody({required this.plan, required this.week});

  final ActivePlanSummary plan;
  final PlanWeek week;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final block = week.blockWeeks;
    final rule = plan.progressionRule;
    final approved = plan.approvedOn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: TracendSpacing.xs),
        Text(week.label, style: textTheme.titleMedium),
        if (block != null) ...[
          const SizedBox(height: TracendSpacing.sm),
          Semantics(
            label: '${week.label}. ${week.week - 1} weeks done.',
            excludeSemantics: true,
            child: Row(
              children: [
                for (var i = 1; i <= block; i++) ...[
                  if (i > 1) const SizedBox(width: 5),
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: i < week.week
                            ? colors.stateStable
                            : i == week.week
                            ? colors.accentSignal
                            : colors.surfaceRaised,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (rule != null) ...[
          const SizedBox(height: TracendSpacing.md),
          TrainNote(
            icon: CupertinoIcons.arrow_up_right,
            label: 'Plan rule',
            text: rule,
          ),
        ],
        const SizedBox(height: TracendSpacing.md),
        Text(
          approved == null
              ? 'Changes to your plan always need your approval.'
              : 'You approved this plan on ${dayMonth(approved)}. Changes '
                    'always need your approval.',
          style: textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _WeekCaption extends StatelessWidget {
  const _WeekCaption({required this.weekStart, required this.onThisWeek});

  final DateTime weekStart;
  final VoidCallback onThisWeek;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          'Week of ${dayMonth(weekStart)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      TextButton(onPressed: onThisWeek, child: const Text('This week')),
    ],
  );
}

class _TrainSkeleton extends StatelessWidget {
  const _TrainSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading Train',
    child: const ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TracendSkeleton.block(height: 66, radius: 16),
          SizedBox(height: 14),
          TracendSkeleton.block(height: 58, radius: 14),
          SizedBox(height: TracendSpacing.sm),
          TracendSkeleton.block(height: 290),
          SizedBox(height: TracendSpacing.lg),
          TracendSkeleton.block(height: 240),
        ],
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(TracendRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your plan could not load', style: textTheme.titleMedium),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            'Check your connection and try again. Nothing was filled in for '
            'you.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: TracendSpacing.xs),
          BetaDiagnostic(error),
          const SizedBox(height: TracendSpacing.md),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _StaleNote extends StatelessWidget {
  const _StaleNote({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const StatusChip(
        label: 'Offline. Showing your plan from earlier.',
        icon: CupertinoIcons.wifi_slash,
        tone: StatusTone.caution,
      ),
      const SizedBox(height: TracendSpacing.xxs),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: BetaDiagnostic(error),
      ),
    ],
  );
}

class _NoPlan extends StatelessWidget {
  const _NoPlan({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(TracendRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('No active plan', style: trainDisplay(context, size: 26)),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            'Your workouts appear here once you approve a plan. Finish '
            'setting up your plan, then check again.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: TracendSpacing.md),
          OutlinedButton(onPressed: onRetry, child: const Text('Check again')),
        ],
      ),
    );
  }
}
