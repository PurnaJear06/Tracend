import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, Supabase;
import 'package:tracend/app/breadcrumbs.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/train/exercise_history.dart';
import 'package:tracend/features/train/rest_timer.dart';
import 'package:tracend/features/train/set_timing.dart';
import 'package:tracend/features/train/widgets/focus_exercise_page.dart';
import 'package:tracend/features/train/widgets/rest_timer_view.dart';
import 'package:tracend/features/train/widgets/rir_picker.dart';
import 'package:tracend/features/train/widgets/workout_finish_sheet.dart';
import 'package:tracend/features/train/widgets/workout_summary_sheet.dart';
import 'package:tracend/features/train/workout_draft.dart';
import 'package:tracend/features/train/workout_events.dart';
import 'package:tracend/features/train/workout_logic.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_recorder.dart';
import 'package:tracend/features/workout_hr/watch_workout_prompt.dart';
import 'package:tracend/shared/home_widgets/lock_screen_numbers.dart';
import 'package:tracend/shared/live_activity/workout_activity_bridge.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_skeleton.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// Logs a workout in focus mode: one exercise per page, a rest timer that
/// takes over between sets and shrinks to a pill, and a finish that asks how
/// hard the whole workout was before saving it (UX_FLOWS.md §6). It records
/// when each set began and ended and the rest taken (Contract 2), publishes
/// the workout's events and takes the Live Activity's commands (Contract 3)
/// through [events].
class ActiveWorkoutScreen extends StatefulWidget {
  const ActiveWorkoutScreen({
    required this.workout,
    required this.repository,
    this.sessionDate,
    this.restAlerts = const MethodChannelRestAlertScheduler(),
    this.notifications = const MethodChannelNotificationRepository(),
    this.clock = DateTime.now,
    this.events,
    this.activity = const MethodChannelWorkoutActivityBridge(),
    this.lockScreenNumbers = readLockScreenNumbers,
    this.watchPrompt,
    super.key,
  });

  final PlannedWorkout workout;
  final WorkoutRepository repository;
  final DateTime? sessionDate;

  /// The lock-screen alert at the end of a rest. It is only scheduled when
  /// the athlete turned "Rest timer alerts" on in [notifications].
  final RestAlertScheduler restAlerts;
  final NotificationRepository notifications;

  /// The time source for the elapsed time, the rest timer and set times.
  final DateTime Function() clock;

  /// The workout's event stream and command sink. The screen makes its own
  /// when none is given, and closes it when it goes away.
  final WorkoutEventHub? events;

  /// The workout's Live Activity: the set in progress and the rest. The rest
  /// timer controller is its only driver; the workout events above do not
  /// touch it. Its "Log set", Skip and +30s buttons arrive as
  /// [WorkoutCommand]s through [events]' command sink.
  final WorkoutActivityBridge activity;

  /// Whether the athlete allows numbers on the Lock Screen. Read once when the
  /// workout opens; the card shows the set's kg and reps only when true.
  final Future<bool> Function() lockScreenNumbers;

  /// Decides whether to suggest a Watch workout before the first set. The
  /// screen makes the server-backed one for the Supabase repository and
  /// suggests nothing otherwise.
  final WatchWorkoutPromptSource? watchPrompt;

  static int _open = 0;

  /// Whether a workout screen is open anywhere in the app. A link from the
  /// Live Activity then needs nothing more than the app coming forward.
  static bool get isOpen => _open > 0;

  /// The longest workout the server records (3 hours).
  static const maxSessionSeconds = 10800;

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

enum _Sync { saving, saved, offline, attention }

enum _Leave { save, discard }

/// What a Done press from the Live Activity did.
enum _Tick { ticked, stale, unsuggested }

/// What follows a set: the label, and the set it names (1-based) with the
/// index of its exercise in the workout.
typedef _Next = ({
  String full,
  String short,
  int exercise,
  int exerciseOrder,
  int setNumber,
});

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
    activity: widget.activity,
    clock: widget.clock,
  );
  final PageController _pages = PageController();
  late final WorkoutEventHub _events = widget.events ?? WorkoutEventHub();
  StreamSubscription<void>? _commands;
  StreamSubscription<void>? _heartRate;
  WatchWorkoutPromptSource? _watchPrompt;

  /// The Watch-workout suggestion shows above the first set only.
  bool _suggestWatch = false;

  /// A set was done or the suggestion was answered: it is not shown again.
  bool _watchSuggestionOver = false;
  final SetTimingRecorder _timing = SetTimingRecorder();

  String? _sessionId;
  String _idempotencyKey = newIdempotencyKey();
  int _revision = 0;
  late DateTime _startedAt = widget.clock();

  /// When the server's copy of this session began, when known. Set times
  /// before it stay on this phone (see [WorkoutSetDraft.toMap]).
  DateTime? _serverStartedAt;

  /// The server refused this phone's set times (22023, for example a phone
  /// clock far off): this session syncs without them from then on.
  bool _timingRefused = false;
  bool _ready = false;
  _Sync _sync = _Sync.saving;

  /// The workout is finished or discarded: nothing is saved any more.
  bool _closed = false;

  bool _viewingCompleted = false;
  bool _completedFromHealth = false;
  int? _completedDuration;

  ExerciseHistoryResult? _history;
  HistoryStatus _historyStatus = HistoryStatus.loading;

  /// The athlete allows kg and reps on the Lock Screen, so the Live Activity
  /// shows the set's target.
  bool _targetsOnLockScreen = false;

  /// The exercise page on screen: the set the Live Activity names follows it.
  int _page = 0;

  /// The rest shows full screen; false when it is shrunk to the pill.
  bool _restExpanded = true;

  /// What follows the rest, in full for the ring and the toast, and short
  /// for the pill.
  _Next? _restNext;

  /// The set the running rest follows, for its reps-left picker.
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
    ActiveWorkoutScreen._open++;
    _commands = _events.handleCommands(_onCommand, clock: widget.clock);
    final repository = widget.repository;
    if (repository is SupabaseWorkoutRepository) {
      _heartRate = SetHeartRateRecorder.shared(Supabase.instance.client).listen(
        _events.events,
        loadSession: () => repository.loadSession(
          widget.workout,
          localDate: widget.sessionDate,
        ),
      );
    }
    _watchPrompt =
        widget.watchPrompt ??
        (repository is SupabaseWorkoutRepository
            ? SupabaseWatchWorkoutPromptSource(Supabase.instance.client)
            : null);
    _restore();
  }

  @override
  void dispose() {
    ActiveWorkoutScreen._open--;
    // Finish, discard and save-and-leave stop the rest before the screen
    // goes; anything else (the app returning to sign-in) leaves the rest in
    // the draft and ends only its Live Activity.
    _rest.detach();
    unawaited(widget.activity.detachButtons(_onButton));
    _saveTimer?.cancel();
    _ticker?.cancel();
    unawaited(_commands?.cancel());
    unawaited(_heartRate?.cancel());
    _events.close();
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
    var local = saved == null ? null : _decode(saved);
    if (local != null &&
        _leftOnEarlierDay(local) &&
        local['session_id'] != server?['session_id'] &&
        await _sendLeftOver(local)) {
      // An unfinished workout from an earlier day stays on its own day (the
      // server closes it as discarded and still takes what was left unsent),
      // so this phone's copy never opens today's workout or carries its sets
      // and start time into it. It is dropped only once everything in it has
      // reached the server; otherwise it stays and opens as it was saved.
      await widget.repository.clearDraft(widget.workout.id);
      local = null;
    }
    final draft = _newer(server, local);
    if (draft != null) {
      _sessionId = draft['session_id'] as String?;
      _idempotencyKey = draft['idempotency_key'] as String? ?? _idempotencyKey;
      _revision = (draft['revision'] as num?)?.toInt() ?? 0;
      _startedAt =
          DateTime.tryParse('${draft['actual_started_at'] ?? ''}')?.toLocal() ??
          _startedAt;
      _hydrate(draft['exercises']);
      if (server != null && server['session_id'] == _sessionId) {
        _serverStartedAt = DateTime.tryParse(
          '${server['actual_started_at'] ?? ''}',
        );
      }
      if (local != null && local['session_id'] == _sessionId) {
        _restoreClearedLoads(local[_clearedLoadsKey]);
        _serverStartedAt ??= DateTime.tryParse(
          '${local[_serverStartedKey] ?? ''}',
        );
        _timing.pendingStart = DateTime.tryParse(
          '${local[SetTimingRecorder.draftKey] ?? ''}',
        );
        _timingRefused = local[_timingRefusedKey] == true;
      }
    }
    final storedRest = RestTimer.fromJson(local?[RestTimer.draftKey]);
    await _rest.restore(local?[RestTimer.draftKey]);
    if (_rest.timer != null) {
      _restExpanded = false;
      _restNext = _nextAfterCurrent();
    } else if (storedRest != null) {
      // The rest ran out while the app was away: it ended at its end time.
      _timing.restEnded(storedRest.endsAt);
    }
    _pendingFinish = await widget.repository.loadPendingFinish(
      widget.workout.id,
    );
    await _loadLockScreenChoice();
    _ready = true;
    final first = _firstOpenExercise();
    _page = first;
    if (mounted) {
      unawaited(widget.activity.attachButtons(_onButton));
      if (_pendingFinish == null) {
        _syncActivity(begin: true);
      } else {
        // The workout was finished and waits to be sent: a card left from
        // before names sets that are done.
        unawaited(_rest.stop());
      }
    }
    if (mounted) setState(() {});
    if (first > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pages.hasClients) _pages.jumpToPage(first);
      });
    }
    unawaited(_loadHistory());
    unawaited(_loadWatchSuggestion());
    try {
      if (_sessionId == null) {
        final id = await widget.repository.start(
          widget.workout,
          _idempotencyKey,
          localDate: widget.sessionDate,
        );
        _sessionId = id;
        _serverStartedAt ??= await _serverStartOf(id);
      }
    } catch (e) {
      debugPrint('Non-critical error: workout start waits: $e');
      _sessionId ??= 'pending-$_idempotencyKey';
      _sync = _Sync.offline;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    await _save();
  }

  /// The keys of a saved draft that the server reads; the rest only this
  /// phone needs.
  static const _serverDraftKeys = [
    'workout_id',
    'session_id',
    'idempotency_key',
    'revision',
    'exercises',
    'notes',
  ];

  /// The five set keys the server may refuse when this phone's times are off.
  static const _timingKeys = [
    'started_at',
    'completed_at',
    'rest_before_seconds',
    'rir',
    'timing_source',
  ];

  /// Sends what an earlier day's draft holds that the server may not have:
  /// its sets, and its finish when one was saved. True when nothing is left
  /// on this phone that the server lacks, so the draft may go: no set was
  /// done and no finish waits, or everything reached the server. False
  /// keeps the draft (offline, or a draft whose session was never created
  /// and has no finish to send).
  Future<bool> _sendLeftOver(Map<String, dynamic> draft) async {
    final repository = widget.repository;
    try {
      final finish = await repository.loadPendingFinish(widget.workout.id);
      if (finish == null && !_hasDoneSet(draft)) return true;
      var id = draft['session_id'] as String?;
      if (id == null || id.startsWith('pending-')) {
        final key = draft['idempotency_key'] as String?;
        final started = DateTime.tryParse(
          '${draft['actual_started_at'] ?? ''}',
        );
        if (finish == null || key == null || started == null) return false;
        id = await repository.start(
          widget.workout,
          key,
          localDate: started.toLocal(),
        );
      }
      final revision = (draft['revision'] as num?)?.toInt() ?? 0;
      final payload = {
        for (final key in _serverDraftKeys)
          if (draft.containsKey(key)) key: draft[key],
        'session_id': id,
      };
      try {
        await repository.sync(id, revision, payload);
      } on PostgrestException catch (e) {
        if (e.code != '22023') rethrow;
        await repository.sync(id, revision, _withoutTiming(payload));
      }
      if (finish != null) {
        await repository.completeWithEffort(
          id,
          revision,
          finish.durationSeconds,
          payload,
          sessionEffort: finish.sessionEffort,
        );
      }
      AppBreadcrumbs.workout(
        'Earlier workout sent',
        data: {'finished': finish != null},
      );
      return true;
    } catch (e) {
      debugPrint('Non-critical error: earlier workout kept on the phone: $e');
      return false;
    }
  }

  static bool _hasDoneSet(Map<String, dynamic> draft) {
    final exercises = draft['exercises'];
    if (exercises is! List) return false;
    return exercises.any(
      (exercise) =>
          exercise is Map &&
          exercise['sets'] is List &&
          (exercise['sets'] as List).any(
            (set) => set is Map && set['completed'] == true,
          ),
    );
  }

  static Map<String, dynamic> _withoutTiming(Map<String, dynamic> payload) => {
    ...payload,
    'exercises': [
      for (final exercise in payload['exercises'] as List)
        {
          ...(exercise as Map<String, dynamic>),
          'sets': [
            for (final set in exercise['sets'] as List)
              {
                for (final entry in (set as Map<String, dynamic>).entries)
                  if (!_timingKeys.contains(entry.key)) entry.key: entry.value,
              },
          ],
        },
    ],
  };

  bool _leftOnEarlierDay(Map<String, dynamic> draft) {
    final started = DateTime.tryParse('${draft['actual_started_at'] ?? ''}');
    if (started == null) return false;
    final now = widget.clock();
    return workoutLeftOnEarlierDay(
      startedAt: started,
      now: now,
      sessionDate: widget.sessionDate ?? now,
      maxSeconds: ActiveWorkoutScreen.maxSessionSeconds,
    );
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

  /// The local draft field that holds [_serverStartedAt].
  static const _serverStartedKey = 'server_started_at';

  /// The local draft field that holds [_timingRefused].
  static const _timingRefusedKey = 'timing_refused';

  /// When the server's copy of session [id] began, read back from the
  /// server; the phone's clock only when that read fails (an estimate: a
  /// refused time then falls back to syncing without times).
  Future<DateTime> _serverStartOf(String id) async {
    try {
      final session = await widget.repository.loadSession(
        widget.workout,
        localDate: widget.sessionDate,
      );
      if (session != null && session['session_id'] == id) {
        final start = DateTime.tryParse(
          '${session['actual_started_at'] ?? ''}',
        );
        if (start != null) return start;
      }
    } catch (e) {
      debugPrint('Non-critical error: session start not read back: $e');
    }
    return widget.clock();
  }

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

  Future<void> _loadLockScreenChoice() async {
    try {
      _targetsOnLockScreen = await widget.lockScreenNumbers();
    } catch (e) {
      debugPrint('Non-critical error: lock screen choice not read: $e');
      _targetsOnLockScreen = false;
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
      // The pre-filled kg and reps may now come from the history.
      _syncActivity();
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
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
      _rest.tick();
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

  /// The draft. With [notBefore] (for the server), set times before it are
  /// left out; without [timing], every set's timing keys are.
  Map<String, dynamic> _draft({DateTime? notBefore, bool timing = true}) => {
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
              {
                'number': j + 1,
                ...draft.sets[j].toMap(notBefore: notBefore, timing: timing),
              },
          ],
        },
    ],
  };

  /// The draft kept on this phone: the synced draft plus the start time,
  /// the running rest and the end of the last rest, which only the device
  /// needs.
  Map<String, dynamic> _localDraft() => {
    ..._draft(),
    'actual_started_at': _startedAt.toUtc().toIso8601String(),
    _serverStartedKey: ?_serverStartedAt?.toUtc().toIso8601String(),
    if (_timingRefused) _timingRefusedKey: true,
    RestTimer.draftKey: ?_rest.toDraft(),
    SetTimingRecorder.draftKey: ?_timing.pendingStart
        ?.toUtc()
        .toIso8601String(),
    _clearedLoadsKey: _clearedLoads(),
  };

  void _changed() {
    // A first set ends the suggestion for this workout for good: undoing the
    // set does not bring the card back.
    if (_anySetDone) {
      _watchSuggestionOver = true;
      _suggestWatch = false;
    }
    _revision++;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), _save);
    setState(() {});
  }

  /// Saves the draft on the phone and sends it to the server. Returns how
  /// the send went, or null when nothing was sent (a closed workout).
  Future<_Sync?> _save() async {
    if (_closed || _viewingCompleted) return null;
    await widget.repository.saveDraft(
      widget.workout.id,
      jsonEncode(_localDraft()),
    );
    var id = _sessionId;
    if (id == null) return null;
    if (id.startsWith('pending-')) {
      try {
        id = await widget.repository.start(
          widget.workout,
          _idempotencyKey,
          localDate: widget.sessionDate,
        );
        _sessionId = id;
        _serverStartedAt = await _serverStartOf(id);
      } catch (e) {
        debugPrint('Non-critical error: workout start still waits: $e');
        if (mounted) setState(() => _sync = _Sync.offline);
        return _Sync.offline;
      }
    }
    if (mounted) setState(() => _sync = _Sync.saving);
    final first = await _send(id);
    final _Sync result;
    if (first != null) {
      result = first;
    } else {
      // Missing keys keep the server's values, so the same revision goes
      // again without the times, and so does every later sync.
      _timingRefused = true;
      AppBreadcrumbs.workout('Set times refused; syncing without them');
      await widget.repository.saveDraft(
        widget.workout.id,
        jsonEncode(_localDraft()),
      );
      result = await _send(id) ?? _Sync.attention;
    }
    if (mounted) setState(() => _sync = result);
    return result;
  }

  /// One `sync_workout_draft` call. Null when the server refused the draft
  /// (22023) while it still carried this phone's set times; any other
  /// refusal needs attention.
  Future<_Sync?> _send(String id) async {
    try {
      await widget.repository.sync(
        id,
        _revision,
        _draft(
          notBefore: _serverStartedAt ?? _startedAt,
          timing: !_timingRefused,
        ),
      );
      return _Sync.saved;
    } on PostgrestException catch (e) {
      debugPrint('Non-critical error: workout sync refused: ${e.code}');
      return e.code == '22023' && !_timingRefused ? null : _Sync.attention;
    } catch (e) {
      debugPrint('Non-critical error: workout sync waits: $e');
      return _Sync.offline;
    }
  }

  // Sets ------------------------------------------------------------------------

  /// A rest whose end passed between ticks or while the app was away ended
  /// at its stored end time.
  void _expireRest(DateTime now) {
    final timer = _rest.timer;
    if (timer == null || !timer.isExpired(now)) return;
    _timing.restEnded(timer.endsAt);
    unawaited(_rest.ranOut());
  }

  bool _resting(DateTime now) {
    final timer = _rest.timer;
    return timer != null && !timer.isExpired(now);
  }

  /// The end times of every done set in the workout except [except].
  Iterable<DateTime> _endsExcept(WorkoutSetDraft except) => [
    for (final draft in _exercises)
      for (final set in draft.sets)
        if (!identical(set, except) && set.completed && set.completedAt != null)
          set.completedAt!,
  ];

  void _doneSet(int exercise, String load, String reps) {
    final draft = _exercises[exercise];
    final index = draft.currentSetIndex;
    if (index == null) return;
    final now = widget.clock();
    _expireRest(now);
    final set = draft.sets[index]
      ..load = load
      ..reps = reps
      ..completed = true;
    final started = _timing.completed(
      set,
      now: now,
      resting: _resting(now),
      otherEnds: _endsExcept(set),
    );
    if (draft.skipped) draft.status = 'unknown';
    if (draft.newBests(_historyOf(exercise)).contains(index)) {
      TracendHaptics.medium();
      _momentToken++;
      _momentExercise = exercise;
      _moment = NewBestMoment(set: index, token: _momentToken);
    } else {
      TracendHaptics.light();
    }
    final order = draft.exercise.order;
    if (started != null) {
      _events.emit(
        SetStarted(at: started, exerciseOrder: order, setNumber: index + 1),
      );
    }
    _events.emit(
      SetCompleted(
        at: now,
        exerciseOrder: order,
        setNumber: index + 1,
        reps: set.repetitions,
        loadKg: set.loadKg?.toDouble(),
        rir: set.rir,
      ),
    );
    final next = _nextLabel(exercise);
    final restSeconds = draft.exercise.restSeconds;
    if (next != null && restSeconds > 0) {
      _restNext = next;
      _restAfter = (exercise, index);
      _restEffortDismissed = false;
      _restExpanded = true;
      _timing.restStarted();
      unawaited(
        _rest
            .start(
              restSeconds,
              nextLabel: next.full,
              exerciseName: draft.exercise.name,
              next: _activitySet(next),
            )
            .then((_) => _persistRest()),
      );
      final timer = _rest.timer;
      if (timer != null) {
        _events.emit(
          RestStarted(
            at: now,
            seconds: restSeconds,
            endsAt: timer.endsAt,
            nextLabel: next.full,
          ),
        );
      }
    } else {
      // No rest follows: the activity names the next set, or says every set
      // is logged.
      _rest.present(
        next == null ? null : _activitySet(next),
        begin: true,
        nextLabel: next?.full ?? '',
      );
    }
    _changed();
  }

  void _undoSet(int exercise, int set) {
    _exercises[exercise].sets[set]
      ..completed = false
      ..startedAt = null
      ..completedAt = null
      ..restBeforeSeconds = null
      ..timingSource = null
      ..setRir(null);
    // A rest measured from the undone tick is measured again.
    for (final draft in _exercises) {
      for (final other in draft.sets) {
        if (!other.completed || other.startedAt == null) continue;
        other.restBeforeSeconds = restTakenSeconds(
          other.startedAt,
          _endsExcept(other),
        );
      }
    }
    if (_momentExercise == exercise && _moment?.set == set) {
      _moment = null;
      _momentExercise = null;
    }
    if (_restAfter == (exercise, set)) _restAfter = null;
    _changed();
    _syncActivity();
  }

  void _setRir(int exercise, int set, int? rir) {
    _exercises[exercise].sets[set].setRir(rir);
    _changed();
  }

  /// Gives [rir] to the done sets of [exercise] that read as unanswered; a
  /// set with reps left or an older RPE keeps its effort.
  int _fillRir(int exercise, int rir) {
    var filled = 0;
    for (final set in _exercises[exercise].sets) {
      if (set.completed && set.shownRir == null) {
        set.setRir(rir);
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
    final now = widget.clock();
    _expireRest(now);
    final started = _timing.touched(set, now: now, resting: _resting(now));
    if (started != null) {
      _events.emit(
        SetStarted(
          at: started,
          exerciseOrder: draft.exercise.order,
          setNumber: index + 1,
        ),
      );
    }
    _changed();
    _syncActivity();
  }

  /// How long a button press waits for the server copy before it answers;
  /// iOS gives up on a press after 8 s, and the save carries on after that.
  static const _pressSaveWait = Duration(seconds: 5);

  /// A Live Activity button, sent through the workout's one command sink
  /// (Contract 3). Completes with whether the screen handled it, and drops a
  /// press that waited past [LiveActivityButton.pressTimeout].
  Future<bool> _onButton(LiveActivityButton button) =>
      _events.send(workoutCommandFor(button), expiresAt: button.expiresAt);

  /// The Live Activity's buttons. True when the command was acted on or
  /// knowingly ignored as out of date (the card is then redrawn to the true
  /// state); false when nothing could act on it (the workout is closed or
  /// ending, or the set cannot be ticked from the card), so the card asks the
  /// athlete to open the app. Completes when the rest, its Live Activity call
  /// and the draft are saved, since iOS may suspend the app right after a
  /// press. Commands arrive one at a time, so each sees the last one's state.
  ///
  /// The press also waits for the Live Activity update its change sent
  /// (bounded by [RestTimerController.activityWait], and a failed or slow
  /// update never undoes the change), so the card is current before iOS can
  /// suspend the app. In-app taps do not wait: nothing suspends the app
  /// there, and the timer must not stall on iOS.
  Future<bool> _onCommand(WorkoutCommand command) async {
    final handled = await _handleCommand(command);
    await _rest.activityUpdated();
    return handled;
  }

  Future<bool> _handleCommand(WorkoutCommand command) async {
    if (!mounted || !_ready || _closed || _finishing || _viewingCompleted) {
      return false;
    }
    // A button may wake the app after the rest ran out unnoticed: that rest
    // ended at its stored end, so Skip and +30s then have nothing to change.
    final running = _rest.timer;
    _expireRest(widget.clock());
    if (running != null && _rest.timer == null) await _persistRest();
    switch (command) {
      case CompleteCurrentSet(:final exerciseOrder, :final setNumber):
        // A running rest means the card is out of date (its set was ticked
        // and the next rest started): the athlete is not doing a set now.
        // Every card change comes from this screen, so the card already
        // shows the true state; the refresh only clears a stuck "Open
        // Tracend to continue".
        if (_rest.timer != null) {
          _rest.refresh();
          return true;
        }
        switch (_completeSet(exerciseOrder, setNumber)) {
          case _Tick.ticked:
            await _saveForPress();
          case _Tick.stale:
            // The set is no longer the current one (a repeated or late
            // press): nothing is logged, and the card is redrawn to the true
            // set.
            _rest.refresh();
          case _Tick.unsuggested:
            return false;
        }
      case SkipRest():
        await _skipRest();
      case AddRest(:final seconds):
        if (seconds > 0) await _adjustRest(Duration(seconds: seconds));
    }
    return true;
  }

  /// Ticks set [setNumber] (1-based) of the exercise at [exerciseOrder] with
  /// the kg and reps the screen suggests, but only while it is still that
  /// exercise's current, unticked set.
  _Tick _completeSet(int exerciseOrder, int setNumber) {
    final exercise = _exercises.indexWhere(
      (e) => e.exercise.order == exerciseOrder,
    );
    if (exercise < 0) return _Tick.stale;
    final draft = _exercises[exercise];
    final index = draft.currentSetIndex;
    if (draft.skipped || index == null || index != setNumber - 1) {
      return _Tick.stale;
    }
    final suggestion = suggestSet(draft, index, _historyOf(exercise));
    if ((num.tryParse(suggestion.reps) ?? 0) <= 0) return _Tick.unsuggested;
    _doneSet(exercise, suggestion.load, suggestion.reps);
    return _Tick.ticked;
  }

  /// Saves a ticked set to the phone and the server now, as the 250 ms
  /// timer after an in-app tick would, because iOS may suspend the app
  /// before it fires. A failed send is handled inside [_save] exactly as for
  /// an in-app tick (the draft waits and syncs later); the set is logged
  /// either way.
  Future<void> _saveForPress() async {
    _saveTimer?.cancel();
    try {
      await _save().timeout(_pressSaveWait, onTimeout: () => null);
    } catch (e) {
      debugPrint('Non-critical error: saving a button press failed: $e');
    }
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
    _syncActivity();
  }

  /// What comes after the current set of [exercise]: its next set, else the
  /// next exercise with sets to do; null when the workout has nothing left.
  _Next? _nextLabel(int exercise) {
    final draft = _exercises[exercise];
    final set = draft.currentSetIndex;
    if (set != null && !draft.skipped) {
      return (
        full: 'Set ${set + 1} of ${draft.exercise.name}',
        short: 'Set ${set + 1}',
        exercise: exercise,
        exerciseOrder: draft.exercise.order,
        setNumber: set + 1,
      );
    }
    for (var i = 1; i < _exercises.length; i++) {
      final index = (exercise + i) % _exercises.length;
      final other = _exercises[index];
      final otherSet = other.currentSetIndex;
      if (!other.skipped && otherSet != null) {
        return (
          full: other.exercise.name,
          short: other.exercise.name,
          exercise: index,
          exerciseOrder: other.exercise.order,
          setNumber: otherSet + 1,
        );
      }
    }
    return null;
  }

  /// The set the Live Activity names while no rest runs: the current set of
  /// the exercise on screen, else the next exercise with a set to do; null
  /// when every set is logged. "Log set" on the card logs this set with the
  /// kg and reps the logger pre-fills for it ([suggestSet]).
  _Next? _setInProgress() => _exercises.isEmpty
      ? null
      : _nextLabel(_page.clamp(0, _exercises.length - 1).toInt());

  /// [next] as the Live Activity shows it. The target is the same kg and
  /// reps the logger pre-fills and "Log set" logs, and only travels while the
  /// athlete allows numbers on the Lock Screen.
  ActivitySet _activitySet(_Next next) {
    final draft = _exercises[next.exercise];
    final suggestion = suggestSet(
      draft,
      next.setNumber - 1,
      _historyOf(next.exercise),
    );
    final reps = num.tryParse(suggestion.reps);
    final canLog = (reps ?? 0) > 0;
    return (
      exerciseOrder: next.exerciseOrder,
      setNumber: next.setNumber,
      setCount: draft.sets.length,
      exerciseName: draft.exercise.name,
      target: _targetsOnLockScreen && canLog
          ? describeSet(
              loadKg: num.tryParse(suggestion.load),
              repetitions: reps!.round(),
              assisted: draft.assisted,
            )
          : '',
      canLog: canLog,
    );
  }

  /// Shows the set in progress on the Live Activity. [begin] asks for a card
  /// when none shows (the workout just opened); an edit only moves a card
  /// that is there, so one the athlete dismissed stays gone.
  void _syncActivity({bool begin = false}) {
    if (!mounted ||
        !_ready ||
        _closed ||
        _finishing ||
        _viewingCompleted ||
        _pendingFinish != null) {
      return;
    }
    final next = _setInProgress();
    _rest.present(
      next == null ? null : _activitySet(next),
      begin: begin,
      nextLabel: next?.full ?? '',
    );
  }

  /// The next set to do in the workout, for a rest restored after a
  /// relaunch.
  _Next? _nextAfterCurrent() {
    for (var i = 0; i < _exercises.length; i++) {
      final draft = _exercises[i];
      final set = draft.currentSetIndex;
      if (!draft.skipped && set != null) {
        return (
          full: set == 0
              ? draft.exercise.name
              : 'Set ${set + 1} of ${draft.exercise.name}',
          short: set == 0 ? draft.exercise.name : 'Set ${set + 1}',
          exercise: i,
          exerciseOrder: draft.exercise.order,
          setNumber: set + 1,
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
    if (_rest.timer == null) return;
    final now = widget.clock();
    await _rest.adjust(delta);
    final timer = _rest.timer;
    if (timer == null) _timing.restEnded(now);
    _events.emit(RestAdjusted(at: now, endsAt: timer?.endsAt ?? now));
    await _persistRest();
  }

  Future<void> _skipRest() async {
    if (_rest.timer == null) return;
    final now = widget.clock();
    _timing.restEnded(now);
    await _rest.skip();
    _events.emit(RestAdjusted(at: now, endsAt: now));
    await _persistRest();
  }

  Future<void> _restEnded() async {
    final timer = _rest.timer;
    if (timer == null) return;
    _timing.restEnded(timer.endsAt);
    await _rest.ranOut();
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
    _events.emit(WorkoutEnded(at: widget.clock(), completed: false));
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
    _events.emit(WorkoutEnded(at: widget.clock(), completed: false));
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
    final saved = await _save();
    if (saved == _Sync.attention) {
      // The server holds older sets than this phone: finishing now would
      // finish from those, and clear the phone's copy.
      if (!mounted) return;
      setState(() {
        _finishing = false;
        _pendingFinish = PendingWorkoutFinish(
          sessionEffort: effort,
          durationSeconds: durationSeconds,
        );
        _finishError =
            'Tracend could not save your sets, so the workout is not '
            'finished yet. They are kept on this phone.';
      });
      unawaited(TracendHaptics.warning());
      return;
    }
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
    _events.emit(WorkoutEnded(at: widget.clock(), completed: true));
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
                onPageChanged: _pageChanged,
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

  void _pageChanged(int page) {
    TracendHaptics.selection();
    _page = page;
    _syncActivity();
    final exercise = _exercises[page].exercise;
    _events.emit(
      ExerciseAdvanced(
        at: widget.clock(),
        exerciseOrder: exercise.order,
        name: exercise.name,
      ),
    );
  }

  Widget? _restEffort() {
    final after = _restAfter;
    if (after == null || _restEffortDismissed) return null;
    final (exercise, set) = after;
    final row = _exercises[exercise].sets[set];
    if (!row.completed) return null;
    return RirPicker(
      title: 'Reps left on set ${set + 1}',
      value: row.rir,
      onSelected: (value) => _setRir(exercise, set, value),
      onClear: () => _setRir(exercise, set, null),
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
      onRir: (set, rir) => _setRir(i, set, rir),
      onFillRir: (rir) => _fillRir(i, rir),
      onPain: () {
        _exercises[i].pain = !_exercises[i].pain;
        _changed();
      },
      onMore: () => _more(i),
    );
  }

  bool get _anySetDone =>
      _exercises.any((exercise) => exercise.completedCount > 0);

  /// Asks whether to suggest a Watch workout, only for a workout with no set
  /// done yet (a draft restored mid-workout is past the point of starting one).
  Future<void> _loadWatchSuggestion() async {
    final source = _watchPrompt;
    if (source == null || _viewingCompleted || _anySetDone) return;
    final suggest = await source.shouldSuggest();
    if (!suggest ||
        !mounted ||
        _closed ||
        _watchSuggestionOver ||
        _anySetDone) {
      return;
    }
    setState(() => _suggestWatch = true);
  }

  void _answerWatchSuggestion({required bool noWatch}) {
    final source = _watchPrompt;
    _watchSuggestionOver = true;
    setState(() => _suggestWatch = false);
    if (source == null) return;
    unawaited(noWatch ? source.mute() : source.snooze());
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
      if (_suggestWatch && !_viewingCompleted && !_closed)
        WatchWorkoutPromptCard(
          onNotNow: () => _answerWatchSuggestion(noWatch: false),
          onNoWatch: () => _answerWatchSuggestion(noWatch: true),
        ),
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
