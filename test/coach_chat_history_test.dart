import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/coach/widgets/coach_message_bubble.dart';
import 'package:tracend/shared/coach_draft_requests.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

Widget _app(
  CoachRepository repository,
  CoachThreadMemory memory, {
  Duration age = const Duration(hours: 1),
  bool active = true,
  CoachDraftRequests? drafts,
}) => MaterialApp(
  theme: TracendTheme.dark,
  home: Scaffold(
    body: CoachScreen(
      repository: repository,
      threadMemory: memory,
      // Threads are last updated at [_when]; this is how long ago that was.
      now: () => _when.add(age),
      active: active,
      draftRequests: drafts,
    ),
  ),
);

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
}

Future<void> _send(WidgetTester tester, String question) async {
  await tester.enterText(find.byType(TextField), question);
  await tester.tap(find.byTooltip('Send message'));
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Saved conversations'));
  await tester.pumpAndSettle();
}

/// The app leaves and returns, in the order the platform reports it.
void _backgroundAndResume(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

final _when = DateTime(2026, 9, 29);

CoachThread _thread(String id, String title) =>
    CoachThread(id: id, title: title, updatedAt: _when);

CoachMessage _user(String id, String text) =>
    CoachMessage(id: id, role: 'user', content: text, createdAt: _when);

CoachMessage _answer(String id, String text) => CoachMessage(
  id: id,
  role: 'assistant',
  content: text,
  createdAt: _when,
  modelProvider: 'deepseek',
  model: 'deepseek-flash',
  answerSource: 'model',
);

CoachMessage _summary({
  String safetyState = 'unavailable',
  CoachChatDiagnostic? diagnostic,
}) => CoachMessage(
  id: 'summary-$safetyState',
  role: 'assistant',
  content: safetyState == 'limited'
      ? 'Please talk to a doctor before you train again.'
      : 'Here is what your data shows.',
  createdAt: _when,
  modelProvider: 'deterministic',
  model: 'coach-data-summary-v1',
  answerSource: 'data_summary',
  safetyState: safetyState,
  evidence: safetyState == 'limited'
      ? const []
      : const [
          {
            'code': 'APPROVED_PLAN_ACTIVE',
            'label': 'Approved plan active',
            'source': 'coach_context',
          },
        ],
  diagnostic: diagnostic,
);

void main() {
  group('opening Coach', () {
    Future<_HistoryRepository> open(
      WidgetTester tester, {
      required Duration age,
      String remembered = 't-old',
    }) async {
      final repository = _HistoryRepository(
        threads: [_thread('t-old', 'Taking a 15 days break')],
        messages: {
          't-old': [
            _user('o1', 'I am thinking of taking a break'),
            _answer('o2', 'A short break is fine.'),
          ],
        },
      );
      await tester.pumpWidget(_app(repository, _Memory(remembered), age: age));
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('reopens a conversation whose last message is 2 hours old', (
      tester,
    ) async {
      await _tall(tester);
      await open(tester, age: const Duration(hours: 2));

      expect(find.text('I am thinking of taking a break'), findsOneWidget);
      expect(find.text('Continue last chat'), findsNothing);
    });

    testWidgets('starts a new conversation when the last message is 7 hours '
        'old, and offers to continue the old one', (tester) async {
      await _tall(tester);
      final repository = await open(tester, age: const Duration(hours: 7));

      expect(find.text('I am thinking of taking a break'), findsNothing);
      expect(find.textContaining('Ask about training'), findsOneWidget);
      expect(find.text('Continue last chat'), findsOneWidget);
      expect(find.text('Taking a 15 days break'), findsOneWidget);
      expect(repository.created, 0);

      // The new question starts its own thread, not the old one.
      repository._replies.add(_answer('a1', 'Yes, train legs.'));
      await _send(tester, 'Should I train legs today?');
      expect(repository.sent, [('thread-1', 'Should I train legs today?')]);
      expect(find.text('Continue last chat'), findsNothing);
    });

    testWidgets('exactly 6 hours old is no longer reopened', (tester) async {
      await _tall(tester);
      await open(tester, age: coachReopenWindow);

      expect(find.text('Continue last chat'), findsOneWidget);
    });

    testWidgets('uses the newest conversation when none is remembered', (
      tester,
    ) async {
      await _tall(tester);
      await open(tester, age: const Duration(hours: 7), remembered: 'gone');

      expect(find.text('Continue last chat'), findsOneWidget);
      expect(find.text('Taking a 15 days break'), findsOneWidget);
    });

    testWidgets('Continue last chat opens that conversation', (tester) async {
      await _tall(tester);
      final memory = _Memory('t-old');
      final repository = _HistoryRepository(
        threads: [_thread('t-old', 'Taking a 15 days break')],
        messages: {
          't-old': [
            _user('o1', 'I am thinking of taking a break'),
            _answer('o2', 'A short break is fine.'),
          ],
        },
      );
      await tester.pumpWidget(
        _app(repository, memory, age: const Duration(days: 6)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue last chat'));
      await tester.pumpAndSettle();

      expect(find.text('I am thinking of taking a break'), findsOneWidget);
      expect(find.text('A short break is fine.'), findsOneWidget);
      expect(find.text('Continue last chat'), findsNothing);
      expect(memory.remembered, ['t-old']);
    });

    testWidgets('Continue last chat offers the remembered conversation, not '
        'the newest one', (tester) async {
      await _tall(tester);
      final memory = _Memory('t-old');
      final repository = _HistoryRepository(
        threads: [
          _thread('t-new', 'Meal ideas'),
          _thread('t-old', 'Taking a 15 days break'),
        ],
        messages: {
          't-new': [_user('n1', 'Give me meal ideas')],
          't-old': [_user('o1', 'I am thinking of taking a break')],
        },
      );
      await tester.pumpWidget(
        _app(repository, memory, age: const Duration(days: 6)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Taking a 15 days break'), findsOneWidget);
      await tester.tap(find.text('Continue last chat'));
      await tester.pumpAndSettle();

      expect(find.text('I am thinking of taking a break'), findsOneWidget);
      expect(find.text('Give me meal ideas'), findsNothing);
    });

    testWidgets('a new conversation without earlier ones has no Continue row', (
      tester,
    ) async {
      await _tall(tester);
      await tester.pumpWidget(_app(_HistoryRepository(), _Memory()));
      await tester.pumpAndSettle();

      expect(find.text('Continue last chat'), findsNothing);
    });
  });

  group('coming back to Coach', () {
    final thread = _thread('t-old', 'Taking a 15 days break');
    final messages = {
      't-old': [
        _user('o1', 'I am thinking of taking a break'),
        _answer('o2', 'A short break is fine.'),
      ],
    };

    Future<(_HistoryRepository, _Memory)> openAt(
      WidgetTester tester,
      Duration age,
    ) async {
      await _tall(tester);
      final repository = _HistoryRepository(
        threads: [thread],
        messages: messages,
        replies: [Completer<CoachMessage>()],
      );
      final memory = _Memory('t-old');
      await tester.pumpWidget(_app(repository, memory, age: age));
      await tester.pumpAndSettle();
      expect(find.text('I am thinking of taking a break'), findsOneWidget);
      return (repository, memory);
    }

    Future<void> leaveAndReturn(
      WidgetTester tester,
      _HistoryRepository repository,
      _Memory memory,
      Duration after,
    ) async {
      await tester.pumpWidget(
        _app(repository, memory, age: const Duration(hours: 1), active: false),
      );
      await tester.pumpWidget(_app(repository, memory, age: after));
      await tester.pumpAndSettle();
    }

    testWidgets('the tab re-activated after 7 hours starts a new '
        'conversation', (tester) async {
      final (repository, memory) = await openAt(
        tester,
        const Duration(hours: 1),
      );
      await leaveAndReturn(
        tester,
        repository,
        memory,
        const Duration(hours: 7),
      );

      expect(find.text('I am thinking of taking a break'), findsNothing);
      expect(find.text('Continue last chat'), findsOneWidget);

      repository._replies
        ..clear()
        ..add(_answer('a1', 'Yes, train legs.'));
      await _send(tester, 'Should I train legs today?');
      expect(repository.sent, [('thread-1', 'Should I train legs today?')]);
    });

    testWidgets('the tab re-activated after 2 hours keeps the chat', (
      tester,
    ) async {
      final (repository, memory) = await openAt(
        tester,
        const Duration(hours: 1),
      );
      await leaveAndReturn(
        tester,
        repository,
        memory,
        const Duration(hours: 2),
      );

      expect(find.text('I am thinking of taking a break'), findsOneWidget);
      expect(find.text('Continue last chat'), findsNothing);
    });

    testWidgets('resuming the app after 7 hours starts a new conversation', (
      tester,
    ) async {
      final (repository, memory) = await openAt(
        tester,
        const Duration(hours: 1),
      );
      await tester.pumpWidget(
        _app(repository, memory, age: const Duration(hours: 7)),
      );
      expect(find.text('I am thinking of taking a break'), findsOneWidget);

      _backgroundAndResume(tester);
      await tester.pumpAndSettle();

      expect(find.text('I am thinking of taking a break'), findsNothing);
      expect(find.text('Continue last chat'), findsOneWidget);
    });

    testWidgets('resuming while another tab shows changes nothing', (
      tester,
    ) async {
      final (repository, memory) = await openAt(
        tester,
        const Duration(hours: 1),
      );
      await tester.pumpWidget(
        _app(repository, memory, age: const Duration(hours: 7), active: false),
      );

      _backgroundAndResume(tester);
      await tester.pumpAndSettle();

      expect(find.text('I am thinking of taking a break'), findsOneWidget);
    });

    testWidgets('a typed draft keeps the chat, and the next return checks '
        'again', (tester) async {
      final (repository, memory) = await openAt(
        tester,
        const Duration(hours: 1),
      );
      await tester.enterText(find.byType(TextField), 'Should I train legs');
      await leaveAndReturn(
        tester,
        repository,
        memory,
        const Duration(hours: 7),
      );

      expect(find.text('I am thinking of taking a break'), findsOneWidget);
      expect(find.text('Continue last chat'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await leaveAndReturn(
        tester,
        repository,
        memory,
        const Duration(hours: 8),
      );

      expect(find.text('I am thinking of taking a break'), findsNothing);
      expect(find.text('Continue last chat'), findsOneWidget);
    });

    testWidgets('a question left by another screen opens a fresh chat when '
        'the old one is over 6 hours old', (tester) async {
      await _tall(tester);
      final repository = _HistoryRepository(
        threads: [thread],
        messages: messages,
        replies: [Completer<CoachMessage>()],
      );
      final memory = _Memory('t-old');
      final drafts = CoachDraftRequests();
      await tester.pumpWidget(
        _app(repository, memory, age: const Duration(hours: 1), drafts: drafts),
      );
      await tester.pumpAndSettle();
      expect(find.text('I am thinking of taking a break'), findsOneWidget);

      await tester.pumpWidget(
        _app(repository, memory, age: const Duration(hours: 7), drafts: drafts),
      );
      drafts.request('Can we talk it through?');
      await tester.pumpAndSettle();

      expect(find.text('I am thinking of taking a break'), findsNothing);
      expect(find.text('Continue last chat'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Can we talk it through?',
      );
      expect(repository.sent, isEmpty, reason: 'the question is not sent');
    });

    testWidgets('a question left by another screen stays in a fresh chat', (
      tester,
    ) async {
      await _tall(tester);
      final repository = _HistoryRepository(
        threads: [thread],
        messages: messages,
        replies: [Completer<CoachMessage>()],
      );
      final memory = _Memory('t-old');
      final drafts = CoachDraftRequests();
      await tester.pumpWidget(
        _app(repository, memory, age: const Duration(hours: 1), drafts: drafts),
      );
      await tester.pumpAndSettle();
      drafts.request('Can we talk it through?');
      await tester.pumpAndSettle();
      expect(find.text('I am thinking of taking a break'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Can we talk it through?',
      );
    });

    testWidgets('a send in flight keeps the chat', (tester) async {
      final (repository, memory) = await openAt(
        tester,
        const Duration(hours: 1),
      );
      await tester.enterText(find.byType(TextField), 'Should I train legs?');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(repository.sent, [('t-old', 'Should I train legs?')]);

      await leaveAndReturn(
        tester,
        repository,
        memory,
        const Duration(hours: 7),
      );

      expect(find.text('I am thinking of taking a break'), findsOneWidget);
      expect(find.text('Continue last chat'), findsNothing);
    });

    testWidgets('a chat opened on purpose stays open for the visit', (
      tester,
    ) async {
      await _tall(tester);
      final repository = _HistoryRepository(
        threads: [thread],
        messages: messages,
      );
      final memory = _Memory('t-old');
      await tester.pumpWidget(
        _app(repository, memory, age: const Duration(days: 6)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue last chat'));
      await tester.pumpAndSettle();

      _backgroundAndResume(tester);
      await tester.pumpAndSettle();
      expect(find.text('I am thinking of taking a break'), findsOneWidget);

      // Six hours after it was opened, the next return starts fresh.
      await tester.pumpWidget(
        _app(repository, memory, age: const Duration(days: 6, hours: 7)),
      );
      _backgroundAndResume(tester);
      await tester.pumpAndSettle();
      expect(find.text('I am thinking of taking a break'), findsNothing);
      expect(find.text('Continue last chat'), findsOneWidget);
    });
  });

  group('landing on the newest message', () {
    List<CoachMessage> longThread() => [
      for (var i = 0; i < 30; i++) ...[
        _user('u$i', 'Question $i ${'about my training ' * 6}'),
        _answer('a$i', 'Answer $i ${'with a long explanation ' * 25}'),
      ],
    ];

    ScrollPosition position(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CoachScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    void expectAtNewest(WidgetTester tester) {
      final scroll = position(tester);
      expect(scroll.maxScrollExtent, greaterThan(1000));
      expect(scroll.pixels, scroll.maxScrollExtent);
      expect(find.textContaining('Answer 29 '), findsOneWidget);
    }

    testWidgets('a restored long conversation opens at its newest message', (
      tester,
    ) async {
      await _tall(tester);
      tester.view.physicalSize = const Size(800, 900);
      final repository = _HistoryRepository(
        threads: [_thread('t1', 'Long chat')],
        messages: {'t1': longThread()},
      );
      await tester.pumpWidget(_app(repository, _Memory('t1')));
      await tester.pumpAndSettle();

      expectAtNewest(tester);
    });

    testWidgets('a conversation picked from Saved conversations opens at its '
        'newest message', (tester) async {
      await _tall(tester);
      tester.view.physicalSize = const Size(800, 900);
      final repository = _HistoryRepository(
        threads: [_thread('t1', 'Short chat'), _thread('t2', 'Long chat')],
        messages: {
          't1': [_user('s1', 'Short question')],
          't2': longThread(),
        },
      );
      await tester.pumpWidget(_app(repository, _Memory('t1')));
      await tester.pumpAndSettle();
      expect(find.text('Short question'), findsOneWidget);

      await _openSheet(tester);
      await tester.tap(find.text('Long chat'));
      await tester.pumpAndSettle();

      expectAtNewest(tester);
    });
  });

  testWidgets('reopens the conversation the user last had open', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _HistoryRepository(
      threads: [_thread('t-new', 'Newest'), _thread('t-old', 'Older')],
      messages: {
        't-new': [_user('n1', 'Newest question')],
        't-old': [_user('o1', 'Older question')],
      },
    );
    await tester.pumpWidget(_app(repository, _Memory('t-old')));
    await tester.pumpAndSettle();

    expect(find.text('Older question'), findsOneWidget);
    expect(find.text('Newest question'), findsNothing);
    expect(repository.created, 0);
  });

  testWidgets('falls back to the newest conversation when the remembered '
      'one is gone', (tester) async {
    await _tall(tester);
    final repository = _HistoryRepository(
      threads: [_thread('t-new', 'Newest'), _thread('t-old', 'Older')],
      messages: {
        't-new': [_user('n1', 'Newest question')],
        't-old': [_user('o1', 'Older question')],
      },
    );
    await tester.pumpWidget(_app(repository, _Memory('t-deleted')));
    await tester.pumpAndSettle();

    expect(find.text('Newest question'), findsOneWidget);
  });

  testWidgets('opening Coach creates no thread; the first send creates one, '
      'remembers it and refreshes the list', (tester) async {
    await _tall(tester);
    final repository = _HistoryRepository(
      replies: [_answer('a1', 'Keep your deficit steady.')],
    );
    final memory = _Memory();
    await tester.pumpWidget(_app(repository, memory));
    await tester.pumpAndSettle();

    expect(repository.created, 0);
    expect(find.textContaining('Ask about training'), findsOneWidget);

    await _send(tester, 'How long until I reach 72 kg?');

    expect(repository.created, 1);
    expect(repository.sent, [('thread-1', 'How long until I reach 72 kg?')]);
    expect(memory.remembered, ['thread-1']);
    expect(repository.threadLoads, 2);
    await _openSheet(tester);
    expect(
      find.widgetWithText(TracendListRow, 'How long until I reach 72 kg?'),
      findsOneWidget,
    );
  });

  testWidgets('New starts a draft; its thread is created by the first send', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _HistoryRepository(
      threads: [_thread('t1', 'First chat')],
      messages: {
        't1': [_user('u1', 'First question')],
      },
      replies: [_answer('a1', 'Answer')],
    );
    await tester.pumpWidget(_app(repository, _Memory()));
    await tester.pumpAndSettle();
    expect(find.text('First question'), findsOneWidget);

    await _openSheet(tester);
    await tester.tap(find.text('New conversation'));
    await tester.pumpAndSettle();

    expect(find.text('First question'), findsNothing);
    expect(repository.created, 0);

    await _send(tester, 'A new topic');
    expect(repository.created, 1);
    expect(repository.sent, [('thread-1', 'A new topic')]);
  });

  testWidgets('a data summary is labeled, shows the beta diagnostic, and '
      'Retry asks the same question again as a new turn', (tester) async {
    await _tall(tester);
    final repository = _HistoryRepository(
      replies: [
        _summary(
          diagnostic: const CoachChatDiagnostic(
            failureCode: 'provider_response_invalid',
            initialRule: 'evidence_code_not_permitted',
            repairRule: 'reasoning_step_too_long',
          ),
        ),
        _answer('a2', 'Here is my full take.'),
      ],
    );
    await tester.pumpWidget(_app(repository, _Memory()));
    await tester.pumpAndSettle();

    await _send(tester, 'How is my weight going?');

    expect(find.text('Data summary · not an AI answer'), findsOneWidget);
    expect(find.textContaining('AI answer ·'), findsNothing);
    // The diagnostic sits with the evidence, as a small secondary line.
    await tester.tap(find.text('Evidence used and data gaps'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Beta diagnostic: provider_response_invalid · first attempt: '
        'evidence_code_not_permitted · repair: reasoning_step_too_long',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(repository.sent, [
      ('thread-1', 'How is my weight going?'),
      ('thread-1', 'How is my weight going?'),
    ]);
    expect(repository.created, 1);
    expect(find.text('Here is my full take.'), findsOneWidget);
    expect(find.text('AI answer · checked by Tracend'), findsOneWidget);
    expect(find.textContaining('deepseek'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a safety referral is a safety note without data-summary '
      'styling', (tester) async {
    await _tall(tester);
    final repository = _HistoryRepository(
      replies: [
        _summary(
          safetyState: 'limited',
          diagnostic: const CoachChatDiagnostic(
            failureCode: 'provider_timeout',
          ),
        ),
      ],
    );
    await tester.pumpWidget(_app(repository, _Memory()));
    await tester.pumpAndSettle();

    await _send(tester, 'I felt dizzy during my last set');

    expect(find.text('Safety note · not an AI answer'), findsOneWidget);
    expect(find.text('Data summary · not an AI answer'), findsNothing);
    expect(find.textContaining('AI answer ·'), findsNothing);
    expect(find.text('Evidence used and data gaps'), findsNothing);
    expect(find.text('Beta diagnostic: provider_timeout'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a stored data summary keeps its label; Retry only on the '
      'last message', (tester) async {
    await _tall(tester);
    final repository = _HistoryRepository(
      threads: [_thread('t1', 'Weight'), _thread('t2', 'Later')],
      messages: {
        't1': [
          _user('u1', 'How is my weight going?'),
          _summary(),
          _user('u2', 'And my training?'),
          _answer('a2', 'Training is on track.'),
        ],
        't2': [_user('u3', 'Plan for today?'), _summary()],
      },
      replies: [_answer('a3', 'Train as planned.')],
    );
    await tester.pumpWidget(_app(repository, _Memory('t1')));
    await tester.pumpAndSettle();

    expect(find.text('Data summary · not an AI answer'), findsOneWidget);
    expect(find.textContaining('Beta diagnostic'), findsNothing);
    expect(find.text('Retry'), findsNothing);

    await _openSheet(tester);
    await tester.tap(find.widgetWithText(TracendListRow, 'Later'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(repository.sent, [('t2', 'Plan for today?')]);
    expect(repository.created, 0);
  });

  testWidgets('a real failure is one inline message under the failed '
      'question, with the raw text as its second line, plus a toast', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _HistoryRepository(
      replies: [
        Exception(
          'FunctionException(status: 503, details: {code: provider_http_error})',
        ),
        _answer('a2', 'Back again.'),
      ],
    );
    await tester.pumpWidget(_app(repository, _Memory()));
    await tester.pumpAndSettle();

    await _send(tester, 'Hello');

    const raw =
        'FunctionException(status: 503, details: {code: provider_http_error})';
    final inline = find.byType(CoachTurnError);
    expect(inline, findsOneWidget);
    expect(
      find.descendant(
        of: inline,
        matching: find.text(
          'Coach couldn’t answer. Your approved plan is unchanged.',
        ),
      ),
      findsOneWidget,
    );
    expect(find.descendant(of: inline, matching: find.text(raw)), findsOne);
    // Under the question it failed to answer.
    expect(
      tester.getTopLeft(inline).dy,
      greaterThan(tester.getBottomLeft(find.text('Hello')).dy),
    );
    // The toast replaces the SnackBar; it is never the only copy.
    expect(find.text('Coach couldn’t answer'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(repository.threadLoads, 2);

    await tester.pumpAndSettle(TracendToast.visibleFor);
    expect(find.text('Coach couldn’t answer'), findsNothing);
    expect(inline, findsOneWidget);

    await tester.tap(find.descendant(of: inline, matching: find.text('Retry')));
    await tester.pumpAndSettle();
    expect(repository.sent.map((sent) => sent.$2), ['Hello', 'Hello']);
    expect(find.byType(CoachTurnError), findsNothing);
    expect(find.text('Back again.'), findsOneWidget);
  });

  testWidgets('a reply that arrives after switching conversations is not '
      'added to the new one', (tester) async {
    await _tall(tester);
    final late = Completer<CoachMessage>();
    final repository = _HistoryRepository(
      threads: [_thread('t1', 'First chat')],
      messages: {
        't1': [_user('u1', 'First question')],
      },
      replies: [late],
    );
    await tester.pumpWidget(_app(repository, _Memory()));
    await tester.pumpAndSettle();

    await _send(tester, 'A slow question');
    await _openSheet(tester);
    await tester.tap(find.text('New conversation'));
    await tester.pumpAndSettle();
    late.complete(_answer('late', 'A late answer'));
    await tester.pumpAndSettle();

    expect(find.text('A late answer'), findsNothing);
    expect(find.textContaining('Ask about training'), findsOneWidget);
  });

  testWidgets('a first send stays with its conversation when the user moves '
      'on while its thread is being created', (tester) async {
    await _tall(tester);
    final memory = _Memory();
    final creating = Completer<String>();
    final repository = _HistoryRepository(
      replies: [
        _answer('a1', 'Answer to the first question'),
        _answer('a2', 'Answer to the second question'),
      ],
    )..createGate = creating;
    await tester.pumpWidget(_app(repository, memory));
    await tester.pumpAndSettle();

    await _send(tester, 'First question');
    await _openSheet(tester);
    await tester.tap(find.text('New conversation'));
    await tester.pumpAndSettle();
    creating.complete('thread-1');
    await tester.pumpAndSettle();

    expect(find.text('Answer to the first question'), findsNothing);
    expect(find.textContaining('Ask about training'), findsOneWidget);
    expect(memory.remembered, isEmpty);

    await _send(tester, 'Second question');
    expect(repository.sent, [
      ('thread-1', 'First question'),
      ('thread-2', 'Second question'),
    ]);
    expect(find.text('Answer to the second question'), findsOneWidget);
    expect(memory.remembered, ['thread-2']);

    await _openSheet(tester);
    expect(
      find.widgetWithText(TracendListRow, 'First question'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TracendListRow, 'Second question'),
      findsOneWidget,
    );
  });

  testWidgets('a new conversation is listed as soon as its thread exists', (
    tester,
  ) async {
    await _tall(tester);
    final reply = Completer<CoachMessage>();
    final repository = _HistoryRepository(replies: [reply]);
    await tester.pumpWidget(_app(repository, _Memory()));
    await tester.pumpAndSettle();

    await _send(tester, 'How long until I reach 72 kg?');
    await _openSheet(tester);

    expect(
      find.widgetWithText(TracendListRow, 'How long until I reach 72 kg?'),
      findsOneWidget,
    );
    reply.complete(_answer('a1', 'About 18 weeks at your current trend.'));
    await tester.pumpAndSettle();
  });

  testWidgets('only the newest thread-list refresh updates the list', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _HistoryRepository(
      threads: [_thread('t1', 'Current title')],
      messages: {
        't1': [_user('u1', 'Hello')],
      },
      replies: [_answer('a1', 'One'), _answer('a2', 'Two')],
    );
    await tester.pumpWidget(_app(repository, _Memory()));
    await tester.pumpAndSettle();
    final older = Completer<List<CoachThread>>();
    final newer = Completer<List<CoachThread>>();
    repository.threadListGates.addAll([older, newer]);

    await _send(tester, 'First');
    await _send(tester, 'Second');
    newer.complete([_thread('t1', 'Newest title')]);
    await tester.pumpAndSettle();
    older.complete([_thread('t1', 'Stale title')]);
    await tester.pumpAndSettle();
    await _openSheet(tester);

    expect(find.widgetWithText(TracendListRow, 'Newest title'), findsOneWidget);
    expect(find.widgetWithText(TracendListRow, 'Stale title'), findsNothing);
  });

  testWidgets('a list requested before a new conversation existed does not '
      'remove it', (tester) async {
    await _tall(tester);
    final secondReply = Completer<CoachMessage>();
    final repository = _HistoryRepository(
      threads: [_thread('t1', 'First chat')],
      messages: {
        't1': [_user('u1', 'Hello')],
      },
      replies: [_answer('a1', 'One'), secondReply],
    );
    await tester.pumpWidget(_app(repository, _Memory('t1')));
    await tester.pumpAndSettle();
    final beforeNewThread = Completer<List<CoachThread>>();
    repository.threadListGates.add(beforeNewThread);

    await _send(tester, 'Follow-up in the first chat');
    await _openSheet(tester);
    await tester.tap(find.text('New conversation'));
    await tester.pumpAndSettle();
    await _send(tester, 'A brand new question');
    beforeNewThread.complete([_thread('t1', 'First chat')]);
    await tester.pumpAndSettle();
    await _openSheet(tester);

    expect(
      find.widgetWithText(TracendListRow, 'A brand new question'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TracendListRow, 'First chat'), findsOneWidget);
    secondReply.complete(_answer('a2', 'Two'));
    await tester.pumpAndSettle();
  });

  testWidgets('Retry keeps the message the user is typing', (tester) async {
    await _tall(tester);
    final repository = _HistoryRepository(
      replies: [_summary(), _answer('a2', 'Here is my full take.')],
    );
    await tester.pumpWidget(_app(repository, _Memory()));
    await tester.pumpAndSettle();

    await _send(tester, 'How is my weight going?');
    await tester.enterText(find.byType(TextField), 'My next question');
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(repository.sent.map((sent) => sent.$2), [
      'How is my weight going?',
      'How is my weight going?',
    ]);
    expect(find.text('My next question'), findsOneWidget);
  });

  testWidgets('the composer is disabled while a conversation loads', (
    tester,
  ) async {
    await _tall(tester);
    final loading = Completer<List<CoachMessage>>();
    final repository = _HistoryRepository(threads: [_thread('t1', 'First')]);
    repository.messageGates['t1'] = loading;
    await tester.pumpWidget(_app(repository, _Memory()));
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    loading.complete([_user('u1', 'First question')]);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  group('deleting a saved conversation', () {
    Future<_HistoryRepository> openSheet(WidgetTester tester) async {
      await _tall(tester);
      final repository = _HistoryRepository(
        threads: [_thread('t1', 'Open chat'), _thread('t2', 'Old chat')],
        messages: {
          't1': [_user('u1', 'Open question')],
          't2': [_user('u2', 'Old question')],
        },
      );
      await tester.pumpWidget(_app(repository, _Memory('t1')));
      await tester.pumpAndSettle();
      await _openSheet(tester);
      return repository;
    }

    Future<void> swipe(WidgetTester tester, String title) async {
      await tester.drag(
        find.widgetWithText(TracendListRow, title),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('asks first; Cancel keeps it', (tester) async {
      final repository = await openSheet(tester);

      await swipe(tester, 'Old chat');
      expect(find.text('Delete this conversation?'), findsOneWidget);
      expect(find.text('Delete conversation'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.deleted, isEmpty);
      expect(find.widgetWithText(TracendListRow, 'Old chat'), findsOneWidget);
    });

    testWidgets('Delete conversation removes it and says so', (tester) async {
      final repository = await openSheet(tester);

      await swipe(tester, 'Old chat');
      await tester.tap(find.text('Delete conversation'));
      await tester.pumpAndSettle();

      expect(repository.deleted, ['t2']);
      expect(find.widgetWithText(TracendListRow, 'Old chat'), findsNothing);
      expect(find.text('Conversation deleted'), findsOneWidget);
      // The open conversation is untouched.
      expect(find.text('Open question'), findsOneWidget);
      await tester.pumpAndSettle(TracendToast.visibleFor);
    });

    testWidgets('deleting the open conversation starts a new one', (
      tester,
    ) async {
      final repository = await openSheet(tester);

      await swipe(tester, 'Open chat');
      await tester.tap(find.text('Delete conversation'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(400, 40));
      await tester.pumpAndSettle();

      expect(repository.deleted, ['t1']);
      expect(find.text('Open question'), findsNothing);
      expect(find.textContaining('Ask about training'), findsOneWidget);
      await tester.pumpAndSettle(TracendToast.visibleFor);
    });

    testWidgets('a failed delete puts the conversation back', (tester) async {
      final repository = await openSheet(tester);
      repository.deleteError = Exception('network down');

      await swipe(tester, 'Old chat');
      await tester.tap(find.text('Delete conversation'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TracendListRow, 'Old chat'), findsOneWidget);
      expect(find.text('Couldn’t delete the conversation'), findsOneWidget);
      await tester.pumpAndSettle(TracendToast.visibleFor);
      await tester.tapAt(const Offset(400, 40));
      await tester.pumpAndSettle();
      expect(
        find.text('The conversation could not be deleted.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('while a reply is on its way the Coach is thinking, and the '
      'send plays the light haptic', (tester) async {
    await _tall(tester);
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    final reply = Completer<CoachMessage>();
    final repository = _HistoryRepository(replies: [reply]);
    await tester.pumpWidget(_app(repository, _Memory()));
    await tester.pumpAndSettle();

    await _send(tester, 'How was my week?');

    expect(haptics, ['HapticFeedbackType.lightImpact']);
    expect(find.text('Coach is thinking'), findsOneWidget);
    reply.complete(_answer('a1', 'A steady week.'));
    await tester.pumpAndSettle();
    expect(find.text('Coach is thinking'), findsNothing);
    expect(find.text('A steady week.'), findsOneWidget);
  });
}

class _Memory implements CoachThreadMemory {
  _Memory([this.stored]);

  String? stored;
  final remembered = <String>[];

  @override
  Future<String?> lastThreadId() async => stored;

  @override
  Future<void> remember(String threadId) async {
    remembered.add(threadId);
    stored = threadId;
  }
}

/// Behaves like the server: a sent question is saved when its turn starts, and
/// the first question names a new thread, so the list changes after a send.
class _HistoryRepository implements CoachRepository, CoachChatRepository {
  _HistoryRepository({
    List<CoachThread> threads = const [],
    Map<String, List<CoachMessage>> messages = const {},
    List<Object> replies = const [],
  }) : _threads = List.of(threads),
       _messages = messages,
       _replies = List.of(replies);

  final List<CoachThread> _threads;
  final Map<String, List<CoachMessage>> _messages;
  final List<Object> _replies;
  final sent = <(String, String)>[];
  int created = 0;
  int threadLoads = 0;

  /// When set, the next createThread waits for it.
  Completer<String>? createGate;

  /// Answered in order by the next loadThreads calls, before the live list.
  final threadListGates = <Completer<List<CoachThread>>>[];

  /// When set, loadMessages for this thread waits for it.
  final messageGates = <String, Completer<List<CoachMessage>>>{};

  @override
  Future<List<CoachThread>> loadThreads() {
    threadLoads++;
    if (threadListGates.isNotEmpty) return threadListGates.removeAt(0).future;
    return Future.value(List.of(_threads));
  }

  @override
  Future<String> createThread({bool remember = true}) {
    created++;
    final gate = createGate;
    createGate = null;
    return gate?.future ?? Future.value('thread-$created');
  }

  @override
  Future<List<CoachMessage>> loadMessages(String threadId) =>
      messageGates.remove(threadId)?.future ??
      Future.value(_messages[threadId] ?? const []);

  @override
  Future<CoachMessage> sendMessage(
    String threadId,
    String question, {
    String? idempotencyKey,
  }) {
    sent.add((threadId, question));
    if (!_threads.any((thread) => thread.id == threadId)) {
      _threads.insert(0, _thread(threadId, question));
    }
    final reply = _replies.removeAt(0);
    if (reply is Completer<CoachMessage>) return reply.future;
    if (reply is Exception) return Future.error(reply);
    return Future.value(reply as CoachMessage);
  }

  final deleted = <String>[];

  /// When set, deleteThread fails with it.
  Object? deleteError;

  @override
  Future<void> deleteThread(String threadId) async {
    if (deleteError case final error?) throw error;
    deleted.add(threadId);
    _threads.removeWhere((thread) => thread.id == threadId);
  }

  @override
  Future<CoachDecision?> loadLatest() async => null;

  @override
  Future<CoachDecision> generate({String? localDate}) =>
      throw StateError('not needed');

  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
}
