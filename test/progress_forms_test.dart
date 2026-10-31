import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/progress/physique_check_repository.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/progress_screen.dart';
import 'package:tracend/features/progress/widgets/measurement_widgets.dart';

class _Physique extends FixturePhysiqueCheckRepository {
  const _Physique(this.provider);
  final String? provider;
  @override
  Future<String?> loadProvider() async => provider;
}

class _Progress implements ProgressRepository {
  _Progress({
    this.consented = false,
    this.failAcknowledge = false,
    this.failConsentRead = false,
    this.failSave = false,
  });

  bool consented;
  final bool failAcknowledge;
  final bool failConsentRead;
  final bool failSave;
  int grants = 0;
  int consentReads = 0;
  int acknowledged = 0;
  BodyMeasurement? saved;

  @override
  Future<List<BodyMeasurement>> loadMeasurements() async => [
    BodyMeasurement(date: DateTime(2026, 8, 1), weightKg: 80),
  ];

  @override
  Future<ProgressSummary> loadSummary() async => const ProgressSummary(
    observationCount: 1,
    currentWeightKg: 80,
    weightChangeKg: null,
    currentWaistCm: null,
    waistChangeCm: null,
  );

  @override
  Future<void> saveMeasurement(BodyMeasurement measurement) async {
    if (failSave) {
      throw const PostgrestException(message: 'check', code: '23514');
    }
    saved = measurement;
  }

  @override
  Future<List<ProgressPhotoSet>> loadPhotoSets() async => const [];

  @override
  Future<bool> hasPhotoStorageConsent() async {
    consentReads++;
    if (failConsentRead) throw Exception('offline');
    return consented;
  }

  @override
  Future<void> grantPhotoStorageConsent() async {
    grants++;
    consented = true;
  }

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
  Future<WeeklyProgressReview?> loadLatestWeeklyReview() async =>
      WeeklyProgressReview(
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
      );

  @override
  Future<WeeklyReviewJob?> loadLatestWeeklyReviewJob() async => null;

  @override
  Future<void> requestWeeklyReview() async {}

  @override
  Future<void> acknowledgeWeeklyReview(String reviewId) async {
    acknowledged++;
    if (failAcknowledge) throw Exception('offline');
  }
}

Future<XFile?> _photo(ImageSource source) async => null;

Future<void> _pump(
  WidgetTester tester,
  ProgressRepository repository, {
  PhysiqueCheckRepository physique = const FixturePhysiqueCheckRepository(),
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: ProgressScreen(
          repository: repository,
          physique: physique,
          now: () => DateTime(2026, 8, 25),
          pickPhoto: _photo,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

void main() {
  group('private photo storage consent', () {
    testWidgets('agreed earlier: no question and no new record', (
      tester,
    ) async {
      final repository = _Progress(consented: true);
      await _pump(tester, repository);
      await _reveal(tester, find.text('Take progress photos'));
      await tester.tap(find.text('Take progress photos'));
      await tester.pumpAndSettle();
      expect(find.text('I agree and continue'), findsNothing);
      expect(find.text('Front photo'), findsOneWidget);
      expect(repository.grants, 0);
    });

    testWidgets('the first time asks once and records once', (tester) async {
      final repository = _Progress();
      await _pump(tester, repository);
      await _reveal(tester, find.text('Take progress photos'));
      await tester.tap(find.text('Take progress photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I agree and continue'));
      await tester.pumpAndSettle();
      expect(repository.grants, 1);
      // Closing and opening again in the same session asks nothing more.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('Take progress photos'));
      await tester.tap(find.text('Take progress photos'));
      await tester.pumpAndSettle();
      expect(find.text('I agree and continue'), findsNothing);
      expect(repository.grants, 1);
    });

    testWidgets(
      'an account without physique checks is told photos stay out of AI',
      (tester) async {
        await _pump(tester, _Progress());
        await _reveal(tester, find.text('Take progress photos'));
        await tester.tap(find.text('Take progress photos'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('never sent to an AI model'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a physique-check account is told the truth about AI', (
      tester,
    ) async {
      await _pump(tester, _Progress(), physique: const _Physique('Anthropic'));
      await _reveal(tester, find.text('Take progress photos'));
      await tester.tap(find.text('Take progress photos'));
      await tester.pumpAndSettle();
      expect(find.textContaining('never sent to an AI model'), findsNothing);
      expect(
        find.textContaining(
          'sent to an AI model only if you choose a physique check',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('asks for your permission first'),
        findsOneWidget,
      );
    });

    testWidgets('if the record cannot be read nothing is asked or written', (
      tester,
    ) async {
      final repository = _Progress(failConsentRead: true);
      await _pump(tester, repository);
      await _reveal(tester, find.text('Take progress photos'));
      await tester.tap(find.text('Take progress photos'));
      await tester.pumpAndSettle();
      expect(find.text('I agree and continue'), findsNothing);
      expect(
        find.text('Could not check your photo settings. Try again.'),
        findsOneWidget,
      );
      expect(repository.grants, 0);
    });
  });

  group('weekly review', () {
    testWidgets(
      'a failed acknowledgement shows a message instead of crashing',
      (tester) async {
        final repository = _Progress(failAcknowledge: true);
        await _pump(tester, repository);
        await _reveal(tester, find.text('Open weekly review'));
        await tester.tap(find.text('Open weekly review'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mark reviewed'));
        await tester.pumpAndSettle();
        expect(repository.acknowledged, 1);
        expect(tester.takeException(), isNull);
        expect(
          find.text('Could not mark the weekly review as seen. Try again.'),
          findsOneWidget,
        );
      },
    );
  });

  group('weigh-in form', () {
    Future<void> open(WidgetTester tester, _Progress repository) async {
      await _pump(tester, repository);
      await tester.tap(find.byTooltip('Record measurement'));
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Save measurement'));
      await tester.tap(find.text('Save measurement'));
      await tester.pumpAndSettle();
    }

    testWidgets('a weight outside the stored range is stopped on the form', (
      tester,
    ) async {
      final repository = _Progress();
      await open(tester, repository);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Weight *'),
        '400',
      );
      await save(tester);
      expect(find.text('Between 25 and 350 kg'), findsOneWidget);
      expect(repository.saved, isNull);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Weight *'),
        '20',
      );
      await save(tester);
      expect(find.text('Between 25 and 350 kg'), findsOneWidget);
    });

    testWidgets('each measurement has its own range', (tester) async {
      final repository = _Progress();
      await open(tester, repository);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Weight *'),
        '80',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Waist'), '5');
      await tester.enterText(find.widgetWithText(TextFormField, 'Arm'), '150');
      await save(tester);
      expect(find.text('Between 30 and 250 cm'), findsOneWidget);
      expect(find.text('Between 10 and 100 cm'), findsOneWidget);
      expect(repository.saved, isNull);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Waist'),
        '85,5',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Arm'), '38');
      await save(tester);
      expect(repository.saved!.waistCm, 85.5);
      expect(repository.saved!.armCm, 38);
    });

    testWidgets(
      'a value the database still refuses is not a connection problem',
      (tester) async {
        final repository = _Progress(failSave: true);
        await open(tester, repository);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Weight *'),
          '80',
        );
        await save(tester);
        expect(
          find.text(
            'A value is outside the range Tracend accepts. Check the numbers and try again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('connection'), findsNothing);
      },
    );

    test('the save message names the range only for a check violation', () {
      expect(
        measurementSaveMessage(
          const PostgrestException(message: 'x', code: '23514'),
        ),
        contains('outside the range'),
      );
      expect(
        measurementSaveMessage(const PostgrestException(message: 'x')),
        'Could not save measurement. Check your connection and try again.',
      );
      expect(
        measurementSaveMessage(Exception('offline')),
        'Could not save measurement. Check your connection and try again.',
      );
    });

    test('the form ranges are the database ranges', () {
      expect(measurementRanges, const [
        (25, 350),
        (30, 250),
        (30, 250),
        (30, 250),
        (10, 100),
        (20, 150),
      ]);
    });
  });
}
