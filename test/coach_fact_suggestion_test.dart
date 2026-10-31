import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/coach/memory/coach_memory.dart';
import 'package:tracend/features/coach/memory/coach_memory_repository.dart';
import 'package:tracend/features/coach/memory/fact_suggestion.dart';
import 'package:tracend/features/coach/widgets/fact_suggestion_chip.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

final _when = DateTime(2026, 10, 18);

Map<String, dynamic> _wire({
  String action = 'add',
  String kind = 'food_dislike',
  String subject = 'mushrooms',
  String statement = 'Dislikes mushrooms',
  String? factId,
  String? previous,
  String reason = 'You said this in your message.',
}) => {
  'action': action,
  'kind': kind,
  'subject': subject,
  'statement': statement,
  'fact_id': factId,
  'previous': previous,
  'reason': reason,
  'origin': 'athlete_statement',
};

class _Chat implements CoachRepository, CoachChatRepository, CoachRawResponses {
  _Chat(this.suggestions);

  final List<Map<String, dynamic>> suggestions;

  @override
  Future<List<CoachThread>> loadThreads() async => const [];

  @override
  Future<String> createThread({bool remember = true}) async => 't1';

  @override
  Future<List<CoachMessage>> loadMessages(String threadId) async => const [];

  @override
  Future<CoachMessage> sendMessage(
    String threadId,
    String question, {
    String? idempotencyKey,
  }) async => CoachMessage(
    id: 'a',
    role: 'assistant',
    content: 'Noted.',
    createdAt: _when,
  );

  @override
  Future<Map<String, dynamic>?> loadLastRawResponse() async => {
    'fact_suggestions': suggestions,
  };

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

class _Memory implements CoachMemoryRepository {
  final calls = <String>[];
  Object? failure;

  @override
  Future<CoachMemory> load() async => const CoachMemory();

  @override
  Future<CoachFact> saveFact({
    required CoachFactKind kind,
    required String subject,
    required String statement,
    CoachFactSource source = CoachFactSource.athleteTyped,
    String? supersedes,
  }) async {
    calls.add(
      'save ${kind.wire} | $subject | $statement | ${source.wire} | ${supersedes ?? '-'}',
    );
    if (failure != null) throw failure!;
    return CoachFact(
      id: 'new',
      lineageId: 'new',
      version: 1,
      kind: kind,
      subject: subject,
      statement: statement,
      source: source,
      confirmedAt: _when,
    );
  }

  @override
  Future<CoachFact> reconfirmFact(String factId) async {
    calls.add('reconfirm $factId');
    if (failure != null) throw failure!;
    return CoachFact(
      id: factId,
      lineageId: factId,
      version: 2,
      kind: CoachFactKind.injuryLimitation,
      subject: 'left knee',
      statement: 'Left knee pain',
      source: CoachFactSource.athleteTyped,
      confirmedAt: _when,
    );
  }

  @override
  Future<void> deleteFact(String factId) async {
    calls.add('delete $factId');
    if (failure != null) throw failure!;
  }

  @override
  Future<void> deleteNote(String noteId) async {}

  @override
  Future<void> forgetAll() async {}
}

class _LastThread implements CoachThreadMemory {
  const _LastThread();

  @override
  Future<String?> lastThreadId() async => null;

  @override
  Future<void> remember(String threadId) async {}
}

Future<void> _ask(
  WidgetTester tester,
  List<Map<String, dynamic>> suggestions,
  _Memory memory,
) async {
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
          repository: _Chat(suggestions),
          threadMemory: const _LastThread(),
          memory: memory,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'I hate mushrooms');
  await tester.tap(find.byTooltip('Send message'));
  await tester.pumpAndSettle();
}

void main() {
  group('a suggestion in the response', () {
    test('is read key for key, and an unreadable one is skipped', () {
      final read = CoachFactSuggestion.listFromResponse({
        'fact_suggestions': [
          _wire(),
          _wire(action: 'update', factId: 'f1', previous: 'Likes pizza'),
          _wire(action: 'update'),
          _wire(kind: 'medication'),
          _wire(action: 'delete'),
          {'action': 'add'},
          'text',
        ],
      });
      expect(read.map((item) => item.action), [
        CoachFactSuggestionAction.add,
        CoachFactSuggestionAction.update,
      ]);
      expect(read.last.factId, 'f1');
      expect(read.last.previous, 'Likes pizza');
      expect(read.first.kind, CoachFactKind.foodDislike);
      expect(CoachFactSuggestion.listFromResponse(null), isEmpty);
      expect(CoachFactSuggestion.listFromResponse({}), isEmpty);
    });
  });

  group('the suggestion card', () {
    Future<void> show(
      WidgetTester tester,
      Map<String, dynamic> wire, {
      VoidCallback? onConfirm,
      VoidCallback? onDismiss,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: FactSuggestionChip(
            suggestion: CoachFactSuggestion.tryFromJson(wire)!,
            onConfirm: onConfirm ?? () {},
            onDismiss: onDismiss ?? () {},
          ),
        ),
      ),
    );

    testWidgets('an add shows the words that would be saved and why', (
      tester,
    ) async {
      await show(tester, _wire());
      expect(find.text('Remember this?'), findsOneWidget);
      expect(find.text('“Dislikes mushrooms”'), findsOneWidget);
      expect(find.text('You said this in your message.'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
    });

    testWidgets('an update shows the saved words and the new ones', (
      tester,
    ) async {
      await show(
        tester,
        _wire(
          action: 'update',
          kind: 'food_like',
          statement: 'Likes mushrooms',
          factId: 'f1',
          previous: 'Dislikes mushrooms',
          reason: 'This differs from what you confirmed on 2026-09-02.',
        ),
      );
      expect(find.text('Update what Coach remembers?'), findsOneWidget);
      expect(find.text('Saved: “Dislikes mushrooms”'), findsOneWidget);
      expect(find.text('“Likes mushrooms”'), findsOneWidget);
    });

    testWidgets('a resolve names what would be forgotten', (tester) async {
      await show(
        tester,
        _wire(
          action: 'resolve',
          kind: 'injury_limitation',
          statement: 'Left knee pain',
          factId: 'f1',
          previous: 'Left knee pain',
        ),
      );
      expect(find.text('Forget this?'), findsOneWidget);
      expect(find.text('“Left knee pain”'), findsOneWidget);
    });

    testWidgets('a still-true card names the saved words and asks', (
      tester,
    ) async {
      await show(
        tester,
        _wire(
          action: 'reconfirm',
          kind: 'injury_limitation',
          statement: 'Left knee pain',
          factId: 'f1',
          previous: 'Left knee pain',
          reason:
              'You confirmed “Left knee pain” on 2026-09-02. Is it still true?',
        ),
      );
      expect(find.text('Still true?'), findsOneWidget);
      expect(find.text('“Left knee pain”'), findsOneWidget);
      expect(find.textContaining('Is it still true?'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
    });

    testWidgets('a review offers nothing to save, only OK', (tester) async {
      await show(
        tester,
        _wire(
          action: 'review',
          kind: 'allergy',
          statement: 'Allergy or intolerance: peanuts',
          factId: 'f1',
          previous: 'Allergy or intolerance: peanuts',
        ),
      );
      expect(find.text('Check what Coach remembers'), findsOneWidget);
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('while saving, both buttons are off', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: FactSuggestionChip(
              suggestion: CoachFactSuggestion.tryFromJson(_wire())!,
              busy: true,
              onConfirm: () {},
              onDismiss: () {},
            ),
          ),
        ),
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
    });
  });

  group('under the reply', () {
    testWidgets(
      'nothing is saved until Confirm, then it is saved as Coach suggested',
      (tester) async {
        final memory = _Memory();
        await _ask(tester, [_wire()], memory);
        expect(find.text('Remember this?'), findsOneWidget);
        expect(memory.calls, isEmpty);
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(memory.calls, [
          'save food_dislike | mushrooms | Dislikes mushrooms | coach_suggestion_confirmed | -',
        ]);
        expect(find.text('Remember this?'), findsNothing);
        await tester.pumpAndSettle(TracendToast.visibleFor);
      },
    );

    testWidgets('dismissing saves nothing', (tester) async {
      final memory = _Memory();
      await _ask(tester, [_wire()], memory);
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(memory.calls, isEmpty);
      expect(find.text('Remember this?'), findsNothing);
    });

    testWidgets('an update replaces the fact it names', (tester) async {
      final memory = _Memory();
      await _ask(tester, [
        _wire(
          action: 'update',
          kind: 'food_like',
          statement: 'Likes mushrooms',
          factId: 'f1',
          previous: 'Dislikes mushrooms',
        ),
      ], memory);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(memory.calls, [
        'save food_like | mushrooms | Likes mushrooms | coach_suggestion_confirmed | f1',
      ]);
      await tester.pumpAndSettle(TracendToast.visibleFor);
    });

    testWidgets('a resolve deletes the fact it names', (tester) async {
      final memory = _Memory();
      await _ask(tester, [
        _wire(
          action: 'resolve',
          kind: 'injury_limitation',
          statement: 'Left knee pain',
          factId: 'f9',
          previous: 'Left knee pain',
        ),
      ], memory);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(memory.calls, ['delete f9']);
      await tester.pumpAndSettle(TracendToast.visibleFor);
    });

    testWidgets(
      'a still-true card confirms the fact again, saving no new words',
      (tester) async {
        final memory = _Memory();
        await _ask(tester, [
          _wire(
            action: 'reconfirm',
            kind: 'injury_limitation',
            statement: 'Left knee pain',
            factId: 'f7',
            previous: 'Left knee pain',
          ),
        ], memory);
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(memory.calls, ['reconfirm f7']);
        expect(find.text('Still true?'), findsNothing);
        await tester.pumpAndSettle(TracendToast.visibleFor);
      },
    );

    testWidgets('a failed save keeps the card and says nothing was changed', (
      tester,
    ) async {
      final memory = _Memory()..failure = Exception('offline');
      await _ask(tester, [_wire()], memory);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(
        find.text('It could not be saved. Nothing was changed.'),
        findsOneWidget,
      );
      expect(find.text('Remember this?'), findsOneWidget);
    });

    testWidgets('a reply without suggestions shows no card', (tester) async {
      await _ask(tester, const [], _Memory());
      expect(find.byType(FactSuggestionChip), findsNothing);
    });
  });
}
