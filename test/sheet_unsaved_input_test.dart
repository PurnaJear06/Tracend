import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/memory/coach_fact_editor.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/widgets/nutrition_sheets.dart';
import 'package:tracend/features/progress/widgets/measurement_widgets.dart';
import 'package:tracend/features/readiness/choice_widgets.dart';
import 'package:tracend/features/readiness/pain_check_sheet.dart';
import 'package:tracend/features/readiness/pain_reporting.dart';
import 'package:tracend/features/today/check_in_sheet.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

import 'pain_fakes.dart';

/// Half-typed meals, check-ins, measurements and pain reports are not lost to
/// a stray swipe, scrim tap or close button (UX_FLOWS.md, DESIGN_SYSTEM.md
/// sheets): a sheet with unsaved input asks first, a clean one closes.

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

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

typedef _Opener = Future<void> Function(BuildContext context);

Future<void> _open(WidgetTester tester, _Opener opener) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => opener(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Close'));
  await tester.pumpAndSettle();
}

void _expectAsked() => expect(find.text('Discard changes?'), findsOneWidget);

void _expectClosed(String title) {
  expect(find.text('Discard changes?'), findsNothing);
  expect(find.text(title), findsNothing);
}

void main() {
  group('manual meal sheet', () {
    Future<void> openMeal(WidgetTester tester) => _open(
      tester,
      (context) => showTracendSheet<void>(
        context,
        title: 'Enter meal',
        scrollable: false,
        builder: (_) => ManualMealSheet(onSave: (_) async {}),
      ),
    );

    testWidgets('closes at once while nothing is typed', (tester) async {
      await openMeal(tester);

      await _close(tester);

      _expectClosed('Enter meal');
    });

    testWidgets('asks before losing a typed food name', (tester) async {
      await openMeal(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Food name'),
        'Rice',
      );
      await tester.pumpAndSettle();

      await _close(tester);

      _expectAsked();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Rice'), findsOneWidget);
    });

    testWidgets('asks once another meal is chosen', (tester) async {
      await openMeal(tester);
      await tester.tap(find.text('Dinner'));
      await tester.pumpAndSettle();

      await _close(tester);

      _expectAsked();
    });

    testWidgets('still asks while the meal is being saved, and leaves '
        'without asking once it is saved', (tester) async {
      final saving = Completer<void>();
      await _open(
        tester,
        (context) => showTracendSheet<void>(
          context,
          title: 'Enter meal',
          scrollable: false,
          builder: (_) => ManualMealSheet(onSave: (_) => saving.future),
        ),
      );
      for (final (label, text) in [
        ('Food name', 'Rice'),
        ('Serving', '1 bowl'),
        ('Calories', '200'),
        ('Protein (g)', '4'),
        ('Carbohydrate (g)', '40'),
        ('Fat (g)', '1'),
      ]) {
        await tester.enterText(find.widgetWithText(TextFormField, label), text);
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirm meal'));
      await tester.tap(find.text('Confirm meal'));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);

      await _close(tester);
      _expectAsked();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();

      saving.complete();
      await tester.pumpAndSettle();
      _expectClosed('Enter meal');
    });
  });

  group('candidate sheet', () {
    Future<void> openCandidates(WidgetTester tester) => _open(
      tester,
      (context) => showTracendSheet<void>(
        context,
        title: 'Review candidates',
        scrollable: false,
        builder: (_) => CandidateSheet(
          candidates: const [_candidate],
          onDiscard: () async {},
        ),
      ),
    );

    testWidgets('opening the editors is not an edit', (tester) async {
      await openCandidates(tester);

      await _close(tester);

      _expectClosed('Review candidates');
    });

    testWidgets('asks once a food is deselected', (tester) async {
      await openCandidates(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      await _close(tester);

      _expectAsked();
    });
  });

  group('measurement sheet', () {
    Future<void> openMeasurement(WidgetTester tester) => _open(
      tester,
      (context) => showTracendSheet<void>(
        context,
        title: 'Record measurement',
        scrollable: false,
        builder: (_) => const MeasurementEntrySheet(),
      ),
    );

    testWidgets('closes at once while empty', (tester) async {
      await openMeasurement(tester);

      await _close(tester);

      _expectClosed('Record measurement');
    });

    testWidgets('asks before losing a typed weight', (tester) async {
      await openMeasurement(tester);
      await tester.enterText(find.byType(TextFormField).first, '81.4');
      await tester.pumpAndSettle();

      await _close(tester);

      _expectAsked();
    });
  });

  group('coach fact editor', () {
    Future<void> openEditor(WidgetTester tester) => _open(
      tester,
      (context) => showTracendSheet<void>(
        context,
        title: 'Add a fact',
        builder: (_) => CoachFactEditor(save: (_, _) async => null),
      ),
    );

    testWidgets('closes at once while empty', (tester) async {
      await openEditor(tester);

      await _close(tester);

      _expectClosed('Add a fact');
    });

    testWidgets('asks before losing typed words', (tester) async {
      await openEditor(tester);
      await tester.enterText(find.byType(TextField), 'Left knee hurts');
      await tester.pumpAndSettle();

      await _close(tester);

      _expectAsked();
    });
  });

  group('check-in sheet', () {
    Future<void> openCheckIn(WidgetTester tester) => _open(
      tester,
      (context) => showCheckInSheet(
        context,
        _environment,
        sender: (_, _, _, _) async => true,
      ),
    );

    testWidgets('closes at once when nothing is answered', (tester) async {
      await openCheckIn(tester);

      await _close(tester);

      _expectClosed('Daily check-in');
    });

    testWidgets('asks before losing a note', (tester) async {
      await openCheckIn(tester);
      await tester.enterText(find.byType(TextField), 'Slept badly');
      await tester.pumpAndSettle();

      await _close(tester);

      _expectAsked();
    });

    testWidgets('asks before losing a changed answer', (tester) async {
      await openCheckIn(tester);
      await tester.ensureVisible(find.text('Very poor'));
      await tester.tap(find.text('Very poor'));
      await tester.pumpAndSettle();

      await _close(tester);

      _expectAsked();
    });
  });

  group('pain check sheet', () {
    Future<void> openPain(WidgetTester tester) => _open(
      tester,
      (context) => showPainCheckSheet(
        context,
        reporting: PainReporting(repository: FakePainCheckRepository()),
        exerciseName: 'Bench press',
        localDate: '2026-11-02',
      ),
    );

    testWidgets('closes at once before anything is answered', (tester) async {
      await openPain(tester);

      await _close(tester);

      _expectClosed('Pain or discomfort');
    });

    testWidgets('asks once a strength is picked', (tester) async {
      await openPain(tester);
      await tester.tap(find.byType(SeverityChip).first);
      await tester.pumpAndSettle();

      await _close(tester);

      _expectAsked();
    });
  });
}
