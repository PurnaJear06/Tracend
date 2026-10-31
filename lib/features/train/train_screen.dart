import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_repository.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/readiness/day_adjustment_card.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/readiness/pain_reporting.dart';
import 'package:tracend/features/readiness/safety_copy.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/guidance/cardio_week_sheet.dart';
import 'package:tracend/features/train/guidance/deload_card.dart';
import 'package:tracend/features/train/guidance/guidance_copy.dart';
import 'package:tracend/features/train/guidance/training_guidance_controller.dart';
import 'package:tracend/features/train/offline_safety_notes.dart';
import 'package:tracend/features/train/open_workout.dart';
import 'package:tracend/features/train/train_view_models.dart';
import 'package:tracend/features/train/training_pause_repository.dart';
import 'package:tracend/features/train/widgets/action_cards.dart';
import 'package:tracend/features/train/widgets/break_widgets.dart';
import 'package:tracend/features/train/widgets/exercise_detail_sheet.dart';
import 'package:tracend/features/train/widgets/exercise_list_card.dart';
import 'package:tracend/features/train/widgets/muscle_map.dart';
import 'package:tracend/features/train/widgets/muscles_sheet.dart';
import 'package:tracend/features/train/widgets/open_workout_card.dart';
import 'package:tracend/features/train/widgets/prescription_cards.dart';
import 'package:tracend/features/train/widgets/readiness_line.dart';
import 'package:tracend/features/train/widgets/train_parts.dart';
import 'package:tracend/features/train/widgets/training_load_sheet.dart';
import 'package:tracend/features/train/widgets/week_rail_card.dart';
import 'package:tracend/features/train/widgets/week_summary_card.dart';
import 'package:tracend/features/train/widgets/workout_hero.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/app_lifecycle.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/plan_changes.dart';
import 'package:tracend/shared/training_availability.dart';
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
    this.planChanges,
    this.workoutRequests,
    this.resumeRequests,
    this.dayAdjustment,
    this.guidance,
    this.proposals,
    this.onTalkToCoach,
    this.onCheckIn,
    this.active = true,
    this.workoutLogs,
    this.showToday,
    this.onRetryConnection,
    this.pain,
    this.pauses = const FixtureTrainingPauseRepository(),
    super.key,
  });

  /// Sets and ends breaks ("Taking a break", "End break early").
  final TrainingPauseRepository pauses;

  /// Whether this tab is the one on screen. Opening it again reloads a hub
  /// that is not fresh.
  final bool active;

  /// Announces a workout logged elsewhere (Today's "Save workout"), so the
  /// hub counts it.
  final Listenable? workoutLogs;

  /// Counts the taps on Today's session card: Train then selects today.
  final ValueListenable<int>? showToday;

  /// Asks the app to check the connection again while it is open on the
  /// saved plan; the shell's way out of its offline mode. Null where the app
  /// is never offline.
  final Future<void> Function()? onRetryConnection;

  /// Sends the pain check made during a workout started from here.
  final PainReporting? pain;

  /// Today's same-day readiness adjustment, shared with Today. Null without a
  /// backend, where there is none.
  final DayAdjustmentController? dayAdjustment;

  /// Today's training guidance: the lighter-week card and the cardio row. Null
  /// without a backend, where there is none.
  final TrainingGuidanceController? guidance;

  /// Answers the lighter week's proposal. The lighter-week card needs both
  /// this and [guidance].
  final CoachProposalRepository? proposals;

  /// Opens Coach with the readiness card's question in the box.
  final ValueChanged<String>? onTalkToCoach;

  /// Opens today's check-in, which Today owns.
  final VoidCallback? onCheckIn;

  /// Reloads the hub when a Coach proposal changed the plan.
  final PlanChanges? planChanges;

  /// Counts the taps on the workout's Live Activity that ask for the workout
  /// in progress. The newest workout left open on this phone reopens.
  final ValueListenable<int>? workoutRequests;

  /// Today's Resume card: the open workout it names reopens here.
  final ResumeRequests? resumeRequests;
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
  /// A tab opened again reloads a hub older than this.
  static const _reselectAfter = Duration(minutes: 1);

  /// Weeks the strip can page back; the hub carries 28 days.
  static const _weeksBack = 3;

  late final WorkoutRepository _source =
      widget.repository ?? FixtureWorkoutRepository();

  TrainingHubData? _hub;
  Object? _hubError;
  bool _hubLoading = true;

  /// The sore-area notes the phone kept, read once a saved plan is on screen.
  OfflineSafetyNotes? _safetyNotes;
  bool _safetyNotesRead = false;

  late Future<_Readiness> _readiness;

  /// The brief's numbers behind today's readiness, for the readiness card's
  /// "what Tracend sees". Null until the brief loads.
  ComputedMetrics? _computed;

  /// The day [_readiness] and [_computed] were loaded for.
  late DateTime _readinessDay;

  List<WorkoutRepairCandidate> _repairs = const [];
  List<WorkoutReconciliation> _reconciliations = const [];
  final Set<String> _respondedReconciliationIds = {};
  final Set<String> _respondedRepairSessionIds = {};
  String? _busyReconciliationId;

  late DateTime _selected;
  late DateTime _weekStart;
  bool _forward = true;

  /// The selected day follows today, across midnight, until the athlete picks
  /// another day.
  bool _followsToday = true;

  /// When the hub last arrived, and for which phone day.
  late final LoadStamp _loaded = LoadStamp(_clock);
  late final ResumeObserver _resume = ResumeObserver(_reloadIfStale);

  /// Which hub load started last; an older reply is dropped.
  int _hubLoads = 0;

  HealthkitCompletionCandidate? _candidate;
  bool _healthkitBusy = false;

  BodySide _side = BodySide.front;

  /// A break call is on its way, and the break set a moment ago here (its
  /// card offers Undo).
  bool _pauseBusy = false;
  String? _justSetPauseId;

  /// The Live Activity or Today's Resume card asked for a workout in
  /// progress and the hub that holds the workouts has not loaded yet.
  bool _resumePending = false;

  /// The open workout Today's Resume card asked for; null for the Live
  /// Activity, which asks for the newest.
  OpenWorkout? _resumeTarget;

  /// The workouts left open on this phone, newest first, whatever their day.
  List<OpenWorkout> _open = const [];

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
    widget.planChanges?.addListener(_planChanged);
    widget.workoutLogs?.addListener(_planChanged);
    widget.showToday?.addListener(_showToday);
    _resume.attach();
    final requests = widget.workoutRequests;
    _resumeTarget = widget.resumeRequests?.take();
    _resumePending = (requests?.value ?? 0) > 0 || _resumeTarget != null;
    requests?.addListener(_workoutRequested);
    widget.resumeRequests?.addListener(_resumeRequested);
  }

  @override
  void dispose() {
    _resume.detach();
    widget.planChanges?.removeListener(_planChanged);
    widget.workoutLogs?.removeListener(_planChanged);
    widget.showToday?.removeListener(_showToday);
    widget.workoutRequests?.removeListener(_workoutRequested);
    widget.resumeRequests?.removeListener(_resumeRequested);
    super.dispose();
  }

  @override
  void didUpdateWidget(TrainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      _reloadIfStale(within: _reselectAfter);
    }
  }

  /// Coming back to the app or to this tab reloads a hub that is old or
  /// belongs to a day that is over, and moves the selection to the new today
  /// unless the athlete picked another day.
  void _reloadIfStale({Duration? within}) {
    if (!mounted || _hubLoading && _hub == null) return;
    // A saved plan shown for want of a connection is tried again every time.
    if (_hub?.cachedAt != null || _loaded.isStale(within: within)) {
      unawaited(_refresh());
    }
  }

  /// The hub on screen was loaded on an earlier day than the phone's today.
  bool get _dayRolledOver {
    final day = _loaded.day;
    return day != null && day != localDayKey(_clock());
  }

  /// Today's session card: the selection goes to today, and the hub is
  /// reloaded if its day is over.
  void _showToday() {
    if (!mounted) return;
    _followsToday = true;
    _select(_today);
    _reloadIfStale(within: _reselectAfter);
  }

  void _workoutRequested() {
    _resumePending = true;
    _resumeTarget = null;
    unawaited(_resumeWorkout());
  }

  void _resumeRequested() {
    final target = widget.resumeRequests?.take();
    if (target == null) return;
    _resumePending = true;
    _resumeTarget = target;
    unawaited(_resumeWorkout());
  }

  /// Reopens a workout left open on this phone, whatever its day: the one
  /// Today's Resume card named, or the newest for the Live Activity. Nothing
  /// opens over a workout that is already on screen, and a request the hub
  /// could not answer is dropped, so it never opens a workout later on its
  /// own.
  Future<void> _resumeWorkout() async {
    if (!_resumePending || _hub == null || _hubLoading) return;
    _resumePending = false;
    final target = _resumeTarget;
    _resumeTarget = null;
    if (ActiveWorkoutScreen.isOpen) return;
    final open = await _readOpenWorkouts();
    if (!mounted || ActiveWorkoutScreen.isOpen) return;
    final chosen = target == null
        ? open.firstOrNull
        : open.where((o) => o.isOn(target.workoutId, target.date)).firstOrNull;
    if (chosen != null) {
      await _reopen(chosen);
    } else if (target != null) {
      _resumeGone();
    }
  }

  /// This phone's open workouts, newest first; empty when they cannot be
  /// read or the repository keeps none.
  Future<List<OpenWorkout>> _readOpenWorkouts() async {
    final source = _source;
    if (source is! OpenWorkoutRepository) return const [];
    try {
      return await (source as OpenWorkoutRepository).loadOpenWorkouts();
    } catch (error) {
      logNonCritical(error, 'open workouts not read');
      return const [];
    }
  }

  Future<void> _loadOpenWorkouts() async {
    final open = await _readOpenWorkouts();
    if (mounted) setState(() => _open = open);
  }

  /// Opens [open] in the logger on the day it is logged under. The drafts
  /// are read again first: a workout the send of waiting workouts already
  /// filed on its day is answered on Today, never started again here. A send
  /// still under way is the logger's to wait for, within its own bound. A
  /// draft made before the plan was copied with new ids moves to its copy in
  /// the current plan first.
  Future<void> _reopen(OpenWorkout open) async {
    final current = await _readOpenWorkouts();
    if (!mounted) return;
    setState(() => _open = current);
    final still = current
        .where((o) => o.isOn(open.workoutId, open.date))
        .firstOrNull;
    if (still == null) {
      _resumeGone();
      return;
    }
    var workout = _planWorkout(still.workoutId);
    if (workout == null) {
      workout = await _moveToCurrentPlan(still);
      if (workout == null || !mounted) return;
      // The hub on screen still names the old copy's ids.
      unawaited(_refresh());
    }
    if (_reachable(still.date)) _select(still.date);
    await _start(workout, still.date);
  }

  /// Moves [open]'s draft to its workout's copy in the current plan and
  /// returns that copy, as the logger does when a start finds its workout gone
  /// (P0002). Null when there is no copy, or when the plan cannot be read: the
  /// athlete is told, and the sets stay on this phone.
  Future<PlannedWorkout?> _moveToCurrentPlan(OpenWorkout open) async {
    final source = _source;
    final identity = WorkoutIdentity.fromJson(open.identityJson);
    if (identity != null && source is WorkoutPlanRemapper) {
      final remapper = source as WorkoutPlanRemapper;
      try {
        final current = await remapper.moveToCurrentPlan(
          open.workoutId,
          identity,
          ownerId: remapper.signedInUserId,
        );
        if (current != null) return current;
      } catch (error) {
        logNonCritical(error, 'current plan not read');
        if (mounted) {
          TracendToast.show(
            context,
            'Your plan changed since this workout began. Connect to open it in '
            'your current plan. Its sets are kept on this phone.',
            icon: CupertinoIcons.wifi_slash,
          );
        }
        return null;
      }
    }
    if (mounted) {
      TracendToast.show(
        context,
        'This workout is no longer in your plan. Its sets are kept on this '
        'phone.',
        icon: CupertinoIcons.exclamationmark_circle,
      );
    }
    return null;
  }

  void _resumeGone() {
    TracendToast.show(
      context,
      workoutFiledMessage,
      icon: CupertinoIcons.checkmark_circle,
    );
  }

  /// The plan's workout with [id], or null when the plan has none.
  PlannedWorkout? _planWorkout(String id) {
    for (final workout in _hub?.workouts ?? const <PlannedWorkout>[]) {
      if (workout.id == id) return workout;
    }
    return null;
  }

  /// Whether [open] is a draft of [workout]: by its id, or, for a draft made
  /// before the plan was copied with new ids, by the identity it stored.
  bool _isDraftOf(OpenWorkout open, PlannedWorkout workout) {
    if (open.workoutId == workout.id) return true;
    if (_planWorkout(open.workoutId) != null) return false;
    return WorkoutIdentity.fromJson(open.identityJson)?.matches(workout) ??
        false;
  }

  /// The plan's workout [open] is a draft of, or null.
  PlannedWorkout? _planWorkoutOf(OpenWorkout open) =>
      _planWorkout(open.workoutId) ??
      (_hub?.workouts ?? const <PlannedWorkout>[])
          .where((workout) => _isDraftOf(open, workout))
          .firstOrNull;

  /// The workout left open for [workout] on [date], if any.
  OpenWorkout? _openOn(PlannedWorkout workout, DateTime date) => _open
      .where((o) => sameDay(o.date, date) && _isDraftOf(o, workout))
      .firstOrNull;

  void _planChanged() {
    if (mounted) unawaited(_refresh());
  }

  /// Reloads the week and tells Today and Coach the plan's days changed.
  void _breakChanged() {
    if (!mounted) return;
    if (widget.planChanges != null) {
      widget.planChanges!.announce();
    } else {
      unawaited(_refresh());
    }
  }

  Future<void> _takeBreak() async {
    final id = await takeBreak(
      context,
      today: _today,
      repository: widget.pauses,
    );
    if (id == null || !mounted) return;
    setState(() => _justSetPauseId = id);
    _breakChanged();
  }

  Future<void> _endBreak(TrainingPause pause) async {
    setState(() => _pauseBusy = true);
    try {
      final changed = await endBreak(
        context,
        pause: pause,
        today: _today,
        repository: widget.pauses,
        justSet: pause.id == _justSetPauseId,
      );
      if (!changed || !mounted) return;
      setState(() => _justSetPauseId = null);
      _breakChanged();
    } finally {
      if (mounted) setState(() => _pauseBusy = false);
    }
  }

  /// "Try again" on the offline note: the plan is read again, and the app is
  /// asked to check the connection so it can leave its offline mode.
  Future<void> _retryConnection() async {
    final reconnect = widget.onRetryConnection;
    await Future.wait<void>([_refresh(), ?reconnect?.call()]);
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> _loadHub() async {
    final load = ++_hubLoads;
    if (mounted) setState(() => _hubLoading = true);
    unawaited(_loadOpenWorkouts());
    final source = _source;
    // Opened on the saved plan because the account could not be checked: the
    // phone's copy shows at once, and the load below replaces it when the
    // server answers. Without this an expired session waits for its refresh
    // to fail before anything shows.
    if (_hub == null && widget.onRetryConnection != null) {
      unawaited(_showSaved(load));
    }
    // Read beside the hub, so a connection too slow for them does not hold
    // the plan back; they are given a few seconds once the hub is in.
    final repairsLoad = source is WorkoutRepairRepository
        ? _optional(
            (source as WorkoutRepairRepository).loadRepairCandidates(),
            'repair candidates',
          )
        : Future<List<WorkoutRepairCandidate>?>.value();
    final reconciliationsLoad = source is WorkoutReconciliationRepository
        ? _optional(
            (source as WorkoutReconciliationRepository).loadReconciliations(),
            'workout matches',
          )
        : Future<List<WorkoutReconciliation>?>.value();
    TrainingHubData? loadedHub;
    Object? failure;
    try {
      loadedHub = await _loadHubData();
    } catch (error) {
      failure = error;
    }
    final repairs = (await repairsLoad)
        ?.where((c) => !_respondedRepairSessionIds.contains(c.sessionId))
        .toList();
    final reconciliations = (await reconciliationsLoad)
        ?.where((r) => !_respondedReconciliationIds.contains(r.id))
        .toList();
    if (loadedHub == null) {
      logNonCritical(failure!, 'Train: training hub failed');
      _resumePending = false;
      _resumeTarget = null;
      if (!mounted || load != _hubLoads) return;
      setState(() {
        _hubError = failure;
        _hubLoading = false;
        if (repairs != null) _repairs = repairs;
        if (reconciliations != null) _reconciliations = reconciliations;
      });
      return;
    }
    final hub = loadedHub;
    if (!mounted || load != _hubLoads) return;
    _loaded.mark();
    setState(() {
      _show(hub);
      _hubLoading = false;
      if (repairs != null) _repairs = repairs;
      if (reconciliations != null) _reconciliations = reconciliations;
    });
    unawaited(_resumeWorkout());
    if (hub.cachedAt != null) unawaited(_loadSafetyNotes());
    // The hub names the athlete's own today: the day readiness is read for.
    // A saved copy names the phone's day, which is not the server's to teach.
    if (hub.localToday != null && hub.cachedAt == null) {
      unawaited(widget.dayAdjustment?.load(localToday: hub.localToday));
      unawaited(widget.guidance?.load(localToday: hub.localToday));
    }
  }

  /// Puts [hub] on screen: the selection follows its today, and the
  /// readiness numbers are read again when they were read for another day.
  /// Called inside `setState`.
  void _show(TrainingHubData hub) {
    _hub = hub;
    _hubError = null;
    if (_followsToday && hub.localToday != null) {
      final today = normalizedDate(hub.localToday!);
      if (!sameDay(today, _selected)) _candidate = null;
      _selected = today;
      _weekStart = mondayOf(today);
    }
    // The readiness numbers were read for the phone's day: read them again
    // for the server's when the two differ.
    if (hub.localToday != null && !sameDay(hub.localToday!, _readinessDay)) {
      _computed = null;
      _readiness = _loadReadiness()..ignore();
    }
  }

  /// The phone's copy of the plan, on screen while the server is tried. A
  /// load that already finished (or a newer one) is not overwritten.
  Future<void> _showSaved(int load) async {
    final source = _source;
    if (source is! SavedTrainingHubRepository) return;
    TrainingHubData? saved;
    try {
      saved = await (source as SavedTrainingHubRepository)
          .loadSavedTrainingHub();
    } catch (error) {
      logNonCritical(error, 'Train: saved plan not read');
    }
    if (saved == null || !mounted || load != _hubLoads || _hub != null) return;
    final hub = saved;
    setState(() {
      _show(hub);
      _hubLoading = false;
    });
    unawaited(_resumeWorkout());
    unawaited(_loadSafetyNotes());
  }

  /// What the phone last kept about sore areas, said beside a saved plan: the
  /// day card needs the server, but a hold is still a hold with no signal.
  Future<void> _loadSafetyNotes() async {
    final source = _source;
    OfflineSafetyNotes? notes;
    if (source is SavedSafetyNotesRepository) {
      try {
        notes = await (source as SavedSafetyNotesRepository)
            .loadSavedSafetyNotes();
      } catch (error) {
        logNonCritical(error, 'Train: safety notes not read');
      }
    }
    if (!mounted) return;
    setState(() {
      _safetyNotes = notes;
      _safetyNotesRead = true;
    });
  }

  /// [read], or null when it fails or takes longer than a few seconds: the
  /// lists beside the hub are a convenience, never a reason to wait.
  Future<List<T>?> _optional<T>(Future<List<T>> read, String what) async {
    try {
      return await read.timeout(const Duration(seconds: 5));
    } catch (error) {
      logNonCritical(error, what);
      return null;
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
    // The hub's day once it is known: the server's today, not the phone's.
    final today = _today;
    _readinessDay = today;
    final brief = await repository.load(today);
    final computed = brief.computed;
    if (mounted && sameDay(today, _readinessDay)) {
      setState(() => _computed = computed);
    }
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
        logNonCritical(error, 'health status');
      }
    }
    String? verdict;
    try {
      final decision = await widget.coach.loadLatest();
      if (decision != null && decision.localDate == DayBoxesStrip.iso(today)) {
        verdict = decision.finalDecision;
      }
    } catch (error) {
      logNonCritical(error, 'coach decision');
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
      logNonCritical(error, 'Apple Health candidate');
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
    _followsToday = sameDay(day, _today);
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

  /// [workout] as the athlete's accepted same-day adjustment leaves it, when
  /// [date] is today, for showing; any other day's workout is the plan as
  /// written.
  PlannedWorkout _forDay(PlannedWorkout workout, DateTime date) {
    final adjustment = widget.dayAdjustment?.current;
    if (adjustment == null || !sameDay(date, _today)) return workout;
    return adjustment.applyTo(workout);
  }

  /// The plan's own copy of [shown], which may be today's adjusted view.
  PlannedWorkout _planned(PlannedWorkout shown) {
    for (final workout in _hub?.workouts ?? const <PlannedWorkout>[]) {
      if (workout.id == shown.id) return workout;
    }
    return shown;
  }

  /// Opens the logger for [planned], the plan as written. The logger takes
  /// held weights from today's accepted answer, never its set counts: the
  /// server decides the sets when the workout starts, and the logger follows
  /// the rows it reads back. Nothing starts while an answer is on its way, so
  /// a start never races the answer it should carry. The adjustment is read
  /// again whenever the workout screen closes.
  Future<void> _start(PlannedWorkout planned, DateTime date) async {
    final readiness = widget.dayAdjustment;
    if (readiness?.busy ?? false) {
      TracendToast.show(
        context,
        'Saving your choice for today. Try again in a moment.',
        icon: CupertinoIcons.hourglass,
      );
      return;
    }
    final adjustment = readiness?.current;
    final workout = adjustment == null || !sameDay(date, _today)
        ? planned
        : adjustment.applyTo(planned, sets: false);
    final completed = await startWorkout(
      context,
      workout: workout,
      repository: _source,
      sessionDate: date,
      pain: widget.pain,
    );
    if (readiness != null) unawaited(readiness.load());
    await _loadOpenWorkouts();
    if (completed && mounted) {
      setState(() => _candidate = null);
      await _refresh();
    }
  }

  /// A start the athlete asked for on this screen. If the day changed since
  /// the hub loaded, the screen still believes the old day is today: it
  /// reloads instead of sending that day's date. One workout runs at a time:
  /// while another has sets logged the athlete is asked first, and starting
  /// this one anyway leaves that one's draft as it is.
  Future<void> _startChosen(PlannedWorkout planned, DateTime date) async {
    if (_dayRolledOver) {
      TracendToast.show(
        context,
        'A new day has started. Check today’s workout, then start it.',
        icon: CupertinoIcons.calendar,
      );
      await _refresh();
      return;
    }
    final open = await _readOpenWorkouts();
    if (!mounted) return;
    // The same workout open on another day comes first, whatever else is
    // newer: it shares this start's draft, so starting would open it.
    final elsewhere = open.where(
      (o) => !(sameDay(o.date, date) && _isDraftOf(o, planned)),
    );
    final other =
        elsewhere.where((o) => _isDraftOf(o, planned)).firstOrNull ??
        elsewhere.firstOrNull;
    if (other != null) {
      final name = other.nameOr(_planWorkoutOf(other)?.name);
      final day = weekdayName(other.date).substring(0, 3);
      final sets = other.doneSets == 1 ? 'set' : 'sets';
      // The same workout on another day shares its draft on this phone, so it
      // can only be resumed.
      final sameWorkout = _isDraftOf(other, planned);
      final choice = await showTracendActionSheet<bool>(
        context,
        title: '$name ($day) has ${other.doneSets} $sets logged.',
        message: sameWorkout
            ? 'Resume it, or finish it first, before you start it again.'
            : null,
        actions: [
          const TracendSheetAction(
            label: 'Resume it',
            value: true,
            isDefault: true,
          ),
          if (!sameWorkout)
            const TracendSheetAction(
              label: 'Start this one anyway',
              value: false,
            ),
        ],
      );
      if (!mounted || choice == null) return;
      if (choice) {
        await _reopen(other);
        return;
      }
    }
    await _start(planned, date);
  }

  /// "I did it, log it for Fri 30 Oct" on a missed day: for a workout trained
  /// and not logged. It asks first, then the session is logged under that day.
  Future<void> _logMissed(PlannedWorkout planned, DateTime date) async {
    final day = weekdayName(date);
    final logged = await showTracendConfirm(
      context,
      title: 'Log ${planned.name} for $day ${dayMonth(date)}?',
      message:
          'For a workout you did that day and did not log. Your sets are '
          'saved on $day.',
      confirmLabel: 'Log for $day',
    );
    if (!logged || !mounted) return;
    await _startChosen(planned, date);
  }

  void _openExercise(PlannedWorkout workout, PlannedExercise exercise) =>
      showExerciseDetailSheet(
        context,
        workout: workout,
        exercise: exercise,
        repository: _source,
        progressionRule: _hub?.plan?.progressionRule,
      );

  /// Opens the summary of the day's session. A session of [workout] under any
  /// plan version opens through [workout]; a [session] of another workout, one
  /// the active plan has no copy of, opens through its own workout id and
  /// name, so the summary finds the session the day holds.
  void _viewSummary(
    PlannedWorkout workout,
    DateTime date, {
    TrainingSessionSummary? session,
  }) {
    final id = session?.workoutId;
    final own =
        session == null ||
        id == null ||
        id == workout.id ||
        session.currentWorkoutId == workout.id;
    showWorkoutSummarySheet(
      context,
      workout: own
          ? workout
          : PlannedWorkout(
              id: id,
              name: session.name,
              objective: '',
              estimatedMinutes: 0,
              exercises: const [],
            ),
      repository: _source,
      date: date,
    );
  }

  Future<void> _openOverview(
    PlannedWorkout workout,
    DateTime date, {
    required bool done,
    required bool canStart,
    TrainingSessionSummary? session,
  }) async {
    final action = await showWorkoutOverviewSheet(
      context,
      workout: workout,
      isCompleted: done,
      canStart: canStart,
      onExerciseTap: (exercise) => _openExercise(workout, exercise),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case WorkoutOverviewAction.start:
        await _startChosen(_planned(workout), date);
      case WorkoutOverviewAction.doToday:
        await _startChosen(_planned(workout), _today);
      case WorkoutOverviewAction.viewSummary:
        _viewSummary(workout, date, session: session);
    }
  }

  Future<void> _autoComplete(HealthkitCompletionCandidate candidate) async {
    final source = _source;
    if (source is! SupabaseWorkoutRepository) return;
    // A workout in progress on this phone is resumed, never completed from
    // Apple Health: that would record a second session beside it.
    final planned = _planWorkout(candidate.plannedWorkoutId);
    final open = await _readOpenWorkouts();
    if (!mounted) return;
    final inProgress = open.any(
      (o) =>
          sameDay(o.date, candidate.localDate) &&
          (planned == null
              ? o.workoutId == candidate.plannedWorkoutId
              : _isDraftOf(o, planned)),
    );
    if (inProgress) {
      setState(() => _open = open);
      TracendToast.show(
        context,
        'This workout is in progress on this phone. Resume it to finish it.',
        icon: CupertinoIcons.play_circle,
      );
      return;
    }
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
      logNonCritical(error, 'Train: Apple Health completion failed');
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
      logNonCritical(error, 'Train: workout repair failed');
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
      logNonCritical(error, 'Train: workout match response failed');
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
  Widget build(BuildContext context) {
    final listenables = <Listenable>[?widget.dayAdjustment, ?widget.guidance];
    return Material(
      type: MaterialType.transparency,
      // The shared adjustment answers on Today as well: the day's sets and
      // held weights follow it here at once. The guidance feeds the cardio row.
      child: listenables.isEmpty
          ? _buildPage(context)
          : ListenableBuilder(
              listenable: Listenable.merge(listenables),
              builder: (context, _) => _buildPage(context),
            ),
    );
  }

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
        if (hub.cachedAt != null || _hubError != null) ...[
          _OfflineNote(
            savedAt: hub.cachedAt,
            error: _hubError,
            now: _clock(),
            onRetry: _retryConnection,
          ),
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
    // "This week" is the current week, whichever week the strip shows.
    final currentWeek = [
      for (var i = 0; i < 7; i++) _currentWeek.add(Duration(days: i)),
    ];
    final doneThisWeek = currentWeek.where(hub.isDayCompleted).length;
    final open = _open;
    final assigned = hub.workouts.any((w) => w.weekday != null);
    // A day of a break has nothing due, so it does not count as planned.
    final plannedThisWeek = assigned
        ? currentWeek
              .where(
                (d) =>
                    hub.workoutForWeekday(d.weekday) != null &&
                    !hub.isDayPaused(d),
              )
              .length
        : hub.plan?.sessionsPerWeek ?? hub.workouts.length;
    final availability = hub.availability;
    final breakSet =
        availability.runningPause != null || availability.upcomingPause != null;
    final attention = _repairs.isNotEmpty || _reconciliations.isNotEmpty;
    final offline = hub.cachedAt != null;
    // The cardio week is the last seven days up to today: it belongs to this
    // week's summary only, never to a past week the athlete paged back to.
    // The guidance is the server's last answer: on a saved plan it may be
    // stale, and what it would open cannot be checked, so none of it shows.
    final cardio = !offline && sameDay(_weekStart, _currentWeek)
        ? widget.guidance?.current?.cardioWeek
        : null;
    return [
      if (open.isNotEmpty) ...[
        OpenWorkoutCard(
          workouts: open,
          now: _today,
          nameFor: (workout) => _planWorkoutOf(workout)?.name,
          onResume: (workout) => unawaited(_reopen(workout)),
        ),
        const SizedBox(height: TracendSpacing.sm),
      ],
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
            : hub.isDayPaused(date)
            ? DayBoxStatus.paused
            : hub.workoutForWeekday(date.weekday) != null
            ? DayBoxStatus.planned
            : DayBoxStatus.rest,
        workoutNameFor: (date) => hub.workoutForWeekday(date.weekday)?.name,
        onSelected: _select,
        onPreviousWeek: _canShift(-1) ? () => _shiftWeek(-1) : null,
        onNextWeek: _canShift(1) ? () => _shiftWeek(1) : null,
      ),
      const SizedBox(height: 14),
      // Recovery and the day's adjustment come from the server: a saved plan
      // has neither. What was last known about sore areas is said instead.
      if (offline && _safetyNotesRead) ...[
        _OfflineSafety(notes: _safetyNotes, now: _clock()),
        const SizedBox(height: TracendSpacing.sm),
      ],
      if (!offline) ...[
        _ReadinessSlot(
          readiness: _readiness,
          load: load,
          onOpenAccount: widget.onOpenAccount,
        ),
        const SizedBox(height: TracendSpacing.sm),
      ],
      if (!offline &&
          widget.dayAdjustment != null &&
          sameDay(_selected, _today))
        DayAdjustmentCard(
          controller: widget.dayAdjustment!,
          forDate: DayBoxesStrip.iso(_today),
          computed: sameDay(_readinessDay, _today) ? _computed : null,
          onCheckIn: widget.onCheckIn,
          onTalkToCoach: widget.onTalkToCoach ?? (_) {},
        ),
      if (!offline && widget.guidance != null && widget.proposals != null)
        DeloadCard(
          controller: widget.guidance!,
          proposals: widget.proposals!,
          onPlanChanged: widget.planChanges?.announce,
        ),
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
      if (!offline && availability.upcomingPause != null) ...[
        BreakCard(
          pause: availability.upcomingPause!,
          today: _today,
          busy: _pauseBusy,
          justSet: availability.upcomingPause!.id == _justSetPauseId,
          onEnd: () => _endBreak(availability.upcomingPause!),
        ),
        const SizedBox(height: TracendSpacing.sm),
      ],
      _DaySwitcher(
        dayKey: DayBoxesStrip.iso(_selected),
        forward: _forward,
        child: _dayContent(hub, offline: offline),
      ),
      if (!offline && !breakSet && sameDay(_selected, _today))
        TakeBreakButton(onPressed: _pauseBusy ? null : _takeBreak),
      const SectionLabel('This week'),
      WeekSummaryCard(
        done: doneThisWeek,
        planned: plannedThisWeek,
        loadLabel: load.rowLabel,
        onLoadTap: () => showTrainingLoadSheet(context, model: load),
        cardioLabel: cardio == null ? null : cardioRowValue(cardio),
        onCardioTap: cardio == null
            ? null
            : () => showCardioWeekSheet(context, week: cardio),
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

  Widget _dayContent(TrainingHubData hub, {required bool offline}) {
    final date = _selected;
    final today = _today;
    // A day of a break: nothing is due, never missed. The running break's card
    // offers End break early; an older break's day just says so.
    if (hub.isDayPaused(date) && !hub.isDayCompleted(date)) {
      final running = hub.availability.runningPause;
      final covers =
          running != null &&
          !date.isBefore(running.startDate) &&
          !date.isAfter(running.endDate);
      return covers
          ? BreakCard(
              pause: running,
              today: today,
              busy: _pauseBusy,
              justSet: running.id == _justSetPauseId,
              onEnd: offline ? null : () => _endBreak(running),
            )
          : BreakDayCard(date: date, today: today);
    }
    final planned = hub.workoutForWeekday(date.weekday);
    final workout = planned == null ? null : _forDay(planned, date);
    if (workout == null) {
      DateTime? nextDate;
      PlannedWorkout? next;
      for (
        var d = date.add(const Duration(days: 1));
        d.weekday != DateTime.monday;
        d = d.add(const Duration(days: 1))
      ) {
        final candidate = hub.workoutForWeekday(d.weekday);
        if (candidate != null &&
            !hub.isDayCompleted(d) &&
            !hub.isDayPaused(d)) {
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
    // A day that has not begun is previewed, never started: the server
    // refuses a start for it. A past day with nothing logged is missed: it is
    // done today, or logged for its day only through the quiet action. A day
    // with a workout left open on this phone resumes it.
    final upcoming = date.isAfter(today);
    final open = done ? null : _openOn(workout, date);
    final missed = !done && open == null && date.isBefore(today);
    final state = done
        ? HeroDayState.done
        : open != null
        ? HeroDayState.inProgress
        : upcoming
        ? HeroDayState.upcoming
        : missed
        ? HeroDayState.missed
        : HeroDayState.planned;
    TrainingSessionSummary? doneSession;
    TrainingSessionSummary? daySession;
    if (done) {
      // The session of this workout, under any plan version: the hub names
      // the active copy as currentWorkoutId. A day done as another workout
      // shows no session of its own (its minutes are not this workout's),
      // but View summary still opens that session.
      for (final session in hub.recentSessions) {
        if (!sameDay(session.date, date)) continue;
        daySession ??= session;
        if (session.workoutId == null ||
            session.workoutId == workout.id ||
            session.currentWorkoutId == workout.id) {
          doneSession = session;
          break;
        }
      }
    }
    final summarySession = doneSession ?? daySession;
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
          onOpenOverview: () => _openOverview(
            workout,
            date,
            done: done,
            canStart: !upcoming && !missed,
            session: summarySession,
          ),
          onStart: widget.dayAdjustment?.busy ?? false
              ? null
              : open != null
              ? () => _reopen(open)
              : () => _startChosen(_planned(workout), date),
          onViewSummary: () =>
              _viewSummary(workout, date, session: summarySession),
          onDoToday: upcoming || missed
              ? () => _startChosen(_planned(workout), _today)
              : null,
          onLogMissed: missed
              ? () => _logMissed(_planned(workout), date)
              : null,
          onOpenMuscles: () => showMusclesSheet(context, workout: workout),
          healthkitCandidate: candidate,
          healthkitBusy: _healthkitBusy,
          onHealthkitComplete: candidate == null || !canAutoComplete
              ? null
              : () => _autoComplete(candidate),
          onHealthkitManual: candidate == null
              ? null
              : () => _startChosen(
                  _planned(workout),
                  normalizedDate(candidate.localDate),
                ),
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

/// Sore areas on a saved plan: the safety route and the areas on hold as
/// Tracend last said them, or, with nothing saved, that holds cannot be
/// checked offline. Fixed wording from the rules; it names no condition.
class _OfflineSafety extends StatelessWidget {
  const _OfflineSafety({required this.notes, required this.now});

  final OfflineSafetyNotes? notes;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.tracendColors;
    final notes = this.notes;
    final route = notes?.safetyRoute;
    final words = route == null ? null : safetyWords(route);
    final saved = notes == null ? null : DateTime.tryParse(notes.localDate);
    final empty = notes == null || notes.isEmpty;
    return TracendCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (words != null) ...[
            Text(words.title, style: text.titleSmall),
            const SizedBox(height: TracendSpacing.xxs),
            Text(words.body, style: text.bodyMedium),
            const SizedBox(height: TracendSpacing.xs),
          ],
          for (final line in notes?.lines ?? const <String>[])
            Padding(
              padding: const EdgeInsets.only(bottom: TracendSpacing.xxs),
              child: Text(line, style: text.bodyMedium),
            ),
          if (empty)
            Text(offlinePainHoldsUnknown, style: text.bodyMedium)
          else
            Text(
              saved == null
                  ? offlinePainHoldsUnknown
                  : 'From your last check on ${shortDate(saved, now: now)}. '
                        "A new pain report can't be checked offline. Skip any "
                        'area on hold.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// Said above the plan when it is not fresh: the server could not be reached.
/// A copy this phone saved says from when; a plan already on screen that
/// could not be reloaded says "from earlier".
class _OfflineNote extends StatelessWidget {
  const _OfflineNote({
    required this.savedAt,
    required this.error,
    required this.now,
    required this.onRetry,
  });

  /// When the phone saved the plan on screen; null for a plan loaded in this
  /// run that could not be reloaded.
  final DateTime? savedAt;
  final Object? error;
  final DateTime now;
  final Future<void> Function() onRetry;

  /// A saved plan older than this says how old it is.
  static const _oldAfterDays = 14;

  static String label(DateTime? savedAt, DateTime now) {
    if (savedAt == null) return 'Offline. Showing your plan from earlier.';
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(savedAt.year, savedAt.month, savedAt.day)).inDays;
    final from =
        'Offline. Showing your saved plan from '
        '${shortDate(savedAt, now: now)}';
    return days >= _oldAfterDays
        ? '$from, $days days ago. It may have changed.'
        : '$from.';
  }

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: TracendSpacing.xs,
          children: [
            StatusChip(
              label: label(savedAt, now),
              icon: CupertinoIcons.wifi_slash,
              tone: StatusTone.caution,
            ),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: TracendSpacing.xxs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: BetaDiagnostic(error),
          ),
        ],
      ],
    );
  }
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
