import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/readiness/day_adjustment_card.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/readiness/readiness_copy.dart';
import 'package:tracend/features/train/train_screen.dart';
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
_pump(WidgetTester tester, Map<String, dynamic> json) async {
  final repository = FakeDayAdjustmentRepository(json);
  final controller = DayAdjustmentController(
    repository: repository,
    clock: trainNow,
  );
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
          repository: TrainFixtureRepository(),
          brief: TrainBriefRepository(computed: trainComputed()),
          coach: const TrainCoachRepository(),
          now: trainNow,
          dayAdjustment: controller,
          onTalkToCoach: questions.add,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repository, controller, questions);
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

  test('an unadjusted workout has no note', () {
    expect(dayAdjustmentNote(upperA), isNull);
  });
}
