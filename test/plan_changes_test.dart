import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/nutrition_screen.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/plan_changes.dart';

class _CountingNutrition extends FixtureNutritionRepository {
  _CountingNutrition();

  int targetLoads = 0;

  @override
  Future<NutritionTargets?> loadTargets() {
    targetLoads++;
    return super.loadTargets();
  }
}

class _CountingWorkouts extends FixtureWorkoutRepository {
  int hubLoads = 0;

  @override
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28}) {
    hubLoads++;
    return super.loadTrainingHub(periodDays: periodDays);
  }
}

void main() {
  testWidgets('Nutrition reloads its targets when a proposal changed them', (
    tester,
  ) async {
    final repository = _CountingNutrition();
    final changes = PlanChanges();
    addTearDown(changes.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: NutritionScreen(repository: repository, planChanges: changes),
      ),
    );
    await tester.pumpAndSettle();
    final before = repository.targetLoads;
    changes.announce();
    await tester.pumpAndSettle();
    expect(repository.targetLoads, before + 1);
  });

  testWidgets('Train reloads the hub when a proposal changed the plan', (
    tester,
  ) async {
    final repository = _CountingWorkouts();
    final changes = PlanChanges();
    addTearDown(changes.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: TrainScreen(repository: repository, planChanges: changes),
      ),
    );
    await tester.pumpAndSettle();
    final before = repository.hubLoads;
    changes.announce();
    await tester.pumpAndSettle();
    expect(repository.hubLoads, before + 1);
  });

  testWidgets('a screen that is gone stops listening', (tester) async {
    final repository = _CountingNutrition();
    final changes = PlanChanges();
    addTearDown(changes.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: NutritionScreen(repository: repository, planChanges: changes),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    final before = repository.targetLoads;
    changes.announce();
    await tester.pump();
    expect(repository.targetLoads, before);
  });
}
