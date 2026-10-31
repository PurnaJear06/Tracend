import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/coach/proposals/coach_proposal.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_card.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_repository.dart';
import 'package:tracend/shared/plan_changes.dart';

final _when = DateTime(2026, 10, 18);

CoachProposal _pending() => CoachProposal.listFromJson(
  json.decode(
    File('test/contract/fixtures/coach_proposals_v1_0.json').readAsStringSync(),
  ),
).first;

CoachMessage _user(String id, String text) =>
    CoachMessage(id: id, role: 'user', content: text, createdAt: _when);

CoachMessage _reply(String id, {String? proposalId}) => CoachMessage(
  id: id,
  role: 'assistant',
  content: 'Here is a proposal you can approve below.',
  createdAt: _when,
  modelProvider: 'anthropic',
  model: 'claude-haiku-5-5',
  proposalId: proposalId,
);

class _Chat implements CoachRepository, CoachChatRepository {
  _Chat(this.messages, [this.replies = const []]);

  final List<CoachMessage> messages;
  final List<CoachMessage> replies;
  final sent = <String>[];

  @override
  Future<List<CoachThread>> loadThreads() async => [
    CoachThread(id: 't1', title: 'Thread', updatedAt: _when),
  ];

  @override
  Future<String> createThread({bool remember = true}) async => 't1';

  @override
  Future<List<CoachMessage>> loadMessages(String threadId) async => messages;

  @override
  Future<CoachMessage> sendMessage(
    String threadId,
    String question, {
    String? idempotencyKey,
  }) async {
    sent.add(question);
    return replies.removeAt(0);
  }

  @override
  Future<void> deleteThread(String threadId) async {}

  @override
  Future<CoachDecision?> loadLatest() async => null;

  @override
  Future<CoachDecision> generate({String? localDate}) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> loadUsage() async => {};
}

class _Proposals implements CoachProposalRepository {
  _Proposals(this.proposal);

  CoachProposal proposal;
  final answers = <String>[];

  /// When set, load waits for it: the card appears after the thread laid out.
  Completer<void>? loadGate;

  @override
  Future<List<CoachProposal>> load({String? id}) async {
    await loadGate?.future;
    return [proposal];
  }

  @override
  Future<CoachProposalAnswer> respond(
    String id,
    CoachProposalAction action, {
    String? note,
  }) async {
    answers.add(action.wire);
    final accepted = action == CoachProposalAction.approve;
    proposal = proposal.withStatus(
      accepted
          ? CoachProposalStatus.accepted
          : action == CoachProposalAction.change
          ? CoachProposalStatus.changed
          : CoachProposalStatus.declined,
      DateTime.now().add(const Duration(days: 7)),
    );
    return CoachProposalAnswer(
      proposalId: id,
      status: accepted
          ? 'accepted'
          : action == CoachProposalAction.change
          ? 'changed'
          : 'declined',
      changedPlan: accepted,
    );
  }

  @override
  Future<CoachProposalAnswer> undo(String id) => throw UnimplementedError();
}

class _Memory implements CoachThreadMemory {
  @override
  Future<String?> lastThreadId() async => 't1';

  @override
  Future<void> remember(String threadId) async {}
}

Future<void> _open(
  WidgetTester tester,
  _Chat chat, {
  CoachProposalRepository? proposals,
  PlanChanges? changes,
  Size size = const Size(800, 2800),
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: CoachScreen(
          repository: chat,
          threadMemory: _Memory(),
          proposals: proposals,
          planChanges: changes,
          now: () => _when.add(const Duration(hours: 1)),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('a card that loads after the thread laid out keeps the view on '
      'the newest message', (tester) async {
    final proposal = _pending();
    final gate = Completer<void>();
    final repository = _Proposals(proposal)..loadGate = gate;
    await _open(
      tester,
      _Chat([
        for (var i = 0; i < 20; i++) ...[
          _user('u$i', 'Question $i ${'about my training ' * 8}'),
          if (i < 19) _reply('a$i') else _reply('a$i', proposalId: proposal.id),
        ],
      ]),
      proposals: repository,
      size: const Size(800, 900),
      settle: false,
    );
    final scroll = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CoachScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(scroll.pixels, scroll.maxScrollExtent);
    final before = scroll.maxScrollExtent;

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CoachProposalCard), findsOneWidget);
    expect(scroll.maxScrollExtent, greaterThan(before));
    expect(scroll.pixels, scroll.maxScrollExtent);
  });

  testWidgets('a reloaded reply shows its proposal card; approving announces '
      'the plan change', (tester) async {
    final proposal = _pending();
    final repository = _Proposals(proposal);
    final changes = PlanChanges();
    addTearDown(changes.dispose);
    var announced = 0;
    changes.addListener(() => announced++);
    await _open(
      tester,
      _Chat([
        _user('u1', 'Take a diet break'),
        _reply('a1', proposalId: proposal.id),
      ]),
      proposals: repository,
      changes: changes,
    );
    expect(find.byType(CoachProposalCard), findsOneWidget);
    expect(find.text('Take a diet break'), findsWidgets);
    await tester.ensureVisible(find.text('Approve'));
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();
    expect(repository.answers, ['approve']);
    expect(announced, 1);
    expect(find.text('Applied'), findsOneWidget);
  });

  testWidgets('a reply sent now shows its card under it', (tester) async {
    final proposal = _pending();
    final chat = _Chat(const [], [_reply('a2', proposalId: proposal.id)]);
    await _open(tester, chat, proposals: _Proposals(proposal));
    await tester.enterText(find.byType(TextField), 'Take a diet break');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(chat.sent, ['Take a diet break']);
    expect(find.byType(CoachProposalCard), findsOneWidget);
  });

  testWidgets('Change it sends the follow-up message to Coach', (tester) async {
    final proposal = _pending();
    final chat = _Chat(
      [_user('u1', 'Take a diet break'), _reply('a1', proposalId: proposal.id)],
      [_reply('a3')],
    );
    final repository = _Proposals(proposal);
    await _open(tester, chat, proposals: repository);
    await tester.ensureVisible(find.text('Change it'));
    await tester.tap(find.text('Change it'));
    await tester.pumpAndSettle();
    expect(repository.answers, ['change']);
    expect(chat.sent, [proposal.changeRequestMessage]);
  });

  testWidgets('a reply without a proposal, or with no proposals backend, '
      'shows no card', (tester) async {
    final proposal = _pending();
    await _open(
      tester,
      _Chat([_user('u1', 'Hi'), _reply('a1')]),
      proposals: _Proposals(proposal),
    );
    expect(find.byType(CoachProposalCard), findsNothing);
    expect(find.byType(CoachProposalLoader), findsNothing);
    await _open(
      tester,
      _Chat([_user('u1', 'Hi'), _reply('a1', proposalId: proposal.id)]),
    );
    expect(find.byType(CoachProposalLoader), findsNothing);
  });

  test('a stored or live message carries its proposal id', () {
    final stored = CoachMessage.fromJson(
      {
        'id': 'a1',
        'role': 'assistant',
        'content': 'Here is a proposal you can approve below.',
        'created_at': '2026-10-18T09:00:00Z',
        'proposal_id': 'p1',
      },
      fallbackId: 'x',
      fallbackCreatedAt: _when,
    );
    expect(stored.proposalId, 'p1');
    final plain = CoachMessage.fromJson(
      {'id': 'a2', 'role': 'assistant', 'content': 'Keep today as planned.'},
      fallbackId: 'x',
      fallbackCreatedAt: _when,
    );
    expect(plain.proposalId, isNull);
  });
}
