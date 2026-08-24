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

CoachDecision _decision({
  String confidence = 'high',
  String reason = 'Evidence supports the current plan.',
}) => CoachDecision(
  id: 'decision-1',
  localDate: '2026-08-24',
  trainingAction: 'Proceed',
  trainingSummary: 'Training stays as planned.',
  nutritionAction: 'Keep intake unchanged',
  nutritionSummary: 'Prioritize protein.',
  finalDecision: 'Keep the approved plan.',
  reason: reason,
  confidence: confidence,
  evidence: const [
    {
      'code': 'RECOVERY_WITHIN_BASELINE',
      'label': 'Recovery indicators are within the recent baseline',
      'source': 'feature_snapshot',
    },
  ],
  missingData: const ['workout_execution'],
  riskFlags: const [],
  createdAt: DateTime(2026, 8, 24),
);

void main() {
  testWidgets('confidence always comes from the decision', (tester) async {
    await tester.pumpWidget(_app(_DecisionRepository(confidence: 'low')));
    await tester.pumpAndSettle();
    expect(find.text('Confidence: low'), findsOneWidget);
    expect(find.textContaining('medium'), findsNothing);
  });

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

  testWidgets('long decision reason expands beyond six lines', (tester) async {
    final longReason = List.generate(
      12,
      (i) => 'Evidence point $i supports maintaining the approved plan today.',
    ).join(' ');
    await tester.pumpWidget(_app(_DecisionRepository(reason: longReason)));
    await tester.pumpAndSettle();
    expect(find.text('Show more'), findsOneWidget);
    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('short decision reason has no dead expansion control', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_DecisionRepository()));
    await tester.pumpAndSettle();
    expect(find.text('Show more'), findsNothing);
  });

  testWidgets('empty decision state offers generation', (tester) async {
    await tester.pumpWidget(_app(_EmptyRepository()));
    await tester.pumpAndSettle();
    expect(find.text('No daily decision yet'), findsOneWidget);
    expect(find.text('Generate today’s decision'), findsOneWidget);
  });

  testWidgets('loading and error states remain safe', (tester) async {
    await tester.pumpWidget(_app(_FailureRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate today’s decision'));
    await tester.pumpAndSettle();
    expect(
      find.text('Coaching is unavailable. Your approved plan is unchanged.'),
      findsOneWidget,
    );
  });
}

class _DecisionRepository implements CoachRepository {
  const _DecisionRepository({this.confidence = 'high', this.reason});
  final String confidence;
  final String? reason;

  @override
  Future<CoachDecision?> loadLatest() async => _decision(
    confidence: confidence,
    reason: reason ?? 'Evidence supports the current plan.',
  );
  @override
  Future<CoachDecision> generate() async => _decision();
  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
}

class _EmptyRepository implements CoachRepository {
  const _EmptyRepository();
  @override
  Future<CoachDecision?> loadLatest() async => null;
  @override
  Future<CoachDecision> generate() async => _decision();
  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
}

class _FailureRepository implements CoachRepository {
  const _FailureRepository();
  @override
  Future<CoachDecision?> loadLatest() async => null;
  @override
  Future<CoachDecision> generate() => throw StateError('offline');
  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
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
