import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/widgets/week_rail_card.dart';
import 'package:tracend/features/train/widgets/week_summary_card.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/plan_changes.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

import 'train_fixtures.dart';

/// Train across a night and a tab switch: the screen follows the day it is
/// opened on, reloads a hub that is old, and never starts a workout under a
/// day that is over.
void main() {
  late DateTime now;
  late TrainFixtureRepository repository;
  late WorkoutLogChanges logs;
  late ValueNotifier<int> showToday;

  setUp(() {
    now = DateTime(2026, 10, 2, 23, 30);
    repository = TrainFixtureRepository();
    logs = WorkoutLogChanges();
    showToday = ValueNotifier<int>(0);
    addTearDown(logs.dispose);
    addTearDown(showToday.dispose);
  });

  Future<void> pumpTrain(WidgetTester tester, {bool active = true}) async {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TracendMotionScope(
        level: TracendMotionLevel.static,
        child: MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: TrainScreen(
              repository: repository,
              brief: TrainBriefRepository(computed: trainComputed()),
              coach: const TrainCoachRepository(),
              now: () => now,
              active: active,
              workoutLogs: logs,
              showToday: showToday,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  DayBoxesStrip strip(WidgetTester tester) =>
      tester.widget<DayBoxesStrip>(find.byType(DayBoxesStrip));

  void rollOverToSaturday() {
    now = DateTime(2026, 10, 3, 7);
    repository.hub = trainHub(localToday: DateTime(2026, 10, 3));
  }

  testWidgets('resuming on a new day reloads the hub and moves to the new '
      'today', (tester) async {
    await pumpTrain(tester);
    expect(strip(tester).selectedDate, DateTime(2026, 10, 2));
    final loads = repository.hubLoads;

    rollOverToSaturday();
    await resume(tester);

    expect(repository.hubLoads, loads + 1);
    expect(strip(tester).today, DateTime(2026, 10, 3));
    expect(strip(tester).selectedDate, DateTime(2026, 10, 3));
  });

  testWidgets('a day the athlete picked stays selected across midnight', (
    tester,
  ) async {
    await pumpTrain(tester);
    await tester.tap(find.byKey(const ValueKey('day-box-2026-09-30')));
    await tester.pumpAndSettle();

    rollOverToSaturday();
    await resume(tester);

    expect(strip(tester).today, DateTime(2026, 10, 3));
    expect(strip(tester).selectedDate, DateTime(2026, 9, 30));
  });

  testWidgets('a hub less than ten minutes old is not reloaded on resume, an '
      'older one is', (tester) async {
    await pumpTrain(tester);
    final loads = repository.hubLoads;

    now = now.add(const Duration(minutes: 9));
    await resume(tester);
    expect(repository.hubLoads, loads);

    now = now.add(const Duration(minutes: 2));
    await resume(tester);
    expect(repository.hubLoads, loads + 1);
  });

  testWidgets('opening the tab again reloads a hub older than a minute', (
    tester,
  ) async {
    await pumpTrain(tester, active: false);
    final loads = repository.hubLoads;

    now = now.add(const Duration(seconds: 30));
    await pumpTrain(tester);
    expect(repository.hubLoads, loads);

    await pumpTrain(tester, active: false);
    now = now.add(const Duration(minutes: 2));
    await pumpTrain(tester);
    expect(repository.hubLoads, loads + 1);
  });

  testWidgets('Start after midnight reloads instead of sending the old day', (
    tester,
  ) async {
    await pumpTrain(tester);
    final loads = repository.hubLoads;
    // The day ended while the app stayed in front; no resume came yet.
    rollOverToSaturday();

    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();

    final route = ModalRoute.of(tester.element(find.byType(TrainScreen)));
    expect(route?.isCurrent, isTrue, reason: 'no workout screen opened');
    expect(repository.hubLoads, loads + 1);
    expect(find.textContaining('A new day has started'), findsOneWidget);
    expect(strip(tester).selectedDate, DateTime(2026, 10, 3));
  });

  testWidgets('a workout saved from Today reloads the hub', (tester) async {
    await pumpTrain(tester);
    final loads = repository.hubLoads;
    logs.announce();
    await tester.pumpAndSettle();
    expect(repository.hubLoads, loads + 1);
  });

  testWidgets('Today\'s session card selects today again', (tester) async {
    await pumpTrain(tester);
    await tester.tap(find.byKey(const ValueKey('day-box-2026-09-30')));
    await tester.pumpAndSettle();
    expect(strip(tester).selectedDate, DateTime(2026, 9, 30));

    showToday.value++;
    await tester.pumpAndSettle();

    expect(strip(tester).selectedDate, DateTime(2026, 10, 2));
  });

  testWidgets('This week counts the current week while an earlier one is '
      'browsed', (tester) async {
    await pumpTrain(tester);
    WeekSummaryCard card() =>
        tester.widget<WeekSummaryCard>(find.byType(WeekSummaryCard));
    final done = card().done;
    final planned = card().planned;
    expect(done, greaterThan(0));

    await tester.fling(find.byType(DayBoxesStrip), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(strip(tester).weekStart, DateTime(2026, 9, 21));

    expect(card().done, done);
    expect(card().planned, planned);
  });

  testWidgets('a reload that finishes after a newer one is dropped', (
    tester,
  ) async {
    final slow = _GatedHubRepository();
    repository = slow;
    await pumpTrain(tester);

    // The resume's load is slow and still on the old day...
    slow.gate = Completer<TrainingHubData>();
    now = DateTime(2026, 10, 3, 0, 20);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    // ...a newer load (the plan changed) answers first, for the new day.
    slow.gate = null;
    slow.hub = trainHub(localToday: DateTime(2026, 10, 3));
    logs.announce();
    await tester.pumpAndSettle();
    expect(strip(tester).today, DateTime(2026, 10, 3));

    slow.pending.single.complete(trainHub());
    await tester.pumpAndSettle();
    expect(strip(tester).today, DateTime(2026, 10, 3));
  });
}

class _GatedHubRepository extends TrainFixtureRepository {
  /// While set, the next hub load waits for it.
  Completer<TrainingHubData>? gate;
  final pending = <Completer<TrainingHubData>>[];

  @override
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28}) {
    final held = gate;
    if (held == null) return super.loadTrainingHub(periodDays: periodDays);
    pending.add(held);
    return held.future;
  }
}
