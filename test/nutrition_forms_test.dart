import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/nutrition_screen.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_sheets.dart';

class _NoticeRepository extends FixtureNutritionRepository
    implements MealPhotoRepository {
  _NoticeRepository(this.notice);

  final Future<PhotoAiNotice> notice;

  @override
  Future<PhotoAiNotice> loadMealPhotoNotice() => notice;

  @override
  Future<void> recordMealPhotoConsent({
    required String noticeVersion,
    required bool granted,
  }) async {}

  @override
  Future<String> analyzeMealPhoto({
    required DateTime date,
    required String mealType,
    required Uint8List bytes,
  }) async => 'meal-1';
}

const _candidate = MealCandidate(
  id: 'c1',
  name: 'Rice bowl',
  servingLabel: '1 bowl',
  calories: 520,
  protein: 24.5,
  carbohydrate: 72,
  fat: 14,
  confidence: 'medium',
);

void main() {
  group('manual meal fields', () {
    testWidgets('every nutrition field takes a decimal point', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.light,
          home: const Scaffold(body: ManualMealSheet()),
        ),
      );
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      // Name and serving are text; calories, protein, carbs and fat are numbers.
      expect(fields, hasLength(6));
      for (final field in fields.skip(2)) {
        expect(field.keyboardType, decimalKeyboard);
        expect(field.keyboardType.decimal, isTrue);
      }
    });

    testWidgets('12.5 g and a decimal comma are accepted', (tester) async {
      ManualMealResult? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await Navigator.of(context).push<ManualMealResult>(
                      MaterialPageRoute(
                        builder: (_) => const Scaffold(body: ManualMealSheet()),
                      ),
                    ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Oats');
      await tester.enterText(fields.at(1), '80 g');
      await tester.enterText(fields.at(2), '300');
      await tester.enterText(fields.at(3), '12.5');
      await tester.enterText(fields.at(4), '52,5');
      await tester.enterText(fields.at(5), '6');
      await tester.ensureVisible(find.text('Confirm meal'));
      await tester.tap(find.text('Confirm meal'));
      await tester.pumpAndSettle();
      expect(result!.food.protein, 12.5);
      expect(result!.food.carbohydrate, 52.5);
    });

    test('numbers are read with a point or a comma and never below zero', () {
      expect(parseDecimal('12.5'), 12.5);
      expect(parseDecimal(' 12,5 '), 12.5);
      expect(parseDecimal('abc'), isNull);
      expect(parseDecimal(null), isNull);
    });
  });

  group('candidate editor', () {
    Future<List<MealCandidate>?> open(WidgetTester tester) async {
      List<MealCandidate>? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => confirmed = await Navigator.of(context)
                    .push<List<MealCandidate>>(
                      MaterialPageRoute(
                        builder: (_) => const Scaffold(
                          body: CandidateSheet(candidates: [_candidate]),
                        ),
                      ),
                    ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return confirmed;
    }

    testWidgets('a value that cannot be confirmed keeps the editor open', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Edit estimate'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Calories'),
        'abc',
      );
      await tester.pump();

      await tester.tap(find.text('Done editing'));
      await tester.pumpAndSettle();
      // Still open, with the message, so the confirm button never sends a
      // value the athlete cannot see.
      expect(find.text('Done editing'), findsOneWidget);
      expect(find.text('Enter zero or more'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Calories'),
        '480',
      );
      await tester.pump();
      await tester.tap(find.text('Done editing'));
      await tester.pumpAndSettle();
      expect(find.text('Edit estimate'), findsOneWidget);
      expect(find.textContaining('480 kcal'), findsOneWidget);
    });

    testWidgets('an emptied name also keeps the editor open', (tester) async {
      await open(tester);
      await tester.tap(find.text('Edit estimate'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Food name'),
        '  ',
      );
      await tester.pump();
      await tester.tap(find.text('Done editing'));
      await tester.pumpAndSettle();
      expect(find.text('Done editing'), findsOneWidget);
      expect(find.text('Enter a value'), findsOneWidget);
    });

    testWidgets(
      'what is confirmed is what the fields show, decimals included',
      (tester) async {
        List<MealCandidate>? confirmed;
        await tester.pumpWidget(
          MaterialApp(
            theme: TracendTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async => confirmed = await Navigator.of(context)
                      .push<List<MealCandidate>>(
                        MaterialPageRoute(
                          builder: (_) => const Scaffold(
                            body: CandidateSheet(candidates: [_candidate]),
                          ),
                        ),
                      ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit estimate'));
        await tester.pumpAndSettle();
        // 24.5 g shows as 24.5, not rounded to 25.
        expect(find.widgetWithText(TextFormField, '24.5'), findsOneWidget);
        await tester.ensureVisible(find.text('Confirm selected foods'));
        await tester.tap(find.text('Confirm selected foods'));
        await tester.pumpAndSettle();
        expect(confirmed!.single.protein, 24.5);
      },
    );
  });

  group('Log meal waits for the photo notice', () {
    Widget app(Future<PhotoAiNotice> notice) => MaterialApp(
      theme: TracendTheme.light,
      home: Scaffold(
        body: NutritionScreen(repository: _NoticeRepository(notice)),
      ),
    );

    Finder logButton() => find.byKey(const ValueKey('log-a-meal'));

    Future<void> reveal(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        logButton(),
        240,
        scrollable: find.byType(Scrollable).first,
      );
    }

    bool enabled(WidgetTester tester) {
      final widget = tester.widget(logButton());
      return widget is ButtonStyleButton && widget.onPressed != null;
    }

    testWidgets('disabled while it loads, enabled after', (tester) async {
      final notice = Completer<PhotoAiNotice>();
      await tester.pumpWidget(app(notice.future));
      await tester.pump();
      await tester.pump();
      await reveal(tester);
      expect(enabled(tester), isFalse);

      notice.complete(
        const PhotoAiNotice(
          version: 'v1',
          providerLabel: 'Anthropic',
          model: 'm',
          body: 'b',
          granted: true,
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester);
      expect(enabled(tester), isTrue);
    });

    testWidgets('a notice that fails to load does not lock the button', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(Future.delayed(Duration.zero, () => throw Exception('offline'))),
      );
      await tester.pumpAndSettle();
      await reveal(tester);
      expect(enabled(tester), isTrue);
    });

    testWidgets('a notice that never loads stops blocking after ten seconds', (
      tester,
    ) async {
      await tester.pumpWidget(app(Completer<PhotoAiNotice>().future));
      await tester.pump();
      await reveal(tester);
      expect(enabled(tester), isFalse);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      await reveal(tester);
      expect(enabled(tester), isTrue);
    });
  });
}
