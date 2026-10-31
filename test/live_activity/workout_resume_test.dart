import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/open_workout.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/home_widgets/home_widget_bridge.dart';

import '../train_fixtures.dart';

/// Train's fixture with this phone's open workouts: the drafts in [drafts].
class _OpenDrafts extends TrainFixtureRepository
    implements OpenWorkoutRepository {
  _OpenDrafts({super.hubError});

  final drafts = <String, String>{};

  @override
  Future<List<OpenWorkout>> loadOpenWorkouts() async =>
      openWorkoutsFrom(Map.of(drafts));
}

/// A draft of [workout] logged under [day] with one set done.
String _draft(PlannedWorkout workout, DateTime day) => jsonEncode({
  'workout_id': workout.id,
  'session_id': 'session-${workout.id}',
  'workout_name': workout.name,
  'session_local_date':
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}',
  'actual_started_at': DateTime(2026, 10, 2, 8).toUtc().toIso8601String(),
  'exercises': [
    {
      'order': 1,
      'sets': [
        {'number': 1, 'completed': true},
      ],
    },
  ],
});

/// The workout card's "Open" and a tap on the card open the workout in
/// progress (`tracend://workout`): Train reopens the newest workout left open
/// on this phone, whatever its day, and never opens one over a workout
/// already open.
void main() {
  final requests = ValueNotifier<int>(0);

  setUp(() => requests.value = 0);

  Future<_OpenDrafts> pump(
    WidgetTester tester, {
    _OpenDrafts? repository,
    bool hasDraft = true,
    bool settle = true,
  }) async {
    final repo = repository ?? _OpenDrafts();
    if (hasDraft) repo.drafts[upperA.id] = _draft(upperA, trainToday);
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: TrainScreen(
            repository: repo,
            brief: TrainBriefRepository(computed: trainComputed()),
            coach: const TrainCoachRepository(),
            now: trainNow,
            workoutRequests: requests,
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    return repo;
  }

  test('the link names the workout', () {
    expect(HomeWidgetTab.fromKey('workout'), HomeWidgetTab.workout);
    expect(HomeWidgetTab.workout.key, 'workout');
  });

  testWidgets('a request reopens today\'s workout that was left open', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(ActiveWorkoutScreen), findsNothing);

    requests.value++;
    await tester.pumpAndSettle();

    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    expect(ActiveWorkoutScreen.isOpen, isTrue);
  });

  testWidgets('a past day\'s open workout reopens on its own day', (
    tester,
  ) async {
    final repo = await pump(tester, hasDraft: false);
    final wednesday = DateTime(2026, 9, 30);
    repo.drafts[lowerA.id] = _draft(lowerA, wednesday);

    requests.value++;
    await tester.pumpAndSettle();

    final screen = tester.widget<ActiveWorkoutScreen>(
      find.byType(ActiveWorkoutScreen),
    );
    expect(screen.workout.id, lowerA.id);
    expect(screen.sessionDate, wednesday);
  });

  testWidgets('a request that launched the app waits for the hub', (
    tester,
  ) async {
    requests.value = 1;

    await pump(tester);

    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
  });

  testWidgets('with no workout started a request opens nothing', (
    tester,
  ) async {
    await pump(tester, hasDraft: false);

    requests.value++;
    await tester.pumpAndSettle();

    expect(find.byType(ActiveWorkoutScreen), findsNothing);
    expect(ActiveWorkoutScreen.isOpen, isFalse);
  });

  testWidgets('a request over an open workout opens no second one', (
    tester,
  ) async {
    await pump(tester);
    requests.value++;
    await tester.pumpAndSettle();
    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);

    requests.value++;
    await tester.pumpAndSettle();

    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
  });

  testWidgets('a request the hub could not answer opens nothing', (
    tester,
  ) async {
    final repo = _OpenDrafts(hubError: Exception('offline'));
    requests.value = 1;

    await pump(tester, repository: repo);

    expect(find.byType(ActiveWorkoutScreen), findsNothing);
  });
}
