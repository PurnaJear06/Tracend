import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/progress/physique_check_repository.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/shell/app_shell.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/train/workout_repository.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

/// Every repository read the five tabs make, by name. Each fake returns the
/// fixture answer and counts the call, so a count here is one round trip in
/// the app.
class _Reads {
  final counts = <String, int>{};

  void hit(String name) => counts[name] = (counts[name] ?? 0) + 1;

  int get total => counts.values.fold(0, (sum, count) => sum + count);

  Map<String, int> snapshot() => Map.of(counts);

  /// Reads made since [before].
  Map<String, int> since(Map<String, int> before) => {
    for (final entry in counts.entries)
      if (entry.value - (before[entry.key] ?? 0) > 0)
        entry.key: entry.value - (before[entry.key] ?? 0),
  };
}

class _Workouts extends FixtureWorkoutRepository {
  _Workouts(this.reads);
  final _Reads reads;

  @override
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28}) {
    reads.hit('workouts.loadTrainingHub($periodDays)');
    return super.loadTrainingHub(periodDays: periodDays);
  }

  @override
  Future<PlannedWorkout> loadTodayWorkout() {
    reads.hit('workouts.loadTodayWorkout');
    return super.loadTodayWorkout();
  }
}

class _Coach extends FixtureCoachRepository {
  const _Coach(this.reads);
  final _Reads reads;

  @override
  Future<CoachDecision?> loadLatest() {
    reads.hit('coach.loadLatest');
    return super.loadLatest();
  }
}

class _Nutrition extends FixtureNutritionRepository {
  const _Nutrition(this.reads);
  final _Reads reads;

  @override
  Future<NutritionTargets?> loadTargets() {
    reads.hit('nutrition.loadTargets');
    return super.loadTargets();
  }

  @override
  Future<NutritionSummary> loadSummary(DateTime date) {
    reads.hit('nutrition.loadSummary');
    return super.loadSummary(date);
  }

  @override
  Future<List<MealEntry>> loadMeals(DateTime date) {
    reads.hit('nutrition.loadMeals');
    return super.loadMeals(date);
  }

  @override
  Future<NutritionSchedule> loadSchedule(DateTime date) {
    reads.hit('nutrition.loadSchedule');
    return super.loadSchedule(date);
  }
}

class _Progress extends FixtureProgressRepository {
  const _Progress(this.reads);
  final _Reads reads;

  @override
  Future<List<BodyMeasurement>> loadMeasurements() {
    reads.hit('progress.loadMeasurements');
    return super.loadMeasurements();
  }

  @override
  Future<ProgressSummary> loadSummary() {
    reads.hit('progress.loadSummary');
    return super.loadSummary();
  }

  @override
  Future<List<ProgressPhotoSet>> loadPhotoSets() {
    reads.hit('progress.loadPhotoSets');
    return super.loadPhotoSets();
  }

  @override
  Future<WeeklyProgressReview?> loadLatestWeeklyReview() {
    reads.hit('progress.loadLatestWeeklyReview');
    return super.loadLatestWeeklyReview();
  }

  @override
  Future<WeeklyReviewJob?> loadLatestWeeklyReviewJob() {
    reads.hit('progress.loadLatestWeeklyReviewJob');
    return super.loadLatestWeeklyReviewJob();
  }
}

class _Physique extends FixturePhysiqueCheckRepository {
  const _Physique(this.reads);
  final _Reads reads;

  @override
  Future<String?> loadProvider() {
    reads.hit('physique.loadProvider');
    return super.loadProvider();
  }

  @override
  Future<PhysiqueAnalysis?> loadLatestAnalysis() {
    reads.hit('physique.loadLatestAnalysis');
    return super.loadLatestAnalysis();
  }
}

class _Brief extends FixtureDailyBriefRepository {
  const _Brief(this.reads);
  final _Reads reads;

  @override
  Future<DailyBrief> load(DateTime date) {
    reads.hit('brief.load');
    return super.load(date);
  }
}

class _Health extends ManualHealthRepository {
  const _Health(this.reads);
  final _Reads reads;

  @override
  Future<HealthSyncStatus> loadStatus() {
    reads.hit('health.loadStatus');
    return super.loadStatus();
  }

  @override
  Future<HealthHistory> loadHistory() {
    reads.hit('health.loadHistory');
    return super.loadHistory();
  }
}

Future<_Reads> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final reads = _Reads();
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: AppShell(
        environment: _environment,
        health: _Health(reads),
        repositories: AppShellRepositories(
          workouts: _Workouts(reads),
          coach: _Coach(reads),
          nutrition: _Nutrition(reads),
          progress: _Progress(reads),
          physique: _Physique(reads),
          brief: _Brief(reads),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return reads;
}

Future<Map<String, int>> _open(
  WidgetTester tester,
  _Reads reads,
  String tab,
) async {
  final before = reads.snapshot();
  await tester.tap(find.byKey(ValueKey('tab-${tab.toLowerCase()}')));
  await tester.pumpAndSettle();
  return reads.since(before);
}

void main() {
  testWidgets('launch reads only what Today needs', (tester) async {
    final reads = await _pumpShell(tester);
    debugPrint('READS launch total=${reads.total} ${reads.counts}');

    expect(reads.counts.keys.where((k) => k.startsWith('progress.')), isEmpty);
    expect(reads.counts.keys.where((k) => k.startsWith('physique.')), isEmpty);
    expect(reads.counts.keys.where((k) => k.startsWith('workouts.')), isEmpty);
  });

  testWidgets('each tab reads when first opened and never again on return', (
    tester,
  ) async {
    final reads = await _pumpShell(tester);
    final firstOpen = <String, Map<String, int>>{};
    for (final tab in ['Train', 'Coach', 'Nutrition', 'Progress']) {
      firstOpen[tab] = await _open(tester, reads, tab);
      debugPrint('READS first open $tab ${firstOpen[tab]}');
    }

    expect(firstOpen['Train'], contains('workouts.loadTrainingHub(28)'));
    expect(firstOpen['Nutrition'], contains('nutrition.loadSummary'));
    expect(firstOpen['Progress'], contains('progress.loadMeasurements'));

    final settled = reads.snapshot();
    for (final tab in ['Today', 'Train', 'Coach', 'Nutrition', 'Progress']) {
      expect(await _open(tester, reads, tab), isEmpty, reason: 'back to $tab');
    }
    expect(reads.since(settled), isEmpty);
  });

  testWidgets('a tab keeps its state after the first open', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('tab-nutrition')));
    await tester.pumpAndSettle();
    final nutrition = tester.state(find.byKey(const ValueKey('tab_nutrition')));

    await tester.tap(find.byKey(const ValueKey('tab-progress')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-nutrition')));
    await tester.pumpAndSettle();

    expect(
      tester.state(find.byKey(const ValueKey('tab_nutrition'))),
      nutrition,
    );
  });
}
