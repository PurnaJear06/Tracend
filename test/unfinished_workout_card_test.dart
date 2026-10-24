import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/today/widgets/unfinished_workout_card.dart';
import 'package:tracend/features/train/unfinished_workout.dart';
import 'package:tracend/features/train/workout_repository.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

final _legsB = UnfinishedWorkout(
  sessionId: 'd1450000-0000-4000-8000-000000000001',
  plannedWorkoutId: 'd1430000-0000-4000-8000-000000000001',
  name: 'Legs B',
  localDate: DateTime(2026, 10, 23),
  loggedSets: 23,
  totalSets: 25,
);

/// Offers one workout until it is answered, then the next one (or none).
class _Offers extends FixtureWorkoutRepository
    implements UnfinishedWorkoutRepository {
  _Offers(this.queue);

  final List<UnfinishedWorkout> queue;
  final saved = <(String, int)>[];

  /// When set, the next read waits for it (a slow one).
  Completer<UnfinishedWorkout?>? hold;
  final discarded = <String>[];
  Object? failWith;

  @override
  Future<UnfinishedWorkout?> loadUnfinishedWorkout() async {
    final waiting = hold;
    if (waiting != null) {
      hold = null;
      return waiting.future;
    }
    return queue.isEmpty ? null : queue.first;
  }

  @override
  Future<void> saveUnfinishedWorkout(
    UnfinishedWorkout workout, {
    required int sessionEffort,
  }) async {
    final error = failWith;
    if (error != null) throw error;
    saved.add((workout.sessionId, sessionEffort));
    queue.remove(workout);
  }

  @override
  Future<void> discardUnfinishedWorkout(UnfinishedWorkout workout) async {
    final error = failWith;
    if (error != null) throw error;
    discarded.add(workout.sessionId);
    queue.remove(workout);
  }
}

class _Brief implements DailyBriefRepository {
  const _Brief();

  @override
  Future<DailyBrief> load(DateTime date) async => const DailyBrief(
    localDate: '2026-10-24',
    workout: null,
    checkIn: null,
    health: null,
    nutrition: null,
  );
}

class _Health implements HealthRepository {
  const _Health();

  @override
  Future<HealthHistory> loadHistory() async => const HealthHistory([]);

  @override
  Future<HealthSyncStatus> loadStatus() async =>
      const HealthSyncStatus(state: HealthConnectionState.manualOnly);

  @override
  Future<HealthSyncStatus> connectAndSync() => loadStatus();

  @override
  Future<HealthSyncStatus> sync() => loadStatus();
}

Widget _today(
  WorkoutRepository? workouts, {
  DateTime Function() clock = DateTime.now,
}) => MaterialApp(
  theme: TracendTheme.dark,
  home: Scaffold(
    body: TodayScreen(
      environment: _environment,
      workouts: workouts,
      brief: const _Brief(),
      health: const _Health(),
      nutrition: const FixtureNutritionRepository(),
      coach: const FixtureCoachRepository(),
      clock: clock,
    ),
  ),
);

Future<void> _open(
  WidgetTester tester,
  WorkoutRepository? workouts, {
  DateTime Function() clock = DateTime.now,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_today(workouts, clock: clock));
  await tester.pumpAndSettle();
}

final _message = find.text(
  "You didn't finish Legs B on Fri 23 Oct · 23 sets logged",
);
final _saveButton = find.widgetWithText(FilledButton, 'Save workout');
final _discardButton = find.widgetWithText(OutlinedButton, 'Discard');

void main() {
  group('UnfinishedWorkoutCard', () {
    Widget card({bool busy = false, VoidCallback? onSave}) => MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: UnfinishedWorkoutCard(
          workout: _legsB,
          busy: busy,
          onSave: onSave ?? () {},
          onDiscard: () {},
          now: DateTime(2026, 10, 24),
        ),
      ),
    );

    testWidgets('names the workout, its day and the sets logged', (
      tester,
    ) async {
      await tester.pumpWidget(card());

      expect(_message, findsOneWidget);
      expect(find.text('Workout not finished'), findsOneWidget);
      expect(_saveButton, findsOneWidget);
      expect(_discardButton, findsOneWidget);
    });

    testWidgets('one set reads as one set', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: UnfinishedWorkoutCard(
              workout: UnfinishedWorkout(
                sessionId: _legsB.sessionId,
                plannedWorkoutId: _legsB.plannedWorkoutId,
                name: 'Pull',
                localDate: DateTime(2026, 10, 22),
                loggedSets: 1,
                totalSets: 12,
              ),
              busy: false,
              onSave: () {},
              onDiscard: () {},
              now: DateTime(2026, 10, 24),
            ),
          ),
        ),
      );

      expect(
        find.text("You didn't finish Pull on Thu 22 Oct · 1 set logged"),
        findsOneWidget,
      );
    });

    testWidgets('both buttons wait while an answer is on its way', (
      tester,
    ) async {
      var saves = 0;
      await tester.pumpWidget(card(busy: true, onSave: () => saves++));

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(saves, 0);
    });
  });

  group('Today', () {
    testWidgets('offers the workout and saves it with the athlete effort', (
      tester,
    ) async {
      final repository = _Offers([_legsB]);
      await _open(tester, repository);

      expect(_message, findsOneWidget);

      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(find.text('How hard was this workout overall?'), findsOneWidget);
      expect(
        find.text('2 sets are not logged. They stay unlogged, not skipped.'),
        findsOneWidget,
      );
      // Nothing is saved before the athlete answers.
      expect(repository.saved, isEmpty);

      await tester.tap(find.bySemanticsLabel('7, Hard'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save workout').last);
      await tester.pumpAndSettle();

      expect(repository.saved, [(_legsB.sessionId, 7)]);
      expect(_message, findsNothing);
      expect(find.textContaining('Legs B saved to Fri 23 Oct'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('"Not now" saves nothing', (tester) async {
      final repository = _Offers([_legsB]);
      await _open(tester, repository);

      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(repository.saved, isEmpty);
      expect(_message, findsOneWidget);
    });

    testWidgets('a save that fails keeps the card and says so', (tester) async {
      final repository = _Offers([_legsB])..failWith = StateError('offline');
      await _open(tester, repository);

      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('6, Moderate'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save workout').last);
      await tester.pumpAndSettle();

      expect(find.text('Could not save the workout. Try again.'), findsOne);
      expect(_message, findsOneWidget);
      expect(
        tester.widget<FilledButton>(_saveButton).onPressed,
        isNotNull,
        reason: 'the athlete can try again',
      );
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('discard asks first, then keeps the workout out', (
      tester,
    ) async {
      final repository = _Offers([_legsB]);
      await _open(tester, repository);

      await tester.tap(_discardButton);
      await tester.pumpAndSettle();
      expect(find.text('Discard Legs B?'), findsOneWidget);
      expect(repository.discarded, isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.discarded, isEmpty);
      expect(_message, findsOneWidget);

      await tester.tap(_discardButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard').last);
      await tester.pumpAndSettle();

      expect(repository.discarded, [_legsB.sessionId]);
      expect(_message, findsNothing);
    });

    testWidgets('after an answer the next workout offered shows', (
      tester,
    ) async {
      final earlier = UnfinishedWorkout(
        sessionId: 'd1450000-0000-4000-8000-000000000002',
        plannedWorkoutId: 'd1430000-0000-4000-8000-000000000002',
        name: 'Upper',
        localDate: DateTime(2026, 10, 22),
        loggedSets: 9,
        totalSets: 12,
      );
      final repository = _Offers([_legsB, earlier]);
      await _open(tester, repository);

      await tester.tap(_discardButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard').last);
      await tester.pumpAndSettle();

      expect(find.textContaining("You didn't finish Upper"), findsOneWidget);
    });

    testWidgets(
      'a slow read from before an answer never brings the card back',
      (tester) async {
        final repository = _Offers([_legsB]);
        var away = Duration.zero;
        await _open(tester, repository, clock: () => DateTime.now().add(away));
        expect(_message, findsOneWidget);

        // Coming back to the app starts a read that is slow to answer.
        final slow = Completer<UnfinishedWorkout?>();
        repository.hold = slow;
        away = const Duration(hours: 1);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        await tester.tap(_discardButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard').last);
        await tester.pumpAndSettle();
        expect(_message, findsNothing);

        // The read began before the answer and still says it is offered.
        slow.complete(_legsB);
        await tester.pumpAndSettle();

        expect(_message, findsNothing);
        expect(repository.discarded, [_legsB.sessionId]);
      },
    );

    testWidgets('shows no card when nothing is offered', (tester) async {
      await _open(tester, _Offers([]));

      expect(find.text('Workout not finished'), findsNothing);
    });

    testWidgets('shows no card from a repository that offers none', (
      tester,
    ) async {
      await _open(tester, FixtureWorkoutRepository());

      expect(find.text('Workout not finished'), findsNothing);
    });
  });
}
