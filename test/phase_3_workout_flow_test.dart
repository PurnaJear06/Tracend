import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';

class _MemoryWorkoutRepository implements WorkoutRepository {
  String? saved;
  int syncCalls = 0;
  int completeCalls = 0;
  bool failSync = false;
  Map<String, dynamic>? serverSession;
  @override
  Future<void> clearDraft(String workoutId) async => saved = null;
  @override
  Future<void> complete(
    String sessionId,
    int revision,
    int durationSeconds,
    Map<String, dynamic> draft,
  ) async {
    completeCalls++;
    saved = null;
  }

  @override
  Future<String?> loadDraft(String workoutId) async => saved;
  @override
  Future<Map<String, dynamic>?> loadSession(PlannedWorkout workout, {DateTime? localDate}) async =>
      serverSession;
  @override
  Future<PlannedWorkout> loadTodayWorkout() async => PlannedWorkout.fixture;
  @override
  Future<void> saveDraft(String workoutId, String json) async => saved = json;
  @override
  Future<String> start(PlannedWorkout workout, String idempotencyKey, {DateTime? localDate}) async =>
      'server-session';
  @override
  Future<void> sync(
    String sessionId,
    int revision,
    Map<String, dynamic> draft,
  ) async {
    syncCalls++;
    if (failSync) throw Exception('offline');
  }
}

Widget _app(Widget child) =>
    MaterialApp(theme: TracendTheme.light, home: child);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('set edits autosave and a completed set permits completion', (
    tester,
  ) async {
    final repository = _MemoryWorkoutRepository();
    await tester.pumpWidget(
      _app(
        ActiveWorkoutScreen(
          workout: PlannedWorkout.fixture,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'kg').first,
      '22.5',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'reps').first,
      '10',
    );
    await tester.tap(find.byTooltip('Complete set 1').first);
    await tester.pump(const Duration(milliseconds: 400));
    final draft = Map<String, dynamic>.from(
      jsonDecode(repository.saved!) as Map,
    );
    final exercises = draft['exercises'] as List;
    final firstExercise = Map<String, dynamic>.from(exercises.first as Map);
    final sets = firstExercise['sets'] as List;
    final firstSet = Map<String, dynamic>.from(sets.first as Map);
    expect(firstSet['completed'], isTrue);
    expect(find.text('1 sets complete'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Complete workout'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Complete workout'));
    await tester.pumpAndSettle();
    expect(repository.completeCalls, 1);
  });

  testWidgets('offline sync keeps the local draft and exposes pending state', (
    tester,
  ) async {
    final repository = _MemoryWorkoutRepository()..failSync = true;
    await tester.pumpWidget(
      _app(
        ActiveWorkoutScreen(
          workout: PlannedWorkout.fixture,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Complete set 1').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.saved, isNotNull);
    expect(find.text('Saved on device · sync pending'), findsOneWidget);
  });

  testWidgets('server session restores entered sets after reopening', (
    tester,
  ) async {
    final repository = _MemoryWorkoutRepository()
      ..serverSession = {
        'session_id': 'server-session',
        'state': 'in_progress',
        'revision': 4,
        'idempotency_key': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'actual_started_at': DateTime.now()
            .subtract(const Duration(minutes: 30))
            .toIso8601String(),
        'exercises': [
          {
            'order': 1,
            'status': 'performed',
            'pain_flag': false,
            'sets': [
              {
                'number': 1,
                'load_kg': 24,
                'repetitions': 10,
                'rpe': 8,
                'completed': true,
              },
            ],
          },
        ],
      };
    await tester.pumpWidget(
      _app(
        ActiveWorkoutScreen(
          workout: PlannedWorkout.fixture,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 sets complete'), findsOneWidget);
    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(fields.elementAt(0).initialValue, '24');
    expect(fields.elementAt(1).initialValue, '8');
    expect(fields.elementAt(2).initialValue, '10');
  });

  testWidgets('Today opens the bounded daily check-in sheet', (tester) async {
    const environment = AppEnvironment(
      supabaseUrl: '',
      supabasePublishableKey: '',
      name: 'test',
      authMode: 'owner_email_password',
    );
    await tester.pumpWidget(_app(const TodayScreen(environment: environment)));
    await tester.scrollUntilVisible(
      find.text('Add today’s check-in'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Add today’s check-in'),
        matching: find.byType(ListTile),
      ),
    );
    tile.onTap!();
    await tester.pumpAndSettle();
    expect(find.text('Daily check-in'), findsOneWidget);
    expect(find.text('Sleep quality'), findsOneWidget);
    expect(find.text('Available to train today'), findsOneWidget);
    expect(find.text('Save check-in'), findsOneWidget);
  });
}
