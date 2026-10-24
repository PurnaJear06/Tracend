import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/widgets/coach_message_bubble.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';

final _when = DateTime(2026, 10, 24, 9);

CoachThread _thread(String id, String title) =>
    CoachThread(id: id, title: title, updatedAt: _when);

CoachMessage _user(String id, String text) =>
    CoachMessage(id: id, role: 'user', content: text, createdAt: _when);

CoachMessage _answer(
  String id,
  String text, {
  List<String> followUps = const [],
}) => CoachMessage(
  id: id,
  role: 'assistant',
  content: text,
  createdAt: _when,
  answerSource: 'model',
  suggestedFollowUps: followUps,
);

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

class _Repository implements CoachRepository, CoachChatRepository {
  _Repository({
    this.threads = const [],
    this.messages = const {},
    this.replies = const [],
  });

  final List<CoachThread> threads;
  final Map<String, List<CoachMessage>> messages;
  final List<Object> replies;
  final sent = <(String, String)>[];
  int created = 0;

  /// A thread's load waits for its gate.
  final gates = <String, Completer<List<CoachMessage>>>{};

  @override
  Future<List<CoachThread>> loadThreads() async => List.of(threads);

  @override
  Future<String> createThread({bool remember = true}) async =>
      'created-${++created}';

  @override
  Future<List<CoachMessage>> loadMessages(String threadId) =>
      gates.remove(threadId)?.future ??
      Future.value(messages[threadId] ?? const []);

  @override
  Future<CoachMessage> sendMessage(
    String threadId,
    String question, {
    String? idempotencyKey,
  }) {
    sent.add((threadId, question));
    final reply = replies.removeAt(0);
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

Future<void> _show(
  WidgetTester tester,
  _Repository repository,
  _Memory memory, {
  Duration age = const Duration(hours: 1),
  AiCoachingConsentController? consent,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
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
          repository: repository,
          threadMemory: memory,
          now: () => _when.add(age),
          aiConsent: consent,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Saved conversations'));
  await tester.pumpAndSettle();
}

/// Picks a saved conversation from the sheet without waiting for it to load.
Future<void> _pick(WidgetTester tester, String title) async {
  await _openSheet(tester);
  await tester.tap(find.text(title));
  await tester.pump();
  await tester.pump();
}

Future<void> _send(WidgetTester tester, String question) async {
  await tester.enterText(find.byType(TextField), question);
  await tester.tap(find.byTooltip('Send message'));
  await tester.pump();
}

_Repository _threeChats() => _Repository(
  threads: [
    _thread('a', 'Chat A'),
    _thread('b', 'Chat B'),
    _thread('c', 'Chat C'),
  ],
  messages: {
    'a': [_user('a1', 'Question in A'), _answer('a2', 'Answer in A')],
    'b': [_user('b1', 'Question in B'), _answer('b2', 'Answer in B')],
    'c': [_user('c1', 'Question in C'), _answer('c2', 'Answer in C')],
  },
  replies: [_answer('r', 'Reply')],
);

void main() {
  group('switching conversations', () {
    testWidgets('B then C quickly: C shows its own messages and the next '
        'send goes to C, whichever load finishes last', (tester) async {
      final repository = _threeChats();
      final b = repository.gates['b'] = Completer();
      final c = repository.gates['c'] = Completer();
      await _show(tester, repository, _Memory('a'));

      await _pick(tester, 'Chat B');
      await _pick(tester, 'Chat C');
      c.complete(repository.messages['c']!);
      await tester.pumpAndSettle();
      b.complete(repository.messages['b']!);
      await tester.pumpAndSettle();

      expect(find.text('Answer in C'), findsOneWidget);
      expect(find.text('Answer in B'), findsNothing);
      expect(find.text('Answer in A'), findsNothing);
      await _send(tester, 'Hello');
      expect(repository.sent, [('c', 'Hello')]);
    });

    testWidgets('B then C: B finishing first is dropped and C stays '
        'loading', (tester) async {
      final repository = _threeChats();
      final b = repository.gates['b'] = Completer();
      final c = repository.gates['c'] = Completer();
      await _show(tester, repository, _Memory('a'));

      await _pick(tester, 'Chat B');
      await _pick(tester, 'Chat C');
      b.complete(repository.messages['b']!);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Answer in B'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      c.complete(repository.messages['c']!);
      await tester.pumpAndSettle();

      expect(find.text('Answer in C'), findsOneWidget);
      expect(find.text('Answer in B'), findsNothing);
    });

    testWidgets('tapping B then New conversation before B loads shows an '
        'empty new chat, not B', (tester) async {
      final repository = _threeChats();
      final b = repository.gates['b'] = Completer();
      await _show(tester, repository, _Memory('a'));

      await _pick(tester, 'Chat B');
      await _openSheet(tester);
      await tester.tap(find.text('New conversation'));
      await tester.pumpAndSettle();
      b.complete(repository.messages['b']!);
      await tester.pumpAndSettle();

      expect(find.text('Answer in B'), findsNothing);
      expect(find.textContaining('Ask about training'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      await _send(tester, 'Fresh question');
      await tester.pumpAndSettle();
      expect(repository.sent, [('created-1', 'Fresh question')]);
    });

    testWidgets('opening a chat that cannot load puts the open chat back, '
        'with its messages and its thread', (tester) async {
      final repository = _threeChats();
      final memory = _Memory('a');
      repository.gates['b'] = Completer()
        ..future.ignore()
        ..completeError(Exception('offline'));
      await _show(tester, repository, memory);

      await _pick(tester, 'Chat B');
      await tester.pumpAndSettle();

      expect(find.text('Conversation could not be opened.'), findsOneWidget);
      expect(find.text('Answer in A'), findsOneWidget);
      expect(find.text('Answer in B'), findsNothing);
      expect(memory.remembered, isEmpty);
      await _send(tester, 'Still here?');
      expect(repository.sent, [('a', 'Still here?')]);
      await tester.pumpAndSettle();
      await _openSheet(tester);
      expect(find.textContaining('Open now'), findsOneWidget);
    });

    testWidgets('a failed open from a new chat goes back to the new chat', (
      tester,
    ) async {
      final repository = _threeChats();
      repository.gates['b'] = Completer()
        ..future.ignore()
        ..completeError(Exception('offline'));
      await _show(
        tester,
        repository,
        _Memory('a'),
        age: const Duration(hours: 7),
      );
      expect(find.textContaining('Ask about training'), findsOneWidget);

      await _pick(tester, 'Chat B');
      await tester.pumpAndSettle();

      expect(find.text('Conversation could not be opened.'), findsOneWidget);
      expect(find.textContaining('Ask about training'), findsOneWidget);
      expect(find.text('Answer in B'), findsNothing);
      expect(find.text('Continue last chat'), findsOneWidget);
    });

    testWidgets('B failing while C loads, then C failing, restores the chat '
        'that was open', (tester) async {
      final repository = _threeChats();
      final b = repository.gates['b'] = Completer();
      final c = repository.gates['c'] = Completer();
      await _show(tester, repository, _Memory('a'));

      await _pick(tester, 'Chat B');
      await _pick(tester, 'Chat C');
      b.future.ignore();
      c.future.ignore();
      b.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Conversation could not be opened.'), findsNothing);
      c.completeError(Exception('offline'));
      await tester.pumpAndSettle();

      expect(find.text('Conversation could not be opened.'), findsOneWidget);
      expect(find.text('Answer in A'), findsOneWidget);
    });

    testWidgets('a saved chat cannot be opened while a reply is on its way, '
        'and the reply lands in the new chat that sent it', (tester) async {
      final late = Completer<CoachMessage>();
      final repository = _threeChats();
      repository.replies
        ..clear()
        ..addAll([late, _answer('r2', 'Second answer')]);
      repository.gates['b'] = Completer()
        ..future.ignore()
        ..completeError(Exception('offline'));
      await _show(
        tester,
        repository,
        _Memory('a'),
        age: const Duration(hours: 7),
      );

      await _send(tester, 'A slow one');
      await _pick(tester, 'Chat B');
      await tester.pump();

      expect(
        find.textContaining('Coach is still answering'),
        findsOneWidget,
        reason: 'the switch is held with a note',
      );
      expect(repository.gates, contains('b'), reason: 'B was never loaded');
      late.complete(_answer('late', 'The slow answer'));
      await tester.pumpAndSettle();

      expect(find.text('The slow answer'), findsOneWidget);
      await _send(tester, 'And another');
      await tester.pumpAndSettle();
      expect(repository.created, 1, reason: 'one thread, not a second one');
      expect(repository.sent, [
        ('created-1', 'A slow one'),
        ('created-1', 'And another'),
      ]);
    });

    testWidgets('a failed reply is not lost to a switch that was held', (
      tester,
    ) async {
      final late = Completer<CoachMessage>();
      final repository = _threeChats();
      repository.replies
        ..clear()
        ..add(late);
      await _show(tester, repository, _Memory('a'));

      await _send(tester, 'A slow one');
      await _pick(tester, 'Chat B');
      late.completeError(Exception('boom'));
      await tester.pumpAndSettle();

      expect(find.byType(CoachTurnError), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Answer in A'), findsOneWidget);
    });
  });

  group('New conversation on a new chat', () {
    testWidgets('keeps offering the chat the fresh view replaced', (
      tester,
    ) async {
      final repository = _Repository(
        threads: [_thread('t-new', 'Meal ideas'), _thread('t-old', 'A break')],
      );
      await _show(
        tester,
        repository,
        _Memory('t-old'),
        age: const Duration(days: 6),
      );
      expect(find.text('A break'), findsOneWidget);

      await _openSheet(tester);
      await tester.tap(find.text('New conversation'));
      await tester.pumpAndSettle();

      expect(find.text('Continue last chat'), findsOneWidget);
      expect(find.text('A break'), findsOneWidget);
      expect(find.text('Meal ideas'), findsNothing);
    });
  });

  group('a follow-up while Coach is busy', () {
    _Repository chatWithChip(List<Object> replies) => _Repository(
      threads: [_thread('a', 'Chat A')],
      messages: {
        'a': [
          _user('a1', 'Question in A'),
          _answer('a2', 'Answer in A', followUps: ['Plan my meals']),
        ],
      },
      replies: replies,
    );

    testWidgets('waits, is shown, and sends when the reply arrives', (
      tester,
    ) async {
      final slow = Completer<CoachMessage>();
      final repository = chatWithChip([slow, _answer('r2', 'Meal plan')]);
      await _show(tester, repository, _Memory('a'));

      await _send(tester, 'How is my week?');
      await tester.tap(find.text('Plan my meals'));
      await tester.pump();

      expect(repository.sent, [('a', 'How is my week?')]);
      expect(
        find.text('Sends when Coach is ready: Plan my meals'),
        findsOneWidget,
      );
      slow.complete(_answer('r1', 'A steady week.'));
      await tester.pumpAndSettle();

      expect(repository.sent, [
        ('a', 'How is my week?'),
        ('a', 'Plan my meals'),
      ]);
      expect(find.textContaining('Sends when Coach is ready'), findsNothing);
      expect(find.text('Meal plan'), findsOneWidget);
    });

    testWidgets('Cancel removes it', (tester) async {
      final slow = Completer<CoachMessage>();
      final repository = chatWithChip([slow]);
      await _show(tester, repository, _Memory('a'));

      await _send(tester, 'How is my week?');
      await tester.tap(find.text('Plan my meals'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      slow.complete(_answer('r1', 'A steady week.'));
      await tester.pumpAndSettle();

      expect(repository.sent, [('a', 'How is my week?')]);
      expect(find.textContaining('Sends when Coach is ready'), findsNothing);
    });

    testWidgets('lands in the composer when the reply it waited for failed', (
      tester,
    ) async {
      final slow = Completer<CoachMessage>();
      final repository = chatWithChip([slow]);
      await _show(tester, repository, _Memory('a'));

      await _send(tester, 'How is my week?');
      await tester.tap(find.text('Plan my meals'));
      await tester.pump();
      slow.completeError(Exception('boom'));
      await tester.pumpAndSettle();

      expect(repository.sent, [('a', 'How is my week?')]);
      expect(find.textContaining('Sends when Coach is ready'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Plan my meals',
      );
    });

    testWidgets('Cancel puts the text in the composer', (tester) async {
      final slow = Completer<CoachMessage>();
      final repository = chatWithChip([slow]);
      await _show(tester, repository, _Memory('a'));

      await _send(tester, 'How is my week?');
      await tester.tap(find.text('Plan my meals'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Plan my meals',
      );
      slow.complete(_answer('r1', 'A steady week.'));
      await tester.pumpAndSettle();
      expect(repository.sent, [('a', 'How is my week?')]);
    });

    testWidgets('a newer follow-up moves the one it replaces to the '
        'composer', (tester) async {
      final slow = Completer<CoachMessage>();
      final repository = _Repository(
        threads: [_thread('a', 'Chat A')],
        messages: {
          'a': [
            _user('a1', 'Question in A'),
            _answer(
              'a2',
              'Answer in A',
              followUps: ['Plan my meals', 'Review my sleep'],
            ),
          ],
        },
        replies: [slow],
      );
      await _show(tester, repository, _Memory('a'));

      await _send(tester, 'How is my week?');
      await tester.tap(find.text('Plan my meals'));
      await tester.pump();
      await tester.tap(find.text('Review my sleep'));
      await tester.pump();

      expect(
        find.text('Sends when Coach is ready: Review my sleep'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Plan my meals',
      );
    });

    testWidgets('New conversation moves the waiting text to the composer', (
      tester,
    ) async {
      final slow = Completer<CoachMessage>();
      final repository = chatWithChip([slow]);
      await _show(tester, repository, _Memory('a'));

      await _send(tester, 'How is my week?');
      await tester.tap(find.text('Plan my meals'));
      await tester.pump();
      await _openSheet(tester);
      await tester.tap(find.text('New conversation'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sends when Coach is ready'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Plan my meals',
      );
      slow.complete(_answer('r1', 'A steady week.'));
      await tester.pumpAndSettle();
    });

    testWidgets('opening another chat during the cooldown moves the waiting '
        'text to the composer', (tester) async {
      final repository = _Repository(
        threads: [_thread('a', 'Chat A'), _thread('b', 'Chat B')],
        messages: {
          'a': [
            _user('a1', 'Question in A'),
            _answer('a2', 'Answer in A', followUps: ['Plan my meals']),
          ],
          'b': [_user('b1', 'Question in B')],
        },
        replies: [
          const CoachUnavailableException('Slow down.', retryAfterSeconds: 5),
        ],
      );
      await _show(tester, repository, _Memory('a'));

      await _send(tester, 'How is my week?');
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Plan my meals'));
      await tester.pump();
      await _pick(tester, 'Chat B');
      await tester.pumpAndSettle();

      expect(find.text('Question in B'), findsOneWidget);
      expect(find.textContaining('Sends when Coach is ready'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Plan my meals',
      );
    });

    testWidgets('with AI coaching off by then, the text stays in the composer '
        'and no consent sheet opens', (tester) async {
      final slow = Completer<CoachMessage>();
      final repository = chatWithChip([slow]);
      final consent = AiCoachingConsentController(
        FixtureAiCoachingConsentRepository(AiCoachingChoice.granted),
        initial: AiCoachingChoice.granted,
      );
      await _show(tester, repository, _Memory('a'), consent: consent);

      await _send(tester, 'How is my week?');
      await tester.tap(find.text('Plan my meals'));
      await tester.pump();
      await consent.record(granted: false);
      slow.complete(_answer('r1', 'A steady week.'));
      await tester.pumpAndSettle();

      expect(repository.sent, [('a', 'How is my week?')]);
      expect(find.text('Allow AI coaching'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Plan my meals',
      );
    });

    testWidgets('respects the cooldown after a rate-limited reply', (
      tester,
    ) async {
      final repository = chatWithChip([
        const CoachUnavailableException('Slow down.', retryAfterSeconds: 2),
        _answer('r2', 'Meal plan'),
      ]);
      await _show(tester, repository, _Memory('a'));

      await _send(tester, 'How is my week?');
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Plan my meals'));
      await tester.pump();

      expect(repository.sent, [('a', 'How is my week?')]);
      expect(find.textContaining('Sends when Coach is ready'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(repository.sent.last, ('a', 'Plan my meals'));
    });
  });
}
