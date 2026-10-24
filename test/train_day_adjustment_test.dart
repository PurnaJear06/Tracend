import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/readiness/day_adjustment_card.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/readiness/readiness_copy.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/features/train/widgets/train_parts.dart';

import 'day_adjustment_fixtures.dart';
import 'train_fixtures.dart';

const _upper = [
  (1, 'Bench press', 3),
  (2, 'Barbell row', 3),
  (3, 'Overhead press', 3),
  (4, 'Lat pulldown', 3),
  (5, 'Cable fly', 2),
  (6, 'Triceps pushdown', 2),
];

Future<(FakeDayAdjustmentRepository, DayAdjustmentController, List<String>)>
_pump(
  WidgetTester tester,
  Map<String, dynamic> json, {
  TrainFixtureRepository? repository,
  TrainBriefRepository? brief,
  DateTime Function()? now,
}) async {
  final fake = FakeDayAdjustmentRepository(json);
  final controller = DayAdjustmentController(repository: fake, clock: trainNow);
  addTearDown(controller.dispose);
  final questions = <String>[];
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: TrainScreen(
          repository: repository ?? TrainFixtureRepository(),
          brief: brief ?? TrainBriefRepository(computed: trainComputed()),
          coach: const TrainCoachRepository(),
          now: now ?? trainNow,
          dayAdjustment: controller,
          onTalkToCoach: questions.add,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (fake, controller, questions);
}

void main() {
  testWidgets('the card sits under the readiness line and asks for the '
      "hub's day", (tester) async {
    final (repository, _, _) = await _pump(
      tester,
      adjustmentJson(exercises: _upper),
    );
    expect(find.text('One set fewer today'), findsOneWidget);
    expect(repository.loads.single, DateTime(2026, 10, 2));
    final card = tester.getTopLeft(find.byType(DayAdjustmentCard)).dy;
    final hero = tester.getTopLeft(find.text('Upper body A').first).dy;
    expect(card, lessThan(hero));
    // Nothing is applied until the athlete taps.
    expect(find.text('3 × 6 to 8 at 72.5 kg'), findsOneWidget);
    expect(repository.responses, isEmpty);
  });

  testWidgets('one tap lightens the exercise lines and shows what changed', (
    tester,
  ) async {
    final (repository, _, _) = await _pump(
      tester,
      adjustmentJson(exercises: _upper),
    );
    await tester.tap(find.text('Use lighter session'));
    await tester.pumpAndSettle();
    expect(repository.responses.single.accept, isTrue);
    // Bench press 3 -> 2 sets with last time's weight held.
    expect(find.text('2 × 6 to 8 · hold 57.5 kg × 6'), findsOneWidget);
    // The plan's own count stays beside it, struck through.
    expect(find.text('3'), findsWidgets);
    // Cable fly had 2 sets: not cut, its weight is held.
    expect(find.text('2 × 12 · hold 57.5 kg × 6'), findsNWidgets(2));
    expect(find.text('12 sets'), findsOneWidget);
  });

  testWidgets('VoiceOver hears the cut', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, adjustmentJson(exercises: _upper));
    await tester.tap(find.text('Use lighter session'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        RegExp(
          'Bench press, 2 sets of 6 to 8 reps, down '
          'from 3 sets',
        ),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('Undo brings the plan back', (tester) async {
    await _pump(tester, adjustmentJson(exercises: _upper));
    await tester.tap(find.text('Use lighter session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(undoLabel));
    await tester.pumpAndSettle();
    expect(find.text('3 × 6 to 8 at 72.5 kg'), findsOneWidget);
    expect(find.text('16 sets'), findsOneWidget);
  });

  testWidgets('holding weights keeps the sets and says "hold"', (tester) async {
    await _pump(tester, adjustmentJson(exercises: _upper, kind: 'hold_load'));
    await tester.tap(find.text('Hold weights'));
    await tester.pumpAndSettle();
    expect(find.text('3 × 6 to 8 · hold 57.5 kg × 6'), findsWidgets);
    expect(find.text('16 sets'), findsOneWidget);
  });

  testWidgets('the overview names what changed', (tester) async {
    await _pump(
      tester,
      adjustmentJson(exercises: _upper, status: 'accepted', origin: 'proposed'),
    );
    expect(find.text('12 sets'), findsOneWidget);
    await tester.tap(find.text('Upper body A').first);
    await tester.pumpAndSettle();
    expect(find.text('Lighter today: 12 of 16 sets'), findsOneWidget);
  });

  testWidgets('a declined answer leaves the plan as written', (tester) async {
    await _pump(tester, adjustmentJson(exercises: _upper, status: 'declined'));
    expect(find.text(declinedTitle), findsOneWidget);
    expect(find.text('16 sets'), findsOneWidget);
  });

  testWidgets('an easy-cardio answer does not change the strength sets', (
    tester,
  ) async {
    await _pump(
      tester,
      adjustmentJson(
        exercises: _upper,
        kind: 'swap_to_easy_cardio',
        status: 'accepted',
        origin: 'proposed',
      ),
    );
    expect(find.text('Easy cardio set for today.'), findsOneWidget);
    expect(find.text('16 sets'), findsOneWidget);
  });

  testWidgets('a safety day shows the referral and leaves the plan startable', (
    tester,
  ) async {
    await _pump(
      tester,
      adjustmentJson(
        exercises: _upper,
        kind: 'none',
        status: 'none',
        band: 'red',
        triggers: const ['pain_severe'],
        safetyRoute: 'pain_referral',
      ),
    );
    expect(find.text("Don't train through this pain"), findsOneWidget);
    expect(find.text('Train as planned'), findsNothing);
    expect(find.text('16 sets'), findsOneWidget);
    expect(find.text('Start workout'), findsWidgets);
  });

  testWidgets('an adjustment for another day is neither shown nor applied', (
    tester,
  ) async {
    await _pump(
      tester,
      adjustmentJson(
        exercises: _upper,
        day: '2026-10-03',
        status: 'accepted',
        origin: 'proposed',
      ),
    );
    expect(find.byType(DayAdjustmentCard), findsOneWidget);
    expect(find.text('Lighter session set for today.'), findsNothing);
    expect(find.text('16 sets'), findsOneWidget);
  });

  testWidgets('another day of the week has no readiness card', (tester) async {
    await _pump(
      tester,
      adjustmentJson(exercises: _upper, status: 'accepted', origin: 'proposed'),
    );
    await tester.tap(find.byKey(const ValueKey('day-box-2026-10-03')));
    await tester.pumpAndSettle();
    // Readiness is for today only: no card on another day.
    expect(find.byType(DayAdjustmentCard), findsNothing);
    expect(find.text('Lighter session set for today.'), findsNothing);
  });

  group(
    "the logger gets the plan's sets, never the phone's copy of the answer",
    () {
      Future<void> startFromHero(WidgetTester tester) async {
        await tester.tap(find.text('Start workout').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
      }

      PlannedWorkout given(WidgetTester tester) => tester
          .widget<ActiveWorkoutScreen>(find.byType(ActiveWorkoutScreen))
          .workout;

      testWidgets('an accepted answer: plan set counts, held weights', (
        tester,
      ) async {
        await _pump(tester, adjustmentJson(exercises: _upper));
        await tester.tap(find.text('Use lighter session'));
        await tester.pumpAndSettle();
        await startFromHero(tester);
        final bench = given(tester).exercises.first;
        expect(bench.setCount, 3, reason: 'the server decides the sets');
        expect(bench.loadHeld, isTrue);
        expect(bench.nextTarget?.loadKg, 57.5);
      });

      testWidgets(
        "a severe-pain day after an accepted answer: still the plan's "
        'sets, and the referral stays on top',
        (tester) async {
          final (fake, controller, _) = await _pump(
            tester,
            adjustmentJson(exercises: _upper),
          );
          await tester.tap(find.text('Use lighter session'));
          await tester.pumpAndSettle();
          // The check-in changed: the rules now route the day out, while the
          // accepted row is still the one start_workout applies.
          fake.json = adjustmentJson(
            exercises: _upper,
            kind: 'none',
            status: 'none',
            band: 'red',
            triggers: const ['pain_severe'],
            safetyRoute: 'pain_referral',
          );
          await controller.load();
          await tester.pumpAndSettle();
          expect(find.text("Don't train through this pain"), findsOneWidget);
          expect(find.text('Train as planned'), findsNothing);
          await startFromHero(tester);
          final bench = given(tester).exercises.first;
          expect(bench.setCount, 3);
          expect(bench.loadHeld, isFalse);
        },
      );

      testWidgets('Start waits while an answer is on its way', (tester) async {
        final (fake, _, _) = await _pump(
          tester,
          adjustmentJson(exercises: _upper),
        );
        final gate = fake.respondGate = Completer<void>();
        await tester.tap(find.text('Use lighter session'));
        await tester.pump();
        final start = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Start workout').first,
        );
        expect(start.onPressed, isNull);
        expect(find.byType(ActiveWorkoutScreen), findsNothing);
        gate.complete();
        await tester.pumpAndSettle();
        final after = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Start workout').first,
        );
        expect(after.onPressed, isNotNull);
      });

      testWidgets('closing the workout reads the adjustment again', (
        tester,
      ) async {
        final (fake, _, _) = await _pump(
          tester,
          adjustmentJson(exercises: _upper),
        );
        await tester.tap(find.text('Use lighter session'));
        await tester.pumpAndSettle();
        expect(find.text(undoLabel), findsOneWidget);
        await startFromHero(tester);
        // The workout started: the server now says so.
        fake.json = adjustmentJson(
          exercises: _upper,
          status: 'accepted',
          origin: 'proposed',
          available: false,
          unavailable: 'session_started',
        );
        final reads = fake.loads.length;
        Navigator.of(
          tester.element(find.byType(ActiveWorkoutScreen)),
        ).pop(false);
        await tester.pumpAndSettle();
        expect(fake.loads.length, greaterThan(reads));
        expect(find.text(undoLabel), findsNothing);
        expect(find.text('Lighter session today'), findsOneWidget);
      });
    },
  );

  group('the card and the numbers are for one day', () {
    testWidgets('readiness is read again for the hub\'s day when the phone '
        'differs', (tester) async {
      final brief = TrainBriefRepository(computed: trainComputed());
      await _pump(
        tester,
        adjustmentJson(exercises: _upper),
        brief: brief,
        now: () => DateTime(2026, 10, 1, 23, 50),
      );
      expect(brief.loads.first, DateTime(2026, 10, 1));
      expect(brief.loads.last, DateTime(2026, 10, 2));
      expect(find.text('One set fewer today'), findsOneWidget);
    });
  });

  test('an unadjusted workout has no note', () {
    expect(dayAdjustmentNote(upperA), isNull);
  });
}
