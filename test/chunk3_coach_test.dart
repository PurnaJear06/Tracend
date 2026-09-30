import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';

Widget _app(CoachRepository repository) => MaterialApp(
  theme: TracendTheme.dark,
  home: Scaffold(body: CoachScreen(repository: repository)),
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

void main() {
  testWidgets('coaching context uses the evidence accordion', (tester) async {
    await tester.pumpWidget(_app(_ChatRepository()));
    await tester.pumpAndSettle();
    expect(find.text('Your coaching context'), findsOneWidget);
    expect(
      find.text('7 of 8 sources available · 1 needs data'),
      findsOneWidget,
    );
    // Collapsed by default: source rows are not mounted yet.
    expect(find.text('Apple Health summaries'), findsNothing);
    await tester.tap(find.text('Your coaching context'));
    await tester.pumpAndSettle();
    expect(find.text('Apple Health summaries'), findsOneWidget);
    expect(find.textContaining('latest 2026-07-10'), findsOneWidget);
  });

  testWidgets('an ongoing conversation has no pinned cards above it', (
    tester,
  ) async {
    await _tall(tester);
    await tester.pumpWidget(_app(_ChatRepository()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Explain today');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    // Today's decision lives on Today; what the Coach can see shows only on
    // a new conversation.
    expect(find.text('HEAD COACH'), findsNothing);
    expect(find.text('No daily decision yet'), findsNothing);
    expect(find.text('Your coaching context'), findsNothing);
    expect(find.text('Your approved plan remains available.'), findsOneWidget);
  });

  testWidgets('message evidence accordion expands to real evidence', (
    tester,
  ) async {
    await _tall(tester);
    await tester.pumpWidget(_app(_ChatRepository()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Explain today');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(find.text('Evidence used and data gaps'), findsOneWidget);
    expect(find.text('Recovery is within baseline'), findsNothing);
    await tester.tap(find.text('Evidence used and data gaps'));
    await tester.pumpAndSettle();
    expect(find.text('Recovery is within baseline'), findsOneWidget);
    expect(find.text('feature_snapshot'), findsOneWidget);
    expect(find.textContaining('Missing: workout_execution'), findsOneWidget);
  });

  testWidgets('suggested follow-ups invoke the real send callback', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _ChatRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Explain today');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(find.text('What should I eat next?'), findsOneWidget);
    await tester.tap(find.text('What should I eat next?'));
    await tester.pumpAndSettle();
    expect(repository.sentQuestions, contains('What should I eat next?'));
  });

  testWidgets('Coach chat shows a safe alert without parser details', (
    tester,
  ) async {
    await _tall(tester);
    await tester.pumpWidget(_app(_ChatFailureRepository()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'How is my recovery?');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(
      find.text('Coach couldn’t complete that response. Please try again.'),
      findsWidgets,
    );
    expect(find.textContaining('Unexpected end of JSON input'), findsNothing);
  });
}

class _ChatRepository
    implements CoachRepository, CoachChatRepository, CoachContextRepository {
  final List<String> sentQuestions = [];

  @override
  Future<CoachDecision?> loadLatest() async => null;
  @override
  Future<CoachDecision> generate() => throw StateError('not needed');
  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};

  @override
  Future<List<CoachContextSource>> loadContextStatus() async => const [
    CoachContextSource(
      key: 'approved_plan',
      label: 'Approved training plan',
      available: true,
      records: 0,
    ),
    CoachContextSource(
      key: 'goal_profile',
      label: 'Goal and profile schedule',
      available: true,
      records: 0,
    ),
    CoachContextSource(
      key: 'healthkit',
      label: 'Apple Health summaries',
      available: true,
      records: 38,
      latestDate: '2026-07-10',
    ),
    CoachContextSource(
      key: 'check_in',
      label: 'Recovery check-ins',
      available: true,
      records: 3,
      latestDate: '2026-07-11',
    ),
    CoachContextSource(
      key: 'nutrition',
      label: 'Confirmed nutrition',
      available: true,
      records: 4,
    ),
    CoachContextSource(
      key: 'workouts',
      label: 'Completed Tracend workouts',
      available: false,
      records: 0,
    ),
    CoachContextSource(
      key: 'measurements',
      label: 'Body measurements',
      available: true,
      records: 7,
    ),
    CoachContextSource(
      key: 'conversation',
      label: 'Saved Coach conversation history',
      available: true,
      records: 4,
    ),
  ];

  @override
  Future<List<CoachThread>> loadThreads() async => const [];
  @override
  Future<String> createThread() async => 'thread-1';
  @override
  Future<List<CoachMessage>> loadMessages(String threadId) async => const [];

  @override
  Future<CoachMessage> sendMessage(String threadId, String question) async {
    sentQuestions.add(question);
    return CoachMessage(
      id: 'answer-1',
      role: 'assistant',
      content: 'Your approved plan remains available.',
      createdAt: DateTime(2026, 8, 24),
      evidence: const [
        {'label': 'Recovery is within baseline', 'source': 'feature_snapshot'},
      ],
      missingData: const ['workout_execution'],
      suggestedFollowUps: const ['What should I eat next?'],
    );
  }

  @override
  Future<void> deleteThread(String threadId) async {}
}

class _ChatFailureRepository extends _ChatRepository {
  @override
  Future<CoachMessage> sendMessage(String threadId, String question) =>
      throw const CoachUnavailableException(
        'Coach couldn’t complete that response. Please try again.',
        code: 'provider_response_invalid',
      );
}
