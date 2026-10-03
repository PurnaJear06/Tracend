import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/train/exercise_history.dart';
import 'package:tracend/features/train/rest_timer.dart';
import 'package:tracend/features/train/widgets/focus_exercise_page.dart';
import 'package:tracend/features/train/widgets/rest_timer_view.dart';
import 'package:tracend/features/train/widgets/rpe_picker.dart';
import 'package:tracend/features/train/widgets/workout_finish_sheet.dart';
import 'package:tracend/features/train/widgets/workout_summary_sheet.dart';
import 'package:tracend/features/train/workout_draft.dart';
import 'package:tracend/features/train/workout_logic.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_skeleton.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// Logs a workout in focus mode: one exercise per page, a rest timer that
/// takes over between sets and shrinks to a pill, and a finish that asks how
/// hard the whole workout was before saving it (UX_FLOWS.md §6).
class ActiveWorkoutScreen extends StatefulWidget {
  const ActiveWorkoutScreen({
    required this.workout,
    required this.repository,
    this.sessionDate,
    this.restAlerts = const MethodChannelRestAlertScheduler(),
    this.notifications = const MethodChannelNotificationRepository(),
    this.clock = DateTime.now,
    super.key,
  });

  final PlannedWorkout workout;
  final WorkoutRepository repository;
  final DateTime? sessionDate;

  /// The lock-screen alert at the end of a rest. It is only scheduled when
  /// the athlete turned "Rest timer alerts" on in [notifications].
  final RestAlertScheduler restAlerts;
  final NotificationRepository notifications;

  /// The time source for the elapsed time and the rest timer.
  final DateTime Function() clock;

  /// The longest workout the server records (3 hours).
  static const maxSessionSeconds = 10800;

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

enum _Sync { saving, saved, offline, attention }

enum _Leave { save, discard }

typedef _Next = ({String full, String short});

/// Schedules the lock-screen alert only while the athlete's toggle is on;
/// cancelling always goes through, so no alert outlives its rest.
class _GatedRestAlerts implements RestAlertScheduler {
  _GatedRestAlerts(this._inner);

  final RestAlertScheduler _inner;
  bool enabled = false;

  @override
  Future<bool> scheduleRestAlert(int seconds) async =>
      enabled && await _inner.scheduleRestAlert(seconds);

  @override
  Future<void> cancelRestAlert() => _inner.cancelRestAlert();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen> {
  late final List<ExerciseDraft> _exercises = [
    for (final exercise in widget.workout.exercises) ExerciseDraft(exercise),
  ];
  late final _GatedRestAlerts _alerts = _GatedRestAlerts(widget.restAlerts);
  late final RestTimerController _rest = RestTimerController(
    alerts: _alerts,
    clock: widget.clock,
  );
  final PageController _pages = PageController();

  String? _sessionId;
  String _idempotencyKey = newIdempotencyKey();
  int _revision = 0;
  late DateTime _startedAt = widget.clock();
  bool _ready = false;
  _Sync _sync = _Sync.saving;

  /// The workout is finished or discarded: nothing is saved any more.
  bool _closed = false;

  bool _viewingCompleted = false;
  bool _completedFromHealth = false;
  int? _completedDuration;

  ExerciseHistoryResult? _history;
  HistoryStatus _historyStatus = HistoryStatus.loading;

  /// The rest shows full screen; false when it is shrunk to the pill.
  bool _restExpanded = true;

  /// What follows the rest, in full for the ring and the toast, and short
  /// for the pill.
  _Next? _restNext;

  /// The set the running rest follows, for its effort picker.
  (int, int)? _restAfter;
  bool _restEffortDismissed = false;

  int _momentToken = 0;
  int? _momentExercise;
  NewBestMoment? _moment;

  PendingWorkoutFinish? _pendingFinish;
  bool _finishing = false;
  String? _finishError;
  String? _finishDiagnostic;

  Timer? _saveTimer;
  Timer? _ticker;

  /// The elapsed seconds and rest seconds on screen at the last tick.
  (int, int?)? _shownSeconds;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _ticker?.cancel();
    _pages.dispose();
    super.dispose();
  }

  // Restore and start ---------------------------------------------------------

  Future<void> _restore() async {
    unawaited(_loadAlertPreference());
    Map<String, dynamic>? server;
    try {
      server = await widget.repository.loadSession(
        widget.workout,
        localDate: widget.sessionDate,
      );
    } catch (e) {
      debugPrint('Non-critical error: workout session not loaded: $e');
      _sync = _Sync.offline;
    }
    if (server != null && server['state'] == 'completed') {
      _sessionId = server['session_id'] as String?;
      _viewingCompleted = true;
      _completedFromHealth = server['completion_source'] == 'healthkit';
      _completedDuration = (server['duration_seconds'] as num?)?.toInt();
      _hydrate(server['exercises']);
      _ready = true;
      if (mounted) setState(() {});
      unawaited(_loadHistory());
      return;
    }
    final saved = await widget.repository.loadDraft(widget.workout.id);
    final local = saved == null ? null : _decode(saved);
    final draft = _newer(server, local);
    if (draft != null) {
      _sessionId = draft['session_id'] as String?;
      _idempotencyKey = draft['idempotency_key'] as String? ?? _idempotencyKey;
      _revision = (draft['revision'] as num?)?.toInt() ?? 0;
      _startedAt =
          DateTime.tryParse('${draft['actual_started_at'] ?? ''}')?.toLocal() ??
          _startedAt;
      _hydrate(draft['exercises']);
      if (local != null && local['session_id'] == _sessionId) {
        _restoreClearedLoads(local[_clearedLoadsKey]);
      }
    }
    await _rest.restore(local?[RestTimer.draftKey]);
    if (_rest.timer != null) {
      _restExpanded = false;
      _restNext = _nextAfterCurrent();
    }
    _pendingFinish = await widget.repository.loadPendingFinish(
      widget.workout.id,
    );
    _ready = true;
    final first = _firstOpenExercise();
    if (mounted) setState(() {});
    if (first > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pages.hasClients) _pages.jumpToPage(first);
      });
    }
    unawaited(_loadHistory());
    try {
      _sessionId ??= await widget.repository.start(
        widget.workout,
        _idempotencyKey,
        localDate: widget.sessionDate,
      );
    } catch (e) {
      debugPrint('Non-critical error: workout start waits: $e');
      _sessionId ??= 'pending-$_idempotencyKey';
      _sync = _Sync.offline;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    await _save();
  }

  static Map<String, dynamic>? _decode(String saved) {
    try {
      return decodeDraft(saved);
    } on FormatException {
      return null;
    }
  }

  /// The server's copy of an in-progress workout, unless this phone holds
  /// newer edits of the same session that have not synced yet.
  static Map<String, dynamic>? _newer(
    Map<String, dynamic>? server,
    Map<String, dynamic>? local,
  ) {
    final live = server != null && server['state'] == 'in_progress'
        ? server
        : null;
    if (live == null) return local;
    if (local == null || local['session_id'] != live['session_id']) {
      return live;
    }
    final localRevision = (local['revision'] as num?)?.toInt() ?? 0;
    final serverRevision = (live['revision'] as num?)?.toInt() ?? 0;
    return localRevision > serverRevision
        ? {...local, 'actual_started_at': live['actual_started_at']}
        : live;
  }

  void _hydrate(Object? exercises) {
    if (exercises is! List) return;
    for (final row in exercises) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      final order = (map['order'] as num?)?.toInt();
      final index = _exercises.indexWhere((e) => e.exercise.order == order);
      if (index >= 0) _exercises[index].restore(map);
    }
  }

  /// Sets whose load the athlete emptied on purpose, kept only in this
  /// phone's draft (the server stores just an empty load), so a restored
  /// workout never suggests a weight there again.
  static const _clearedLoadsKey = 'cleared_loads';

  List<Map<String, int>> _clearedLoads() => [
    for (final draft in _exercises)
      for (var j = 0; j < draft.sets.length; j++)
        if (draft.sets[j].loadEdited && draft.sets[j].load.isEmpty)
          {'order': draft.exercise.order, 'number': j + 1},
  ];

  void _restoreClearedLoads(Object? rows) {
    if (rows is! List) return;
    for (final row in rows) {
      if (row is! Map) continue;
      final order = (row['order'] as num?)?.toInt();
      final number = (row['number'] as num?)?.toInt();
      final index = _exercises.indexWhere((e) => e.exercise.order == order);
      if (index < 0 || number == null) continue;
      final sets = _exercises[index].sets;
      if (number < 1 || number > sets.length) continue;
      final set = sets[number - 1];
      if (set.load.isEmpty) set.loadEdited = true;
    }
  }

  Future<void> _loadAlertPreference() async {
    try {
      final preferences = await widget.notifications.load();
      _alerts.enabled =
          preferences.restTimerAlertsEnabled && preferences.isAuthorized;
    } catch (e) {
      debugPrint('Non-critical error: rest alerts stay in the app: $e');
      _alerts.enabled = false;
    }
  }

  Future<void> _loadHistory() async {
    try {
      final result = await widget.repository.loadExerciseHistory([
        for (final exercise in widget.workout.exercises) exercise.historyKey,
      ]);
      if (!mounted) return;
      setState(() {
        _history = result;
        _historyStatus = HistoryStatus.ready;
      });
    } catch (e) {
      debugPrint('Non-critical error: exercise history not loaded: $e');
      if (mounted) setState(() => _historyStatus = HistoryStatus.unavailable);
    }
  }

  ExerciseHistory? _historyOf(int exercise) =>
      _history?[_exercises[exercise].exercise.historyKey];

  int _firstOpenExercise() {
    final index = _exercises.indexWhere(
      (e) => !e.skipped && e.currentSetIndex != null,
    );
    return index < 0 ? 0 : index;
  }

  // Time -----------------------------------------------------------------------

  int get _elapsedSeconds {
    final seconds = widget.clock().difference(_startedAt).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  bool get _overCap => _elapsedSeconds >= ActiveWorkoutScreen.maxSessionSeconds;

  /// Redraws only when a shown second changes: the elapsed time or the
  /// rest left.
  void _tick() {
    if (!mounted || _closed) return;
    final now = widget.clock();
    final timer = _rest.timer;
    if (timer != null && timer.isExpired(now)) {
      unawaited(_restEnded());
    }
    final shown = (_elapsedSeconds, _rest.timer?.remainingSeconds(now));
    if (shown == _shownSeconds) return;
    setState(() => _shownSeconds = shown);
  }

  static String _clockText(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:$rest'
        : '$minutes:$rest';
  }

  static String _spokenClock(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return [
      if (hours > 0) '$hours ${hours == 1 ? 'hour' : 'hours'}',
      '$minutes ${minutes == 1 ? 'minute' : 'minutes'}',
    ].join(' ');
  }

  // Draft and sync -------------------------------------------------------------

  Map<String, dynamic> _draft() => {
    'workout_id': widget.workout.id,
    'session_id': _sessionId,
    'idempotency_key': _idempotencyKey,
    'revision': _revision,
    'exercises': [
      for (final draft in _exercises)
        {
          'order': draft.exercise.order,
          'status': draft.status,
          'pain_flag': draft.pain,
          'rest_seconds': draft.exercise.restSeconds,
          'sets': [
            for (var j = 0; j < draft.sets.length; j++)
              {'number': j + 1, ...draft.sets[j].toMap()},
          ],
        },
    ],
  };

  /// The draft kept on this phone: the synced draft plus the start time and
  /// the running rest, which only the device needs.
  Map<String, dynamic> _localDraft() => {
    ..._draft(),
    'actual_started_at': _startedAt.toUtc().toIso8601String(),
    RestTimer.draftKey: ?_rest.toDraft(),
    _clearedLoadsKey: _clearedLoads(),
  };

  void _changed() {
    _revision++;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), _save);
    setState(() {});
  }

  Future<void> _save() async {
    if (_closed || _viewingCompleted) return;
    await widget.repository.saveDraft(
      widget.workout.id,
      jsonEncode(_localDraft()),
    );
    var id = _sessionId;
    if (id == null) return;
    if (id.startsWith('pending-')) {
      try {
        id = await widget.repository.start(
          widget.workout,
          _idempotencyKey,
          localDate: widget.sessionDate,
        );
        _sessionId = id;
      } catch (e) {
        debugPrint('Non-critical error: workout start still waits: $e');
        if (mounted) setState(() => _sync = _Sync.offline);
        return;
      }
    }
    if (mounted) setState(() => _sync = _Sync.saving);
    _Sync result;
    try {
      await widget.repository.sync(id, _revision, _draft());
      result = _Sync.saved;
    } on PostgrestException catch (e) {
      debugPrint('Non-critical error: workout sync refused: ${e.code}');
      result = _Sync.attention;
    } catch (e) {
      debugPrint('Non-critical error: workout sync waits: $e');
      result = _Sync.offline;
    }
    if (mounted) setState(() => _sync = result);
  }

  // Sets ------------------------------------------------------------------------

  void _doneSet(int exercise, String load, String reps) {
    final draft = _exercises[exercise];
    final index = draft.currentSetIndex;
    if (index == null) return;
    draft.sets[index]
      ..load = load
      ..reps = reps
      ..completed = true;
    if (draft.skipped) draft.status = 'unknown';
    if (draft.newBests(_historyOf(exercise)).contains(index)) {
      TracendHaptics.medium();
      _momentToken++;
      _momentExercise = exercise;
      _moment = NewBestMoment(set: index, token: _momentToken);
    } else {
      TracendHaptics.light();
    }
    final next = _nextLabel(exercise);
    if (next != null && draft.exercise.restSeconds > 0) {
      _restNext = next;
      _restAfter = (exercise, index);
      _restEffortDismissed = false;
      _restExpanded = true;
      unawaited(
        _rest.start(draft.exercise.restSeconds).then((_) => _persistRest()),
      );
    }
    _changed();
  }

  void _undoSet(int exercise, int set) {
    _exercises[exercise].sets[set]
      ..completed = false
      ..rpe = '';
    if (_momentExercise == exercise && _moment?.set == set) {
      _moment = null;
      _momentExercise = null;
    }
    if (_restAfter == (exercise, set)) _restAfter = null;
    _changed();
  }

  void _setRpe(int exercise, int set, int? rpe) {
    _exercises[exercise].sets[set].rpe = rpe == null ? '' : '$rpe';
    _changed();
  }

  int _fillRpe(int exercise, int rpe) {
    var filled = 0;
    for (final set in _exercises[exercise].sets) {
      if (set.completed && set.rpe.isEmpty) {
        set.rpe = '$rpe';
        filled++;
      }
    }
    if (filled > 0) _changed();
    return filled;
  }

  void _editCurrent(int exercise, {String? load, String? reps}) {
    final draft = _exercises[exercise];
    final index = draft.currentSetIndex;
    if (index == null) return;
    final set = draft.sets[index];
    if (load != null) {
      set
        ..load = load
        ..loadEdited = true;
    }
    if (reps != null) set.reps = reps;
    _changed();
  }

  Future<void> _more(int exercise) async {
    final draft = _exercises[exercise];
    final skip = await showTracendActionSheet<bool>(
      context,
      title: draft.exercise.name,
      message: draft.skipped
          ? 'This exercise is marked as skipped.'
          : 'Skipped exercises are saved as skipped, not as done.',
      actions: [
        TracendSheetAction(
          label: draft.skipped ? 'Unmark skipped' : 'Mark as skipped',
          value: !draft.skipped,
        ),
      ],
      cancelLabel: 'Keep logging',
    );
    if (skip == null || !mounted) return;
    draft.status = skip ? 'skipped' : 'unknown';
    _changed();
  }

  /// What comes after the current set of [exercise]: its next set, else the
  /// next exercise with sets to do; null when the workout has nothing left.
  _Next? _nextLabel(int exercise) {
    final draft = _exercises[exercise];
    final set = draft.currentSetIndex;
    if (set != null) {
      return (
        full: 'Set ${set + 1} of ${draft.exercise.name}',
        short: 'Set ${set + 1}',
      );
    }
    for (var i = 1; i < _exercises.length; i++) {
      final other = _exercises[(exercise + i) % _exercises.length];
      if (!other.skipped && other.currentSetIndex != null) {
        return (full: other.exercise.name, short: other.exercise.name);
      }
    }
    return null;
  }

  /// The next set to do in the workout, for a rest restored after a
  /// relaunch.
  _Next? _nextAfterCurrent() {
    for (final draft in _exercises) {
      final set = draft.currentSetIndex;
      if (!draft.skipped && set != null) {
        return set == 0
            ? (full: draft.exercise.name, short: draft.exercise.name)
            : (
                full: 'Set ${set + 1} of ${draft.exercise.name}',
                short: 'Set ${set + 1}',
              );
      }
    }
    return null;
  }

  // Rest -----------------------------------------------------------------------

  Future<void> _persistRest() async {
    if (!mounted || _closed) return;
    setState(() {});
    await widget.repository.saveDraft(
      widget.workout.id,
      jsonEncode(_localDraft()),
    );
  }

  Future<void> _adjustRest(Duration delta) async {
    await _rest.adjust(delta);
    await _persistRest();
  }

  Future<void> _skipRest() async {
    await _rest.skip();
    await _persistRest();
  }

  Future<void> _restEnded() async {
    if (_rest.timer == null) return;
    await _rest.stop();
    if (!mounted) return;
    unawaited(TracendHaptics.success());
    TracendToast.show(
      context,
      _restNext == null
          ? 'Rest is over'
          : 'Rest is over. Next: ${_restNext!.full}',
      icon: CupertinoIcons.timer,
    );
    await _persistRest();
  }

  // Leave, discard, finish -----------------------------------------------------

  int get _completedSets =>
      _exercises.fold(0, (total, e) => total + e.completedCount);
  int get _totalSets => _exercises.fold(0, (total, e) => total + e.sets.length);

  Future<void> _confirmLeave() async {
    if (_viewingCompleted || _closed) {
      Navigator.of(context).pop();
      return;
    }
    final done = _completedSets;
    final choice = await showTracendActionSheet<_Leave>(
      context,
      title: 'Leave this workout?',
      message: done == 0
          ? 'Nothing is logged yet. You can start again later today.'
          : '$done ${done == 1 ? 'set is' : 'sets are'} saved on your phone. '
                'You can carry on later today.',
      actions: const [
        TracendSheetAction(
          label: 'Save and leave',
          value: _Leave.save,
          isDefault: true,
        ),
        TracendSheetAction(
          label: 'Discard workout',
          value: _Leave.discard,
          destructive: true,
        ),
      ],
      cancelLabel: 'Keep logging',
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _Leave.save:
        await _saveAndLeave();
      case _Leave.discard:
        await _discard();
    }
  }

  Future<void> _saveAndLeave() async {
    await _rest.stop();
    _saveTimer?.cancel();
    await _save();
    if (!mounted) return;
    _closed = true;
    // The toast lives in the root overlay, so it outlasts this screen.
    TracendToast.show(
      context,
      'Workout paused',
      icon: CupertinoIcons.pause_fill,
    );
    Navigator.of(context).pop(false);
  }

  Future<void> _discard() async {
    final confirmed = await showTracendConfirm(
      context,
      title: 'Discard this workout?',
      message: 'The sets you logged today are deleted. This cannot be undone.',
      confirmLabel: 'Discard workout',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    _saveTimer?.cancel();
    _closed = true;
    await _rest.stop();
    try {
      await widget.repository.abandon(
        _sessionId ?? 'pending-$_idempotencyKey',
        workoutId: widget.workout.id,
      );
    } catch (e) {
      debugPrint('Non-critical error: discard refused: $e');
      _closed = false;
      await _save();
      if (mounted) {
        unawaited(TracendHaptics.warning());
        TracendToast.show(
          context,
          'The workout could not be discarded. Try again.',
          icon: CupertinoIcons.exclamationmark_triangle,
        );
      }
      return;
    }
    if (!mounted) return;
    TracendToast.show(context, 'Workout discarded', icon: CupertinoIcons.trash);
    Navigator.of(context).pop(false);
  }

  Future<void> _finish() async {
    if (_viewingCompleted) {
      Navigator.of(context).pop();
      return;
    }
    if (_finishing) return;
    if (_completedSets == 0) {
      unawaited(TracendHaptics.warning());
      TracendToast.show(
        context,
        'Tick at least one set first.',
        icon: CupertinoIcons.info_circle,
      );
      return;
    }
    final effort = await showWorkoutFinishSheet(
      context,
      workoutName: widget.workout.name,
      unloggedSets: _totalSets - _completedSets,
    );
    if (effort == null || !mounted) return;
    final seconds = _elapsedSeconds;
    await _finishWith(
      effort,
      seconds > ActiveWorkoutScreen.maxSessionSeconds
          ? ActiveWorkoutScreen.maxSessionSeconds
          : seconds,
    );
  }

  Future<void> _finishWith(int effort, int durationSeconds) async {
    setState(() {
      _finishing = true;
      _finishError = null;
      _finishDiagnostic = null;
    });
    await _rest.stop();
    _saveTimer?.cancel();
    await _save();
    try {
      await widget.repository.completeWithEffort(
        _sessionId ?? 'pending-$_idempotencyKey',
        _revision,
        durationSeconds,
        _draft(),
        sessionEffort: effort,
      );
    } catch (e) {
      debugPrint('Non-critical error: workout finish waits: $e');
      if (!mounted) return;
      setState(() {
        _finishing = false;
        _pendingFinish = PendingWorkoutFinish(
          sessionEffort: effort,
          durationSeconds: durationSeconds,
        );
        if (e is PostgrestException) {
          _finishError = 'Tracend could not finish this workout. Try again.';
          _finishDiagnostic = e.message;
        } else {
          _finishError =
              'Finishing needs a connection. Your sets and effort are saved '
              'on this phone.';
        }
      });
      unawaited(TracendHaptics.warning());
      return;
    }
    _closed = true;
    if (!mounted) return;
    setState(() {
      _finishing = false;
      _pendingFinish = null;
    });
    unawaited(TracendHaptics.success());
    await showWorkoutSummarySheet(context, _summary(effort, durationSeconds));
    if (!mounted) return;
    TracendToast.show(context, 'Workout saved');
    Navigator.of(context).pop(true);
  }

  WorkoutSummary _summary(int effort, int durationSeconds) {
    final bests = <WorkoutNewBest>[];
    for (var i = 0; i < _exercises.length; i++) {
      final draft = _exercises[i];
      final history = _historyOf(i);
      final indexes = draft.newBests(history);
      if (indexes.isEmpty) continue;
      // Each new best beats the one before it, so the last is the strongest.
      final top = draft.sets[indexes.reduce((a, b) => a > b ? a : b)];
      bests.add(
        WorkoutNewBest(
          exercise: draft.exercise.name,
          lifted: describeSet(
            loadKg: top.loadKg,
            repetitions: top.repetitions,
            assisted: draft.assisted,
          ),
          previous: describeBest(history?.bestSet),
        ),
      );
    }
    return WorkoutSummary(
      workoutName: widget.workout.name,
      date: widget.sessionDate ?? widget.clock(),
      durationSeconds: durationSeconds,
      completedSets: _completedSets,
      weightLiftedKg: weightLiftedKg([
        for (final draft in _exercises) draft.loggedExercise,
      ]),
      effort: effort,
      newBests: bests,
    );
  }

  // Build ----------------------------------------------------------------------

  void _goToPage(int page) {
    if (!_pages.hasClients) return;
    final duration = TracendMotionScope.movement(
      context,
      TracendMotion.emphasized,
    );
    if (duration == Duration.zero) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: duration,
        curve: TracendMotion.curve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return PopScope<bool>(
      canPop: _viewingCompleted || _closed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: colors.canvas,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _header(context),
              Expanded(child: _body(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final elapsed = _elapsedSeconds;
    final String detail;
    final String detailSpoken;
    if (_viewingCompleted) {
      final duration = _completedDuration;
      detail = duration == null
          ? 'Completed'
          : 'Completed · ${(duration / 60).round()} min';
      detailSpoken = detail;
    } else {
      detail = _ready ? _clockText(elapsed) : '0:00';
      detailSpoken = 'Elapsed ${_spokenClock(elapsed)}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.sm,
        TracendSpacing.xs,
        TracendSpacing.md,
        0,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Pressable(
                onTap: _confirmLeave,
                semanticLabel: _viewingCompleted ? 'Close' : 'Leave workout',
                borderRadius: BorderRadius.circular(TracendRadii.pill),
                child: SizedBox.square(
                  dimension: 44,
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    size: 22,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: TracendSpacing.xs),
              Expanded(
                child: Column(
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        widget.workout.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: text.labelSmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Semantics(
                      label: detailSpoken,
                      excludeSemantics: true,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          detail,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: _viewingCompleted
                              ? text.titleMedium
                              : TracendTheme.numeric(
                                  colors,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: _overCap
                                      ? colors.accentAmber
                                      : colors.textPrimary,
                                ).copyWith(height: 1.1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: TracendSpacing.xs),
              _finishPill(context),
            ],
          ),
          const SizedBox(height: TracendSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(left: TracendSpacing.xxs),
            child: Row(
              children: [
                Expanded(child: _progress(context)),
                if (!_viewingCompleted) ...[
                  const SizedBox(width: TracendSpacing.sm),
                  _syncStatus(context),
                ],
              ],
            ),
          ),
          const SizedBox(height: TracendSpacing.xs),
        ],
      ),
    );
  }

  Widget _finishPill(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final label = _viewingCompleted
        ? 'Done'
        : _finishing
        ? 'Saving'
        : 'Finish';
    return Pressable(
      onTap: _ready && !_finishing ? _finish : null,
      semanticLabel: _viewingCompleted
          ? 'Done'
          : _finishing
          ? 'Saving workout'
          : 'Finish workout',
      borderRadius: BorderRadius.circular(TracendRadii.pill),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.accentSignal,
            borderRadius: BorderRadius.circular(TracendRadii.pill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TracendSpacing.md,
              vertical: 10,
            ),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: text.labelLarge?.copyWith(color: colors.onAccentSignal),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _progress(BuildContext context) {
    final colors = context.tracendColors;
    final total = _totalSets;
    final done = _completedSets;
    // Segments fill in order: the bar counts sets, not which set is which.
    return Semantics(
      label: '$done of $total sets done',
      excludeSemantics: true,
      child: SizedBox(
        height: 4,
        child: Row(
          children: [
            for (var i = 0; i < total; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: AnimatedContainer(
                  duration: TracendMotionScope.fade(
                    context,
                    TracendMotion.standard,
                  ),
                  decoration: BoxDecoration(
                    color: i < done ? colors.stateStable : colors.surfaceRaised,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _syncStatus(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final (String word, IconData icon, Color color) = switch (_sync) {
      _Sync.saving => (
        'Syncing',
        CupertinoIcons.arrow_2_circlepath,
        colors.textSecondary,
      ),
      _Sync.saved => (
        'Saved',
        CupertinoIcons.checkmark_alt_circle_fill,
        colors.stateStable,
      ),
      _Sync.offline => (
        'Offline',
        CupertinoIcons.wifi_slash,
        colors.accentAmber,
      ),
      _Sync.attention => (
        'Needs attention',
        CupertinoIcons.exclamationmark_triangle_fill,
        colors.stateAttention,
      ),
    };
    final spoken = switch (_sync) {
      _Sync.saving => 'Saving changes',
      _Sync.saved => 'Saved and synced',
      _Sync.offline => 'Offline. Saved on this phone',
      _Sync.attention => 'Sync needs attention. Saved on this phone',
    };
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(word, style: text.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (!_ready) {
      return Semantics(
        label: 'Loading workout',
        child: const Padding(
          padding: EdgeInsets.all(TracendSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TracendSkeleton.line(widthFactor: 0.3),
              SizedBox(height: TracendSpacing.sm),
              TracendSkeleton.line(widthFactor: 0.7, height: 30),
              SizedBox(height: TracendSpacing.lg),
              TracendSkeleton.block(height: 260),
            ],
          ),
        ),
      );
    }
    final timer = _rest.timer;
    final now = widget.clock();
    final media = MediaQuery.of(context);
    final level = TracendMotionScope.of(context);
    return Stack(
      children: [
        Column(
          children: [
            ..._banners(context),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _exercises.length,
                onPageChanged: (_) => TracendHaptics.selection(),
                itemBuilder: (context, i) => _exercisePage(i),
              ),
            ),
          ],
        ),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: TracendMotionScope.fade(
              context,
              TracendMotion.emphasized,
            ),
            reverseDuration: TracendMotionScope.fade(
              context,
              TracendMotion.standard,
            ),
            transitionBuilder: (child, animation) =>
                level == TracendMotionLevel.full
                ? SlideTransition(
                    position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                        .animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: TracendMotion.curve,
                          ),
                        ),
                    child: child,
                  )
                : FadeTransition(opacity: animation, child: child),
            child: timer != null && _restExpanded
                ? RestTimerOverlay(
                    key: const ValueKey('rest-full'),
                    remainingSeconds: timer.remainingSeconds(now),
                    remainingShare: 1 - timer.progress(now),
                    nextLabel: _restNext?.full ?? '',
                    onMinus: () => _adjustRest(-RestTimer.step),
                    onPlus: () => _adjustRest(RestTimer.step),
                    onSkip: _skipRest,
                    onHide: () => setState(() => _restExpanded = false),
                    effort: _restEffort(),
                  )
                : const SizedBox.shrink(key: ValueKey('rest-none')),
          ),
        ),
        Positioned(
          left: TracendSpacing.sm,
          right: TracendSpacing.sm,
          bottom: media.padding.bottom + TracendSpacing.sm,
          child: AnimatedSwitcher(
            duration: TracendMotionScope.fade(context, TracendMotion.standard),
            transitionBuilder: (child, animation) =>
                level == TracendMotionLevel.full
                ? SlideTransition(
                    position:
                        Tween(
                          begin: const Offset(0, 1.4),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: TracendMotion.settle,
                          ),
                        ),
                    child: FadeTransition(opacity: animation, child: child),
                  )
                : FadeTransition(opacity: animation, child: child),
            child: timer != null && !_restExpanded
                ? RestTimerPill(
                    key: const ValueKey('rest-pill'),
                    remainingSeconds: timer.remainingSeconds(now),
                    remainingShare: 1 - timer.progress(now),
                    nextLabel: _restNext?.short ?? '',
                    onMinus: () => _adjustRest(-RestTimer.step),
                    onPlus: () => _adjustRest(RestTimer.step),
                    onSkip: _skipRest,
                    onExpand: () => setState(() => _restExpanded = true),
                  )
                : const SizedBox.shrink(key: ValueKey('rest-pill-none')),
          ),
        ),
      ],
    );
  }

  Widget? _restEffort() {
    final after = _restAfter;
    if (after == null || _restEffortDismissed) return null;
    final (exercise, set) = after;
    final row = _exercises[exercise].sets[set];
    if (!row.completed) return null;
    return RpePicker(
      title: 'Effort for set ${set + 1}',
      value: row.rpeValue,
      onSelected: (value) => _setRpe(exercise, set, value),
      onClear: () => _setRpe(exercise, set, null),
      dismissLabel: 'Not now',
      onDismiss: () => setState(() => _restEffortDismissed = true),
    );
  }

  Widget _exercisePage(int i) {
    final draft = _exercises[i];
    final history = _historyOf(i);
    final next = i + 1 < _exercises.length
        ? _exercises[i + 1].exercise.name
        : null;
    return FocusExercisePage(
      key: ValueKey('exercise-$i'),
      index: i,
      count: _exercises.length,
      draft: draft,
      history: history,
      historyStatus: _historyStatus,
      newBests: draft.newBests(history),
      readOnly: _viewingCompleted,
      nextExerciseName: next,
      onNext: next == null ? null : () => _goToPage(i + 1),
      moment: _momentExercise == i ? _moment : null,
      onDone: (load, reps) => _doneSet(i, load, reps),
      onLoadChanged: (value) => _editCurrent(i, load: value),
      onRepsChanged: (value) => _editCurrent(i, reps: value),
      onUndo: (set) => _undoSet(i, set),
      onRpe: (set, rpe) => _setRpe(i, set, rpe),
      onFillRpe: (rpe) => _fillRpe(i, rpe),
      onPain: () {
        _exercises[i].pain = !_exercises[i].pain;
        _changed();
      },
      onMore: () => _more(i),
    );
  }

  List<Widget> _banners(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    Widget banner(List<Widget> children) => Padding(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.gutter,
        TracendSpacing.xs,
        TracendSpacing.gutter,
        0,
      ),
      child: TracendCard(
        raised: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
    final pending = _pendingFinish;
    return [
      if (_viewingCompleted && _completedFromHealth)
        banner([
          const StatusChip(
            label: 'Marked complete from Apple Health',
            icon: CupertinoIcons.heart_fill,
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            'No sets were logged. The planned exercises are shown for '
            'reference.',
            style: text.bodyMedium,
          ),
        ]),
      if (!_viewingCompleted && pending != null && !_finishing)
        banner([
          const StatusChip(
            label: 'Finish not sent yet',
            icon: CupertinoIcons.wifi_slash,
            tone: StatusTone.caution,
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            _finishError ??
                'You finished this workout, but it has not reached Tracend '
                    'yet. Your sets and effort are saved on this phone.',
            style: text.bodyMedium,
          ),
          if (_finishDiagnostic != null) ...[
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              _finishDiagnostic!,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: TracendSpacing.sm),
          FilledButton(
            onPressed: () =>
                _finishWith(pending.sessionEffort, pending.durationSeconds),
            child: const Text('Send finish'),
          ),
        ]),
      if (!_viewingCompleted && _overCap)
        banner([
          const StatusChip(
            label: 'Over 3 hours',
            icon: CupertinoIcons.exclamationmark_triangle_fill,
            tone: StatusTone.caution,
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            'This workout will save as 3 hours. Finish it to keep your sets.',
            style: text.bodyMedium,
          ),
        ]),
    ];
  }
}
