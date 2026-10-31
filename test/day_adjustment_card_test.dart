import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/day_adjustment_card.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/readiness/day_adjustment_repository.dart';
import 'package:tracend/features/readiness/readiness_copy.dart';
import 'package:tracend/features/readiness/safety_copy.dart';
import 'package:tracend/features/readiness/safety_referral_sheet.dart';

import 'day_adjustment_fixtures.dart';

final _day = DateTime(2026, 10, 2);

class _Harness {
  _Harness(this.repository, {this.serverToday}) {
    controller = DayAdjustmentController(
      repository: repository,
      serverToday: () async => serverToday ?? _day,
      clock: () => DateTime(2026, 10, 2, 9),
    );
  }

  final FakeDayAdjustmentRepository repository;
  final DateTime? serverToday;
  late final DayAdjustmentController controller;
  final questions = <String>[];
  var checkIns = 0;
}

Future<_Harness> _pump(
  WidgetTester tester,
  Map<String, dynamic> json, {
  DateTime? serverToday,
}) async {
  final harness = _Harness(
    FakeDayAdjustmentRepository(json),
    serverToday: serverToday,
  );
  addTearDown(harness.controller.dispose);
  tester.view.physicalSize = const Size(390, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DayAdjustmentCard(
            controller: harness.controller,
            onTalkToCoach: harness.questions.add,
            onCheckIn: () => harness.checkIns++,
          ),
        ),
      ),
    ),
  );
  await harness.controller.load();
  await tester.pumpAndSettle();
  return harness;
}

/// [text] inside the card (a toast with the same words sits outside it).
Finder _text(String text) => find.descendant(
  of: find.byType(DayAdjustmentCard),
  matching: find.text(text),
);

/// [text] anywhere, for what a sheet shows over the card.
Finder _any(String text) => find.text(text);

void main() {
  group('a proposal waits for the athlete', () {
    testWidgets('says what it proposes and applies nothing by itself', (
      tester,
    ) async {
      final harness = await _pump(tester, adjustmentJson());
      expect(_text('One set fewer today'), findsOneWidget);
      expect(
        _text(
          "You slept poorly and you're sore. One set fewer on 3 exercises and "
          "last time's weights.",
        ),
        findsOneWidget,
      );
      expect(_text('Use lighter session'), findsOneWidget);
      expect(_text('Train as planned'), findsOneWidget);
      expect(_text(otherOptionsLabel), findsOneWidget);
      expect(_text(talkToCoach), findsOneWidget);
      expect(_text(readinessProvenance), findsOneWidget);
      expect(_text(readinessOnlyToday), findsOneWidget);
      expect(_text(undoLabel), findsNothing);
      expect(harness.repository.responses, isEmpty);
    });

    testWidgets('one tap accepts, and the answer carries the server day', (
      tester,
    ) async {
      final harness = await _pump(tester, adjustmentJson());
      await tester.tap(_text('Use lighter session'));
      await tester.pumpAndSettle();
      expect(harness.repository.responses, hasLength(1));
      final answer = harness.repository.responses.single;
      expect(answer.accept, isTrue);
      expect(answer.chosen, isNull);
      expect(answer.day, _day);
      expect(_text('Lighter session set for today.'), findsWidgets);
      expect(_text(undoLabel), findsOneWidget);
      expect(_text(changeLabel), findsOneWidget);
      expect(_text('Use lighter session'), findsNothing);
      expect(
        find.textContaining('9 sets become 6.'),
        findsOneWidget,
        reason: 'the card says what the change does to the session',
      );
    });

    testWidgets('Train as planned keeps the plan and can be changed', (
      tester,
    ) async {
      final harness = await _pump(tester, adjustmentJson());
      await tester.tap(_text('Train as planned'));
      await tester.pumpAndSettle();
      expect(harness.repository.responses.single.accept, isFalse);
      expect(_text(declinedTitle), findsOneWidget);
      expect(_text(changeLabel), findsOneWidget);
      expect(_text(undoLabel), findsNothing);
    });

    testWidgets('Undo returns to the plan until the workout starts', (
      tester,
    ) async {
      final harness = await _pump(tester, adjustmentJson());
      await tester.tap(_text('Use lighter session'));
      await tester.pumpAndSettle();
      await tester.tap(_text(undoLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text(undoneToast),
        findsOneWidget,
      ); // the toast, outside the card
      await tester.pumpAndSettle();
      expect(harness.repository.responses.last.accept, isFalse);
      expect(_text(declinedTitle), findsOneWidget);
      expect(_text(undoLabel), findsNothing);
    });

    testWidgets('another option is one tap, marked as the athlete\'s own', (
      tester,
    ) async {
      final harness = await _pump(tester, adjustmentJson());
      await tester.tap(_text(otherOptionsLabel));
      await tester.pumpAndSettle();
      expect(_any(optionsSheetTitle), findsOneWidget);
      expect(_any('Hold your weights'), findsOneWidget);
      expect(_any('Easy cardio instead'), findsOneWidget);
      await tester.tap(_any('Hold your weights'));
      await tester.pumpAndSettle();
      final answer = harness.repository.responses.single;
      expect(answer.accept, isTrue);
      expect(answer.chosen, DayAdjustmentKind.holdLoad);
      expect(_text('Weights held for today.'), findsWidgets);
    });

    testWidgets('Talk to Coach hands over a question and sends nothing', (
      tester,
    ) async {
      final harness = await _pump(tester, adjustmentJson());
      await tester.tap(_text(talkToCoach));
      await tester.pumpAndSettle();
      expect(harness.questions, hasLength(1));
      expect(harness.questions.single, contains('a lighter session'));
      expect(harness.questions.single, endsWith('?'));
      expect(harness.repository.responses, isEmpty);
    });

    testWidgets('What Tracend sees opens on a tap and names what is missing', (
      tester,
    ) async {
      await _pump(tester, adjustmentJson());
      expect(find.textContaining('Recovery score'), findsNothing);
      await tester.tap(_text(seesTitle));
      await tester.pumpAndSettle();
      expect(
        _text('Recovery score: 60 of 100, high confidence'),
        findsOneWidget,
      );
      expect(_text('Sleep: not in from Apple Health yet'), findsOneWidget);
      expect(
        _text(
          "Last night's sleep is not in from Apple Health yet, so this "
          'leaves it out.',
        ),
        findsOneWidget,
      );
      expect(_text('Confidence: medium.'), findsOneWidget);
    });
  });

  group('the answer in force', () {
    testWidgets('an accepted answer shows Undo and Change', (tester) async {
      await _pump(
        tester,
        adjustmentJson(status: 'accepted', origin: 'proposed'),
      );
      expect(_text('Lighter session set for today.'), findsOneWidget);
      expect(_text(undoLabel), findsOneWidget);
      expect(_text(changeLabel), findsOneWidget);
      expect(_text('Train as planned'), findsNothing);
    });

    testWidgets('once the workout started it is read only', (tester) async {
      await _pump(
        tester,
        adjustmentJson(
          status: 'accepted',
          origin: 'proposed',
          available: false,
          unavailable: 'session_started',
        ),
      );
      expect(_text('Lighter session today'), findsOneWidget);
      expect(find.textContaining('started with this change'), findsOneWidget);
      expect(_text(undoLabel), findsNothing);
      expect(_text(changeLabel), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('a finished session keeps the applied state, read only', (
      tester,
    ) async {
      await _pump(
        tester,
        adjustmentJson(
          status: 'accepted',
          origin: 'chosen',
          kind: 'hold_load',
          available: false,
          unavailable: 'session_done',
        ),
      );
      expect(_text('Weights held today'), findsOneWidget);
      expect(
        find.textContaining('You trained with this change'),
        findsOneWidget,
      );
      expect(_text(undoLabel), findsNothing);
    });

    testWidgets('a declined answer after the start shows nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        adjustmentJson(
          status: 'declined',
          available: false,
          unavailable: 'session_started',
        ),
      );
      expect(find.byType(DayAdjustmentCard), findsOneWidget);
      expect(_text(declinedTitle), findsNothing);
      expect(_text(readinessKicker), findsNothing);
    });

    testWidgets('a rest day shows nothing', (tester) async {
      await _pump(
        tester,
        adjustmentJson(
          kind: 'none',
          status: 'none',
          band: 'green',
          triggers: const [],
          available: false,
          unavailable: 'rest_day',
        ),
      );
      expect(_text(readinessKicker), findsNothing);
    });

    testWidgets('a session Coach already adjusted is said plainly', (
      tester,
    ) async {
      await _pump(
        tester,
        adjustmentJson(
          kind: 'none',
          status: 'none',
          band: 'amber',
          available: false,
          unavailable: 'coach_adjusted',
          explanation: "Coach already adjusted today's session.",
        ),
      );
      expect(_text(coachAdjustedTitle), findsOneWidget);
      expect(_text("Coach already adjusted today's session."), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('a safety route stands over everything', () {
    testWidgets('refers the athlete on and offers no training choice', (
      tester,
    ) async {
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
      expect(_text("Don't train through this pain"), findsOneWidget);
      expect(find.textContaining('see a doctor or physio'), findsOneWidget);
      expect(_text('Train as planned'), findsNothing);
      expect(_text(otherOptionsLabel), findsNothing);
      expect(_text(undoLabel), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(_text(readinessProvenance), findsNothing);
    });

    testWidgets('overrides a stored accepted answer', (tester) async {
      final harness = await _pump(
        tester,
        adjustmentJson(
          status: 'accepted',
          origin: 'proposed',
          safetyRoute: 'pain_referral',
          band: 'red',
          triggers: const ['pain_severe'],
        ),
      );
      expect(_text("Don't train through this pain"), findsOneWidget);
      expect(_text(undoLabel), findsNothing);
      expect(_text(changeLabel), findsNothing);
      expect(_text('Lighter session set for today.'), findsNothing);
      expect(harness.controller.current!.appliedKind, isNull);
      expect(harness.controller.current!.appliedChanges, isEmpty);
    });

    testWidgets('stays after the session started', (tester) async {
      await _pump(
        tester,
        adjustmentJson(
          kind: 'none',
          status: 'none',
          band: 'red',
          triggers: const ['pain_severe'],
          safetyRoute: 'pain_referral',
          available: false,
          unavailable: 'session_started',
        ),
      );
      expect(_text("Don't train through this pain"), findsOneWidget);
    });

    for (final (route, title) in [
      ('urgent', 'Get medical help now'),
      ('clinician_today', 'Get this checked today'),
      ('clinician', 'See a doctor or physio'),
    ]) {
      testWidgets('the $route route has its own words', (tester) async {
        await _pump(
          tester,
          adjustmentJson(
            kind: 'none',
            status: 'none',
            band: 'red',
            safetyRoute: route,
          ),
        );
        expect(_text(title), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
      });
    }

    testWidgets('the safety sheet closes with Got it and trains nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showSafetyReferralSheet(context, 'pain_referral'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(_any("Don't train through this pain"), findsOneWidget);
      expect(_any('Train as planned'), findsNothing);
      await tester.tap(_any(gotItLabel));
      await tester.pumpAndSettle();
      expect(_any("Don't train through this pain"), findsNothing);
    });
  });

  group('heart-derived signals inform and the athlete decides', () {
    final lowRecovery = adjustmentJson(
      kind: 'none',
      status: 'none',
      band: 'unknown',
      triggers: const ['no_check_in', 'recovery_low'],
      confidence: null,
      missing: const ['sleep'],
      explanation:
          'Your recovery reads low. Check in and Tracend will say whether to '
          'adjust today.',
      signals: {
        'recovery_score': 20,
        'recovery_confidence': 'high',
        'recovery_mode': 'night',
        'recovery_low': true,
        'sleep_minutes': null,
      },
    );

    testWidgets('a low recovery score alone shows what it sees and applies '
        'nothing', (tester) async {
      final harness = await _pump(tester, lowRecovery);
      expect(_text(lowRecoveryTitle), findsOneWidget);
      expect(_text(seesTitle), findsOneWidget);
      expect(
        _text('Recovery score: 20 of 100, high confidence'),
        findsOneWidget,
      );
      expect(_text('Sleep: not in from Apple Health yet'), findsOneWidget);
      expect(_text(checkInLabel), findsOneWidget);
      expect(_text(talkToCoach), findsOneWidget);
      expect(_text(chooseYourselfLabel), findsOneWidget);
      expect(harness.repository.responses, isEmpty);
      expect(find.text('Use lighter session'), findsNothing);
      expect(find.text('Hold weights'), findsNothing);
    });

    testWidgets('Check in opens the check-in', (tester) async {
      final harness = await _pump(tester, lowRecovery);
      await tester.tap(_text(checkInLabel));
      expect(harness.checkIns, 1);
    });

    testWidgets('Talk to Coach asks about the low score', (tester) async {
      final harness = await _pump(tester, lowRecovery);
      await tester.tap(_text(talkToCoach));
      expect(harness.questions.single, contains('recovery reads low'));
    });

    testWidgets('the athlete may choose, with nothing pre-selected', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final harness = await _pump(tester, lowRecovery);
      await tester.tap(_text(chooseYourselfLabel));
      await tester.pumpAndSettle();
      expect(_any('Hold your weights'), findsOneWidget);
      expect(_any('One set fewer'), findsOneWidget);
      expect(_any('Easy cardio instead'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(', chosen')),
        findsNothing,
        reason: 'no option is marked as chosen before the athlete picks',
      );
      await tester.tap(_any('One set fewer'));
      await tester.pumpAndSettle();
      final answer = harness.repository.responses.single;
      expect(answer.accept, isTrue);
      expect(answer.chosen, DayAdjustmentKind.reduceSets);
      expect(_text(undoLabel), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a low score next to a fine check-in says so and offers a '
        'choice', (tester) async {
      final harness = await _pump(
        tester,
        adjustmentJson(
          kind: 'none',
          status: 'none',
          band: 'green',
          triggers: const ['recovery_low'],
          explanation:
              'Your recovery reads low, but your check-in looks fine. You can '
              'train as planned or choose a lighter session.',
          signals: {
            'recovery_score': 28,
            'recovery_confidence': 'medium',
            'recovery_mode': 'morning',
            'recovery_low': true,
            'sleep_minutes': 345,
          },
        ),
      );
      expect(find.textContaining('your check-in looks fine'), findsOneWidget);
      expect(
        _text(
          'Recovery score: 28 of 100, medium confidence, an estimate from '
          'this morning',
        ),
        findsOneWidget,
      );
      expect(_text('Sleep: 5 h 45 min'), findsOneWidget);
      expect(_text(checkInLabel), findsNothing);
      expect(harness.repository.responses, isEmpty);
    });

    testWidgets('no check-in and no signal asks for a check-in only', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        adjustmentJson(
          kind: 'none',
          status: 'none',
          band: 'unknown',
          triggers: const ['no_check_in'],
          confidence: null,
          explanation: "Check in to see if today's session needs adjusting.",
        ),
      );
      expect(
        _text("Check in to see if today's session needs adjusting."),
        findsOneWidget,
      );
      expect(_text(checkInLabel), findsOneWidget);
      expect(_text(talkToCoach), findsNothing);
      await tester.tap(_text(checkInLabel));
      expect(harness.checkIns, 1);
    });
  });

  group('words for the other states', () {
    testWidgets('"cannot train today" changes nothing and says so', (
      tester,
    ) async {
      await _pump(
        tester,
        adjustmentJson(
          kind: 'none',
          status: 'none',
          band: 'amber',
          triggers: const ['not_available'],
          explanation:
              "You said you can't train today. Nothing in your plan changes.",
        ),
      );
      expect(
        _text("You said you can't train today. Nothing in your plan changes."),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('mild pain shows only its note', (tester) async {
      await _pump(
        tester,
        adjustmentJson(
          kind: 'none',
          status: 'none',
          band: 'green',
          triggers: const ['pain_mild'],
        ),
      );
      expect(
        _text(
          'Keep any pain at 3 or below, and stop if it builds from set to set.',
        ),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('a green day with nothing to say shows no card', (
      tester,
    ) async {
      await _pump(
        tester,
        adjustmentJson(
          kind: 'none',
          status: 'none',
          band: 'green',
          triggers: const [],
          explanation: 'Your check-in looks fine. Train as planned.',
        ),
      );
      expect(_text(readinessKicker), findsNothing);
    });

    testWidgets('easy cardio names its dose and swaps nothing until tapped', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        adjustmentJson(
          kind: 'swap_to_easy_cardio',
          band: 'red',
          triggers: const ['sleep_very_poor', 'energy_very_low'],
        ),
      );
      expect(_text('Easy cardio instead today'), findsOneWidget);
      expect(_text('Swap to easy cardio'), findsOneWidget);
      expect(harness.repository.responses, isEmpty);
      await tester.tap(_text('Swap to easy cardio'));
      await tester.pumpAndSettle();
      expect(_text('Easy cardio set for today.'), findsWidgets);
    });

    testWidgets('hold load uses its own button', (tester) async {
      await _pump(tester, adjustmentJson(kind: 'hold_load'));
      expect(_text('Hold your weights today'), findsOneWidget);
      expect(_text('Hold weights'), findsOneWidget);
    });
  });

  group('an earlier answer that no longer stands says why', () {
    for (final (reason, words) in [
      ('check_in', 'Your check-in changed'),
      ('new_data', 'New sleep or recovery data came in'),
    ]) {
      testWidgets('reason $reason', (tester) async {
        await _pump(
          tester,
          adjustmentJson(
            previous: {
              'kind': 'reduce_sets',
              'status': 'accepted',
              'answered_at': '2026-10-02T06:41:12+00:00',
              'reason': reason,
            },
          ),
        );
        expect(find.textContaining(words), findsOneWidget);
        expect(
          find.textContaining(
            'Your earlier choice (fewer sets) still applies until you choose '
            'again.',
          ),
          findsOneWidget,
          reason:
              'the server keeps an accepted answer until the athlete '
              'answers again',
        );
        expect(find.textContaining('sets become'), findsNothing);
      });
    }

    testWidgets('an earlier decline is named too', (tester) async {
      await _pump(
        tester,
        adjustmentJson(
          previous: {
            'kind': 'hold_load',
            'status': 'declined',
            'answered_at': '2026-10-02T06:41:12+00:00',
            'reason': 'check_in',
          },
        ),
      );
      expect(
        find.textContaining('You had chosen to train as planned'),
        findsOneWidget,
      );
    });

    test('every reason the server can return has wording', () {
      for (final reason in ['check_in', 'new_data', 'something_new', null]) {
        for (final status in [
          DayAdjustmentStatus.accepted,
          DayAdjustmentStatus.declined,
        ]) {
          final line = previousAnswerLine(
            PreviousDayAnswer(
              kind: DayAdjustmentKind.reduceSets,
              status: status,
              reason: reason,
            ),
          );
          expect(line, isNotEmpty);
          expect(line, isNot(contains('null')));
        }
      }
    });

    test('an accepted answer that no longer stands has no numeric preview', () {
      final adjustment = DayAdjustment.tryParse(
        adjustmentJson(
          kind: 'swap_to_easy_cardio',
          previous: {
            'kind': 'reduce_sets',
            'status': 'accepted',
            'answered_at': '2026-10-02T06:41:12+00:00',
            'reason': 'new_data',
          },
        ),
      )!;
      // previous_answer carries no stored changes, so nothing is derived from
      // today's options: the earlier answer is in words only.
      expect(adjustment.appliedKind, isNull);
      expect(adjustment.appliedChanges, isEmpty);
      expect(adjustment.easesSession, isFalse);
      expect(adjustment.previousAnswer?.kind, DayAdjustmentKind.reduceSets);
    });
  });

  group('stale and missing data are said plainly', () {
    testWidgets('a failed refresh says what shows is older', (tester) async {
      final harness = await _pump(tester, adjustmentJson());
      harness.repository.loadError = const DayAdjustmentException(
        DayAdjustmentFailure.network,
      );
      await harness.controller.load();
      await tester.pumpAndSettle();
      expect(_text(staleLine), findsOneWidget);
      expect(_text('One set fewer today'), findsOneWidget);
    });

    testWidgets('a failed answer says so and the card stays true', (
      tester,
    ) async {
      final harness = await _pump(tester, adjustmentJson());
      harness.repository.respondError = const DayAdjustmentException(
        DayAdjustmentFailure.network,
      );
      await tester.tap(_text('Use lighter session'));
      await tester.pumpAndSettle();
      expect(_text(failureLine(DayAdjustmentFailure.network)), findsOneWidget);
      expect(_text('Use lighter session'), findsOneWidget);
    });

    testWidgets('an answer after the start is refused and the card reads '
        'again', (tester) async {
      final harness = await _pump(tester, adjustmentJson());
      harness.repository
        ..respondError = const DayAdjustmentException(
          DayAdjustmentFailure.unavailable,
        )
        ..json = adjustmentJson(
          status: 'accepted',
          origin: 'proposed',
          available: false,
          unavailable: 'session_started',
        );
      await tester.tap(_text('Use lighter session'));
      await tester.pumpAndSettle();
      expect(_text('Lighter session today'), findsOneWidget);
      expect(_text(undoLabel), findsNothing);
    });

    testWidgets('a payload from another major version is not shown', (
      tester,
    ) async {
      await _pump(tester, {...adjustmentJson(), 'schema_version': '2.0'});
      expect(_text('One set fewer today'), findsNothing);
      expect(_text(readFailureLine), findsOneWidget);
    });
  });

  group('the day is the server\'s', () {
    testWidgets('an adjustment for another day is never shown', (tester) async {
      await _pump(
        tester,
        adjustmentJson(day: '2026-10-03'),
        serverToday: DateTime(2026, 10, 2),
      );
      expect(_text('One set fewer today'), findsNothing);
      expect(_text('Use lighter session'), findsNothing);
    });
  });

  group('a later 1.x payload (joint rules, red flags) stays safe', () {
    Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(
      jsonDecode(File('test/contract/fixtures/$name.json').readAsStringSync())
          as Map,
    );

    // The fixtures carry another workout's ids and day; the server day below
    // matches their local_date.
    Future<_Harness> pumpFixture(WidgetTester tester, String name) =>
        _pump(tester, fixture(name), serverToday: DateTime(2026, 10, 24));

    testWidgets('a red-flag day shows its referral', (tester) async {
      await pumpFixture(tester, 'day_adjustment_v1_1_red_flag');
      expect(_text('Get this checked today'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(_text('Train as planned'), findsNothing);
    });

    testWidgets('an unknown kind on a safety day keeps the referral', (
      tester,
    ) async {
      final json = fixture('day_adjustment_v1_1_red_flag')
        ..['kind'] = 'a_kind_from_the_future'
        ..['safety_route'] = 'a_route_from_the_future';
      await _pump(tester, json, serverToday: DateTime(2026, 10, 24));
      expect(_text('Get medical help now'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('copy', () {
    test('names no condition, model or company', () {
      final text = [
        'lib/features/readiness/readiness_copy.dart',
        'lib/features/readiness/safety_copy.dart',
      ].map((path) => File(path).readAsStringSync()).join('\n').toLowerCase();
      for (final word in [
        'tendin',
        'sprain',
        'sciatica',
        'disc ',
        'meniscus',
        'rotator',
        'impingement',
        'arthritis',
        'diagnos',
        'claude',
        'anthropic',
        'openai',
        'deepseek',
        'gemini',
        'groq',
      ]) {
        expect(text, isNot(contains(word)), reason: word);
      }
    });

    test('every safety route has a title and a body', () {
      for (final route in [
        'pain_referral',
        'urgent',
        'clinician_today',
        'clinician',
        'a_route_this_build_does_not_know',
      ]) {
        final words = safetyWords(route);
        expect(words.title, isNotEmpty);
        expect(words.body, isNotEmpty);
      }
      expect(safetyWords('urgent').body, contains('emergency number'));
      expect(
        safetyWords('red_flag:something_new'),
        safetyWords('urgent'),
        reason: 'a route this build does not know reads as the strictest',
      );
    });

    test('every failure has a line', () {
      for (final failure in DayAdjustmentFailure.values) {
        expect(failureLine(failure), isNotEmpty);
      }
    });
  });
}
