import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  final Map<int, int> rows;
  final bool alreadyStarted;
  var started = false;
  final syncs = <Map<String, dynamic>>[];

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
    started = true;
    return 'srv-1';
  }

  @override
  Future<Map<String, dynamic>?> loadSession(
    PlannedWorkout workout, {
    DateTime? localDate,
  }) async => started || alreadyStarted ? _session() : null;

  @override
  Future<void> sync(
    String sessionId,
    int revision,
    Map<String, dynamic> draft,
  ) async => syncs.add(draft);
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

void main() {
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
