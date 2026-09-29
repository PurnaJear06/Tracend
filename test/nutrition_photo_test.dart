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
  _PhotoRepository({this.failure, this.gate});

  final MealPhotoFailure? failure;
  final Completer<void>? gate;
  int analyzed = 0;

  @override
  Future<String> analyzeMealPhoto({
    required DateTime date,
    required String mealType,
    required Uint8List bytes,
  }) async {
    analyzed++;
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

Future<void> _tap(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.scrollUntilVisible(
    button,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(button);
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

      await _tap(tester, 'Analyze meal photo');
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
      find.textContaining('(analysis: 503 meal_analysis_unavailable)'),
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

  testWidgets('cancelling the picker changes nothing', (tester) async {
    final repository = _PhotoRepository();
    await tester.pumpWidget(_app(repository, (_) async => null));
    await tester.pumpAndSettle();

    await _tap(tester, 'Choose from Photo Library');
    await tester.pumpAndSettle();

    expect(repository.analyzed, 0);
    expect(find.textContaining('Meal photo analysis failed'), findsNothing);
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
}
