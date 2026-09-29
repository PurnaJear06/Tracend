import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

Widget _app(CoachRepository repository, CoachThreadMemory memory) =>
    MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: CoachScreen(repository: repository, threadMemory: memory),
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
      find.widgetWithText(ListTile, 'How long until I reach 72 kg?'),
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
    await tester.tap(find.text('New'));
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
    expect(
      find.text(
        'Beta diagnostic: provider_response_invalid · first attempt: '
        'evidence_code_not_permitted · repair: reasoning_step_too_long',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('AI response'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(repository.sent, [
      ('thread-1', 'How is my weight going?'),
      ('thread-1', 'How is my weight going?'),
    ]);
    expect(repository.created, 1);
    expect(find.text('Here is my full take.'), findsOneWidget);
    expect(find.text('deepseek AI response'), findsOneWidget);
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
    await tester.tap(find.widgetWithText(ListTile, 'Later'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(repository.sent, [('t2', 'Plan for today?')]);
    expect(repository.created, 0);
  });

  testWidgets('a real failure keeps the raw error text and still refreshes '
      'the list', (tester) async {
    await _tall(tester);
    final repository = _HistoryRepository(
      replies: [
        Exception(
          'FunctionException(status: 503, details: {code: provider_http_error})',
        ),
      ],
    );
    await tester.pumpWidget(_app(repository, _Memory()));
    await tester.pumpAndSettle();

    await _send(tester, 'Hello');

    const raw =
        'FunctionException(status: 503, details: {code: provider_http_error})';
    expect(find.widgetWithText(SnackBar, raw), findsOneWidget);
    expect(find.widgetWithText(TracendCard, raw), findsOneWidget);
    expect(repository.threadLoads, 2);
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
    await tester.tap(find.text('New'));
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
    await tester.tap(find.text('New'));
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
    expect(find.widgetWithText(ListTile, 'First question'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Second question'), findsOneWidget);
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
      find.widgetWithText(ListTile, 'How long until I reach 72 kg?'),
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

    expect(find.widgetWithText(ListTile, 'Newest title'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Stale title'), findsNothing);
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
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await _send(tester, 'A brand new question');
    beforeNewThread.complete([_thread('t1', 'First chat')]);
    await tester.pumpAndSettle();
    await _openSheet(tester);

    expect(
      find.widgetWithText(ListTile, 'A brand new question'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ListTile, 'First chat'), findsOneWidget);
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
  Future<String> createThread() {
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
  Future<CoachMessage> sendMessage(String threadId, String question) {
    sent.add((threadId, question));
    if (!_threads.any((thread) => thread.id == threadId)) {
      _threads.insert(0, _thread(threadId, question));
    }
    final reply = _replies.removeAt(0);
    if (reply is Completer<CoachMessage>) return reply.future;
    if (reply is Exception) return Future.error(reply);
    return Future.value(reply as CoachMessage);
  }

  @override
  Future<void> deleteThread(String threadId) async {}

  @override
  Future<CoachDecision?> loadLatest() async => null;

  @override
  Future<CoachDecision> generate() => throw StateError('not needed');

  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
}
