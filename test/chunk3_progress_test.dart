import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/progress_screen.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/train/workout_repository.dart';

Future<XFile?> _photo(ImageSource source) async =>
    XFile.fromData(Uint8List.fromList(const [1, 2, 3]), name: 'pose.jpg');

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
      now: () => DateTime(2026, 8, 25),
      pickPhoto: _photo,
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

  testWidgets('tapping a recent weigh-in opens the detail sheet', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Repository(withTrend: true)));
    await tester.pumpAndSettle();
    final row = find.text('Sat 22 Aug · Entered by you');
    await _reveal(tester, row);
    expect(find.text('\u22120.2'), findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Sat 22 Aug'), findsOneWidget);
    expect(find.text('Weight'), findsOneWidget);
    expect(find.textContaining('manual'), findsNothing);
  });

  testWidgets('recent weigh-ins show three rows and See all shows every one', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Repository(withTrend: true)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sat 1 Aug'), findsNothing);
    await _reveal(tester, find.text('See all'));
    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    expect(find.text('All weigh-ins'), findsOneWidget);
    expect(find.text('Sat 1 Aug · Entered by you'), findsOneWidget);
  });

  testWidgets('the period control filters the weight chart', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(_Repository(withTrend: true)));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('across 4 weigh-ins')), findsOneWidget);
    await tester.tap(find.text('4W'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('across 4 weigh-ins')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('measurement entry and weekly review open; photos guided', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(_Repository(withTrend: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Record measurement'));
    await tester.pumpAndSettle();
    expect(find.text('Save measurement'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await _reveal(tester, find.text('Open weekly review'));
    await tester.tap(find.text('Open weekly review'));
    await tester.pumpAndSettle();
    expect(find.text('Mark reviewed'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Front photo'), findsNothing);
    await _reveal(tester, find.text('Take progress photos'));
    await tester.tap(find.text('Take progress photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I agree and continue'));
    await tester.pumpAndSettle();
    expect(find.text('Front photo'), findsOneWidget);
    expect(find.text('Lower body'), findsOneWidget);
    expect(find.text('Finish later'), findsOneWidget);
  });

  testWidgets('past photo sets open from one card', (tester) async {
    await tester.pumpWidget(
      _app(_Repository(withTrend: true, withPhotos: true)),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('View past sets (2)'));
    expect(find.text('Last set · Sat 22 Aug'), findsOneWidget);
    await tester.tap(find.text('View past sets (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Past photo sets'), findsOneWidget);
    expect(find.text('4 photos'), findsOneWidget);
    expect(find.text('2 of 4 photos · unfinished'), findsOneWidget);
  });

  testWidgets('strength shows workouts and lift tiles in plain words', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_Repository(withTrend: true), training: _TrainingHub()),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Bench press'));
    expect(find.text('Bench press'), findsOneWidget);
    expect(find.text('80 kg'), findsOneWidget);
    expect(find.text('Best · 3 workouts'), findsOneWidget);
    expect(find.text('Last 12 weeks'), findsOneWidget);
    expect(find.textContaining('display-only'), findsNothing);
  });

  testWidgets('the hero shows the weekly rate in plain words', (tester) async {
    await tester.pumpWidget(
      _app(_Repository(withTrend: true), brief: _Brief(withTrends: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('\u22120.3 kg/week'), findsOneWidget);
    expect(find.text('Steady trend'), findsOneWidget);
    expect(find.text('WEIGHT TREND'), findsNothing);
  });

  testWidgets('a failed pose upload retries into the same photo set', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FlakyUploadRepository(failOnUpload: 2);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Take progress photos'));
    await tester.tap(find.text('Take progress photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I agree and continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Take Front photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Take Side photo'));
    await tester.pumpAndSettle();
    expect(find.text('Photo was not saved. Try again when ready.'), findsOne);
    expect(find.textContaining('1 of 4 done'), findsOneWidget);

    await tester.tap(find.byTooltip('Take Side photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Take Back photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Take Lower body'));
    await tester.pumpAndSettle();

    expect(repository.setsStarted, 1);
    expect(repository.uploads, [
      ('set-1', 'front'),
      ('set-1', 'side'),
      ('set-1', 'back'),
      ('set-1', 'lower'),
    ]);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('full page and photo sheet fit 320pt at 2x text', (tester) async {
    _largeTextPhone(tester);
    await tester.pumpWidget(
      _app(
        _Repository(withTrend: true, withPhotos: true),
        brief: _Brief(withTrends: true),
        training: _TrainingHub(),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 30; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.dragUntilVisible(
      find.text('Take progress photos'),
      find.byType(CustomScrollView),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take progress photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I agree and continue'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Progress photos'), findsOneWidget);
  });
}

void _largeTextPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Upload fails once on the given call, then succeeds.
class _FlakyUploadRepository extends _Repository {
  _FlakyUploadRepository({required this.failOnUpload}) : super(withTrend: true);
  final int failOnUpload;
  int setsStarted = 0;
  final uploads = <(String, String)>[];
  int _attempts = 0;

  @override
  Future<String> beginPhotoSet() async => 'set-${++setsStarted}';

  @override
  Future<void> uploadPhoto({
    required String setId,
    required String pose,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (++_attempts == failOnUpload) throw StateError('network');
    uploads.add((setId, pose));
  }
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
  _Repository({this.withTrend = false, this.withPhotos = false});
  final bool withTrend;
  final bool withPhotos;

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
  Future<List<ProgressPhotoSet>> loadPhotoSets() async => withPhotos
      ? [
          ProgressPhotoSet(
            id: 'set-2',
            date: DateTime(2026, 8, 22),
            status: 'complete',
            objectKeys: const ['a', 'b', 'c', 'd'],
          ),
          ProgressPhotoSet(
            id: 'set-1',
            date: DateTime(2026, 8, 1),
            status: 'draft',
            objectKeys: const ['a', 'b'],
          ),
        ]
      : const [];
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
