import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/train/open_workout.dart';
import 'package:tracend/features/train/unfinished_workout.dart';
import 'package:tracend/features/train/workout_repository.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

const _sessionId = 'd1450000-0000-4000-8000-000000000001';

/// Legs B left open on Friday 30 October with two sets done.
final _legsB = OpenWorkout.fromDraft(
  'legs-b',
  jsonEncode({
    'session_id': _sessionId,
    'workout_name': 'Legs B',
    'session_local_date': '2026-10-30',
    'actual_started_at': '2026-10-31T11:30:00Z',
    'exercises': [
      {
        'order': 1,
        'sets': [
          {'number': 1, 'completed': true},
          {'number': 2, 'completed': true},
          {'number': 3, 'completed': false},
        ],
      },
    ],
  }),
)!;

/// This phone's open workouts, and the workout the server offers back.
class _Workouts extends FixtureWorkoutRepository
    implements OpenWorkoutRepository, UnfinishedWorkoutRepository {
  _Workouts({this.open = const [], this.unfinished});

  List<OpenWorkout> open;
  final UnfinishedWorkout? unfinished;
  int reads = 0;

  @override
  Future<List<OpenWorkout>> loadOpenWorkouts() async {
    reads++;
    return open;
  }

  @override
  Future<UnfinishedWorkout?> loadUnfinishedWorkout() async => unfinished;

  @override
  Future<void> saveUnfinishedWorkout(
    UnfinishedWorkout workout, {
    required int sessionEffort,
  }) async {}

  @override
  Future<void> discardUnfinishedWorkout(UnfinishedWorkout workout) async {}
}

class _Brief implements DailyBriefRepository {
  const _Brief();

  @override
  Future<DailyBrief> load(DateTime date) async =>
      const DailyBrief(localDate: '2026-10-31');
}

class _Health implements HealthRepository {
  const _Health();

  @override
  Future<HealthHistory> loadHistory() async => const HealthHistory([]);

  @override
  Future<HealthSyncStatus> loadStatus() async =>
      const HealthSyncStatus(state: HealthConnectionState.manualOnly);

  @override
  Future<HealthSyncStatus> connectAndSync() => loadStatus();

  @override
  Future<HealthSyncStatus> sync() => loadStatus();
}

void main() {
  Future<void> pumpToday(
    WidgetTester tester,
    _Workouts workouts, {
    ValueChanged<OpenWorkout>? onResume,
    bool active = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: TodayScreen(
            environment: _environment,
            workouts: workouts,
            brief: const _Brief(),
            health: const _Health(),
            nutrition: const FixtureNutritionRepository(),
            coach: const FixtureCoachRepository(),
            onResumeWorkout: onResume,
            active: active,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const line = 'Legs B · Fri 30 Oct · 2 sets logged';

  testWidgets('offers the open workout and hands it to Train', (tester) async {
    final resumed = <OpenWorkout>[];
    await pumpToday(tester, _Workouts(open: [_legsB]), onResume: resumed.add);

    expect(find.text('Workout in progress'), findsOneWidget);
    expect(find.text(line), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    await tester.pumpAndSettle();

    expect(resumed.single.workoutId, 'legs-b');
    expect(resumed.single.date, DateTime(2026, 10, 30));
  });

  testWidgets('shows no card where nothing can reopen it', (tester) async {
    await pumpToday(tester, _Workouts(open: [_legsB]));

    expect(find.text(line), findsNothing);
  });

  testWidgets('a workout the server already offers back is answered on that '
      'card only', (tester) async {
    await pumpToday(
      tester,
      _Workouts(
        open: [_legsB],
        unfinished: UnfinishedWorkout(
          sessionId: _sessionId,
          plannedWorkoutId: 'legs-b',
          name: 'Legs B',
          localDate: DateTime(2026, 10, 30),
          loggedSets: 2,
          totalSets: 12,
          saveBy: DateTime(2026, 11, 6),
        ),
      ),
      onResume: (_) {},
    );

    expect(find.text('Workout not finished'), findsOneWidget);
    expect(find.text(line), findsNothing);
  });

  testWidgets('coming back to the tab reads the open workouts again', (
    tester,
  ) async {
    final workouts = _Workouts(open: [_legsB]);
    await pumpToday(tester, workouts, onResume: (_) {}, active: false);
    expect(find.text(line), findsOneWidget);

    // Finished in Train meanwhile.
    workouts.open = const [];
    await pumpToday(tester, workouts, onResume: (_) {});

    expect(find.text(line), findsNothing);
  });
}
