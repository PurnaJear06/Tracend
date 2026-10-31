import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/shared/home_widgets/home_widget_bridge.dart';

import '../train_fixtures.dart';

/// The workout card's "Open" and a tap on the card open the workout in
/// progress (`tracend://workout`): Train reopens today's workout when it has
/// a draft on this phone, and never opens one over a workout already open.
void main() {
  final requests = ValueNotifier<int>(0);

  setUp(() => requests.value = 0);

  Future<TrainFixtureRepository> pump(
    WidgetTester tester, {
    TrainFixtureRepository? repository,
    bool hasDraft = true,
    bool settle = true,
  }) async {
    final repo = repository ?? TrainFixtureRepository();
    if (hasDraft) await repo.saveDraft('upper-a', '{}');
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
    final repo = TrainFixtureRepository(hubError: Exception('offline'));
    requests.value = 1;

    await pump(tester, repository: repo);

    expect(find.byType(ActiveWorkoutScreen), findsNothing);
  });
}
