import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';

final _when = DateTime(2026, 10, 18);

class _Chat implements CoachRepository, CoachChatRepository {
  _Chat([this.threads = const []]);

  final List<CoachThread> threads;
  final created = <bool>[];

  @override
  Future<List<CoachThread>> loadThreads() async => threads;

  @override
  Future<String> createThread({bool remember = true}) async {
    created.add(remember);
    return 'new-thread';
  }

  @override
  Future<List<CoachMessage>> loadMessages(String threadId) async => [
    CoachMessage(id: 'u', role: 'user', content: 'Hi', createdAt: _when),
  ];

  @override
  Future<CoachMessage> sendMessage(
    String threadId,
    String question, {
    String? idempotencyKey,
  }) async => CoachMessage(
    id: 'a',
    role: 'assistant',
    content: 'Hello.',
    createdAt: _when,
  );

  @override
  Future<void> deleteThread(String threadId) async {}

  @override
  Future<CoachDecision?> loadLatest() async => null;

  @override
  Future<CoachDecision> generate() => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> loadUsage() async => {};
}

class _LastThread implements CoachThreadMemory {
  const _LastThread(this.id);
  final String? id;

  @override
  Future<String?> lastThreadId() async => id;

  @override
  Future<void> remember(String threadId) async {}
}

Future<void> _open(WidgetTester tester, _Chat chat, {String? last}) async {
  tester.view.physicalSize = const Size(800, 2800);
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
          threadMemory: _LastThread(last),
          now: () => _when.add(const Duration(hours: 1)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'Hello');
  await tester.tap(find.byTooltip('Send message'));
  await tester.pumpAndSettle();
}

const _notice =
    'This chat isn’t remembered. Coach saves no notes or facts from it, and '
    'other chats can’t see it.';

void main() {
  testWidgets('a new conversation offers "Don\'t remember this chat", off', (
    tester,
  ) async {
    await _open(tester, _Chat());
    expect(find.text('Don’t remember this chat'), findsOneWidget);
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
      isFalse,
    );
    expect(find.text(_notice), findsNothing);
  });

  testWidgets('left off, the conversation is created remembered', (
    tester,
  ) async {
    final chat = _Chat();
    await _open(tester, chat);
    await _send(tester);
    expect(chat.created, [true]);
    expect(find.text(_notice), findsNothing);
    expect(find.text('Don’t remember this chat'), findsNothing);
  });

  testWidgets(
    'turned on, the conversation is created not remembered and says so',
    (tester) async {
      final chat = _Chat();
      await _open(tester, chat);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pump();
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
        isTrue,
      );
      await _send(tester);
      expect(chat.created, [false]);
      expect(find.text(_notice), findsOneWidget);
      // The choice is made before the first message and cannot change after.
      expect(find.byType(CupertinoSwitch), findsNothing);
    },
  );

  testWidgets('the saved conversations mark the ones that are not remembered', (
    tester,
  ) async {
    final chat = _Chat([
      CoachThread(id: 't1', title: 'Remembered chat', updatedAt: _when),
      CoachThread(
        id: 't2',
        title: 'Private chat',
        updatedAt: _when,
        remember: false,
      ),
    ]);
    await _open(tester, chat, last: 't1');
    expect(find.text(_notice), findsNothing);
    await tester.tap(find.byTooltip('Saved conversations'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not remembered'), findsOneWidget);
    await tester.tap(find.text('Private chat'));
    await tester.pumpAndSettle();
    expect(find.text(_notice), findsOneWidget);
  });

  testWidgets(
    'reopening a conversation that is not remembered shows the notice',
    (tester) async {
      final chat = _Chat([
        CoachThread(
          id: 't2',
          title: 'Private chat',
          updatedAt: _when,
          remember: false,
        ),
      ]);
      await _open(tester, chat, last: 't2');
      expect(find.text(_notice), findsOneWidget);
    },
  );

  testWidgets('a new conversation after a private one is remembered again', (
    tester,
  ) async {
    final chat = _Chat();
    await _open(tester, chat);
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pump();
    await _send(tester);
    await tester.tap(find.byTooltip('Saved conversations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New conversation'));
    await tester.pumpAndSettle();
    expect(find.text(_notice), findsNothing);
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
      isFalse,
    );
  });

  test('a thread without the key reads as remembered', () {
    final thread = CoachThread.fromJson({
      'id': 't',
      'title': 'x',
      'updated_at': '2026-10-18T00:00:00+00:00',
    });
    expect(thread.remember, isTrue);
    expect(
      CoachThread.fromJson({
        'id': 't',
        'title': 'x',
        'updated_at': '2026-10-18T00:00:00+00:00',
        'remember': false,
      }).remember,
      isFalse,
    );
  });
}
