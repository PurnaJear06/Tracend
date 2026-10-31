import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/progress_screen.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';

/// The weight card reads the brief (trend, kg a week) and the active goal.
/// They reload with the measurements: on pull to refresh, after a weigh-in,
/// when the app comes back to the front and when the tab is opened again.
class _Progress extends FixtureProgressRepository
    implements ProgressGoalRepository {
  _Progress();

  int goalLoads = 0;
  final saved = <BodyMeasurement>[];

  @override
  Future<String?> loadActiveGoal() async {
    goalLoads++;
    return 'fat_loss';
  }

  @override
  Future<void> saveMeasurement(BodyMeasurement measurement) async {
    saved.add(measurement);
  }
}

class _Brief extends FixtureDailyBriefRepository {
  _Brief();

  int loads = 0;

  @override
  Future<DailyBrief> load(DateTime date) {
    loads++;
    return super.load(date);
  }
}

void main() {
  late DateTime now;
  late _Progress repository;
  late _Brief brief;

  setUp(() {
    now = DateTime(2026, 10, 2, 9);
    repository = _Progress();
    brief = _Brief();
  });

  Future<void> pumpProgress(WidgetTester tester, {bool active = true}) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: ProgressScreen(
            repository: repository,
            brief: brief,
            now: () => now,
            active: active,
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

  testWidgets('pull to refresh reloads the brief and the goal', (tester) async {
    await pumpProgress(tester);
    expect((brief.loads, repository.goalLoads), (1, 1));

    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 400),
      1500,
    );
    await tester.pumpAndSettle();

    expect((brief.loads, repository.goalLoads), (2, 2));
  });

  testWidgets('a saved weigh-in reloads the brief and the goal', (
    tester,
  ) async {
    await pumpProgress(tester);
    await tester.tap(find.byTooltip('Record measurement'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Weight *'),
      '78.4',
    );
    await tester.ensureVisible(find.text('Save measurement'));
    await tester.tap(find.text('Save measurement'));
    await tester.pumpAndSettle();

    expect(repository.saved.single.weightKg, 78.4);
    expect((brief.loads, repository.goalLoads), (2, 2));
  });

  testWidgets('resume reloads data older than ten minutes, not newer', (
    tester,
  ) async {
    await pumpProgress(tester);

    now = now.add(const Duration(minutes: 5));
    await resume(tester);
    expect((brief.loads, repository.goalLoads), (1, 1));

    now = now.add(const Duration(minutes: 6));
    await resume(tester);
    expect((brief.loads, repository.goalLoads), (2, 2));
  });

  testWidgets('resume on a new day reloads at once', (tester) async {
    await pumpProgress(tester);
    now = DateTime(2026, 10, 3, 0, 5);
    await resume(tester);
    expect((brief.loads, repository.goalLoads), (2, 2));
  });

  testWidgets('opening the tab again reloads data older than a minute', (
    tester,
  ) async {
    await pumpProgress(tester, active: false);
    now = now.add(const Duration(seconds: 30));
    await pumpProgress(tester);
    expect(brief.loads, 1);

    await pumpProgress(tester, active: false);
    now = now.add(const Duration(minutes: 2));
    await pumpProgress(tester);
    expect((brief.loads, repository.goalLoads), (2, 2));
  });
}
