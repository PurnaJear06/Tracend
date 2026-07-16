import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/nutrition_screen.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';

void main() {
  testWidgets('Train exposes the approved week and prescription details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: TrainScreen(repository: FixtureWorkoutRepository()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Approved training plan'), findsOneWidget);
    expect(find.textContaining('RPE 8'), findsWidgets);
    expect(find.textContaining('rest'), findsWidgets);
    await tester.scrollUntilVisible(
      find.textContaining('Planned values are never charted'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Planned values are never charted'),
      findsOneWidget,
    );
  });

  testWidgets('Nutrition makes the scheduled next meal primary', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: const NutritionScreen(repository: FixtureNutritionRepository()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pre-workout'), findsWidgets);
    expect(find.text('Log meal'), findsOneWidget);
    expect(find.textContaining('07:45'), findsWidgets);
  });

  testWidgets('Coach sends a persistent-style conversation message', (
    tester,
  ) async {
    final repository = _ChatRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: CoachScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('7 of 8 sources available · 1 needs data'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'What should I do next?');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('What should I do next?'), findsOneWidget);
    expect(repository.sent, isTrue);
  });

  test('fixture training hub never fabricates completed progression', () async {
    final hub = await FixtureWorkoutRepository().loadTrainingHub();
    expect(hub.completedSessions, 0);
    expect(hub.progression, isEmpty);
  });
}

class _ChatRepository
    implements CoachRepository, CoachChatRepository, CoachContextRepository {
  bool sent = false;
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
    sent = true;
    return CoachMessage(
      id: 'answer-1',
      role: 'assistant',
      content: 'Your approved plan remains available.',
      createdAt: DateTime(2026, 7, 4),
    );
  }

  @override
  Future<void> deleteThread(String threadId) async {}
}
