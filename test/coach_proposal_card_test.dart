import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/proposals/coach_proposal.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_card.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_repository.dart';

List<CoachProposal> _fixture() => CoachProposal.listFromJson(
  json.decode(
    File('test/contract/fixtures/coach_proposals_v1_0.json').readAsStringSync(),
  ),
);

/// Answers like the server: approving makes the proposal accepted with an
/// undo window; undo makes it undone.
class _Repository implements CoachProposalRepository {
  _Repository(
    this.proposal, {
    this.answerStatus,
    this.failure,
    this.lostReply,
    this.loadFailure,
  });

  CoachProposal proposal;
  final String? answerStatus;
  final CoachProposalException? failure;

  /// The server writes the answer, then the reply is lost: the call fails
  /// and the proposal already holds this status.
  final CoachProposalStatus? lostReply;

  /// Reading the proposal fails too (the phone is offline).
  final CoachProposalException? loadFailure;
  final calls = <String>[];
  int loads = 0;

  @override
  Future<List<CoachProposal>> load({String? id}) async {
    loads++;
    if (loadFailure != null) throw loadFailure!;
    return [proposal];
  }

  @override
  Future<CoachProposalAnswer> respond(
    String id,
    CoachProposalAction action, {
    String? note,
  }) async {
    calls.add(action.wire);
    if (lostReply != null) {
      proposal = proposal.withStatus(
        lostReply!,
        DateTime.now().add(const Duration(days: 7)),
      );
      throw failure!;
    }
    if (failure != null) throw failure!;
    final status =
        answerStatus ??
        switch (action) {
          CoachProposalAction.approve => 'accepted',
          CoachProposalAction.decline => 'declined',
          CoachProposalAction.change => 'changed',
        };
    final next = CoachProposalStatus.parse(
      status == 'accepted'
          ? 'accepted'
          : status == 'declined'
          ? 'declined'
          : status == 'changed'
          ? 'changed'
          : 'expired',
    )!;
    proposal = proposal.withStatus(
      next,
      DateTime.now().add(const Duration(days: 7)),
    );
    return CoachProposalAnswer(
      proposalId: id,
      status: status,
      reason: status == 'expired' ? 'plan_changed' : null,
      changedPlan: status == 'accepted',
    );
  }

  @override
  Future<CoachProposalAnswer> undo(String id) async {
    calls.add('undo');
    if (lostReply != null) {
      proposal = proposal.withStatus(lostReply!, null);
      throw failure!;
    }
    if (failure != null) throw failure!;
    proposal = proposal.withStatus(CoachProposalStatus.undone, null);
    return CoachProposalAnswer(
      proposalId: id,
      status: 'undone',
      changedPlan: true,
    );
  }
}

Widget _app(Widget child) => MaterialApp(
  theme: TracendTheme.dark,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Future<void> _approve(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Approve'));
  await tester.tap(find.text('Approve'));
  await tester.pumpAndSettle();
  // The confirm sheet repeats the choice.
  expect(find.text('Apply this change?'), findsOneWidget);
  await tester.tap(find.text('Approve').last);
  await tester.pumpAndSettle();
}

void main() {
  late CoachProposal pending;
  late CoachProposal accepted;

  setUp(() {
    final all = _fixture();
    pending = all.first;
    accepted = all[1];
  });

  testWidgets(
    'a pending card shows before and after, reason, downside, expiry',
    (tester) async {
      await tester.pumpWidget(
        _app(
          CoachProposalCard(
            proposal: pending,
            repository: _Repository(pending),
          ),
        ),
      );
      expect(find.text('Take a diet break'), findsOneWidget);
      expect(
        find.textContaining('2-week diet break at maintenance'),
        findsOneWidget,
      );
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('After'), findsOneWidget);
      expect(find.text('2,300 kcal'), findsOneWidget);
      expect(find.text('2,240 kcal'), findsOneWidget);
      expect(find.text('Diet break until 31 Oct'), findsOneWidget);
      expect(find.textContaining('Fat loss pauses'), findsOneWidget);
      expect(find.textContaining('Open until'), findsOneWidget);
      expect(find.text('Waiting for you'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Change it'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
      // No model or company name anywhere on the card (D11).
      expect(find.textContaining('Claude'), findsNothing);
      expect(find.textContaining('Anthropic'), findsNothing);
    },
  );

  group('after an error the proposal is read again', () {
    const offline = CoachProposalException(
      'Could not reach Tracend. Check your connection and try again.',
    );
    const refused = CoachProposalException(
      'This change can no longer be applied. Ask Coach again and it will '
      'start from your latest plan.',
    );

    testWidgets('offline approve says so and leaves Approve usable', (
      tester,
    ) async {
      final repository = _Repository(
        pending,
        failure: offline,
        loadFailure: offline,
      );
      var planChanges = 0;
      await tester.pumpWidget(
        _app(
          CoachProposalCard(
            proposal: pending,
            repository: repository,
            onPlanChanged: () => planChanges++,
          ),
        ),
      );
      await _approve(tester);

      expect(find.textContaining('Could not reach Tracend'), findsOneWidget);
      expect(find.text('Waiting for you'), findsOneWidget);
      expect(planChanges, 0);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('an approve whose reply was lost shows Applied and reloads '
        'the plan', (tester) async {
      final repository = _Repository(
        pending,
        failure: offline,
        lostReply: CoachProposalStatus.accepted,
      );
      var planChanges = 0;
      await tester.pumpWidget(
        _app(
          CoachProposalCard(
            proposal: pending,
            repository: repository,
            onPlanChanged: () => planChanges++,
          ),
        ),
      );
      await _approve(tester);

      expect(find.text('Applied'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.textContaining('Could not reach Tracend'), findsNothing);
      expect(planChanges, 1);
    });

    testWidgets('a retry refused with 55000 on a proposal that is accepted '
        'shows it applied', (tester) async {
      final repository = _Repository(
        pending,
        failure: refused,
        lostReply: CoachProposalStatus.accepted,
      );
      var planChanges = 0;
      await tester.pumpWidget(
        _app(
          CoachProposalCard(
            proposal: pending,
            repository: repository,
            onPlanChanged: () => planChanges++,
          ),
        ),
      );
      await _approve(tester);

      expect(find.text('Applied'), findsOneWidget);
      expect(find.textContaining('can no longer be applied'), findsNothing);
      expect(planChanges, 1);
    });

    testWidgets('a 55000 on a proposal that is still waiting keeps the '
        'error', (tester) async {
      final repository = _Repository(pending, failure: refused);
      await tester.pumpWidget(
        _app(CoachProposalCard(proposal: pending, repository: repository)),
      );
      await _approve(tester);

      expect(find.textContaining('can no longer be applied'), findsOneWidget);
      expect(find.text('Applied'), findsNothing);
    });

    testWidgets('Not now offline says so and keeps the card', (tester) async {
      final repository = _Repository(
        pending,
        failure: offline,
        loadFailure: offline,
      );
      await tester.pumpWidget(
        _app(CoachProposalCard(proposal: pending, repository: repository)),
      );
      await tester.ensureVisible(find.text('Not now'));
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not reach Tracend'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
    });

    testWidgets('a Not now whose reply was lost shows Not now', (tester) async {
      final repository = _Repository(
        pending,
        failure: offline,
        lostReply: CoachProposalStatus.declined,
      );
      await tester.pumpWidget(
        _app(CoachProposalCard(proposal: pending, repository: repository)),
      );
      await tester.ensureVisible(find.text('Not now'));
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not reach Tracend'), findsNothing);
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets('a Change it whose reply was lost still hands the follow-up '
        'to the chat', (tester) async {
      final repository = _Repository(
        pending,
        failure: offline,
        lostReply: CoachProposalStatus.changed,
      );
      CoachProposal? changed;
      await tester.pumpWidget(
        _app(
          CoachProposalCard(
            proposal: pending,
            repository: repository,
            onChangeIt: (proposal) => changed = proposal,
          ),
        ),
      );
      await tester.ensureVisible(find.text('Change it'));
      await tester.tap(find.text('Change it'));
      await tester.pumpAndSettle();

      expect(changed?.id, pending.id);
      expect(find.text('Change requested'), findsOneWidget);
    });

    testWidgets('Undo offline says so and keeps Undo', (tester) async {
      final repository = _Repository(
        accepted,
        failure: offline,
        loadFailure: offline,
      );
      var planChanges = 0;
      await tester.pumpWidget(
        _app(
          CoachProposalCard(
            proposal: accepted,
            repository: repository,
            onPlanChanged: () => planChanges++,
          ),
        ),
      );
      await tester.ensureVisible(find.text('Undo'));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not reach Tracend'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(planChanges, 0);
    });

    testWidgets('an Undo whose reply was lost shows Undone and reloads the '
        'plan', (tester) async {
      final repository = _Repository(
        accepted,
        failure: offline,
        lostReply: CoachProposalStatus.undone,
      );
      var planChanges = 0;
      await tester.pumpWidget(
        _app(
          CoachProposalCard(
            proposal: accepted,
            repository: repository,
            onPlanChanged: () => planChanges++,
          ),
        ),
      );
      await tester.ensureVisible(find.text('Undo'));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Undone'), findsOneWidget);
      expect(find.textContaining('Could not reach Tracend'), findsNothing);
      expect(planChanges, 1);
    });
  });

  testWidgets('training changes list the sessions before and after', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        CoachProposalCard(
          proposal: accepted,
          repository: _Repository(accepted),
        ),
      ),
    );
    expect(find.text('Your sessions now'), findsOneWidget);
    expect(find.text('Your sessions after'), findsOneWidget);
    expect(
      find.text('Mon · Full body A · 6 exercises · 60 min'),
      findsOneWidget,
    );
    expect(
      find.text('Mon · Full body A · 5 exercises · 51 min'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Your regular plan comes back after'),
      findsOneWidget,
    );
  });

  testWidgets(
    'approving asks to confirm, applies, refreshes the plan and offers undo',
    (tester) async {
      final repository = _Repository(pending);
      var planChanges = 0;
      await tester.pumpWidget(
        _app(
          CoachProposalCard(
            proposal: pending,
            repository: repository,
            onPlanChanged: () => planChanges++,
          ),
        ),
      );
      await _approve(tester);
      expect(repository.calls, ['approve']);
      expect(planChanges, 1);
      expect(find.text('Applied'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.textContaining('You can undo this until'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
    },
  );

  testWidgets('cancelling the confirm sheet applies nothing', (tester) async {
    final repository = _Repository(pending);
    await tester.pumpWidget(
      _app(CoachProposalCard(proposal: pending, repository: repository)),
    );
    await tester.ensureVisible(find.text('Approve'));
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.calls, isEmpty);
    expect(find.text('Waiting for you'), findsOneWidget);
  });

  testWidgets('undo restores and refreshes the plan again', (tester) async {
    final repository = _Repository(accepted);
    var planChanges = 0;
    await tester.pumpWidget(
      _app(
        CoachProposalCard(
          proposal: accepted,
          repository: repository,
          onPlanChanged: () => planChanges++,
        ),
      ),
    );
    await tester.ensureVisible(find.text('Undo'));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['undo']);
    expect(planChanges, 1);
    expect(find.text('Undone'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('Not now closes the card without changing the plan', (
    tester,
  ) async {
    final repository = _Repository(pending);
    var planChanges = 0;
    await tester.pumpWidget(
      _app(
        CoachProposalCard(
          proposal: pending,
          repository: repository,
          onPlanChanged: () => planChanges++,
        ),
      ),
    );
    await tester.ensureVisible(find.text('Not now'));
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['decline']);
    expect(planChanges, 0);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets(
    'Change it records the answer and hands the follow-up to the chat',
    (tester) async {
      final repository = _Repository(pending);
      CoachProposal? changed;
      await tester.pumpWidget(
        _app(
          CoachProposalCard(
            proposal: pending,
            repository: repository,
            onChangeIt: (proposal) => changed = proposal,
          ),
        ),
      );
      await tester.ensureVisible(find.text('Change it'));
      await tester.tap(find.text('Change it'));
      await tester.pumpAndSettle();
      expect(repository.calls, ['change']);
      expect(changed?.id, pending.id);
      expect(
        changed?.changeRequestMessage,
        'I want to change this: Take a diet break. Can we adjust it?',
      );
    },
  );

  testWidgets(
    'an approval the server refuses as stale says so and changes nothing',
    (tester) async {
      final repository = _Repository(pending, answerStatus: 'expired');
      var planChanges = 0;
      await tester.pumpWidget(
        _app(
          CoachProposalCard(
            proposal: pending,
            repository: repository,
            onPlanChanged: () => planChanges++,
          ),
        ),
      );
      await _approve(tester);
      expect(planChanges, 0);
      expect(find.textContaining('nothing was applied'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
    },
  );

  testWidgets(
    'a failed answer shows the reason and leaves the buttons usable',
    (tester) async {
      final repository = _Repository(
        pending,
        failure: const CoachProposalException(
          'Could not reach Tracend. Check your connection and try again.',
        ),
      );
      await tester.pumpWidget(
        _app(CoachProposalCard(proposal: pending, repository: repository)),
      );
      await _approve(tester);
      expect(find.textContaining('Could not reach Tracend'), findsOneWidget);
      expect(find.text('Waiting for you'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Approve'),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets('the loader renders a card from a proposal id', (tester) async {
    final repository = _Repository(pending);
    await tester.pumpWidget(
      _app(CoachProposalLoader(proposalId: pending.id, repository: repository)),
    );
    expect(find.byType(CoachProposalCard), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(CoachProposalCard), findsOneWidget);
    expect(find.text('Take a diet break'), findsOneWidget);
    expect(repository.loads, 1);
  });

  testWidgets('the loader offers a retry when the proposal cannot be read', (
    tester,
  ) async {
    final repository = _EmptyRepository();
    await tester.pumpWidget(
      _app(CoachProposalLoader(proposalId: 'missing', repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('This proposal could not be loaded.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(repository.loads, 2);
  });

  testWidgets('an expired card has no actions', (tester) async {
    final expired = _fixture()[2];
    await tester.pumpWidget(
      _app(
        CoachProposalCard(proposal: expired, repository: _Repository(expired)),
      ),
    );
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Not now'), findsNothing);
    expect(find.text('Undo'), findsNothing);
  });
}

class _EmptyRepository implements CoachProposalRepository {
  int loads = 0;

  @override
  Future<List<CoachProposal>> load({String? id}) async {
    loads++;
    return const [];
  }

  @override
  Future<CoachProposalAnswer> respond(
    String id,
    CoachProposalAction action, {
    String? note,
  }) => throw UnimplementedError();

  @override
  Future<CoachProposalAnswer> undo(String id) => throw UnimplementedError();
}
