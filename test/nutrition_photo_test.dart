import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/nutrition_screen.dart';

class _PhotoRepository extends FixtureNutritionRepository
    implements MealPhotoRepository {
  _PhotoRepository({this.failure, this.gate, this.granted = true});

  final MealPhotoFailure? failure;
  final Completer<void>? gate;
  bool granted;
  int analyzed = 0;
  final consents = <String>[];
  String? mealType;

  @override
  Future<PhotoAiNotice> loadMealPhotoNotice() async => PhotoAiNotice(
    version: 'meal-photo-ai-v1',
    providerLabel: 'Groq',
    model: 'qwen/qwen3.8-27b',
    body: 'Tracend sends Groq a resized copy of that one photo.',
    granted: granted,
  );

  @override
  Future<void> recordMealPhotoConsent({
    required String noticeVersion,
    required bool granted,
  }) async {
    consents.add(noticeVersion);
    this.granted = granted;
  }

  @override
  Future<String> analyzeMealPhoto({
    required DateTime date,
    required String mealType,
    required Uint8List bytes,
  }) async {
    analyzed++;
    this.mealType = mealType;
    await gate?.future;
    if (failure != null) throw failure!;
    return 'meal-1';
  }
}

Future<XFile?> _photo(ImageSource source) async =>
    XFile.fromData(Uint8List.fromList(const [1, 2, 3]), name: 'meal.jpg');

Widget _app(_PhotoRepository repository, MealPhotoPicker pickPhoto) =>
    MaterialApp(
      theme: TracendTheme.light,
      home: Scaffold(
        body: NutritionScreen(repository: repository, pickPhoto: pickPhoto),
      ),
    );

/// Opens Log a meal, optionally picks a meal type, then picks [label].
Future<void> _tap(WidgetTester tester, String label, {String? mealType}) async {
  final button = find.byKey(const ValueKey('log-a-meal'));
  await tester.scrollUntilVisible(
    button,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  if (mealType != null) {
    await tester.tap(find.text(mealType));
    await tester.pump();
  }
  await tester.tap(find.text(label));
  await tester.pump();
}

void main() {
  testWidgets(
    'a refused camera explains the setting instead of doing nothing',
    (tester) async {
      final repository = _PhotoRepository();
      await tester.pumpWidget(
        _app(
          repository,
          (_) => throw PlatformException(code: 'camera_access_denied'),
        ),
      );
      await tester.pumpAndSettle();

      await _tap(tester, 'Take a photo');
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.text(
          mealPhotoFailureMessage(
            const MealPhotoFailure('picker', 'camera_access_denied'),
          ),
        ),
        findsOneWidget,
      );
      expect(repository.analyzed, 0);
    },
  );

  testWidgets('a failed analysis names the step and code under the buttons', (
    tester,
  ) async {
    final repository = _PhotoRepository(
      failure: const MealPhotoFailure(
        'analysis',
        '503 meal_analysis_unavailable',
      ),
    );
    await tester.pumpWidget(_app(repository, _photo));
    await tester.pumpAndSettle();

    await _tap(tester, 'Choose from Photo Library');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Photo analysis did not work this time.'),
      findsOneWidget,
    );
    expect(
      find.text('Beta diagnostic · analysis: 503 meal_analysis_unavailable'),
      findsOneWidget,
    );
    expect(repository.analyzed, 1);
  });

  testWidgets('progress shows while the photo is analyzed', (tester) async {
    final gate = Completer<void>();
    final repository = _PhotoRepository(gate: gate);
    await tester.pumpWidget(_app(repository, _photo));
    await tester.pumpAndSettle();

    await _tap(tester, 'Choose from Photo Library');
    await tester.pump();
    expect(find.text('Analyzing meal photo…'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Analyzing meal photo…'), findsNothing);
  });

  testWidgets('a photo meal is saved under the meal type chosen', (
    tester,
  ) async {
    final repository = _PhotoRepository();
    await tester.pumpWidget(_app(repository, _photo));
    await tester.pumpAndSettle();

    await _tap(tester, 'Choose from Photo Library', mealType: 'Dinner');
    await tester.pumpAndSettle();

    expect(repository.mealType, 'dinner');
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    final repository = _PhotoRepository();
    await tester.pumpWidget(_app(repository, (_) async => null));
    await tester.pumpAndSettle();

    await _tap(tester, 'Choose from Photo Library');
    await tester.pumpAndSettle();

    expect(repository.analyzed, 0);
    expect(find.textContaining('Photo analysis did not work'), findsNothing);
  });

  test('access and size problems name what to do', () {
    expect(
      mealPhotoFailureMessage(
        const MealPhotoFailure('picker', 'photo_access_denied'),
      ),
      contains('Settings › Tracend › Photos'),
    );
    expect(
      mealPhotoFailureMessage(
        const MealPhotoFailure('upload', 'photo_too_large'),
      ),
      'This photo is larger than 4 MB. Choose a smaller one.',
    );
  });

  test('a photo iOS cannot load, no food, and limits say what happened', () {
    expect(
      mealPhotoFailureMessage(
        const MealPhotoFailure('picker', 'invalid_image'),
      ),
      contains('iCloud'),
    );
    expect(
      mealPhotoFailureMessage(
        const MealPhotoFailure('analysis', '422 meal_no_food_found'),
      ),
      startsWith('No food was found in this photo.'),
    );
    expect(
      mealPhotoFailureMessage(
        const MealPhotoFailure('analysis', '429 meal_vision_busy'),
      ),
      contains('Wait a minute'),
    );
    expect(
      mealPhotoFailureMessage(
        const MealPhotoFailure('analysis', '429 ai_usage_limit'),
      ),
      contains(r'$2'),
    );
    expect(
      mealPhotoFailureMessage(
        const MealPhotoFailure('analysis', '503 meal_analysis_unavailable'),
      ),
      startsWith('Photo analysis did not work this time.'),
    );
    expect(
      mealPhotoFailureDiagnostic(
        const MealPhotoFailure('analysis', '503 meal_analysis_unavailable'),
      ),
      'Beta diagnostic · analysis: 503 meal_analysis_unavailable',
    );
    expect(
      mealPhotoFailureDiagnostic(
        const MealPhotoFailure('analysis', '429 meal_vision_busy'),
      ),
      isNull,
    );
  });

  testWidgets('the meal photo notice comes before the picker', (tester) async {
    final repository = _PhotoRepository(granted: false);
    var picked = 0;
    await tester.pumpWidget(
      _app(repository, (source) {
        picked++;
        return _photo(source);
      }),
    );
    await tester.pumpAndSettle();

    await _tap(tester, 'Choose from Photo Library');
    await tester.pumpAndSettle();
    expect(find.text('Analyze meal photos with AI?'), findsOneWidget);
    expect(picked, 0);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(picked, 0);
    expect(repository.analyzed, 0);
    expect(repository.consents, isEmpty);
  });

  testWidgets('agreeing records the grant, then the photo is analyzed', (
    tester,
  ) async {
    final repository = _PhotoRepository(granted: false);
    await tester.pumpWidget(_app(repository, _photo));
    await tester.pumpAndSettle();

    await _tap(tester, 'Choose from Photo Library');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agree and continue'));
    await tester.pumpAndSettle();

    expect(repository.consents, ['meal-photo-ai-v1']);
    expect(repository.analyzed, 1);
  });
}
