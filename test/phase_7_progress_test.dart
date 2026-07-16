import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/progress_screen.dart';

void main() {
  testWidgets('Progress starts with honest empty evidence state', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Repository()));
    await tester.pumpAndSettle();
    expect(find.text('Add your first weigh-in'), findsOneWidget);
    expect(find.text('No measurements yet'), findsOneWidget);
    await _reveal(tester, find.text('Record measurement'));
    expect(find.text('Record measurement'), findsOneWidget);
  });

  testWidgets('Measurement form validates and saves canonical values', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Record measurement'));
    await tester.tap(find.text('Record measurement'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save measurement'));
    await tester.tap(find.text('Save measurement'));
    await tester.pump();
    expect(find.text('Enter a valid weight'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Weight *'),
      '78.4',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Waist'), '86');
    await tester.ensureVisible(find.text('Save measurement'));
    await tester.tap(find.text('Save measurement'));
    await tester.pumpAndSettle();
    expect(repository.saved?.weightKg, 78.4);
    expect(repository.saved?.waistCm, 86);
  });

  testWidgets('Trend has accessible summary and weekly review', (tester) async {
    await tester.pumpWidget(_app(_Repository(withTrend: true)));
    await tester.pumpAndSettle();
    expect(find.text('79.0 kg'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Weight trend from')), findsOneWidget);
    await _reveal(tester, find.text('Open weekly review'));
    await tester.tap(find.text('Open weekly review'));
    await tester.pumpAndSettle();
    expect(find.text('1 · Outcome'), findsOneWidget);
    expect(
      find.textContaining('No persistent plan change is implied'),
      findsOneWidget,
    );
  });

  testWidgets('Weekly review request exposes queued feedback', (tester) async {
    final repository = _Repository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Generate review'));
    await tester.tap(find.text('Generate review'));
    await tester.pumpAndSettle();
    expect(repository.reviewRequested, isTrue);
    await _reveal(tester, find.text('Weekly review is preparing'));
    expect(find.text('Weekly review is preparing'), findsOneWidget);
  });

  testWidgets('Weekly review explains an expired session', (tester) async {
    await tester.pumpWidget(_app(_Repository(sessionExpired: true)));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Generate review'));
    await tester.tap(find.text('Generate review'));
    await tester.pump();
    expect(
      find.text('Your session expired. Sign out, then sign in again.'),
      findsOneWidget,
    );
  });

  testWidgets('Stored weekly review shows evidence and acknowledgement', (
    tester,
  ) async {
    final repository = _Repository(withTrend: true);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Open weekly review'));
    await tester.tap(find.text('Open weekly review'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 of 3 planned workouts'), findsOneWidget);
    expect(find.textContaining('No persistent plan change'), findsOneWidget);
    await tester.ensureVisible(find.text('Mark reviewed'));
    await tester.tap(find.text('Mark reviewed'));
    await tester.pumpAndSettle();
    expect(repository.acknowledgedReviewId, 'review-1');
  });
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.pump();
}

Widget _app(ProgressRepository repository) => MaterialApp(
  theme: TracendTheme.light,
  home: Scaffold(body: ProgressScreen(repository: repository)),
);

class _Repository implements ProgressRepository {
  _Repository({this.withTrend = false, this.sessionExpired = false});
  final bool withTrend;
  final bool sessionExpired;
  BodyMeasurement? saved;
  bool reviewRequested = false;
  String? acknowledgedReviewId;
  @override
  Future<List<BodyMeasurement>> loadMeasurements() async => withTrend
      ? [
          BodyMeasurement(date: DateTime(2026, 6, 25), weightKg: 80),
          BodyMeasurement(
            date: DateTime(2026, 7, 2),
            weightKg: 79,
            waistCm: 89,
          ),
        ]
      : [];
  @override
  Future<ProgressSummary> loadSummary() async => withTrend
      ? const ProgressSummary(
          observationCount: 2,
          currentWeightKg: 79,
          weightChangeKg: -1,
          currentWaistCm: 89,
          waistChangeCm: -1,
        )
      : const ProgressSummary(
          observationCount: 0,
          currentWeightKg: null,
          weightChangeKg: null,
          currentWaistCm: null,
          waistChangeCm: null,
        );
  @override
  Future<void> saveMeasurement(BodyMeasurement measurement) async {
    saved = measurement;
  }

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
          week: DateTime(2026, 6, 29),
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
          measurementDays: 1,
          missingData: const [],
          nextFocusCode: 'continue_approved_plan',
          acknowledged: false,
        )
      : null;

  @override
  Future<WeeklyReviewJob?> loadLatestWeeklyReviewJob() async => reviewRequested
      ? WeeklyReviewJob(status: 'queued', week: DateTime(2026, 6, 29))
      : null;

  @override
  Future<void> requestWeeklyReview() async {
    if (sessionExpired) throw const ProgressSessionException();
    reviewRequested = true;
  }

  @override
  Future<void> acknowledgeWeeklyReview(String reviewId) async {
    acknowledgedReviewId = reviewId;
  }
}
