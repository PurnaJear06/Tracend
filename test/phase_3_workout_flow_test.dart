import 'dart:async';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/exercise_history.dart';
import 'package:tracend/features/train/muscle_groups.dart';
import 'package:tracend/features/train/rest_timer.dart';
import 'package:tracend/features/train/widgets/focus_exercise_page.dart';
import 'package:tracend/features/train/widgets/rest_timer_view.dart';
import 'package:tracend/features/train/widgets/set_row.dart';
import 'package:tracend/features/train/workout_events.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/live_activity/workout_activity_bridge.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

import 'live_activity/fake_workout_activity_bridge.dart';
import 'widgets/haptics_recorder.dart';

const _workout = PlannedWorkout(
  id: 'upper-a',
  name: 'Upper A',
  objective: 'Press and push.',
  estimatedMinutes: 45,
  exercises: [
    PlannedExercise(
      order: 1,
      name: 'Bench press',
      setCount: 2,
      repMin: 8,
      repMax: 10,
      targetRpe: 8,
      restSeconds: 90,
      targetLoadKg: 55,
      exerciseSlug: 'bench-press',
      primaryMuscles: [
        MuscleGroup.chest,
        MuscleGroup.triceps,
        MuscleGroup.shoulders,
      ],
    ),
    PlannedExercise(
      order: 2,
      name: 'Push-up',
      setCount: 2,
      repMin: 12,
      repMax: 15,
      targetRpe: 8,
      restSeconds: 60,
    ),
  ],
);

ExerciseHistoryResult _history() => ExerciseHistoryResult.fromJson({
  'exercises': [
    {
      'key': 'bench-press',
      'kind': 'load',
      'last_session': {
        'session_id': 's-1',
        'local_date': '2026-09-29',
        'sets': [
          {'set_number': 1, 'load_kg': 60, 'repetitions': 8},
          {'set_number': 2, 'load_kg': 60, 'repetitions': 7},
        ],
      },
      'best_set': {'kind': 'load', 'load_kg': 60, 'repetitions': 8},
    },
    {'key': 'Push-up', 'kind': 'reps'},
  ],
});

class _Repository implements WorkoutRepository {
  String? saved;
  Map<String, dynamic>? synced;
  bool failStart = false;
  bool failSync = false;

  /// The server refuses (22023) any draft that carries a set end time, as
  /// it does for a phone clock more than 10 minutes ahead.
  bool refuseTimes = false;

  /// The server refuses every draft with this code.
  String? refuseCode;
  int refusals = 0;
  int completeCalls = 0;

  /// Runs when the server creates the session.
  void Function()? onStart;
  bool failComplete = false;
  final efforts = <int>[];
  int? lastDuration;
  Map<String, dynamic>? serverSession;
  PendingWorkoutFinish? pending;
  final abandoned = <String>[];
  ExerciseHistoryResult history = _history();

  Map<String, dynamic> get savedDraft =>
      Map<String, dynamic>.from(jsonDecode(saved!) as Map);

  Map<String, dynamic> savedSet(int exercise, int set) =>
      _set(savedDraft, exercise, set);

  /// A set of the last draft sent to the server.
  Map<String, dynamic> syncedSet(int exercise, int set) =>
      _set(synced!, exercise, set);

  static Map<String, dynamic> _set(
    Map<String, dynamic> draft,
    int exercise,
    int set,
  ) {
    final exercises = draft['exercises'] as List;
    final sets = (exercises[exercise] as Map)['sets'] as List;
    return Map<String, dynamic>.from(sets[set] as Map);
  }

  @override
  Future<void> clearDraft(String workoutId) async => saved = null;

  @override
  Future<String?> loadDraft(String workoutId) async => saved;

  @override
  Future<Map<String, dynamic>?> loadSession(
    PlannedWorkout workout, {
    DateTime? localDate,
  }) async => serverSession;

  @override
  Future<PlannedWorkout> loadTodayWorkout() async => _workout;

  @override
  Future<void> saveDraft(String workoutId, String json) async => saved = json;

  @override
  Future<String> start(
    PlannedWorkout workout,
    String idempotencyKey, {
    DateTime? localDate,
  }) async {
    if (failStart) throw Exception('offline');
    onStart?.call();
    return 'server-session';
  }

  @override
  Future<void> sync(
    String sessionId,
    int revision,
    Map<String, dynamic> draft,
  ) async {
    if (failSync) throw Exception('offline');
    final code = refuseCode;
    if (code != null) {
      refusals++;
      throw PostgrestException(message: 'refused', code: code);
    }
    final sets = [
      for (final exercise in draft['exercises'] as List)
        ...(exercise as Map)['sets'] as List,
    ];
    if (refuseTimes &&
        sets.any((set) => (set as Map)['completed_at'] != null)) {
      refusals++;
      throw const PostgrestException(
        message: 'set time is in the future',
        code: '22023',
      );
    }
    synced = jsonDecode(jsonEncode(draft)) as Map<String, dynamic>;
  }

  @override
  Future<WorkoutCompletion> completeWithEffort(
    String sessionId,
    int revision,
    int durationSeconds,
    Map<String, dynamic> draft, {
    required int sessionEffort,
  }) async {
    completeCalls++;
    if (failComplete) throw Exception('offline');
    efforts.add(sessionEffort);
    lastDuration = durationSeconds;
    saved = null;
    return const WorkoutCompletion(replayed: false);
  }

  @override
  Future<PendingWorkoutFinish?> loadPendingFinish(String workoutId) async =>
      pending;

  @override
  Future<WorkoutDiscard> abandon(
    String sessionId, {
    required String workoutId,
  }) async {
    abandoned.add(sessionId);
    saved = null;
    return const WorkoutDiscard();
  }

  @override
  Future<ExerciseHistoryResult> loadExerciseHistory(
    List<String> keys, {
    int sessions = 8,
  }) async => history;
}

class _Alerts implements RestAlertScheduler {
  final scheduled = <int>[];
  int cancels = 0;

  @override
  Future<bool> scheduleRestAlert(int seconds) async {
    scheduled.add(seconds);
    return true;
  }

  @override
  Future<void> cancelRestAlert() async => cancels++;
}

class _Notifications implements NotificationRepository {
  _Notifications({required this.restAlerts});

  final bool restAlerts;

  @override
  Future<NotificationPreferences> load() async => NotificationPreferences(
    authorizationStatus: 'authorized',
    dailyCheckIn: false,
    weeklyReview: false,
    restTimerAlertsEnabled: restAlerts,
  );

  @override
  Future<NotificationPreferences> configure({
    required bool dailyCheckIn,
    required bool weeklyReview,
    required bool restTimerAlertsEnabled,
  }) => load();
}

/// A clock the test moves by hand.
class _Clock {
  DateTime now = DateTime(2026, 10, 3, 9);
  DateTime call() => now;
  void advance(Duration by) => now = now.add(by);
}

class _Harness {
  _Harness({bool restAlerts = true})
    : notifications = _Notifications(restAlerts: restAlerts);

  final repository = _Repository();
  final alerts = _Alerts();
  late final activity = FakeWorkoutActivityBridge(clock: clock.call);
  final clock = _Clock();
  final _Notifications notifications;
  Object? popped = 'not popped';
}

Future<void> _open(
  WidgetTester tester,
  _Harness h, {
  ThemeData? theme,
  TracendMotionLevel? motion,
  Size size = const Size(390, 844),
  WorkoutEventHub? events,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app = MaterialApp(
    theme: theme ?? TracendTheme.dark,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              h.popped = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => ActiveWorkoutScreen(
                    workout: _workout,
                    repository: h.repository,
                    restAlerts: h.alerts,
                    notifications: h.notifications,
                    clock: h.clock.call,
                    events: events,
                    activity: h.activity,
                  ),
                ),
              );
            },
            child: const Text('Open workout'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    motion == null ? app : TracendMotionScope(level: motion, child: app),
  );
  await tester.tap(find.text('Open workout'));
  await tester.pumpAndSettle();
}

String _field(WidgetTester tester, int index) =>
    tester.widget<TextField>(find.byType(TextField).at(index)).controller!.text;

/// Scrolls the exercise page until [finder] is built, when it is not yet.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) return;
  final page = find.descendant(
    of: find.byType(FocusExercisePage),
    matching: find.byType(Scrollable),
  );
  if (page.evaluate().isEmpty) return;
  await tester.scrollUntilVisible(finder, 200, scrollable: page.first);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _tapLabel(WidgetTester tester, String label) =>
    _tap(tester, find.bySemanticsLabel(label));

Future<void> _tapText(WidgetTester tester, String text) =>
    _tap(tester, find.text(text));

final _finishButton = find.widgetWithText(FilledButton, 'Finish workout');

/// Lets the 250 ms autosave run.
Future<void> _flushSave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'a full workout: log, rest, new best, finish with effort, summary',
    (tester) async {
      final haptics = recordHaptics(tester);
      final h = _Harness();
      await _open(tester, h);

      expect(find.text('Upper A'), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('Bench press'), findsOneWidget);
      expect(find.text('Set 1 of 2'), findsOneWidget);
      expect(find.text('Chest, Shoulders, Triceps'), findsOneWidget);
      // Last time beats the plan's starting load as the suggestion.
      expect(_field(tester, 0), '60');
      expect(_field(tester, 1), '8');
      expect(find.text('From last time'), findsOneWidget);
      expect(find.textContaining('60 kg × 8'), findsWidgets);
      expect(
        find.bySemanticsLabel(RegExp('Set 1 weight in kilograms')),
        findsOneWidget,
      );

      h.clock.advance(const Duration(minutes: 2, seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2:05'), findsOneWidget);

      await _tapLabel(tester, 'More weight');
      expect(_field(tester, 0), '62.5');
      haptics.clear();
      await _tapText(tester, 'Done set 1');

      // 62.5 × 8 beats the best of 60 × 8: the big moment.
      expect(haptics, contains('HapticFeedbackType.mediumImpact'));
      expect(h.repository.savedSet(0, 0)['completed'], isTrue);
      expect(h.repository.savedSet(0, 0)['load_kg'], '62.5');

      // The rest takes over, with what comes next and the set's effort.
      expect(find.byType(RestTimerOverlay), findsOneWidget);
      expect(find.text('Set 2 of Bench press'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
      expect(h.alerts.scheduled, [90]);
      final rest = RestTimer.fromJson(
        h.repository.savedDraft[RestTimer.draftKey],
      );
      expect(
        rest?.endsAt.isAtSameMomentAs(
          h.clock.now.add(const Duration(seconds: 90)),
        ),
        isTrue,
      );

      expect(find.text('Reps left on set 1'), findsOneWidget);
      await _tapLabel(tester, '2 reps left');
      expect(
        tester.getSemantics(find.bySemanticsLabel('2 reps left').first),
        matchesSemantics(
          label: '2 reps left',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isEnabled: true,
          hasEnabledState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      await _flushSave(tester);
      expect(h.repository.savedSet(0, 0)['rir'], 2);
      // The effort the same answer meant on the earlier 1–10 picker.
      expect(h.repository.savedSet(0, 0)['rpe'], '8');

      await _tapLabel(tester, '15 seconds more rest');
      expect(find.text('1:45'), findsOneWidget);
      expect(h.alerts.scheduled.last, 105);

      // The end of the rest: a success haptic and a toast.
      haptics.clear();
      h.clock.advance(const Duration(seconds: 106));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(RestTimerOverlay), findsNothing);
      expect(haptics, contains('HapticFeedbackType.successNotification'));
      expect(
        find.text('Rest is over. Next: Set 2 of Bench press'),
        findsOneWidget,
      );
      expect(h.alerts.cancels, greaterThan(0));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // The new best is marked on the logged set.
      expect(
        find.byWidgetPredicate((w) => w is NewBestStamp && !w.large),
        findsOneWidget,
      );

      // Set 2 starts from set 1. Equal to it is not a new best.
      expect(_field(tester, 0), '62.5');
      expect(find.text('From your last set'), findsOneWidget);
      haptics.clear();
      await _tapText(tester, 'Done set 2');
      expect(haptics, isNot(contains('HapticFeedbackType.mediumImpact')));
      expect(find.text('Push-up'), findsWidgets);

      // Hide the rest to the pill, then skip it.
      await _tapLabel(tester, 'Hide rest timer');
      expect(find.byType(RestTimerOverlay), findsNothing);
      expect(find.byType(RestTimerPill), findsOneWidget);
      expect(find.text('Next: Push-up'), findsOneWidget);
      final cancels = h.alerts.cancels;
      await _tapLabel(tester, 'Skip rest');
      expect(find.byType(RestTimerPill), findsNothing);
      expect(h.alerts.cancels, cancels + 1);

      await _tapText(tester, 'Next exercise');
      expect(find.text('Exercise 2 of 2'), findsOneWidget);
      expect(find.text('No earlier sets for this exercise.'), findsOneWidget);
      // Bodyweight: no load, reps from the plan.
      expect(_field(tester, 0), '');
      expect(_field(tester, 1), '12');
      await _tapText(tester, 'Done set 1');
      await _tapLabel(tester, 'Skip rest');
      expect(find.byType(FirstLogTag), findsWidgets);

      // Finish: effort is required, nothing is preselected.
      await _tapLabel(tester, 'Finish workout');
      expect(find.text('How hard was this workout overall?'), findsOneWidget);
      expect(
        find.text('1 set is not logged. It stays unlogged, not skipped.'),
        findsOneWidget,
      );
      await _tap(tester, _finishButton);
      expect(find.text('Pick a number from 1 to 10 first.'), findsOneWidget);
      expect(h.repository.efforts, isEmpty);
      await _tapLabel(tester, '7, Hard');
      expect(find.text('7, Hard'), findsWidgets);
      haptics.clear();
      await _tap(tester, _finishButton);

      expect(h.repository.efforts, [7]);
      expect(h.repository.lastDuration, 125 + 106);
      expect(haptics, contains('HapticFeedbackType.successNotification'));
      expect(find.text('Workout complete'), findsOneWidget);
      expect(find.text('Weight lifted'), findsOneWidget);
      // 62.5 × 8 twice; the push-ups add nothing.
      expect(find.textContaining('1,000'), findsOneWidget);
      expect(
        find.text('Counts sets with added weight, as you logged them.'),
        findsOneWidget,
      );
      expect(find.text('Bench press 62.5 kg × 8'), findsOneWidget);
      expect(find.text('Previous best 60 kg × 8'), findsOneWidget);
      expect(find.text('7, Hard'), findsOneWidget);

      await _tapText(tester, 'Done');
      expect(h.popped, isTrue);
      expect(find.text('Workout saved'), findsOneWidget);
      expect(h.repository.saved, isNull);
    },
  );

  testWidgets('un-ticking a new best takes the mark away', (tester) async {
    final h = _Harness();
    await _open(tester, h);
    await _tapLabel(tester, 'More weight');
    await _tapText(tester, 'Done set 1');
    await _tapLabel(tester, 'Hide rest timer');
    expect(
      find.byWidgetPredicate((w) => w is NewBestStamp && !w.large),
      findsOneWidget,
    );

    await _tapLabel(tester, 'Undo set 1');
    await _flushSave(tester);
    expect(find.byType(NewBestStamp), findsNothing);
    expect(h.repository.savedSet(0, 0)['completed'], isFalse);
    expect(find.text('Done set 1'), findsOneWidget);
  });

  testWidgets('Fill reps left fills only the logged sets without it', (
    tester,
  ) async {
    final h = _Harness();
    await _open(tester, h);
    await _tapText(tester, 'Done set 1');
    await _tapLabel(tester, '1 rep left');
    await _tapLabel(tester, 'Skip rest');
    await _tapText(tester, 'Done set 2');
    await _tapLabel(tester, 'Skip rest');

    await _tapLabel(tester, 'Fill reps left');
    expect(find.text('Fill reps left for sets without it'), findsOneWidget);
    await _tapLabel(tester, '3 reps left');
    expect(find.text('Reps left 3 added to 1 set'), findsOneWidget);
    await _flushSave(tester);
    expect(h.repository.savedSet(0, 0)['rir'], 1);
    expect(h.repository.savedSet(0, 1)['rir'], 3);
    expect(h.repository.savedSet(0, 1)['rpe'], '7');

    // Each set stays adjustable afterwards.
    await _tapLabel(tester, 'Reps left for set 2: 3 reps left, change');
    await _tapLabel(tester, '5 or more reps left');
    await _flushSave(tester);
    expect(find.text('5+ left'), findsOneWidget);
    expect(h.repository.savedSet(0, 1)['rir'], 5);
    expect(h.repository.savedSet(0, 1)['rpe'], '5');
    expect(h.repository.savedSet(0, 0)['rir'], 1);
  });

  testWidgets('sets from an older draft keep the server\'s timing and RPE', (
    tester,
  ) async {
    const timingKeys = [
      'started_at',
      'completed_at',
      'rest_before_seconds',
      'rir',
      'timing_source',
    ];
    final h = _Harness();
    Map<String, dynamic> set(int number, String rpe) => {
      'number': number,
      'load_kg': '60',
      'repetitions': '8',
      'rpe': rpe,
      'completed': true,
    };
    // Saved by a build from before set timing: no Contract 2 keys.
    h.repository.saved = jsonEncode({
      'workout_id': 'upper-a',
      'session_id': 'server-session',
      'idempotency_key': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'revision': 3,
      'actual_started_at': h.clock.now
          .subtract(const Duration(minutes: 10))
          .toUtc()
          .toIso8601String(),
      'exercises': [
        {
          'order': 1,
          'status': 'unknown',
          'pain_flag': false,
          'sets': [set(1, '8'), set(2, '')],
        },
        // Every set done, so the workout opens on the first exercise.
        {
          'order': 2,
          'status': 'unknown',
          'pain_flag': false,
          'sets': [set(1, ''), set(2, '')],
        },
      ],
    });
    await _open(tester, h, size: const Size(390, 1400));
    await _flushSave(tester);
    for (final key in timingKeys) {
      expect(h.repository.syncedSet(0, 0).containsKey(key), isFalse);
      expect(h.repository.syncedSet(0, 1).containsKey(key), isFalse);
    }
    // The older RPE 8 reads as answered, so Fill leaves it alone.
    expect(find.text('2 left'), findsOneWidget);
    await _tapLabel(tester, 'Fill reps left');
    await _tapLabel(tester, '3 reps left');
    expect(find.text('Reps left 3 added to 1 set'), findsOneWidget);
    await _flushSave(tester);
    final older = h.repository.syncedSet(0, 0);
    expect(older['rpe'], '8');
    expect(older.containsKey('rir'), isFalse);
    final filled = h.repository.syncedSet(0, 1);
    expect((filled['rir'], filled['rpe']), (3, '7'));
    expect(filled.containsKey('started_at'), isFalse);

    // Un-ticking is a clear the server must receive.
    await _tapLabel(tester, 'Undo set 1');
    await _flushSave(tester);
    final undone = h.repository.syncedSet(0, 0);
    for (final key in timingKeys) {
      expect(undone.containsKey(key), isTrue, reason: key);
      expect(undone[key], isNull, reason: key);
    }
  });

  testWidgets('Fill reps left before any set asks for a set first', (
    tester,
  ) async {
    final h = _Harness();
    await _open(tester, h);
    await _tapLabel(tester, 'Fill reps left');
    expect(find.text('Log a set first'), findsOneWidget);
    expect(find.text('Fill reps left for sets without it'), findsNothing);
  });

  testWidgets('Finish with no sets asks for a set first', (tester) async {
    final haptics = recordHaptics(tester);
    final h = _Harness();
    await _open(tester, h);
    await _tapLabel(tester, 'Finish workout');
    expect(find.text('Tick at least one set first.'), findsOneWidget);
    expect(find.text('How hard was this workout overall?'), findsNothing);
    expect(haptics, contains('HapticFeedbackType.warningNotification'));
  });

  testWidgets('discard is confirmed, abandons the session and stops rest', (
    tester,
  ) async {
    final h = _Harness();
    await _open(tester, h);
    await _tapText(tester, 'Done set 1');
    final cancels = h.alerts.cancels;

    await _tapLabel(tester, 'Leave workout');
    expect(find.text('Leave this workout?'), findsOneWidget);
    expect(find.text('Save and leave'), findsOneWidget);
    expect(find.text('Keep logging'), findsOneWidget);
    await tester.tap(find.text('Discard workout'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this workout?'), findsOneWidget);
    await tester.tap(find.text('Discard workout').last);
    await tester.pumpAndSettle();

    expect(h.repository.abandoned, ['server-session']);
    expect(h.alerts.cancels, greaterThan(cancels));
    expect(h.popped, isFalse);
    expect(find.text('Workout discarded'), findsOneWidget);
  });

  testWidgets('cancelling the discard keeps the workout', (tester) async {
    final h = _Harness();
    await _open(tester, h);
    await _tapLabel(tester, 'Leave workout');
    await tester.tap(find.text('Discard workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.repository.abandoned, isEmpty);
    expect(find.text('Bench press'), findsOneWidget);
  });

  testWidgets('the back gesture asks before leaving; save keeps the draft', (
    tester,
  ) async {
    final h = _Harness();
    await _open(tester, h);
    await _tapText(tester, 'Done set 1');
    await _tapLabel(tester, 'Skip rest');

    // The edge swipe and the system back both ask the route to pop.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Leave this workout?'), findsOneWidget);
    expect(
      find.text('1 set is saved on your phone. You can carry on later today.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep logging'));
    await tester.pumpAndSettle();
    expect(find.text('Bench press'), findsOneWidget);
    expect(h.popped, 'not popped');

    await navigator.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save and leave'));
    await tester.pumpAndSettle();
    expect(h.popped, isFalse);
    expect(find.text('Workout paused'), findsOneWidget);
    expect(h.repository.savedSet(0, 0)['completed'], isTrue);
    expect(h.repository.savedDraft.containsKey(RestTimer.draftKey), isFalse);
  });

  testWidgets(
    'a pull down hides the rest even where the scroll view takes drags',
    (tester) async {
      final h = _Harness();
      await _open(tester, h);
      await _tapText(tester, 'Done set 1');
      await tester.drag(
        find.text('Swipe down to keep editing'),
        const Offset(0, 220),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RestTimerOverlay), findsNothing);
      expect(find.byType(RestTimerPill), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('the rest Live Activity gets the exercise and the next set', (
    tester,
  ) async {
    final h = _Harness();
    await _open(tester, h);
    await _tapText(tester, 'Done set 1');

    final start = h.activity.calls.lastWhere(
      (call) => call.method == 'startRest',
    );
    expect(start.exerciseName, 'Bench press');
    expect(start.nextLabel, 'Set 2 of Bench press');
    expect(
      start.endsAt!.isAtSameMomentAs(
        h.clock.now.add(const Duration(seconds: 90)),
      ),
      isTrue,
    );

    // Skip turns it to "Rest done" now, so the next set's Done can follow.
    await _tapLabel(tester, 'Skip rest');
    expect(h.activity.methods.last, 'updateRest');
    expect(h.activity.showingUntil, h.clock.now);
  });

  group('the Live Activity buttons', () {
    DateTime? time(Object? value) =>
        value is String ? DateTime.parse(value).toLocal() : null;

    testWidgets('a whole workout runs from the Lock Screen', (tester) async {
      final h = _Harness();
      await _open(tester, h);
      final t0 = h.clock.now;
      expect(h.activity.onPress, isNotNull);

      // Set 1 is ticked in the app; its rest starts the activity.
      await _tapText(tester, 'Done set 1');

      // +30s, then Skip, then Done for set 2, all from the Lock Screen.
      h.clock.advance(const Duration(seconds: 40));
      expect(await h.activity.pressAdd(30), isTrue);
      expect(h.activity.calls.last.method, 'updateRest');
      expect(h.activity.showingUntil, t0.add(const Duration(seconds: 120)));

      h.clock.advance(const Duration(seconds: 20));
      expect(await h.activity.pressSkip(), isTrue);
      expect(h.activity.showingUntil, h.clock.now);

      h.clock.advance(const Duration(seconds: 45));
      expect(await h.activity.pressDone(), isTrue);
      final rest = h.activity.calls.last;
      expect(rest.method, 'startRest');
      expect(rest.exerciseName, 'Bench press');
      expect(rest.nextLabel, 'Push-up');

      // Each press returned only after the draft on the phone had it.
      expect(h.repository.savedSet(0, 1)['completed'], isTrue);
      expect(h.repository.savedSet(0, 1)['rest_before_seconds'], 60);

      // The rest runs out while the phone sleeps; Done ticks Push-up set 1.
      h.clock.advance(const Duration(minutes: 3));
      expect(await h.activity.pressDone(), isTrue);
      expect(h.repository.savedSet(1, 0)['completed'], isTrue);
      expect(h.repository.savedSet(1, 0)['rest_before_seconds'], 90);
      expect(h.activity.calls.last.nextLabel, 'Set 2 of Push-up');

      // The last set has no rest after it: the activity goes.
      h.clock.advance(const Duration(seconds: 75));
      expect(await h.activity.pressDone(), isTrue);
      expect(h.repository.savedSet(1, 1)['completed'], isTrue);
      expect(h.activity.methods.last, 'end');
      expect(h.activity.showingUntil, isNull);
      await _flushSave(tester);
    });

    testWidgets('Skip after the rest ran out unnoticed keeps its real end', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h);
      final t0 = h.clock.now;
      await _tapText(tester, 'Done set 1');

      h.clock.advance(const Duration(minutes: 4));
      expect(await h.activity.pressSkip(), isTrue);
      expect(h.activity.methods.last, 'startRest');

      await _tapText(tester, 'Done set 2');
      await _flushSave(tester);
      expect(
        time(h.repository.syncedSet(0, 1)['started_at']),
        t0.add(const Duration(seconds: 90)),
      );
    });

    testWidgets('"Rest done" goes two minutes after the rest in the app', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h);
      await _tapText(tester, 'Done set 1');
      await _tapLabel(tester, 'Skip rest');

      h.clock.advance(const Duration(seconds: 119));
      await tester.pump(const Duration(seconds: 1));
      expect(h.activity.methods.last, 'updateRest');

      h.clock.advance(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(h.activity.methods.last, 'end');
      await _tapLabel(tester, 'Leave workout');
      await tester.tap(find.text('Save and leave'));
      await tester.pumpAndSettle();
    });

    testWidgets('a double press on Done ticks one set, not two', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h);
      await _tapText(tester, 'Done set 1');
      expect(await h.activity.pressSkip(), isTrue);

      // The same card, tapped twice before the first tick shows.
      final answers = await Future.wait([
        h.activity.pressDone(),
        h.activity.pressDone(),
      ]);

      expect(answers, [true, true]);
      expect(h.repository.savedSet(0, 1)['completed'], isTrue);
      expect(h.repository.savedSet(1, 0)['completed'], isFalse);
      // The second press changed nothing and the card shows the new rest.
      expect(h.activity.methods.last, 'updateRest');
      expect(
        h.activity.showingUntil,
        h.clock.now.add(const Duration(seconds: 90)),
      );
      await _flushSave(tester);
    });

    testWidgets('a stale Done after an in-app tick ticks nothing', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h);
      await _tapText(tester, 'Done set 1');
      await _tapLabel(tester, 'Skip rest');
      final stale = h.activity.card!;

      // The athlete ticks the same set in the app, rests and skips again.
      await _tapText(tester, 'Done set 2');
      await _tapLabel(tester, 'Skip rest');
      final showing = h.activity.showingUntil;

      expect(
        await h.activity.pressDone(
          exerciseOrder: stale.exerciseOrder,
          setNumber: stale.setNumber,
        ),
        isTrue,
      );
      expect(h.repository.savedSet(1, 0)['completed'], isFalse);
      expect(h.activity.showingUntil, showing);
      expect(h.activity.methods.last, isNot('end'));

      // The card now names Push-up set 1; its Done still works.
      expect(await h.activity.pressDone(), isTrue);
      expect(h.repository.savedSet(1, 0)['completed'], isTrue);
      await _flushSave(tester);
    });

    testWidgets('Done during a rest ticks nothing and redraws the card', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h);
      await _tapText(tester, 'Done set 1');
      final ends = h.activity.showingUntil;
      final calls = h.activity.calls.length;

      expect(await h.activity.pressDone(), isTrue);

      expect(h.repository.savedSet(0, 1)['completed'], isFalse);
      expect(h.activity.calls.length, calls + 1);
      expect(h.activity.methods.last, 'updateRest');
      expect(h.activity.showingUntil, ends);
      await _flushSave(tester);
    });

    testWidgets('a press that waited past the timeout is dropped', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h);
      await _tapText(tester, 'Done set 1');
      expect(await h.activity.pressSkip(), isTrue);
      final late = h.clock.now.subtract(
        LiveActivityButton.pressTimeout + const Duration(seconds: 1),
      );

      expect(await h.activity.pressDone(at: late), isFalse);
      expect(h.repository.savedSet(0, 1)['completed'], isFalse);

      // Just inside the timeout it still counts.
      final edge = h.clock.now.subtract(LiveActivityButton.pressTimeout);
      expect(await h.activity.pressDone(at: edge), isTrue);
      expect(h.repository.savedSet(0, 1)['completed'], isTrue);
      await _flushSave(tester);
    });

    testWidgets('a Done reaches the server before the press answers', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h);
      await _tapText(tester, 'Done set 1');
      expect(await h.activity.pressSkip(), isTrue);

      expect(await h.activity.pressDone(), isTrue);

      // No timer has fired: the press itself sent the draft.
      expect(h.repository.syncedSet(0, 1)['completed'], isTrue);
      await _flushSave(tester);
    });

    testWidgets('a press answers only after the activity update finished', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h);
      await _tapText(tester, 'Done set 1');
      final update = Completer<void>();
      h.activity.hold = update.future;
      final until = h.activity.showingUntil;

      bool? answer;
      unawaited(h.activity.pressSkip().then((v) => answer = v));
      await tester.pump(const Duration(milliseconds: 100));

      // The workout changed and the update was sent, but the card has not
      // moved yet, so the press has not answered.
      expect(h.activity.methods.last, 'updateRest');
      expect(h.activity.showingUntil, until);
      expect(answer, isNull);

      update.complete();
      await tester.pump(const Duration(milliseconds: 100));
      expect(answer, isTrue);
      expect(h.activity.showingUntil, h.clock.now);
    });

    testWidgets('a hanging activity update still lets the press answer', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h);
      await _tapText(tester, 'Done set 1');
      expect(await h.activity.pressSkip(), isTrue);
      h.activity.hold = Completer<void>().future;

      bool? answer;
      unawaited(h.activity.pressDone().then((v) => answer = v));
      await tester.pump(const Duration(seconds: 1));
      expect(answer, isNull);

      await tester.pump(const Duration(seconds: 1));
      expect(answer, isTrue);
      // The set is logged on the phone whatever the card did.
      expect(h.repository.savedSet(0, 1)['completed'], isTrue);
      await _flushSave(tester);
    });

    testWidgets('a failed activity update never undoes the press', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h);
      await _tapText(tester, 'Done set 1');
      h.activity.failWith = StateError('no activity');

      expect(await h.activity.pressSkip(), isTrue);

      expect(h.activity.methods.last, 'updateRest');
      await _tapText(tester, 'Done set 2');
      await _flushSave(tester);
      expect(h.repository.savedSet(0, 1)['completed'], isTrue);
    });

    testWidgets('a failed server send never blocks a logged set', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h);
      await _tapText(tester, 'Done set 1');
      expect(await h.activity.pressSkip(), isTrue);
      h.repository.failSync = true;

      expect(await h.activity.pressDone(), isTrue);

      expect(h.repository.savedSet(0, 1)['completed'], isTrue);
      expect(h.activity.methods.last, 'startRest');
      await tester.pump();
      expect(find.text('Offline'), findsOneWidget);
      h.repository.failSync = false;
      await _flushSave(tester);
    });

    testWidgets('Skip and +30s with no rest running change nothing', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h);
      await _tapText(tester, 'Done set 1');
      expect(await h.activity.pressSkip(), isTrue);
      final calls = h.activity.calls.length;

      expect(await h.activity.pressSkip(), isTrue);
      expect(await h.activity.pressAdd(30), isTrue);

      expect(h.activity.calls.length, calls);
      await _flushSave(tester);
    });

    testWidgets('once the workout is closed the buttons find no workout', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h);
      await _tapText(tester, 'Done set 1');
      await _tapLabel(tester, 'Leave workout');
      await tester.tap(find.text('Save and leave'));
      await tester.pumpAndSettle();

      expect(h.activity.onPress, isNull);
      expect(
        await h.activity.pressDone(exerciseOrder: 1, setNumber: 2),
        isFalse,
      );
      expect(h.activity.showingUntil, isNull);
    });
  });

  testWidgets('the screen torn down mid-rest ends only the Live Activity', (
    tester,
  ) async {
    final h = _Harness();
    await _open(tester, h);
    await _tapText(tester, 'Done set 1');
    await _flushSave(tester);
    final cancels = h.alerts.cancels;
    expect(h.activity.showingUntil, isNotNull);

    // The app returns to sign-in: the screen goes without Leave or Finish.
    await tester.pumpWidget(const SizedBox());

    expect(h.activity.methods.last, 'end');
    expect(h.activity.showingUntil, isNull);
    expect(h.alerts.cancels, cancels);
    expect(h.repository.savedDraft[RestTimer.draftKey], isNotNull);
  });

  testWidgets('rest alerts stay off unless the athlete turned them on', (
    tester,
  ) async {
    final h = _Harness(restAlerts: false);
    await _open(tester, h);
    await _tapText(tester, 'Done set 1');
    expect(find.byType(RestTimerOverlay), findsOneWidget);
    expect(h.alerts.scheduled, isEmpty);
    await _tapLabel(tester, 'Skip rest');
    expect(h.alerts.cancels, greaterThan(0));
  });

  testWidgets('a running rest comes back from the draft as the pill', (
    tester,
  ) async {
    final h = _Harness();
    h.repository.saved = jsonEncode({
      'workout_id': 'upper-a',
      'session_id': 'server-session',
      'idempotency_key': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'revision': 3,
      'actual_started_at': h.clock.now
          .subtract(const Duration(minutes: 10))
          .toUtc()
          .toIso8601String(),
      'exercises': [
        {
          'order': 1,
          'status': 'unknown',
          'pain_flag': false,
          'sets': [
            {
              'number': 1,
              'load_kg': '60',
              'repetitions': '8',
              'rpe': '',
              'completed': true,
            },
            {
              'number': 2,
              'load_kg': '',
              'repetitions': '',
              'rpe': '',
              'completed': false,
            },
          ],
        },
      ],
      RestTimer.draftKey: RestTimer.start(60, now: h.clock.now).toJson(),
    });
    await _open(tester, h);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.byType(RestTimerPill), findsOneWidget);
    expect(find.text('1:00'), findsOneWidget);
    expect(find.text('Set 2 of 2'), findsOneWidget);
  });

  for (final cleared in [true, false]) {
    testWidgets(
      cleared
          ? 'a load cleared on purpose stays empty after reopening'
          : 'an untouched empty load is suggested after reopening',
      (tester) async {
        final h = _Harness();
        h.repository.saved = jsonEncode({
          'workout_id': 'upper-a',
          'session_id': 'server-session',
          'idempotency_key': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'revision': 3,
          'actual_started_at': h.clock.now.toUtc().toIso8601String(),
          'exercises': [
            {
              'order': 1,
              'status': 'unknown',
              'pain_flag': false,
              'sets': [
                {
                  'number': 1,
                  'load_kg': '60',
                  'repetitions': '8',
                  'rpe': '',
                  'completed': true,
                },
                {
                  'number': 2,
                  'load_kg': '',
                  'repetitions': '',
                  'rpe': '',
                  'completed': false,
                },
              ],
            },
          ],
          if (cleared)
            'cleared_loads': [
              {'order': 1, 'number': 2},
            ],
        });
        await _open(tester, h);
        expect(find.text('Set 2 of 2'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('kg-0-1')),
            matching: find.text('60'),
          ),
          cleared ? findsNothing : findsWidgets,
        );
        // The marker lives only in the phone's draft and survives the save.
        expect(
          h.repository.savedDraft['cleared_loads'],
          cleared
              ? [
                  {'order': 1, 'number': 2},
                ]
              : isEmpty,
        );
      },
    );
  }

  testWidgets('offline sync keeps the draft and says Offline', (tester) async {
    final h = _Harness();
    h.repository.failSync = true;
    await _open(tester, h);
    await _tapText(tester, 'Done set 1');
    await _flushSave(tester);
    expect(h.repository.saved, isNotNull);
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('a failed finish waits on the phone and can be sent again', (
    tester,
  ) async {
    final h = _Harness();
    h.repository.failComplete = true;
    await _open(tester, h);
    await _tapText(tester, 'Done set 1');
    await _tapLabel(tester, 'Skip rest');
    await _tapLabel(tester, 'Finish workout');
    await _tapLabel(tester, '6, Moderate');
    await _tap(tester, _finishButton);

    expect(find.text('Finish not sent yet'), findsOneWidget);
    expect(find.textContaining('Finishing needs a connection'), findsOneWidget);
    h.repository.failComplete = false;
    await _tapText(tester, 'Send finish');
    expect(h.repository.efforts, [6]);
    expect(find.text('Workout complete'), findsOneWidget);
  });

  testWidgets('a finish saved on the phone is offered on reopening', (
    tester,
  ) async {
    final h = _Harness();
    h.repository.pending = PendingWorkoutFinish(
      sessionEffort: 9,
      durationSeconds: 2400,
    );
    h.repository.serverSession = {
      'session_id': 'server-session',
      'state': 'in_progress',
      'revision': 2,
      'idempotency_key': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'actual_started_at': '2026-10-03T08:00:00Z',
      'exercises': [
        {
          'order': 1,
          'status': 'unknown',
          'pain_flag': true,
          'sets': [
            {
              'number': 1,
              'load_kg': 60.0,
              'repetitions': 8,
              'rpe': 8.0,
              'completed': true,
            },
          ],
        },
      ],
    };
    await _open(tester, h, size: const Size(390, 1400));
    expect(find.text('Finish not sent yet'), findsOneWidget);
    expect(find.text('Pain noted'), findsOneWidget);
    expect(find.text('2 left'), findsOneWidget);
    await _tapText(tester, 'Send finish');
    expect(h.repository.efforts, [9]);
    expect(h.repository.lastDuration, 2400);
  });

  testWidgets('sessions past three hours warn and save as 180 minutes', (
    tester,
  ) async {
    final h = _Harness();
    h.repository.serverSession = {
      'session_id': 'server-session',
      'state': 'in_progress',
      'revision': 2,
      'idempotency_key': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'actual_started_at': h.clock.now
          .subtract(const Duration(hours: 4))
          .toUtc()
          .toIso8601String(),
      'exercises': const [],
    };
    await _open(tester, h);
    expect(find.text('Over 3 hours'), findsOneWidget);
    await _tapText(tester, 'Done set 1');
    await _tapLabel(tester, 'Skip rest');
    await _tapLabel(tester, 'Finish workout');
    await _tapLabel(tester, '5, Moderate');
    await _tap(tester, _finishButton);
    expect(h.repository.lastDuration, ActiveWorkoutScreen.maxSessionSeconds);
  });

  testWidgets('skipped lives in the more menu; pain stays visible', (
    tester,
  ) async {
    final h = _Harness();
    await _open(tester, h);
    expect(find.text('Pain or discomfort'), findsOneWidget);
    await _tapLabel(tester, 'Pain or discomfort');
    expect(find.text('Pain noted'), findsOneWidget);

    await _tapLabel(tester, 'More for Bench press');
    await tester.tap(find.text('Mark as skipped'));
    await tester.pumpAndSettle();
    await _flushSave(tester);
    final exercise =
        (h.repository.savedDraft['exercises'] as List).first as Map;
    expect(exercise['status'], 'skipped');
    expect(exercise['pain_flag'], isTrue);
    expect(find.text('Exercise 1 of 2, skipped'), findsOneWidget);
  });

  testWidgets('history offline says so instead of inventing a best', (
    tester,
  ) async {
    final h = _Harness();
    h.repository.history = const ExerciseHistoryResult(
      exercises: {},
      fromCache: true,
    );
    await _open(tester, h);
    expect(find.text('Last time and best need a connection.'), findsOneWidget);
    // The plan's starting load and lowest rep target are the starting point.
    expect(_field(tester, 0), '55');
    expect(_field(tester, 1), '8');
    expect(find.text('From your plan'), findsOneWidget);
    await _tapLabel(tester, 'More weight');
    await _tapText(tester, 'Done set 1');
    await _tapLabel(tester, 'Hide rest timer');
    expect(find.byType(NewBestStamp), findsNothing);
    expect(find.byType(FirstLogTag), findsNothing);
  });

  testWidgets(
    'a finished workout is read-only; Apple Health only when it says so',
    (tester) async {
      for (final source in ['manual', 'healthkit']) {
        final h = _Harness();
        h.repository.serverSession = {
          'session_id': 'done-session',
          'state': 'completed',
          'completion_source': source,
          'duration_seconds': 2700,
          'exercises': [
            {
              'order': 1,
              'status': 'performed',
              'pain_flag': false,
              'sets': [
                {
                  'number': 1,
                  'load_kg': 60,
                  'repetitions': 8,
                  'rpe': 8,
                  'completed': true,
                },
              ],
            },
          ],
        };
        await _open(tester, h);
        expect(find.text('Completed · 45 min'), findsOneWidget);
        expect(find.text('Done set 1'), findsNothing);
        expect(find.text('60 kg × 8'), findsOneWidget);
        expect(
          find.text('Marked complete from Apple Health'),
          source == 'healthkit' ? findsOneWidget : findsNothing,
        );
        await _tapLabel(tester, 'Done');
        expect(h.popped, isNull);
      }
    },
  );

  group('motion', () {
    Future<void> logNewBest(WidgetTester tester) async {
      await _tapLabel(tester, 'More weight');
      await tester.tap(find.text('Done set 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('full motion slides the rest in and stamps a new best', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h, motion: TracendMotionLevel.full);
      await logNewBest(tester);
      expect(
        find.ancestor(
          of: find.byType(RestTimerOverlay),
          matching: find.byType(SlideTransition),
        ),
        findsWidgets,
      );
      expect(
        find.byWidgetPredicate((w) => w is NewBestStamp && w.large),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
      await _tapLabel(tester, 'Skip rest');
    });

    testWidgets('Reduce Motion crossfades the rest and fades the stamp in', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h, motion: TracendMotionLevel.reduced);
      await logNewBest(tester);
      expect(
        find.ancestor(
          of: find.byType(RestTimerOverlay),
          matching: find.byType(SlideTransition),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byType(RestTimerOverlay),
          matching: find.byType(FadeTransition),
        ),
        findsWidgets,
      );
      expect(
        find.byWidgetPredicate((w) => w is NewBestStamp && w.large),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
      await _tapLabel(tester, 'Skip rest');
    });
  });

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('fits 320 pt at 2× text (${brightness.name})', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final h = _Harness();
      await _open(
        tester,
        h,
        theme: brightness == Brightness.dark
            ? TracendTheme.dark
            : TracendTheme.light,
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
      await _tapText(tester, 'Done set 1');
      expect(tester.takeException(), isNull);
      await _tapLabel(tester, 'Hide rest timer');
      expect(find.byType(RestTimerPill), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tapLabel(tester, 'Add reps left for set 1');
      expect(tester.takeException(), isNull);
      await _tapLabel(tester, 'Finish workout');
      expect(tester.takeException(), isNull);
      await _tapLabel(tester, '8, Hard');
      await _tap(tester, _finishButton);
      expect(find.text('Workout complete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('set timing and workout events', () {
    /// An event as a line, with times as seconds after [from].
    String describe(WorkoutEvent event, DateTime from) {
      String t(DateTime time) => '${time.difference(from).inSeconds}s';
      return switch (event) {
        SetStarted(:final exerciseOrder, :final setNumber) =>
          'started $exerciseOrder.$setNumber at ${t(event.at)}',
        SetCompleted(
          :final exerciseOrder,
          :final setNumber,
          :final reps,
          :final loadKg,
        ) =>
          'completed $exerciseOrder.$setNumber $loadKg×$reps at ${t(event.at)}',
        RestStarted(:final seconds, :final endsAt, :final nextLabel) =>
          'rest ${seconds}s to ${t(endsAt)}, next $nextLabel',
        RestAdjusted(:final endsAt) => 'rest now ends ${t(endsAt)}',
        ExerciseAdvanced(:final exerciseOrder, :final name) =>
          'exercise $exerciseOrder $name',
        WorkoutEnded(:final completed) => 'ended, completed: $completed',
      };
    }

    DateTime? time(Object? value) =>
        value is String ? DateTime.parse(value).toLocal() : null;

    testWidgets('set times follow the wall clock while the app is away', (
      tester,
    ) async {
      final h = _Harness();
      final hub = WorkoutEventHub();
      final events = <WorkoutEvent>[];
      hub.events.listen(events.add);
      await _open(tester, h, events: hub);
      final t0 = h.clock.now;

      // Set 1: an edit starts it, the tick ends it.
      h.clock.advance(const Duration(seconds: 10));
      await _tapLabel(tester, 'More weight');
      h.clock.advance(const Duration(seconds: 30));
      await _tapText(tester, 'Done set 1');
      expect(find.byType(RestTimerOverlay), findsOneWidget);

      // The phone sleeps through the 90 s rest; the app wakes 4 min later.
      h.clock.advance(const Duration(minutes: 4));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(RestTimerOverlay), findsNothing);

      // Set 2 began when the rest ended, not when the app noticed.
      h.clock.advance(const Duration(seconds: 20));
      await _tapText(tester, 'Done set 2');
      await _flushSave(tester);

      final first = h.repository.syncedSet(0, 0);
      expect(time(first['started_at']), t0.add(const Duration(seconds: 10)));
      expect(time(first['completed_at']), t0.add(const Duration(seconds: 40)));
      expect(first['rest_before_seconds'], isNull);
      expect(first['timing_source'], 'app');
      final second = h.repository.syncedSet(0, 1);
      expect(time(second['started_at']), t0.add(const Duration(seconds: 130)));
      expect(
        time(second['completed_at']),
        t0.add(const Duration(seconds: 300)),
      );
      expect(second['rest_before_seconds'], 90);
      expect(h.repository.savedSet(0, 1)['rest_before_seconds'], 90);

      expect(
        [for (final e in events) describe(e, t0)],
        [
          'started 1.1 at 10s',
          'completed 1.1 62.5×8 at 40s',
          'rest 90s to 130s, next Set 2 of Bench press',
          'started 1.2 at 130s',
          'completed 1.2 62.5×8 at 300s',
          'rest 90s to 390s, next Push-up',
        ],
      );
    });

    testWidgets('the Live Activity commands drive the workout', (tester) async {
      final h = _Harness();
      final hub = WorkoutEventHub();
      final events = <WorkoutEvent>[];
      hub.events.listen(events.add);
      await _open(tester, h, events: hub);
      final t0 = h.clock.now;

      hub.commands.add(
        const CompleteCurrentSet(exerciseOrder: 1, setNumber: 1),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RestTimerOverlay), findsOneWidget);

      h.clock.advance(const Duration(seconds: 50));
      hub.commands.add(const AddRest(30));
      await tester.pumpAndSettle();
      expect(h.alerts.scheduled.last, 70);
      h.clock.advance(const Duration(seconds: 10));
      hub.commands.add(const SkipRest());
      await tester.pumpAndSettle();
      expect(find.byType(RestTimerOverlay), findsNothing);

      h.clock.advance(const Duration(seconds: 30));
      hub.commands.add(
        const CompleteCurrentSet(exerciseOrder: 1, setNumber: 2),
      );
      await tester.pumpAndSettle();
      await _flushSave(tester);
      expect(h.repository.syncedSet(0, 1)['rest_before_seconds'], 60);
      expect(
        time(h.repository.syncedSet(0, 1)['started_at']),
        t0.add(const Duration(seconds: 60)),
      );

      await _tapLabel(tester, 'Skip rest');
      await _tapText(tester, 'Next exercise');
      await _tapLabel(tester, 'Leave workout');
      await tester.tap(find.text('Save and leave'));
      await tester.pumpAndSettle();
      hub.commands.add(
        const CompleteCurrentSet(exerciseOrder: 2, setNumber: 1),
      );
      await tester.pumpAndSettle();

      expect(
        [for (final e in events) describe(e, t0)],
        [
          'completed 1.1 60.0×8 at 0s',
          'rest 90s to 90s, next Set 2 of Bench press',
          'rest now ends 120s',
          'rest now ends 60s',
          'started 1.2 at 60s',
          'completed 1.2 60.0×8 at 90s',
          'rest 90s to 180s, next Push-up',
          'rest now ends 90s',
          'exercise 2 Push-up',
          'ended, completed: false',
        ],
      );
    });

    testWidgets('finishing ends the workout and the stream', (tester) async {
      final h = _Harness();
      final hub = WorkoutEventHub();
      final events = <WorkoutEvent>[];
      var done = false;
      hub.events.listen(events.add, onDone: () => done = true);
      await _open(tester, h, events: hub);
      await _tapText(tester, 'Done set 1');
      await _tapLabel(tester, 'Skip rest');
      await _tapLabel(tester, 'Finish workout');
      await _tapLabel(tester, '6, Moderate');
      await _tap(tester, _finishButton);
      await _tapText(tester, 'Done');

      expect(events.last, isA<WorkoutEnded>());
      expect((events.last as WorkoutEnded).completed, isTrue);
      expect(done, isTrue);
    });

    testWidgets('refused set times: the sets sync without them and finish', (
      tester,
    ) async {
      final h = _Harness();
      h.repository.refuseTimes = true;
      await _open(tester, h);
      await _tapText(tester, 'Done set 1');
      await _flushSave(tester);

      expect(h.repository.refusals, 1);
      final sent = h.repository.syncedSet(0, 0);
      expect(sent['completed'], isTrue);
      expect(sent['repetitions'], '8');
      for (final key in [
        'started_at',
        'completed_at',
        'rest_before_seconds',
        'rir',
        'timing_source',
      ]) {
        expect(sent.containsKey(key), isFalse, reason: key);
      }
      // The phone keeps its times and remembers the refusal.
      expect(h.repository.savedSet(0, 0)['completed_at'], isNotNull);
      expect(h.repository.savedDraft['timing_refused'], isTrue);
      expect(find.text('Saved'), findsOneWidget);

      await _tapLabel(tester, 'Skip rest');
      await _tapText(tester, 'Done set 2');
      await _flushSave(tester);
      expect(h.repository.refusals, 1);
      expect(h.repository.syncedSet(0, 1)['completed'], isTrue);

      await _tapLabel(tester, 'Skip rest');
      await _tapLabel(tester, 'Finish workout');
      await _tapLabel(tester, '7, Hard');
      await _tap(tester, _finishButton);
      expect(h.repository.efforts, [7]);
      expect(find.text('Workout complete'), findsOneWidget);
    });

    for (final code in ['22023', '55000']) {
      testWidgets('a refused final sync ($code) does not finish', (
        tester,
      ) async {
        final h = _Harness();
        await _open(tester, h);
        await _tapText(tester, 'Done set 1');
        await _tapLabel(tester, 'Skip rest');
        await _flushSave(tester);
        h.repository.refuseCode = code;

        await _tapLabel(tester, 'Finish workout');
        await _tapLabel(tester, '7, Hard');
        await _tap(tester, _finishButton);

        expect(h.repository.completeCalls, 0);
        expect(h.repository.efforts, isEmpty);
        expect(h.repository.saved, isNotNull);
        expect(h.repository.savedSet(0, 0)['completed'], isTrue);
        expect(find.text('Needs attention'), findsOneWidget);
        expect(find.text('Finish not sent yet'), findsOneWidget);
        expect(find.textContaining('could not save your sets'), findsOneWidget);
        expect(find.text('Workout complete'), findsNothing);

        // Once the server takes the sets, the finish goes through.
        h.repository.refuseCode = null;
        await _tapText(tester, 'Send finish');
        expect(h.repository.efforts, [7]);
        expect(find.text('Workout complete'), findsOneWidget);
      });
    }

    testWidgets('the server\'s start, read back, bounds the times sent', (
      tester,
    ) async {
      final h = _Harness();
      // The server's clock is 15 minutes ahead of the phone's.
      final serverStart = h.clock.now.add(const Duration(minutes: 15));
      h.repository.onStart = () => h.repository.serverSession = {
        'session_id': 'server-session',
        'state': 'in_progress',
        'revision': 0,
        'idempotency_key': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'actual_started_at': serverStart.toUtc().toIso8601String(),
        'exercises': const [],
      };
      await _open(tester, h);
      h.clock.advance(const Duration(seconds: 40));
      await _tapText(tester, 'Done set 1');
      await _flushSave(tester);

      final sent = h.repository.syncedSet(0, 0);
      expect(sent['completed'], isTrue);
      expect(sent.containsKey('completed_at'), isFalse);
      expect(h.repository.savedSet(0, 0)['completed_at'], isNotNull);
      expect(time(h.repository.savedDraft['server_started_at']), serverStart);
    });

    testWidgets('undo clears the set\'s times and remeasures the next rest', (
      tester,
    ) async {
      final h = _Harness();
      await _open(tester, h);
      final t0 = h.clock.now;
      h.clock.advance(const Duration(seconds: 30));
      await _tapText(tester, 'Done set 1');
      h.clock.advance(const Duration(seconds: 60));
      await _tapLabel(tester, 'Skip rest');
      h.clock.advance(const Duration(seconds: 30));
      await _tapText(tester, 'Done set 2');
      await _tapLabel(tester, 'Skip rest');
      await _flushSave(tester);
      expect(h.repository.savedSet(0, 1)['rest_before_seconds'], 60);

      await _tapLabel(tester, 'Undo set 1');
      await _flushSave(tester);
      final undone = h.repository.savedSet(0, 0);
      expect(undone['completed'], isFalse);
      for (final key in [
        'started_at',
        'completed_at',
        'rest_before_seconds',
        'rir',
        'timing_source',
      ]) {
        expect(undone[key], isNull, reason: key);
      }
      // Set 2 began at the skip; nothing done before it remains.
      expect(
        time(h.repository.savedSet(0, 1)['started_at']),
        t0.add(const Duration(seconds: 90)),
      );
      expect(h.repository.savedSet(0, 1)['rest_before_seconds'], isNull);
    });

    testWidgets('times from before an offline start stay on the phone', (
      tester,
    ) async {
      final h = _Harness();
      h.repository.failStart = true;
      await _open(tester, h);
      final t0 = h.clock.now;
      h.clock.advance(const Duration(seconds: 10));
      await _tapLabel(tester, 'More weight');
      h.clock.advance(const Duration(seconds: 30));
      await _tapText(tester, 'Done set 1');
      await _flushSave(tester);
      expect(h.repository.synced, isNull);

      // The connection returns: the server's session begins now.
      h.repository.failStart = false;
      h.clock.advance(const Duration(minutes: 20));
      await _tapLabel(tester, 'Skip rest');
      await _tapLabel(tester, 'One more rep');
      await _flushSave(tester);

      final sent = h.repository.syncedSet(0, 0);
      expect(sent['completed'], isTrue);
      expect(sent.containsKey('started_at'), isFalse);
      expect(sent.containsKey('completed_at'), isFalse);
      final kept = h.repository.savedSet(0, 0);
      expect(time(kept['started_at']), t0.add(const Duration(seconds: 10)));
      expect(time(kept['completed_at']), t0.add(const Duration(seconds: 40)));
      expect(
        time(h.repository.syncedSet(0, 1)['started_at']),
        t0.add(const Duration(minutes: 20, seconds: 40)),
      );
    });
  });

  testWidgets('Today opens the bounded daily check-in sheet', (tester) async {
    const environment = AppEnvironment(
      supabaseUrl: '',
      supabasePublishableKey: '',
      name: 'test',
      authMode: 'owner_email_password',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: const TodayScreen(environment: environment),
      ),
    );
    await tester.pumpAndSettle();
    // The fixture day is checked in; the chip reopens the check-in.
    await tester.tap(find.text('Checked in'));
    await tester.pumpAndSettle();
    expect(find.text('Daily check-in'), findsOneWidget);
    expect(find.text('Sleep quality'), findsOneWidget);
    expect(find.bySemanticsLabel('Energy: OK'), findsOneWidget);
    expect(find.text('Available to train today'), findsOneWidget);
    // Pinned below the questions, so it is on screen without scrolling.
    expect(find.text('Save check-in').hitTestable(), findsOneWidget);
  });
}
