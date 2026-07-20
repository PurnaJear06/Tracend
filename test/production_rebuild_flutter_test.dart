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

  testWidgets('Train shows HealthKit auto-complete prompt when candidate is present', (
    tester,
  ) async {
    final repository = _HealthkitCandidateRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: TrainScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('Apple Health detected workout'), findsOneWidget);
    expect(find.text('Full body push'), findsOneWidget);
    expect(find.textContaining('Apple Health recorded a 60 min workout'), findsOneWidget);
    expect(find.text('Yes, mark complete'), findsOneWidget);
    expect(find.text('Log manually'), findsOneWidget);
  });

  testWidgets('Train shows HealthKit prompt after tapping a past weekday', (
    tester,
  ) async {
    final repository = _HealthkitCandidateRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: TrainScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    final chips = find.byType(ChoiceChip);
    await tester.tap(chips.at(1));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('Apple Health detected workout'), findsOneWidget);
    expect(find.text('Full body push'), findsOneWidget);
    expect(find.text('Yes, mark complete'), findsOneWidget);
  });

  testWidgets('Train shows Start workout when no HealthKit candidate is present', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: TrainScreen(repository: FixtureWorkoutRepository()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('Apple Health detected workout'), findsNothing);
  });

  testWidgets('Train shows View workout when day is completed', (
    tester,
  ) async {
    final repository = _CompletedDayRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: TrainScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('View workout'), findsOneWidget);
    expect(find.text('Start workout'), findsNothing);
  });
}

class _CompletedDayRepository
    implements WorkoutRepository, TrainingHubRepository, HealthkitCandidateRepository {
  @override
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28}) async =>
      TrainingHubData(
        planTitle: 'Approved training plan',
        workouts: [PlannedWorkout.fixture],
        recentSessions: [],
        completedSessions: 1,
        plannedSessions: 4,
        progression: [],
        completedDays: {DateTime.now()},
      );
  @override
  Future<HealthkitCompletionCandidate?> getHealthkitCandidate(DateTime date) async => null;
  @override
  Future<PlannedWorkout> loadTodayWorkout() async => PlannedWorkout.fixture;
  @override
  Future<String?> loadDraft(String workoutId) async => null;
  @override
  Future<Map<String, dynamic>?> loadSession(PlannedWorkout workout, {DateTime? localDate}) async => null;
  @override
  Future<void> saveDraft(String workoutId, String json) async {}
  @override
  Future<void> clearDraft(String workoutId) async {}
  @override
  Future<String> start(PlannedWorkout workout, String idempotencyKey, {DateTime? localDate}) async => 'session-1';
  @override
  Future<void> sync(String sessionId, int revision, Map<String, dynamic> draft) async {}
  @override
  Future<void> complete(String sessionId, int revision, int durationSeconds, Map<String, dynamic> draft) async {}
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

class _HealthkitCandidateRepository
    implements WorkoutRepository, TrainingHubRepository, HealthkitCandidateRepository {
  @override
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28}) async =>
      const TrainingHubData(
        planTitle: 'Approved training plan',
        workouts: [PlannedWorkout.fixture],
        recentSessions: [],
        completedSessions: 0,
        plannedSessions: 4,
        progression: [],
      );
  @override
  Future<HealthkitCompletionCandidate?> getHealthkitCandidate(DateTime date) async =>
      HealthkitCompletionCandidate(
        plannedWorkoutId: PlannedWorkout.fixture.id,
        plannedWorkoutName: 'Full body push',
        workoutCount: 1,
        workoutMinutes: 60,
        localDate: date,
      );
  @override
  Future<PlannedWorkout> loadTodayWorkout() async => PlannedWorkout.fixture;
  @override
  Future<String?> loadDraft(String workoutId) async => null;
  @override
  Future<Map<String, dynamic>?> loadSession(PlannedWorkout workout, {DateTime? localDate}) async =>
      null;
  @override
  Future<void> saveDraft(String workoutId, String json) async {}
  @override
  Future<void> clearDraft(String workoutId) async {}
  @override
  Future<String> start(
    PlannedWorkout workout,
    String idempotencyKey, {
    DateTime? localDate,
  }) async =>
      'session-1';
  @override
  Future<void> sync(
    String sessionId,
    int revision,
    Map<String, dynamic> draft,
  ) async {}
  @override
  Future<void> complete(
    String sessionId,
    int revision,
    int durationSeconds,
    Map<String, dynamic> draft,
  ) async {}
}
