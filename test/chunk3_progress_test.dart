import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/progress_screen.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/train/workout_repository.dart';

Widget _app(
  ProgressRepository repository, {
  DailyBriefRepository? brief,
  TrainingHubRepository? training,
}) => MaterialApp(
  theme: TracendTheme.dark,
  home: Scaffold(
    body: ProgressScreen(
      repository: repository,
      brief: brief,
      training: training,
    ),
  ),
);

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.pump();
}

void main() {
  testWidgets('computed overlays appear only when real trend inputs exist', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_Repository(withTrend: true), brief: _Brief(withTrends: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('7-day trend'), findsOneWidget);
    expect(find.text('28-day trend'), findsOneWidget);
    expect(find.text('Measured'), findsOneWidget);
  });

  testWidgets('no overlays when computed trends are null', (tester) async {
    await tester.pumpWidget(
      _app(_Repository(withTrend: true), brief: _Brief(withTrends: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('7-day trend'), findsNothing);
    expect(find.text('28-day trend'), findsNothing);
    expect(find.text('Measured'), findsNothing);
  });

  testWidgets('tapping a history row opens the detail sheet', (tester) async {
    await tester.pumpWidget(_app(_Repository(withTrend: true)));
    await tester.pumpAndSettle();
    final row = find.text('22/8/2026 · manual');
    await _reveal(tester, row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Confirmed weigh-in'), findsOneWidget);
    expect(find.textContaining('source: manual'), findsOneWidget);
  });

  testWidgets('body measurement, photo, and weekly review remain reachable', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Repository(withTrend: true)));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Record measurement'));
    expect(find.text('Record measurement'), findsOneWidget);
    await _reveal(tester, find.text('Front photo'));
    expect(find.text('Front photo'), findsOneWidget);
    await _reveal(tester, find.text('Open weekly review'));
    expect(find.text('Open weekly review'), findsOneWidget);
  });

  testWidgets('training evidence shows display-only progression', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_Repository(withTrend: true), training: _TrainingHub()),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Bench press'));
    expect(find.text('Bench press'), findsOneWidget);
    expect(
      find.textContaining('display-only, no detail destination yet'),
      findsOneWidget,
    );
  });

  testWidgets('sparkline wires real weigh-in values into the indicator', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(_Repository(withTrend: true), brief: _Brief(withTrends: true)),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('WEIGHT TREND'));
    expect(
      find.bySemanticsLabel(
        RegExp('Weight across your last .* confirmed weigh-ins'),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}

class _Brief implements DailyBriefRepository {
  const _Brief({required this.withTrends});
  final bool withTrends;

  @override
  Future<DailyBrief> load(DateTime date) async {
    final scores = withTrends
        ? const ComputedScores(
            weightTrend7d: -0.05,
            weightTrend28d: -0.04,
            weightTrendR2: 0.8,
          )
        : const ComputedScores();
    return DailyBrief(
      localDate: '2026-08-22',
      computed: ComputedMetrics(
        scores: scores,
        baselines: const ComputedBaselines(),
        dataConfidence: 'medium',
      ),
    );
  }
}

class _TrainingHub implements TrainingHubRepository {
  @override
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28}) async =>
      TrainingHubData(
        planTitle: 'Approved training plan',
        workouts: const [],
        recentSessions: const [],
        completedSessions: 2,
        plannedSessions: 4,
        progression: const [
          ExerciseProgression(
            exercise: 'Bench press',
            sessions: 3,
            bestLoadKg: 80,
            bestRepetitions: 8,
          ),
        ],
      );
}

class _Repository implements ProgressRepository {
  _Repository({this.withTrend = false});
  final bool withTrend;

  @override
  Future<List<BodyMeasurement>> loadMeasurements() async => withTrend
      ? [
          BodyMeasurement(date: DateTime(2026, 8, 1), weightKg: 80),
          BodyMeasurement(
            date: DateTime(2026, 8, 8),
            weightKg: 79.6,
            waistCm: 89,
          ),
          BodyMeasurement(date: DateTime(2026, 8, 15), weightKg: 79.2),
          BodyMeasurement(date: DateTime(2026, 8, 22), weightKg: 79),
        ]
      : [];

  @override
  Future<ProgressSummary> loadSummary() async => const ProgressSummary(
    observationCount: 4,
    currentWeightKg: 79,
    weightChangeKg: -1,
    currentWaistCm: 89,
    waistChangeCm: -1,
  );

  @override
  Future<void> saveMeasurement(BodyMeasurement measurement) async {}

  @override
  Future<List<ProgressPhotoSet>> loadPhotoSets() async => const [];
  @override
  Future<void> grantPhotoStorageConsent() async {}
  @override
  Future<String> beginPhotoSet() async => 'set-1';
  @override
  Future<void> uploadPhoto({
    required String setId,
    required String pose,
    required Uint8List bytes,
    required String contentType,
  }) async {}
  @override
  Future<List<String>> createPhotoReadUrls(ProgressPhotoSet set) async =>
      const [];
  @override
  Future<void> deletePhotoSet(ProgressPhotoSet set) async {}

  @override
  Future<WeeklyProgressReview?> loadLatestWeeklyReview() async => withTrend
      ? WeeklyProgressReview(
          id: 'review-1',
          week: DateTime(2026, 8, 17),
          outcomeCode: 'week_observed',
          plannedSessions: 3,
          completedWorkouts: 2,
          completedSets: 18,
          adherencePercent: 67,
          checkInDays: 3,
          averageEnergy: 3.7,
          averageSoreness: 2.3,
          healthDays: 5,
          confirmedNutritionDays: 4,
          measurementDays: 4,
          missingData: const [],
          nextFocusCode: 'continue_approved_plan',
          acknowledged: false,
        )
      : null;

  @override
  Future<WeeklyReviewJob?> loadLatestWeeklyReviewJob() async => null;

  @override
  Future<void> requestWeeklyReview() async {}

  @override
  Future<void> acknowledgeWeeklyReview(String reviewId) async {}
}
