import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/train/guidance/guidance_copy.dart';
import 'package:tracend/features/train/guidance/training_guidance.dart';
import 'package:tracend/features/train/guidance/training_guidance_controller.dart';
import 'package:tracend/features/train/guidance/training_guidance_repository.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/plan_changes.dart';

import 'train_fixtures.dart';
import 'training_guidance_fixtures.dart';

class _Harness {
  _Harness({
    required this.repository,
    required this.controller,
    required this.proposals,
    required this.hub,
    required this.planChanges,
  });

  final FakeGuidanceRepository repository;
  final TrainingGuidanceController controller;
  final FakeProposals proposals;
  final TrainFixtureRepository hub;
  final PlanChanges planChanges;
}

Future<_Harness> _pump(
  WidgetTester tester,
  Map<String, dynamic> guidance, {
  FakeProposals? proposals,
}) async {
  final repository = FakeGuidanceRepository(guidance);
  final controller = TrainingGuidanceController(
    repository: repository,
    clock: trainNow,
  );
  addTearDown(controller.dispose);
  final planChanges = PlanChanges();
  addTearDown(planChanges.dispose);
  final workouts = TrainFixtureRepository();
  final fake = proposals ?? FakeProposals(deloadProposal());
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: TrainScreen(
          repository: workouts,
          brief: TrainBriefRepository(computed: trainComputed()),
          coach: const TrainCoachRepository(),
          now: trainNow,
          guidance: controller,
          proposals: fake,
          planChanges: planChanges,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(
    repository: repository,
    controller: controller,
    proposals: fake,
    hub: workouts,
    planChanges: planChanges,
  );
}

Finder _text(String text) => find.text(text);

void main() {
  group('the lighter-week card', () {
    testWidgets('suggested: why, what changes, and nothing stored or '
        'applied until the athlete asks', (tester) async {
      final harness = await _pump(tester, suggestedJson());
      expect(_text(deloadTitle), findsOneWidget);
      expect(_text(deloadSuggestedBy), findsOneWidget);
      expect(
        _text('• ${deloadReasonLine(DeloadReason.performanceDrop)}'),
        findsOneWidget,
      );
      expect(
        _text('• ${deloadReasonLine(DeloadReason.runDown)}'),
        findsOneWidget,
      );
      expect(
        _text('• ${deloadReasonLine(DeloadReason.blockDone)}'),
        findsNothing,
      );
      expect(_text(deloadWhat), findsOneWidget);
      expect(_text(deloadProvenance), findsOneWidget);
      expect(_text(deloadNothingChanges), findsOneWidget);
      expect(_text(deloadSeeChanges), findsOneWidget);
      // The server's day, not the phone's, and no request for a proposal.
      expect(harness.repository.loads.single, trainToday);
      expect(harness.repository.prepares, isEmpty);
      expect(harness.proposals.calls, isEmpty);
      expect(harness.proposals.loadedIds, isEmpty);
    });

    testWidgets('one tap prepares the proposal and shows what changes, with '
        'Approve and Not now but no Change it', (tester) async {
      final harness = await _pump(tester, suggestedJson());
      await tester.tap(_text(deloadSeeChanges));
      await tester.pumpAndSettle();
      expect(harness.repository.prepares.single, trainToday);
      expect(harness.proposals.loadedIds, [deloadProposalId]);
      expect(_text('Deload until 8 Oct'), findsOneWidget);
      expect(_text('RPE 7 or lower'), findsOneWidget);
      expect(_text('Approve'), findsOneWidget);
      expect(_text('Not now'), findsOneWidget);
      expect(_text('Change it'), findsNothing);
      // The sheet's card says who suggested it, and names no model.
      expect(_text('Suggested by Tracend'), findsWidgets);
      expect(find.textContaining('Proposed by Coach'), findsNothing);
      expect(find.textContaining('checked by Tracend'), findsNothing);
      // Opening it applied nothing.
      expect(harness.proposals.calls, isEmpty);
    });

    testWidgets('approving applies it through the proposal flow, announces '
        'the plan change, and Undo takes it back', (tester) async {
      final harness = await _pump(tester, suggestedJson());
      var announced = 0;
      harness.planChanges.addListener(() => announced++);
      await tester.tap(_text(deloadSeeChanges));
      await tester.pumpAndSettle();
      await tester.tap(_text('Approve'));
      await tester.pumpAndSettle();
      expect(_text('Apply this change?'), findsOneWidget);
      expect(harness.proposals.calls, isEmpty, reason: 'not before confirm');
      await tester.tap(_text('Approve').last);
      await tester.pumpAndSettle();
      expect(harness.proposals.calls, ['approve']);
      expect(announced, 1);
      expect(_text('Applied'), findsOneWidget);
      expect(find.textContaining('You can undo this until'), findsOneWidget);
      await tester.tap(_text('Undo'));
      await tester.pumpAndSettle();
      expect(harness.proposals.calls, ['approve', 'undo']);
      expect(announced, 2);
      expect(_text('Undone'), findsOneWidget);
    });

    testWidgets('Not now declines it and changes nothing in the plan', (
      tester,
    ) async {
      final harness = await _pump(tester, suggestedJson());
      var announced = 0;
      harness.planChanges.addListener(() => announced++);
      await tester.tap(_text(deloadSeeChanges));
      await tester.pumpAndSettle();
      await tester.tap(_text('Not now').last);
      await tester.pumpAndSettle();
      expect(harness.proposals.calls, ['decline']);
      expect(announced, 0);
    });

    testWidgets('closing the sheet reads the guidance again', (tester) async {
      final harness = await _pump(tester, suggestedJson());
      harness.repository.onPrepare = () {
        harness.repository.json = suggestedJson(
          change: (json) {
            deloadOf(json)
              ..['status'] = 'pending'
              ..['proposal_origin'] = 'tracend'
              ..['proposal_id'] = deloadProposalId;
          },
        );
      };
      await tester.tap(_text(deloadSeeChanges));
      await tester.pumpAndSettle();
      final before = harness.repository.loads.length;
      await tester.tap(find.bySemanticsLabel(RegExp('Close')).first);
      await tester.pumpAndSettle();
      expect(harness.repository.loads.length, before + 1);
      // The proposal is open now, so the card offers to look at it.
      expect(_text(deloadPendingBody), findsOneWidget);
    });

    testWidgets('pending: the open proposal is shown, none is prepared', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        suggestedJson(
          change: (json) {
            deloadOf(json)
              ..['status'] = 'pending'
              ..['proposal_origin'] = 'tracend'
              ..['proposal_id'] = deloadProposalId;
          },
        ),
      );
      expect(_text(deloadTitle), findsOneWidget);
      expect(_text(deloadPendingBody), findsOneWidget);
      expect(_text(deloadNothingChanges), findsOneWidget);
      await tester.tap(_text(deloadSeeChanges));
      await tester.pumpAndSettle();
      expect(harness.repository.prepares, isEmpty);
      expect(harness.proposals.loadedIds, [deloadProposalId]);
      expect(_text('Approve'), findsOneWidget);
    });

    testWidgets('running: the card keeps Undo within reach', (tester) async {
      final harness = await _pump(
        tester,
        guidanceJson('training_guidance_v1_1'),
        proposals: FakeProposals(
          deloadProposal(status: 'accepted', canUndo: true),
        ),
      );
      // The fixture suggests; make it running instead.
      harness.repository.json = guidanceJson(
        'training_guidance_v1_1',
        change: (json) {
          deloadOf(json)
            ..['status'] = 'running'
            ..['reasons'] = <Object>[]
            ..['proposal_id'] = deloadProposalId;
        },
      );
      await harness.controller.load();
      await tester.pumpAndSettle();
      expect(_text(deloadRunningTitle), findsOneWidget);
      expect(_text(deloadRunningBody), findsOneWidget);
      expect(_text(deloadSeeChanges), findsNothing);
      await tester.tap(_text(deloadRunningAction));
      await tester.pumpAndSettle();
      expect(harness.repository.prepares, isEmpty);
      expect(_text('Undo'), findsOneWidget);
      await tester.tap(_text('Undo'));
      await tester.pumpAndSettle();
      expect(harness.proposals.calls, ['undo']);
    });

    for (final (name, change)
        in <(String, void Function(Map<String, dynamic>))>[
          (
            'declined recently',
            (json) => deloadOf(json)
              ..['status'] = 'not_due'
              ..['reasons'] = <Object>[]
              ..['suppressed_by'] = 'declined_recently',
          ),
          (
            'recent deload',
            (json) => deloadOf(json)
              ..['status'] = 'not_due'
              ..['reasons'] = <Object>[]
              ..['suppressed_by'] = 'recent_deload',
          ),
          (
            'not due',
            (json) => deloadOf(json)
              ..['status'] = 'not_due'
              ..['reasons'] = <Object>[],
          ),
          (
            'a status this build does not know',
            (json) => deloadOf(json)['status'] = 'snoozed',
          ),
          (
            'a suggestion with only reasons this build cannot say',
            (json) => deloadOf(json)['reasons'] = ['a_reason_from_the_future'],
          ),
          (
            'a safety-route day, even if the payload still suggests',
            (json) => json['safety_route'] = 'clinician_today',
          ),
        ]) {
      testWidgets('$name: no card', (tester) async {
        await _pump(tester, suggestedJson(change: change));
        expect(_text(deloadTitle), findsNothing);
        expect(_text(deloadSuggestedBy), findsNothing);
        expect(_text(deloadSeeChanges), findsNothing);
      });
    }

    testWidgets('the safety-route payload hides the card and the cardio '
        'dose', (tester) async {
      await _pump(
        tester,
        guidanceJson('training_guidance_v1_1_withheld', date: '2026-10-02'),
      );
      expect(_text(deloadTitle), findsNothing);
      expect(_text(cardioTitle), findsNothing);
      // The rest of Train is there: only the lighter week and the cardio dose
      // are withheld.
      expect(_text('Train'), findsWidgets);
      expect(find.textContaining('of 150 min'), findsNothing);
      expect(_text(cardioNoDataValue), findsNothing);
    });

    testWidgets('the server no longer suggests it: nothing is stored, the '
        'card goes and says why', (tester) async {
      final harness = await _pump(tester, suggestedJson());
      harness.repository
        ..prepareError = const TrainingGuidanceException(
          TrainingGuidanceFailure.notSuggested,
        )
        ..onPrepare = () {
          harness.repository.json = suggestedJson(
            change: (json) {
              deloadOf(json)
                ..['status'] = 'not_due'
                ..['reasons'] = <Object>[]
                ..['suppressed_by'] = 'safety_route';
            },
          );
        };
      await tester.tap(_text(deloadSeeChanges));
      await tester.pumpAndSettle();
      expect(harness.proposals.loadedIds, isEmpty);
      expect(_text(deloadTitle), findsNothing);
    });

    testWidgets('a lost connection keeps the card and says so', (tester) async {
      final harness = await _pump(tester, suggestedJson());
      harness.repository.prepareError = const TrainingGuidanceException(
        TrainingGuidanceFailure.network,
      );
      await tester.tap(_text(deloadSeeChanges));
      await tester.pumpAndSettle();
      expect(
        _text(deloadFailureLine(TrainingGuidanceFailure.network)),
        findsOneWidget,
      );
      expect(_text(deloadTitle), findsOneWidget);
      expect(harness.proposals.calls, isEmpty);
    });

    testWidgets('a refusal is worded as Tracend\'s, never in Coach\'s voice', (
      tester,
    ) async {
      final harness = await _pump(tester, suggestedJson());
      harness.repository.prepareError = const TrainingGuidanceException(
        TrainingGuidanceFailure.refused,
        code: 'screening_see_professional',
      );
      await tester.tap(_text(deloadSeeChanges));
      await tester.pumpAndSettle();
      expect(
        _text(deloadRefusalLine('screening_see_professional')),
        findsOneWidget,
      );
      expect(find.textContaining('Ask Coach'), findsNothing);
      expect(find.textContaining('I can'), findsNothing);
    });

    testWidgets('without guidance or proposals the screen has no card', (
      tester,
    ) async {
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
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_text(deloadTitle), findsNothing);
      expect(_text(cardioTitle), findsNothing);
    });
  });

  group('Cardio this week', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.ensureVisible(_text(cardioTitle));
      await tester.tap(_text(cardioTitle));
      await tester.pumpAndSettle();
    }

    testWidgets('partial: minutes against the guideline, and what is left', (
      tester,
    ) async {
      await _pump(tester, suggestedJson());
      expect(_text(cardioTitle), findsOneWidget);
      expect(_text('85 of 150 min'), findsOneWidget);
      await openSheet(tester);
      // The row and the sheet's big figure.
      expect(find.text('85 of 150 min', findRichText: true), findsNWidgets(2));
      expect(
        _text('65 min to go to reach the weekly guideline.'),
        findsOneWidget,
      );
      expect(_text(cardioGuideline), findsOneWidget);
      expect(find.textContaining('build toward 300 minutes'), findsOneWidget);
      expect(_text(cardioAllModerate), findsOneWidget);
      expect(_text('Last 7 days, to Sat 24 Oct'), findsOneWidget);
      expect(_text(cardioPermissionNote), findsOneWidget);
      expect(_text(cardioProvenance), findsOneWidget);
    });

    testWidgets('met: it says the guideline is reached', (tester) async {
      await _pump(
        tester,
        suggestedJson(change: (json) => cardioOf(json)['done_min'] = 160),
      );
      expect(_text('160 of 150 min'), findsOneWidget);
      await openSheet(tester);
      expect(_text('You have reached the weekly guideline.'), findsOneWidget);
      expect(find.textContaining('min to go'), findsNothing);
    });

    testWidgets('exactly at the target counts as met', (tester) async {
      await _pump(
        tester,
        suggestedJson(change: (json) => cardioOf(json)['done_min'] = 150),
      );
      await openSheet(tester);
      expect(_text('You have reached the weekly guideline.'), findsOneWidget);
    });

    testWidgets('a connected week with no cardio reads 0, as measured', (
      tester,
    ) async {
      await _pump(
        tester,
        suggestedJson(change: (json) => cardioOf(json)['done_min'] = 0),
      );
      expect(_text('0 of 150 min'), findsOneWidget);
      await openSheet(tester);
      expect(
        _text('150 min to go to reach the weekly guideline.'),
        findsOneWidget,
      );
      // The reason a measured zero can be a permission, not a rest week.
      expect(_text(cardioPermissionNote), findsOneWidget);
    });

    testWidgets('null: not enough data, no minutes and no zero', (
      tester,
    ) async {
      await _pump(
        tester,
        suggestedJson(change: (json) => cardioOf(json)['done_min'] = null),
      );
      expect(_text(cardioNoDataValue), findsOneWidget);
      expect(find.textContaining('of 150 min'), findsNothing);
      await openSheet(tester);
      expect(_text(cardioNoDataTitle), findsOneWidget);
      expect(_text(cardioNoDataBody), findsOneWidget);
      expect(find.textContaining('min to go'), findsNothing);
      expect(find.textContaining('reached'), findsNothing);
      expect(_text(cardioAllModerate), findsNothing);
      expect(_text(cardioPermissionNote), findsOneWidget);
    });

    testWidgets('hard cardio open today says how much and how it counts', (
      tester,
    ) async {
      await _pump(tester, suggestedJson());
      await openSheet(tester);
      expect(_text(cardioHardTitle), findsOneWidget);
      expect(
        find.textContaining('Up to 2 hard sessions a week'),
        findsOneWidget,
      );
      expect(find.textContaining('counts as 2'), findsOneWidget);
      expect(find.textContaining('about 3 hours'), findsOneWidget);
      expect(_text(cardioEasyOnlyTitle), findsNothing);
    });

    testWidgets('easy only: the conditions that would open hard cardio', (
      tester,
    ) async {
      await _pump(
        tester,
        suggestedJson(
          change: (json) => cardioOf(json)
            ..['vigorous_allowed'] = false
            ..['vigorous_sessions_max'] = 0,
        ),
      );
      await openSheet(tester);
      expect(_text(cardioEasyOnlyTitle), findsOneWidget);
      expect(_text(cardioEasyOnlyIntro), findsOneWidget);
      for (final condition in cardioEasyOnlyConditions) {
        expect(_text('• $condition'), findsOneWidget);
      }
      expect(_text(cardioHardTitle), findsNothing);
      expect(_text(cardioEasyTalk), findsOneWidget);
      expect(
        find.textContaining('about 60% of your heart rate'),
        findsOneWidget,
      );
    });

    testWidgets('a goal with no stretch figure shows none', (tester) async {
      await _pump(
        tester,
        suggestedJson(change: (json) => cardioOf(json)['stretch_max'] = null),
      );
      await openSheet(tester);
      expect(find.textContaining('build toward'), findsNothing);
    });

    testWidgets('1.0 has no cardio: no row', (tester) async {
      await _pump(tester, guidanceJson('training_guidance_v1_0'));
      expect(_text(cardioTitle), findsNothing);
    });

    testWidgets('a cardio week this build cannot read: no row, the lighter '
        'week still shows', (tester) async {
      await _pump(
        tester,
        suggestedJson(change: (json) => cardioOf(json).remove('done_min')),
      );
      expect(_text(cardioTitle), findsNothing);
      expect(_text(deloadTitle), findsOneWidget);
    });

    testWidgets('VoiceOver hears the minutes', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, suggestedJson());
      expect(
        find.bySemanticsLabel('Cardio this week: 85 of 150 min'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('who made the lighter week', () {
    Map<String, dynamic> coachPending({String? origin = 'coach'}) =>
        guidanceJson(
          'training_guidance_v1_2_coach_pending',
          change: (json) => deloadOf(json)['proposal_origin'] = origin,
        );

    testWidgets('a pending lighter week Coach made is Coach\'s: its wording '
        'and none of the rules\' reasons', (tester) async {
      await _pump(tester, coachPending());
      expect(_text('Proposed by Coach · checked by Tracend'), findsOneWidget);
      expect(_text(deloadCoachTitle), findsOneWidget);
      expect(_text(deloadCoachPendingBody), findsOneWidget);
      expect(_text(deloadSuggestedBy), findsNothing);
      expect(_text(deloadTitle), findsNothing);
      // The guidance still lists a reason; a Coach card does not claim it.
      expect(
        _text('• ${deloadReasonLine(DeloadReason.runDown)}'),
        findsNothing,
      );
      expect(_text(deloadProvenance), findsNothing);
      expect(_text(deloadWhat), findsNothing);
    });

    testWidgets('no origin named reads as Coach\'s, never as the rules\'', (
      tester,
    ) async {
      await _pump(tester, coachPending(origin: null));
      expect(_text('Proposed by Coach · checked by Tracend'), findsOneWidget);
      expect(_text(deloadSuggestedBy), findsNothing);
    });

    testWidgets('an origin from a later version reads as Coach\'s', (
      tester,
    ) async {
      await _pump(tester, coachPending(origin: 'someone_new'));
      expect(_text(deloadSuggestedBy), findsNothing);
      expect(_text(deloadCoachTitle), findsOneWidget);
    });

    testWidgets('a pending lighter week the rules made keeps their wording', (
      tester,
    ) async {
      await _pump(tester, coachPending(origin: 'tracend'));
      expect(_text(deloadSuggestedBy), findsOneWidget);
      expect(_text(deloadTitle), findsOneWidget);
      expect(
        _text('• ${deloadReasonLine(DeloadReason.runDown)}'),
        findsOneWidget,
      );
      expect(_text(deloadCoachTitle), findsNothing);
    });

    testWidgets('the sheet follows the proposal itself: without the rules\' '
        'evidence it is Coach\'s', (tester) async {
      final harness = await _pump(
        tester,
        coachPending(origin: 'coach'),
        proposals: FakeProposals(deloadProposal(byRules: false)),
      );
      await tester.tap(_text(deloadSeeChanges));
      await tester.pumpAndSettle();
      expect(harness.proposals.loadedIds, [
        '00000000-0000-4000-8000-000000000002',
      ]);
      // The card in the sheet and the card on Train say the same.
      expect(_text('Proposed by Coach · checked by Tracend'), findsNWidgets(2));
      expect(_text(deloadSuggestedBy), findsNothing);
      expect(_text('Change it'), findsNothing);
    });

    testWidgets('the sheet of the rules\' own proposal says so', (
      tester,
    ) async {
      await _pump(tester, coachPending(origin: 'tracend'));
      await tester.tap(_text(deloadSeeChanges));
      await tester.pumpAndSettle();
      expect(_text(deloadSuggestedBy), findsNWidgets(2));
      expect(find.textContaining('Proposed by Coach'), findsNothing);
    });

    testWidgets('a running lighter week Coach made is Coach\'s, with its end '
        'day', (tester) async {
      await _pump(
        tester,
        guidanceJson(
          'training_guidance_v1_2_running',
          change: (json) => deloadOf(json)['proposal_origin'] = 'coach',
        ),
      );
      expect(_text('Proposed by Coach · checked by Tracend'), findsOneWidget);
      expect(
        _text(deloadRunningTitleFor(DateTime(2026, 10, 31))),
        findsOneWidget,
      );
      expect(_text(deloadSuggestedBy), findsNothing);
    });

    testWidgets('a running lighter week the rules made says so, and until '
        'when', (tester) async {
      await _pump(tester, guidanceJson('training_guidance_v1_2_running'));
      expect(_text(deloadSuggestedBy), findsOneWidget);
      final until = dayAndDate(DateTime(2026, 10, 31));
      expect(_text('$deloadRunningTitle until $until'), findsOneWidget);
    });

    testWidgets('a running lighter week with no end day still reads', (
      tester,
    ) async {
      await _pump(
        tester,
        guidanceJson(
          'training_guidance_v1_2_running',
          change: (json) => deloadOf(json)['ends_on'] = null,
        ),
      );
      expect(_text(deloadRunningTitle), findsOneWidget);
    });
  });

  group('another change is waiting in Coach', () {
    testWidgets('nothing is stored or expired; the card says to answer it '
        'first', (tester) async {
      final harness = await _pump(tester, suggestedJson());
      harness.repository.prepareError = const TrainingGuidanceException(
        TrainingGuidanceFailure.otherProposalPending,
      );
      await tester.tap(_text(deloadSeeChanges));
      await tester.pumpAndSettle();
      expect(
        _text('You have a change waiting in Coach. Answer it first.'),
        findsOneWidget,
      );
      expect(harness.proposals.loadedIds, isEmpty);
      expect(harness.proposals.calls, isEmpty);
      // Still suggested, and the guidance was not read again for nothing.
      expect(_text(deloadTitle), findsOneWidget);
      expect(harness.repository.loads.length, 1);
    });
  });

  group('taps and Undo', () {
    testWidgets('a second tap while the first is on its way sends nothing', (
      tester,
    ) async {
      final harness = await _pump(tester, suggestedJson());
      final gate = Completer<void>();
      harness.repository.prepareGate = gate.future;
      final button = find.widgetWithText(FilledButton, deloadSeeChanges);
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.byType(FilledButton).first, warnIfMissed: false);
      await tester.pump();
      expect(harness.repository.prepares.length, 1);
      expect(harness.controller.preparing, isTrue);
      gate.complete();
      await tester.pumpAndSettle();
      expect(harness.repository.prepares.length, 1);
      expect(harness.proposals.loadedIds, [
        deloadProposalId,
      ], reason: 'one sheet');
    });

    testWidgets('after Undo the lighter week is gone and is not offered '
        'again at once', (tester) async {
      final proposals = FakeProposals(deloadProposal());
      final harness = await _pump(
        tester,
        suggestedJson(),
        proposals: proposals,
      );
      proposals.onAnswer = (answer) {
        harness.repository.json = switch (answer) {
          'approve' => guidanceJson(
            'training_guidance_v1_2_running',
            change: (json) => deloadOf(json)['proposal_origin'] = 'tracend',
          ),
          // Undone: not running, and the quiet days start.
          _ => suggestedJson(
            change: (json) {
              deloadOf(json)
                ..['status'] = 'not_due'
                ..['reasons'] = <Object>[]
                ..['suppressed_by'] = 'declined_recently';
            },
          ),
        };
      };
      await tester.tap(_text(deloadSeeChanges));
      await tester.pumpAndSettle();
      await tester.tap(_text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(_text('Approve').last);
      await tester.pumpAndSettle();
      await tester.tap(_text('Undo'));
      await tester.pumpAndSettle();
      expect(proposals.calls, ['approve', 'undo']);
      await tester.tap(find.bySemanticsLabel(RegExp('Close')).first);
      await tester.pumpAndSettle();
      expect(_text(deloadTitle), findsNothing);
      expect(_text(deloadRunningTitle), findsNothing);
      expect(find.textContaining(deloadRunningTitle), findsNothing);
      expect(_text(deloadSeeChanges), findsNothing);
    });

    testWidgets('after approval the running card appears and opens the same '
        'proposal for Undo', (tester) async {
      final proposals = FakeProposals(deloadProposal());
      final harness = await _pump(
        tester,
        suggestedJson(),
        proposals: proposals,
      );
      proposals.onAnswer = (answer) {
        if (answer == 'approve') {
          harness.repository.json = guidanceJson(
            'training_guidance_v1_2_running',
            change: (json) => deloadOf(json)['proposal_origin'] = 'tracend',
          );
        }
      };
      await tester.tap(_text(deloadSeeChanges));
      await tester.pumpAndSettle();
      await tester.tap(_text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(_text('Approve').last);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp('Close')).first);
      await tester.pumpAndSettle();
      expect(find.textContaining(deloadRunningTitle), findsOneWidget);
      await tester.tap(_text(deloadRunningAction));
      await tester.pumpAndSettle();
      expect(_text('Undo'), findsOneWidget);
    });
  });

  group('the cardio row follows the week on screen', () {
    testWidgets('a past week has no cardio row; This week brings it back', (
      tester,
    ) async {
      await _pump(tester, suggestedJson());
      expect(_text(cardioTitle), findsOneWidget);
      await tester.fling(
        find.byKey(const ValueKey('day-box-2026-10-01')),
        const Offset(300, 0),
        1500,
      );
      await tester.pumpAndSettle();
      expect(_text('Week of 21 September'), findsOneWidget);
      expect(_text(cardioTitle), findsNothing);
      expect(_text('Training load'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'This week'));
      await tester.pumpAndSettle();
      expect(_text(cardioTitle), findsOneWidget);
    });
  });

  group('copy', () {
    test('names no condition, model or company, and no heart signal', () {
      final text = File(
        'lib/features/train/guidance/guidance_copy.dart',
      ).readAsStringSync().toLowerCase();
      for (final word in [
        'tendin',
        'sprain',
        'sciatica',
        'meniscus',
        'rotator',
        'arthritis',
        'diagnos',
        'overtrain',
        'burnout',
        'injur',
        'claude',
        'anthropic',
        'openai',
        'deepseek',
        'gemini',
        'groq',
        'hrv',
        'resting heart',
      ]) {
        expect(text, isNot(contains(word)), reason: word);
      }
    });

    test('every reason and failure has a line', () {
      for (final reason in DeloadReason.values) {
        expect(deloadReasonLine(reason), isNotEmpty);
      }
      for (final failure in TrainingGuidanceFailure.values) {
        expect(deloadFailureLine(failure), isNotEmpty);
      }
    });
  });
}
