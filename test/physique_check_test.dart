import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/progress/physique_check_repository.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/progress_screen.dart';
import 'package:tracend/features/progress/widgets/physique_check_widgets.dart';

const _privateCopy = 'Only you can see these. Never sent to AI.';
const _checkCopy =
    'Only you can see these. Sent to Groq only when you start a physique '
    'check.';
const _noticeFirst = 'Tracend sends your front, side and back photos to Groq.';
const _noticeSecond = 'Groq runs qwen/qwen3.8-27b and keeps nothing.';

final _resultJson = <String, Object?>{
  'schema_version': '1.0',
  'development_priorities': [
    {
      'muscle': 'chest',
      'confidence': 'high',
      'reason': 'Upper chest looks flatter than the shoulders.',
    },
    {
      'muscle': 'calves',
      'confidence': 'medium',
      'reason': 'Calves look small next to the thighs.',
    },
    {
      'muscle': 'shoulders',
      'confidence': 'low',
      'reason': 'Side delts are hard to see.',
    },
  ],
  'observations': ['Back is broad for the waist.'],
  'photo_issues': ['lighting', 'pose'],
  'limitations': 'Photos cannot show strength or body fat precisely.',
};

PhysiqueAnalysis _analysis({List<String> confirmed = const []}) =>
    PhysiqueAnalysis(
      id: 'analysis-1',
      photoSetId: 'set-2',
      result: PhysiqueCheckResult.fromJson(_resultJson)!,
      confirmedMuscles: confirmed,
      createdAt: DateTime(2026, 8, 24),
    );

Widget _app(_Physique physique, {bool completeSet = true}) => MaterialApp(
  theme: TracendTheme.dark,
  home: Scaffold(
    body: ProgressScreen(
      repository: _Progress(completeSet: completeSet),
      physique: physique,
      now: () => DateTime(2026, 8, 25),
    ),
  ),
);

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpProgress(
  WidgetTester tester,
  _Physique physique, {
  bool completeSet = true,
}) async {
  await tester.pumpWidget(_app(physique, completeSet: completeSet));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Take progress photos'),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

final _checkAction = find.widgetWithText(OutlinedButton, 'Physique check');

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(PhysiqueCheckSheet), matching: finder);

Future<void> _startCheck(WidgetTester tester) async {
  await tester.tap(_checkAction);
  await tester.pumpAndSettle();
}

Future<void> _tapInSheet(WidgetTester tester, String text) async {
  final target = _inSheet(find.text(text));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  group('PhysiqueCheckResult.fromJson', () {
    test('keeps known values and drops unknown ones', () {
      final result = PhysiqueCheckResult.fromJson({
        'development_priorities': [
          {'muscle': 'neck', 'confidence': 'high', 'reason': 'x'},
          {'muscle': 'chest', 'confidence': 'certain', 'reason': 'x'},
          {'muscle': 'calves', 'confidence': 'low', 'reason': ' Small. '},
          {'muscle': 'calves', 'confidence': 'high', 'reason': 'Repeat.'},
          'quads',
        ],
        'observations': ['Broad back.', 7, '  '],
        'photo_issues': ['blur', 'tan', 'blur'],
        'limitations': 3,
      })!;
      expect(result.priorities.map((p) => p.muscle), ['calves']);
      expect(result.priorities.single.confidence, 'low');
      expect(result.priorities.single.reason, 'Small.');
      expect(result.observations, ['Broad back.']);
      expect(result.photoIssues, ['blur']);
      expect(result.limitations, isEmpty);
    });

    test('a result without a usable priority is null', () {
      expect(
        PhysiqueCheckResult.fromJson({
          'development_priorities': [
            {'muscle': 'neck', 'confidence': 'high', 'reason': 'x'},
          ],
          'observations': ['Broad back.'],
        }),
        isNull,
      );
      expect(PhysiqueCheckResult.fromJson({'observations': []}), isNull);
      expect(PhysiqueCheckResult.fromJson('chest'), isNull);
    });

    test('notice parsing needs a version and a body', () {
      final notice = PhotoAiNotice.fromJson({
        'version': 'progress-photo-ai-v1',
        'provider_label': 'Groq',
        'model': 'qwen/qwen3.8-27b',
        'body': 'One.\n\nTwo.',
        'granted': true,
      })!;
      expect(notice.paragraphs, ['One.', 'Two.']);
      expect(notice.granted, isTrue);
      expect(PhotoAiNotice.fromJson({'version': 'v1', 'body': ' '}), isNull);
    });
  });

  testWidgets('disabled accounts keep the photo card unchanged', (
    tester,
  ) async {
    _tallView(tester);
    await _pumpProgress(tester, _Physique(enabled: false));
    expect(find.text(_privateCopy), findsOneWidget);
    expect(find.text(_checkCopy), findsNothing);
    expect(find.text('Physique check'), findsNothing);
    expect(find.textContaining('Focus suggested'), findsNothing);
  });

  testWidgets(
    'a check run before the feature was switched off stays disclosed',
    (tester) async {
      _tallView(tester);
      await _pumpProgress(
        tester,
        _Physique(enabled: false, latest: _analysis()),
      );
      expect(find.text(_privateCopy), findsNothing);
      expect(
        find.text(
          'Only you can see these. A set was sent to AI only for a physique '
          'check you started.',
        ),
        findsOneWidget,
      );
      expect(_checkAction, findsNothing);
      expect(find.textContaining('Focus suggested'), findsOneWidget);
    },
  );

  testWidgets('deleting a set drops the check that went with it', (
    tester,
  ) async {
    _tallView(tester);
    final physique = _Physique(latest: _analysis());
    await _pumpProgress(tester, physique);
    expect(find.textContaining('Focus suggested'), findsOneWidget);
    await tester.tap(find.text('View past set'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete photo set'));
    await tester.pumpAndSettle();
    physique.latest = null;
    await tester.tap(find.text('Delete set'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Focus suggested'), findsNothing);
    expect(physique.latestLoads, 2);
  });

  testWidgets('enabled accounts see the check on a complete newest set', (
    tester,
  ) async {
    _tallView(tester);
    await _pumpProgress(tester, _Physique());
    expect(find.text(_checkCopy), findsOneWidget);
    expect(find.text(_privateCopy), findsNothing);
    expect(_checkAction, findsOneWidget);
  });

  testWidgets('an unfinished newest set offers no check', (tester) async {
    _tallView(tester);
    await _pumpProgress(tester, _Physique(), completeSet: false);
    expect(find.text(_checkCopy), findsOneWidget);
    expect(_checkAction, findsNothing);
  });

  testWidgets('consent shows the server notice and is recorded first', (
    tester,
  ) async {
    _tallView(tester);
    final physique = _Physique();
    await _pumpProgress(tester, physique);
    await _startCheck(tester);
    expect(find.text('Check your photos with AI?'), findsOneWidget);
    expect(find.text(_noticeFirst), findsOneWidget);
    expect(find.text(_noticeSecond), findsOneWidget);
    expect(physique.log, isEmpty);

    await _tapInSheet(tester, 'Agree and check');
    expect(physique.log, [
      'consent:granted:progress-photo-ai-v1',
      'check:set-2',
    ]);
    expect(
      _inSheet(find.text('AI visual estimate, not a measurement.')),
      findsOneWidget,
    );
  });

  testWidgets('Not now on the notice records nothing and runs nothing', (
    tester,
  ) async {
    _tallView(tester);
    final physique = _Physique();
    await _pumpProgress(tester, physique);
    await _startCheck(tester);
    await _tapInSheet(tester, 'Not now');
    expect(find.byType(PhysiqueCheckSheet), findsNothing);
    expect(physique.log, isEmpty);
  });

  testWidgets('the running state, then the result with tips', (tester) async {
    _tallView(tester);
    final pending = Completer<PhysiqueAnalysis>();
    final physique = _Physique(granted: true, pending: pending);
    await _pumpProgress(tester, physique);
    await tester.tap(_checkAction);
    await tester.pump();
    await tester.pump();
    expect(find.text('Checking your photos…'), findsOneWidget);
    expect(find.text('Usually under 30 seconds.'), findsOneWidget);

    pending.complete(_analysis());
    await tester.pumpAndSettle();
    expect(_inSheet(find.text('Physique check')), findsOneWidget);
    expect(
      _inSheet(find.text('AI visual estimate, not a measurement.')),
      findsOneWidget,
    );
    expect(_inSheet(find.text('Chest')), findsOneWidget);
    expect(
      _inSheet(
        find.text(
          'High confidence · Upper chest looks flatter than the shoulders.',
        ),
      ),
      findsOneWidget,
    );
    expect(_inSheet(find.textContaining('Medium confidence')), findsOneWidget);
    expect(_inSheet(find.textContaining('Low confidence')), findsOneWidget);
    expect(_inSheet(find.text('Back is broad for the waist.')), findsOneWidget);
    expect(_inSheet(find.text('Lighting was uneven')), findsOneWidget);
    expect(
      _inSheet(find.text('Poses differed from the guide')),
      findsOneWidget,
    );
    expect(
      _inSheet(find.text('Photos cannot show strength or body fat precisely.')),
      findsOneWidget,
    );
  });

  testWidgets('at most two focus muscles, then they are saved', (tester) async {
    _tallView(tester);
    final physique = _Physique(granted: true);
    await _pumpProgress(tester, physique);
    await _startCheck(tester);

    await _tapInSheet(tester, 'Chest');
    await _tapInSheet(tester, 'Calves');
    expect(find.text('Pick at most two'), findsNothing);
    await _tapInSheet(tester, 'Shoulders');
    expect(find.text('Pick at most two'), findsOneWidget);
    final boxes = tester
        .widgetList<Checkbox>(_inSheet(find.byType(Checkbox)))
        .map((box) => box.value)
        .toList();
    expect(boxes, [true, true, false]);

    await _tapInSheet(tester, 'Use as my focus');
    expect(physique.log.last, 'focus:chest,calves@analysis-1');
    expect(
      find.text(
        'Your focus is now chest and calves. The Coach uses it now; your '
        'plan uses it at its next review.',
      ),
      findsOneWidget,
    );
    await _tapInSheet(tester, 'Done');
    expect(find.byType(PhysiqueCheckSheet), findsNothing);
  });

  for (final error in PhysiqueCheckError.values.where(
    (error) => error != PhysiqueCheckError.consentRequired,
  )) {
    testWidgets('${error.code} shows its message in the sheet', (tester) async {
      _tallView(tester);
      await _pumpProgress(tester, _Physique(granted: true, checkError: error));
      await _startCheck(tester);
      expect(_inSheet(find.text(error.message)), findsOneWidget);
      expect(
        _inSheet(find.text('Try again')),
        error.retryable ? findsOneWidget : findsNothing,
      );
      expect(_inSheet(find.text('Close')), findsOneWidget);
    });
  }

  test('the error messages match the server codes', () {
    expect(
      PhysiqueCheckError.fromCode('ai_usage_limit').message,
      "You've reached today's AI limit. Try again tomorrow.",
    );
    expect(
      PhysiqueCheckError.fromCode('physique_check_busy').message,
      'The photo check is busy. Try again in a minute.',
    );
    expect(
      PhysiqueCheckError.fromCode('photo_set_unsupported').message,
      "These photos can't be checked. Take a new set with the camera.",
    );
    expect(
      PhysiqueCheckError.fromCode('physique_check_invalid').message,
      "The check didn't return a usable answer. Nothing was saved. Try again.",
    );
    expect(
      PhysiqueCheckError.fromCode('something_new'),
      PhysiqueCheckError.failed,
    );
  });

  testWidgets('a consent_required check shows the notice again', (
    tester,
  ) async {
    _tallView(tester);
    final physique = _Physique(
      granted: true,
      checkError: PhysiqueCheckError.consentRequired,
    );
    await _pumpProgress(tester, physique);
    await _startCheck(tester);
    expect(find.text('Check your photos with AI?'), findsOneWidget);
    expect(find.text(_noticeFirst), findsOneWidget);
  });

  testWidgets('turning off photo checks records a withdrawal', (tester) async {
    _tallView(tester);
    final physique = _Physique(granted: true);
    await _pumpProgress(tester, physique);
    await _startCheck(tester);
    await _tapInSheet(tester, 'Turn off photo checks');
    expect(physique.log.last, 'consent:withdrawn:progress-photo-ai-v1');
    expect(
      find.text('Photo checks are off. The next check asks you first.'),
      findsOneWidget,
    );
    expect(find.text('Turn off photo checks'), findsNothing);

    await _tapInSheet(tester, 'Not now');
    await _startCheck(tester);
    expect(find.text('Check your photos with AI?'), findsOneWidget);
  });

  testWidgets('the latest check shows on the card and opens without a run', (
    tester,
  ) async {
    _tallView(tester);
    final physique = _Physique(latest: _analysis());
    await _pumpProgress(tester, physique);
    expect(find.text('Focus suggested: chest, calves, shoulders'), findsOne);
    await tester.tap(find.text('Focus suggested: chest, calves, shoulders'));
    await tester.pumpAndSettle();
    expect(
      _inSheet(find.text('AI visual estimate, not a measurement.')),
      findsOneWidget,
    );
    expect(physique.log, isEmpty);
    // Not granted, so there is nothing to turn off.
    expect(find.text('Turn off photo checks'), findsNothing);
  });

  testWidgets('a confirmed focus shows on the card and is preselected', (
    tester,
  ) async {
    _tallView(tester);
    final physique = _Physique(
      granted: true,
      latest: _analysis(confirmed: ['calves']),
    );
    await _pumpProgress(tester, physique);
    await tester.tap(find.text('Your focus: calves'));
    await tester.pumpAndSettle();
    final boxes = tester
        .widgetList<Checkbox>(_inSheet(find.byType(Checkbox)))
        .map((box) => box.value)
        .toList();
    expect(boxes, [false, true, false]);
    expect(find.text('Turn off photo checks'), findsOneWidget);
  });

  testWidgets('photo card and result sheet fit 320pt at 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final physique = _Physique(granted: true, latest: _analysis());
    await tester.pumpWidget(_app(physique));
    await tester.pumpAndSettle();
    final summary = find.text('Focus suggested: chest, calves, shoulders');
    await tester.scrollUntilVisible(
      summary,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(summary);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 12; i++) {
      await tester.drag(
        _inSheet(find.byType(Scrollable)).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Turn off photo checks'), findsOneWidget);
  });
}

class _Physique implements PhysiqueCheckRepository {
  _Physique({
    this.enabled = true,
    this.granted = false,
    this.latest,
    this.checkError,
    this.pending,
  });

  final bool enabled;
  bool granted;
  PhysiqueAnalysis? latest;
  final PhysiqueCheckError? checkError;
  final Completer<PhysiqueAnalysis>? pending;
  final log = <String>[];
  int latestLoads = 0;

  @override
  Future<String?> loadProvider() async => enabled ? 'Groq' : null;

  @override
  Future<PhotoAiNotice> loadNotice() async => PhotoAiNotice(
    version: 'progress-photo-ai-v1',
    providerLabel: 'Groq',
    model: 'qwen/qwen3.8-27b',
    body: '$_noticeFirst\n\n$_noticeSecond',
    granted: granted,
  );

  @override
  Future<void> recordConsent({
    required String noticeVersion,
    required bool granted,
  }) async {
    log.add('consent:${granted ? 'granted' : 'withdrawn'}:$noticeVersion');
    this.granted = granted;
  }

  @override
  Future<PhysiqueAnalysis?> loadLatestAnalysis() async {
    latestLoads++;
    return latest;
  }

  @override
  Future<PhysiqueAnalysis> check(String photoSetId) async {
    log.add('check:$photoSetId');
    if (checkError case final error?) throw PhysiqueCheckException(error);
    return pending?.future ?? _analysis();
  }

  @override
  Future<List<String>> setPriorityMuscles(
    List<String> muscles, {
    required String analysisId,
  }) async {
    log.add('focus:${muscles.join(',')}@$analysisId');
    return muscles;
  }
}

class _Progress implements ProgressRepository {
  _Progress({required this.completeSet});
  final bool completeSet;

  @override
  Future<List<BodyMeasurement>> loadMeasurements() async => const [];
  @override
  Future<ProgressSummary> loadSummary() async => const ProgressSummary(
    observationCount: 0,
    currentWeightKg: null,
    weightChangeKg: null,
    currentWaistCm: null,
    waistChangeCm: null,
  );
  @override
  Future<void> saveMeasurement(BodyMeasurement measurement) async {}
  @override
  Future<List<ProgressPhotoSet>> loadPhotoSets() async => [
    ProgressPhotoSet(
      id: 'set-2',
      date: DateTime(2026, 8, 22),
      status: completeSet ? 'complete' : 'draft',
      objectKeys: completeSet ? const ['a', 'b', 'c', 'd'] : const ['a'],
    ),
  ];
  @override
  Future<void> grantPhotoStorageConsent() async {}
  @override
  Future<String> beginPhotoSet() async => 'set-3';
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
  Future<WeeklyProgressReview?> loadLatestWeeklyReview() async => null;
  @override
  Future<WeeklyReviewJob?> loadLatestWeeklyReviewJob() async => null;
  @override
  Future<void> requestWeeklyReview() async {}
  @override
  Future<void> acknowledgeWeeklyReview(String reviewId) async {}
}
