import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/proposals/coach_proposal.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_card.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_repository.dart';
import 'package:tracend/features/coach/proposals/proposal_notices.dart';
import 'package:tracend/features/train/guidance/guidance_copy.dart';
import 'package:tracend/features/train/guidance/training_guidance_repository.dart';

import 'training_guidance_fixtures.dart';

const _reasons = [
  'expired',
  'block_over',
  'block_running',
  'plan_changed',
  'anything_new',
  null,
];

/// Words a Tracend card must never say: Coach's first person and sending the
/// athlete back to Coach to ask again.
void _speaksAsTracend(String text) {
  expect(text, isNotEmpty);
  expect(text, isNot(contains('Coach')), reason: text);
  expect(
    text,
    isNot(matches(RegExp(r"\b(I|I'm|I've|I'll|my)\b"))),
    reason: text,
  );
}

void main() {
  group('notices on a card Tracend made', () {
    test(
      'a stale approval never names Coach or speaks in the first person',
      () {
        for (final reason in _reasons) {
          _speaksAsTracend(
            proposalStaleNotice(reason, CoachProposalOrigin.tracend),
          );
        }
      },
    );

    test('a Coach card still sends the athlete back to Coach', () {
      for (final reason in _reasons) {
        final notice = proposalStaleNotice(reason, CoachProposalOrigin.coach);
        if (reason == 'expired') continue;
        expect(notice, contains('Ask Coach again'));
      }
    });

    test('a refused answer is worded for who made the proposal', () {
      const stale = CoachProposalException(
        'This change can no longer be applied. Ask Coach again and it will '
        'start from your latest plan.',
        stale: true,
      );
      _speaksAsTracend(proposalErrorNotice(stale, CoachProposalOrigin.tracend));
      expect(
        proposalErrorNotice(stale, CoachProposalOrigin.coach),
        contains('Ask Coach again'),
      );
      const route = CoachProposalException(
        safetyRouteDayNotice,
        stale: true,
        safetyRouteDay: true,
      );
      for (final origin in CoachProposalOrigin.values) {
        expect(proposalErrorNotice(route, origin), safetyRouteDayNotice);
      }
      _speaksAsTracend(safetyRouteDayNotice);
      expect(safetyRouteDayNotice, contains('referral'));
      // A failure that is not about the proposal's state is the same for both.
      const offline = CoachProposalException('Could not reach Tracend.');
      for (final origin in CoachProposalOrigin.values) {
        expect(proposalErrorNotice(offline, origin), offline.message);
      }
    });

    test('the server\'s 55000 on a route day is told apart from the rest', () {
      final route = coachProposalErrorMessage(
        const PostgrestException(
          message: 'a deload cannot be approved on a day with a safety route',
          code: '55000',
        ),
      );
      expect(route, safetyRouteDayNotice);
      final other = coachProposalErrorMessage(
        const PostgrestException(
          message: 'proposal is not pending',
          code: '55000',
        ),
      );
      expect(other, contains('can no longer be applied'));
    });

    test('every refusal the function can give has Tracend\'s words', () {
      for (final code in [
        'screening_see_professional',
        'no_active_plan',
        'block_already_active',
        'no_change',
        'profile_incomplete',
        'plan_changed',
        'screening_changed',
        'evidence_changed',
        'a_code_from_the_future',
        null,
      ]) {
        _speaksAsTracend(deloadRefusalLine(code));
      }
      for (final failure in TrainingGuidanceFailure.values) {
        if (failure == TrainingGuidanceFailure.otherProposalPending) continue;
        _speaksAsTracend(deloadFailureLine(failure, code: 'plan_changed'));
      }
      // The one line that names Coach does so on purpose: it sends the
      // athlete to the change that is waiting there.
      expect(
        deloadFailureLine(TrainingGuidanceFailure.otherProposalPending),
        'You have a change waiting in Coach. Answer it first.',
      );
    });
  });

  group('the card shows them', () {
    Future<_Answers> pump(
      WidgetTester tester, {
      required CoachProposal proposal,
      String? answer,
      CoachProposalException? failure,
    }) async {
      final repository = _Answers(
        proposal,
        answerStatus: answer,
        failure: failure,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: CoachProposalCard(
                proposal: proposal,
                repository: repository,
                allowChange: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    Future<void> approve(WidgetTester tester) async {
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve').last);
      await tester.pumpAndSettle();
    }

    testWidgets('an approval that went stale on a lighter week made by the '
        'rules', (tester) async {
      await pump(tester, proposal: deloadProposal(), answer: 'expired');
      await approve(tester);
      expect(
        find.text(
          proposalStaleNotice('plan_changed', CoachProposalOrigin.tracend),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Ask Coach'), findsNothing);
    });

    testWidgets('the same on a lighter week Coach made keeps Coach\'s words', (
      tester,
    ) async {
      await pump(
        tester,
        proposal: deloadProposal(byRules: false),
        answer: 'expired',
      );
      await approve(tester);
      expect(find.textContaining('Ask Coach again'), findsOneWidget);
    });

    testWidgets('a route-day refusal says a lighter week cannot start on a '
        'day with a referral', (tester) async {
      await pump(
        tester,
        proposal: deloadProposal(),
        failure: const CoachProposalException(
          safetyRouteDayNotice,
          stale: true,
          safetyRouteDay: true,
        ),
      );
      await approve(tester);
      expect(find.text(safetyRouteDayNotice), findsOneWidget);
    });

    testWidgets('a stale refusal on the rules\' card does not send the athlete '
        'to Coach', (tester) async {
      await pump(
        tester,
        proposal: deloadProposal(),
        failure: const CoachProposalException(
          'This change can no longer be applied. Ask Coach again and it will '
          'start from your latest plan.',
          stale: true,
        ),
      );
      await approve(tester);
      expect(find.textContaining('Ask Coach'), findsNothing);
      expect(find.textContaining('Pull down on Train'), findsOneWidget);
    });
  });
}

class _Answers extends FakeProposals {
  _Answers(super.proposal, {this.answerStatus, this.failure});

  final String? answerStatus;
  final CoachProposalException? failure;

  @override
  Future<CoachProposalAnswer> respond(
    String id,
    CoachProposalAction action, {
    String? note,
  }) async {
    if (failure != null) throw failure!;
    if (answerStatus == 'expired') {
      return CoachProposalAnswer(
        proposalId: id,
        status: 'expired',
        reason: 'plan_changed',
      );
    }
    return super.respond(id, action, note: note);
  }
}
