import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/workout_draft.dart';
import 'package:tracend/features/train/workout_repository.dart';

import 'live_activity/fake_workout_activity_bridge.dart';

/// How many sets a started workout has is the server's to say: `start_workout`
/// reads the athlete's accepted same-day answer and creates the set rows. The
/// logger is built from the plan and then follows those rows, so no answer
/// pending on the phone, and no accepted row the phone does not know of,
/// can leave the logger and the server with different sets.

const _plan = PlannedWorkout(
  id: 'upper-a',
  name: 'Upper A',
  objective: 'Press.',
  estimatedMinutes: 45,
  exercises: [
    PlannedExercise(
      order: 1,
      name: 'Bench press',
      setCount: 3,
      repMin: 6,
      repMax: 8,
      targetRpe: 8,
      targetLoadKg: 60,
    ),
    PlannedExercise(
      order: 2,
      name: 'Barbell row',
      setCount: 3,
      repMin: 8,
      repMax: 10,
      targetRpe: 8,
      targetLoadKg: 50,
    ),
  ],
);

class _Alerts implements RestAlertScheduler {
  @override
  Future<bool> scheduleRestAlert(int seconds) async => true;

  @override
  Future<void> cancelRestAlert() async {}
}

class _Notifications implements NotificationRepository {
  @override
  Future<NotificationPreferences> load() async => NotificationPreferences(
    authorizationStatus: 'authorized',
    dailyCheckIn: false,
    weeklyReview: false,
    restTimerAlertsEnabled: false,
  );

  @override
  Future<NotificationPreferences> configure({
    required bool dailyCheckIn,
    required bool weeklyReview,
    required bool restTimerAlertsEnabled,
  }) => load();
}

/// A server whose `start_workout` made [rows] set rows per exercise order.
class _Server extends FixtureWorkoutRepository {
  _Server(this.rows, {this.alreadyStarted = false});

  Map<int, int> rows;
  final bool alreadyStarted;
  var started = false;
  final syncs = <Map<String, dynamic>>[];

  /// Reading the session fails while this is true (offline).
  var failReads = false;

  /// The next sync is refused with 22023, as for a set number with no row.
  var refuseNext = false;

  /// `start_workout` answers with this code (22023: the day has not begun,
  /// 55000: the day is already logged), or fails as offline for 'offline'.
  String? startRefusal;

  /// What the session read returns once the start was refused with 55000: the
  /// finished session of an earlier plan version.
  Map<String, dynamic>? loggedSession;

  Map<String, dynamic> _session() => {
    'session_id': 'srv-1',
    'state': 'in_progress',
    'revision': 0,
    'idempotency_key': 'k',
    'local_date': '2026-10-03',
    'actual_started_at': '2026-10-03T09:00:00Z',
    'exercises': [
      for (final exercise in _plan.exercises)
        {
          'order': exercise.order,
          'status': 'unknown',
          'sets': [
            for (var n = 1; n <= (rows[exercise.order] ?? 0); n++)
              {'number': n, 'completed': false},
          ],
        },
    ],
  };

  @override
  Future<String> start(
    PlannedWorkout workout,
    String idempotencyKey, {
    DateTime? localDate,
  }) async {
    final refusal = startRefusal;
    if (refusal == 'offline') throw Exception('offline');
    if (refusal != null) {
      throw PostgrestException(message: 'refused', code: refusal);
    }
    started = true;
    return 'srv-1';
  }

  @override
  Future<Map<String, dynamic>?> loadSession(
    PlannedWorkout workout, {
    DateTime? localDate,
  }) async {
    if (started && failReads) throw Exception('offline');
    if (loggedSession != null && startRefusal == '55000') return loggedSession;
    return started || alreadyStarted ? _session() : null;
  }

  @override
  Future<void> sync(
    String sessionId,
    int revision,
    Map<String, dynamic> draft,
  ) async {
    if (refuseNext) {
      refuseNext = false;
      throw const PostgrestException(message: 'no such set', code: '22023');
    }
    syncs.add(draft);
  }
}

int _benchSets(Map<String, dynamic> draft) =>
    (((draft['exercises'] as List).first as Map)['sets'] as List).length;

Future<void> _tapLabel(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label).first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Logs the current set and skips the rest that follows.
Future<void> _doneSet(WidgetTester tester, int number) async {
  await tester.tap(find.text('Done set $number'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await _tapLabel(tester, 'Skip rest');
}

Future<void> _open(WidgetTester tester, _Server server) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: ActiveWorkoutScreen(
        workout: _plan,
        repository: server,
        restAlerts: _Alerts(),
        notifications: _Notifications(),
        activity: FakeWorkoutActivityBridge(),
        lockScreenNumbers: () async => false,
        clock: () => DateTime(2026, 10, 3, 9),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the workout from a button, so closing it has a screen to return to.
Future<void> _openPushed(WidgetTester tester, _Server server) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => ActiveWorkoutScreen(
                  workout: _plan,
                  repository: server,
                  restAlerts: _Alerts(),
                  notifications: _Notifications(),
                  activity: FakeWorkoutActivityBridge(),
                  lockScreenNumbers: () async => false,
                  clock: () => DateTime(2026, 10, 3, 9),
                ),
              ),
            ),
            child: const Text('Open workout'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open workout'));
  await tester.pumpAndSettle();
}

void main() {
  group('a start the server refuses for good', () {
    testWidgets('a day that has not begun (22023) closes with a message, '
        'not as offline', (tester) async {
      final server = _Server({1: 3, 2: 3})..startRefusal = '22023';
      await _openPushed(tester, server);
      expect(find.byType(ActiveWorkoutScreen), findsNothing);
      expect(
        find.text('This day has not started yet. Open the workout on the day.'),
        findsOneWidget,
      );
      expect(server.syncs, isEmpty);
    });

    testWidgets('a day already logged (55000) opens the finished session, '
        'with the exercises as they were logged', (tester) async {
      final server = _Server({1: 3, 2: 3})
        ..startRefusal = '55000'
        ..loggedSession = {
          'session_id': 'done-1',
          'state': 'completed',
          'duration_seconds': 3000,
          'exercises': [
            {
              'order': 1,
              'status': 'performed',
              'performed_name': 'Incline press',
              'sets': [
                {
                  'number': 1,
                  'completed': true,
                  'repetitions': 8,
                  'load_kg': 50,
                },
              ],
            },
          ],
        };
      await _openPushed(tester, server);
      expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
      expect(find.text('Incline press'), findsWidgets);
      expect(find.text('Bench press'), findsNothing);
      expect(find.text('Done set 1'), findsNothing);
      expect(server.syncs, isEmpty);
    });

    testWidgets('55000 with nothing to show closes with a message', (
      tester,
    ) async {
      final server = _Server({1: 3, 2: 3})..startRefusal = '55000';
      await _openPushed(tester, server);
      expect(find.byType(ActiveWorkoutScreen), findsNothing);
      expect(
        find.text('This workout is already logged for the day.'),
        findsOneWidget,
      );
    });

    testWidgets('a network failure still waits as offline', (tester) async {
      final server = _Server({1: 3, 2: 3})..startRefusal = 'offline';
      await _openPushed(tester, server);
      expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    });
  });

  testWidgets('a fresh start takes the set rows the server made', (
    tester,
  ) async {
    final server = _Server({1: 2, 2: 3});
    await _open(tester, server);
    expect(server.started, isTrue);
    expect(find.text('Set 1 of 2'), findsOneWidget);
    expect(find.text('Set 1 of 3'), findsNothing);
    final payload = server.syncs.isEmpty ? null : server.syncs.last;
    if (payload != null) {
      final bench = (payload['exercises'] as List).first as Map;
      expect(bench['sets'], hasLength(2));
    }
  });

  testWidgets('a session already on the server opens with its rows', (
    tester,
  ) async {
    await _open(tester, _Server({1: 2, 2: 3}, alreadyStarted: true));
    expect(find.text('Set 1 of 2'), findsOneWidget);
  });

  testWidgets('a server with the plan\'s rows leaves the logger as planned', (
    tester,
  ) async {
    await _open(tester, _Server({1: 3, 2: 3}));
    expect(find.text('Set 1 of 3'), findsOneWidget);
  });

  group('the rows are read before anything is synced', () {
    testWidgets('a failed first read keeps the draft on the phone, then '
        'aligns and syncs', (tester) async {
      final handle = tester.ensureSemantics();
      final server = _Server({1: 2, 2: 3})..failReads = true;
      await _open(tester, server);
      expect(server.started, isTrue);
      // Rows unread: still the plan's sets, and nothing was sent.
      expect(find.text('Set 1 of 3'), findsOneWidget);
      expect(server.syncs, isEmpty);
      await _doneSet(tester, 1);
      expect(server.syncs, isEmpty, reason: 'still unread, still not sent');

      server.failReads = false;
      await tester.tap(find.text('Done set 2'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(server.syncs, isNotEmpty);
      expect(_benchSets(server.syncs.last), 2, reason: "the server's rows");
      handle.dispose();
    });

    testWidgets('a 22023 reads the rows again, aligns and sends once more', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final server = _Server({1: 3, 2: 3});
      await _open(tester, server);
      expect(find.text('Set 1 of 3'), findsOneWidget);
      // The server's rows turn out to be fewer than the phone assumed.
      server.rows = {1: 2, 2: 3};
      server.refuseNext = true;
      server.syncs.clear();
      await _tapLabel(tester, 'More weight');
      expect(server.syncs, hasLength(1));
      expect(_benchSets(server.syncs.single), 2);
      handle.dispose();
    });

    testWidgets('a set with entries that has no row is kept and needs '
        'attention', (tester) async {
      final handle = tester.ensureSemantics();
      final server = _Server({1: 3, 2: 3});
      await _open(tester, server);
      await _doneSet(tester, 1);
      await _doneSet(tester, 2);
      // Set 3 gets an entry, then the server turns out to hold two rows.
      await _tapLabel(tester, 'More weight');
      server.rows = {1: 2, 2: 3};
      server.refuseNext = true;
      server.syncs.clear();
      await _tapLabel(tester, 'One more rep');
      expect(server.syncs, isEmpty, reason: 'nothing is sent for a lost set');
      expect(find.text('Needs attention'), findsWidgets);
      expect(find.text('Set 3 of 3'), findsOneWidget, reason: 'kept');
      handle.dispose();
    });
  });

  group('aligning an exercise to the server\'s rows', () {
    test('untouched trailing sets go, missing ones come', () {
      final draft = ExerciseDraft(_plan.exercises.first);
      draft.alignTo(2);
      expect(draft.sets, hasLength(2));
      draft.alignTo(4);
      expect(draft.sets, hasLength(4));
    });

    test('a set with something on it is never dropped', () {
      final draft = ExerciseDraft(_plan.exercises.first);
      draft.sets.last.load = '60';
      draft.alignTo(2);
      expect(draft.sets, hasLength(3));
    });

    test('restoring a draft or session follows its rows', () {
      final draft = ExerciseDraft(_plan.exercises.first)
        ..restore({
          'sets': [
            {'number': 1, 'completed': false},
            {'number': 2, 'completed': false},
          ],
        });
      expect(draft.sets, hasLength(2));
    });
  });
}
