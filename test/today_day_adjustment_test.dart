import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/features/readiness/readiness_copy.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/widgets/today_session_card.dart';
import 'package:tracend/shared/coach_draft_requests.dart';

import 'day_adjustment_fixtures.dart';

const _workout = {
  'id': 'w-upper-a',
  'name': 'Upper body A',
  'estimated_minutes': 48,
  'exercises': [
    {'order': 1, 'name': 'Bench press', 'set_count': 3},
    {'order': 2, 'name': 'Barbell row', 'set_count': 3},
    {'order': 3, 'name': 'Overhead press', 'set_count': 3},
  ],
};

DailyBrief _brief({TodaySession? session, String day = '2026-10-02'}) =>
    DailyBrief(localDate: day, workout: _workout, todaySession: session);

CoachDecision _decision() => CoachDecision(
  id: 'd1',
  localDate: '2026-10-02',
  trainingAction: 'ADJUST_TODAY',
  trainingSummary: 'Keep the session as planned.',
  nutritionAction: 'MAINTAIN_TARGETS',
  nutritionSummary: 'Keep approved nutrition targets.',
  finalDecision: 'Train today.',
  reason: 'Recovery is steady.',
  confidence: 'medium',
  evidence: const [],
  missingData: const [],
  riskFlags: const [],
  createdAt: DateTime(2026, 10, 2),
);

Future<(FakeDayAdjustmentRepository, DayAdjustmentController, List<String>)>
_pump(
  WidgetTester tester,
  Map<String, dynamic> json, {
  DailyBrief? brief,
}) async {
  final repository = FakeDayAdjustmentRepository(json);
  final controller = DayAdjustmentController(
    repository: repository,
    clock: () => DateTime(2026, 10, 2, 9),
    serverToday: () async => DateTime(2026, 10, 2),
  );
  addTearDown(controller.dispose);
  final questions = <String>[];
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [TracendColors.dark],
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TodaySessionCard(
            brief: brief ?? _brief(),
            decision: _decision(),
            aiAllowed: true,
            onOpen: () {},
            dayAdjustment: controller,
            onTalkToCoach: questions.add,
            onCheckIn: () {},
          ),
        ),
      ),
    ),
  );
  await controller.load();
  await tester.pumpAndSettle();
  return (repository, controller, questions);
}

class _NoMemory implements CoachThreadMemory {
  @override
  Future<String?> lastThreadId() async => null;

  @override
  Future<void> remember(String threadId) async {}
}

List<Color> _blocks(WidgetTester tester) => [
  for (final box in tester.widgetList<AnimatedContainer>(
    find.descendant(
      of: find.byType(TodaySessionCard),
      matching: find.byType(AnimatedContainer),
    ),
  ))
    (box.decoration! as BoxDecoration).color!,
];

void main() {
  group("Today's session card with the readiness card", () {
    testWidgets('hides the training note while the card proposes', (
      tester,
    ) async {
      await _pump(tester, adjustmentJson());
      expect(find.text('One set fewer today'), findsOneWidget);
      expect(find.text('Keep the session as planned.'), findsNothing);
      expect(find.textContaining('Coach · '), findsNothing);
    });

    testWidgets('shows the note when there is nothing to adjust', (
      tester,
    ) async {
      await _pump(
        tester,
        adjustmentJson(
          kind: 'none',
          status: 'none',
          band: 'green',
          triggers: const [],
        ),
      );
      expect(find.text('Keep the session as planned.'), findsOneWidget);
    });

    testWidgets('hides the training note on a safety day', (tester) async {
      await _pump(
        tester,
        adjustmentJson(
          kind: 'none',
          status: 'none',
          band: 'red',
          triggers: const ['pain_severe'],
          safetyRoute: 'pain_referral',
        ),
      );
      expect(find.text("Don't train through this pain"), findsOneWidget);
      expect(find.text('Keep the session as planned.'), findsNothing);
    });

    testWidgets('the strip counts the lighter session once accepted', (
      tester,
    ) async {
      await _pump(tester, adjustmentJson());
      expect(find.text('3 exercises · 9 sets · about 48 min'), findsOneWidget);
      expect(_blocks(tester), hasLength(9));
      await tester.tap(find.text('Use lighter session'));
      await tester.pumpAndSettle();
      expect(find.text('3 exercises · 6 sets · about 48 min'), findsOneWidget);
      expect(_blocks(tester), hasLength(6));
    });

    testWidgets('a started session counts "x of 6 sets" against the lighter '
        'session', (tester) async {
      await _pump(
        tester,
        adjustmentJson(
          status: 'accepted',
          origin: 'proposed',
          available: false,
          unavailable: 'session_started',
        ),
        brief: _brief(
          session: const TodaySession(
            state: 'in_progress',
            completedSets: {1: 2, 2: 1},
          ),
        ),
      );
      expect(find.text('3 of 6 sets logged'), findsOneWidget);
      expect(find.text('Lighter session today'), findsOneWidget);
      expect(find.text(undoLabel), findsNothing);
    });

    testWidgets('an adjustment from another day does not change the strip', (
      tester,
    ) async {
      await _pump(
        tester,
        adjustmentJson(status: 'accepted', origin: 'proposed'),
        brief: _brief(day: '2026-10-01'),
      );
      expect(_blocks(tester), hasLength(9));
    });

    testWidgets('a phone date that is not the server day shows no card and no '
        'numbers', (tester) async {
      await _pump(
        tester,
        adjustmentJson(), // the server's day: 2 October
        brief: _brief(day: '2026-10-01'), // loaded for the phone's day
      );
      expect(find.text('One set fewer today'), findsNothing);
      expect(find.text(readinessKicker), findsNothing);
      expect(find.text(seesTitle), findsNothing);
    });

    testWidgets('Talk to Coach hands over a question', (tester) async {
      final (_, _, questions) = await _pump(tester, adjustmentJson());
      await tester.tap(find.text(talkToCoach));
      expect(questions, hasLength(1));
    });
  });

  group('the workout overview page', () {
    final workout = PlannedWorkout.fromHubJson({
      'id': 'w-upper-a',
      'name': 'Upper body A',
      'objective': 'Press.',
      'estimated_minutes': 48,
      'exercises': [
        for (final (i, name) in [
          'Bench press',
          'Barbell row',
          'Overhead press',
        ].indexed)
          {
            'id': 'e${i + 1}',
            'order': i + 1,
            'name': name,
            'set_count': 3,
            'rep_min': 6,
            'rep_max': 8,
            'target_rpe': 8,
          },
      ],
    });

    Future<(FakeDayAdjustmentRepository, DayAdjustmentController)> open(
      WidgetTester tester,
      Map<String, dynamic> json,
    ) async {
      final repository = FakeDayAdjustmentRepository(json);
      final controller = DayAdjustmentController(
        repository: repository,
        clock: () => DateTime(2026, 10, 2, 9),
        serverToday: () async => DateTime(2026, 10, 2),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: WorkoutDetailScreen(
            repository: FixtureWorkoutRepository(),
            workout: workout,
            sessionDate: DateTime(2026, 10, 2),
            dayAdjustment: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (repository, controller);
    }

    testWidgets('shows what an accepted answer changed and starts with the '
        "plan's sets", (tester) async {
      await open(
        tester,
        adjustmentJson(status: 'accepted', origin: 'proposed'),
      );
      expect(find.text('Lighter today: 6 of 9 sets'), findsOneWidget);
      await tester.tap(find.text('Start workout'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final given = tester
          .widget<ActiveWorkoutScreen>(find.byType(ActiveWorkoutScreen))
          .workout;
      expect(given.exercises.first.setCount, 3);
    });

    testWidgets('Start waits while an answer is on its way', (tester) async {
      final (repository, controller) = await open(tester, adjustmentJson());
      repository.respondGate = Completer<void>();
      unawaited(controller.respond(accept: true));
      await tester.pump();
      final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start workout'),
      );
      expect(start.onPressed, isNull);
      repository.respondGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('closing the workout reads the adjustment again', (
      tester,
    ) async {
      final (repository, _) = await open(
        tester,
        adjustmentJson(status: 'accepted', origin: 'proposed'),
      );
      await tester.tap(find.text('Start workout'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final reads = repository.loads.length;
      Navigator.of(tester.element(find.byType(ActiveWorkoutScreen))).pop(false);
      await tester.pumpAndSettle();
      expect(repository.loads.length, greaterThan(reads));
    });
  });

  group('Coach composer', () {
    Widget app(CoachDraftRequests drafts) => MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: CoachScreen(
          repository: const FixtureCoachRepository(),
          threadMemory: _NoMemory(),
          draftRequests: drafts,
        ),
      ),
    );

    String composer(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField).last).controller!.text;

    testWidgets('a question left before Coach opened is in the box, unsent', (
      tester,
    ) async {
      final drafts = CoachDraftRequests()..request('Can we talk it through?');
      await tester.pumpWidget(app(drafts));
      await tester.pumpAndSettle();
      expect(composer(tester), 'Can we talk it through?');
      expect(drafts.take(), isNull, reason: 'it was taken once');
    });

    testWidgets('a question left while Coach is open lands under a draft', (
      tester,
    ) async {
      final drafts = CoachDraftRequests();
      await tester.pumpWidget(app(drafts));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'My own words');
      drafts.request('Can we talk it through?');
      await tester.pump();
      expect(composer(tester), 'My own words\n\nCan we talk it through?');
    });
  });
}
