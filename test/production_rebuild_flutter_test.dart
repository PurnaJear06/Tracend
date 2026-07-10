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

class _ChatRepository implements CoachRepository, CoachChatRepository {
  bool sent = false;
  @override
  Future<CoachDecision?> loadLatest() async => null;
  @override
  Future<CoachDecision> generate() => throw StateError('not needed');
  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
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
