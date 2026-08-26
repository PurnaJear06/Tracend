import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/today/widgets/today_hero.dart';

const _configuredEnvironment = AppEnvironment(
  name: 'test',
  supabaseUrl: 'https://test.supabase.co',
  supabasePublishableKey: 'test-key',
);

const _unconfiguredEnvironment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

Widget _app({
  required HealthRepository health,
  required CoachRepository coach,
  AppEnvironment environment = _configuredEnvironment,
  DailyBriefRepository brief = const FixtureDailyBriefRepository(),
}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      extensions: const [TracendColors.dark],
    ),
    home: Scaffold(
      body: TodayScreen(
        environment: environment,
        health: health,
        coach: coach,
        brief: brief,
      ),
    ),
  );
}

class _FakeHealthRepository implements HealthRepository {
  _FakeHealthRepository({this.status, this.syncThrows = false});

  final HealthSyncStatus? status;
  final bool syncThrows;
  int loadStatusCalls = 0;
  int syncCalls = 0;
  int connectCalls = 0;
  int historyCalls = 0;

  @override
  Future<HealthSyncStatus> loadStatus() async {
    loadStatusCalls++;
    return status ??
        const HealthSyncStatus(state: HealthConnectionState.manualOnly);
  }

  @override
  Future<HealthHistory> loadHistory() async {
    historyCalls++;
    return const HealthHistory([]);
  }

  @override
  Future<HealthSyncStatus> connectAndSync() async {
    connectCalls++;
    return loadStatus();
  }

  @override
  Future<HealthSyncStatus> sync() async {
    syncCalls++;
    if (syncThrows) throw StateError('health sync failed');
    return loadStatus();
  }
}

class _FakeCoachRepository implements CoachRepository {
  _FakeCoachRepository({this.latest});

  final CoachDecision? latest;
  int loadLatestCalls = 0;
  int generateCalls = 0;

  @override
  Future<CoachDecision?> loadLatest() async {
    loadLatestCalls++;
    return latest;
  }

  @override
  Future<CoachDecision> generate() async {
    generateCalls++;
    return latest ??
        CoachDecision(
          id: 'generated',
          localDate: _dateKey(DateTime.now()),
          trainingAction: 'PROCEED_AS_PLANNED',
          trainingSummary: 'Train as planned.',
          nutritionAction: 'MAINTAIN_TARGETS',
          nutritionSummary: 'Keep targets.',
          finalDecision: 'Proceed.',
          reason: 'Evidence supports it.',
          confidence: 'medium',
          evidence: const [],
          missingData: const [],
          riskFlags: const [],
          createdAt: DateTime.now(),
        );
  }

  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
}

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

CoachDecision _decisionFor(String localDate) => CoachDecision(
  id: 'd',
  localDate: localDate,
  trainingAction: 'PROCEED_AS_PLANNED',
  trainingSummary: 'Train as planned.',
  nutritionAction: 'MAINTAIN_TARGETS',
  nutritionSummary: 'Keep targets.',
  finalDecision: 'Proceed.',
  reason: 'Evidence supports it.',
  confidence: 'medium',
  evidence: const [],
  missingData: const [],
  riskFlags: const [],
  createdAt: DateTime.now(),
);

void main() {
  group('TodayHero sync chip', () {
    DailyBrief heroBrief() => DailyBrief(localDate: '2026-08-25');

    testWidgets('tapping the chip runs the sync pipeline', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [TracendColors.dark],
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: TodayHero(brief: heroBrief(), onSync: () => taps++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sync'), findsOneWidget);
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('syncing state shows a spinner and ignores taps', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [TracendColors.dark],
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: TodayHero(
                brief: heroBrief(),
                onSync: () => taps++,
                syncing: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Syncing'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      await tester.tap(find.text('Syncing'), warnIfMissed: false);
      // The spinner animates forever; pump fixed frames instead of settling.
      await tester.pump(const Duration(milliseconds: 100));
      expect(taps, 0);
    });

    testWidgets('shows the last health sync time when the brief has it', (
      tester,
    ) async {
      final brief = DailyBrief(
        localDate: '2026-08-25',
        health: const {'last_synced_at': '2026-08-25T09:05:00+00:00'},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [TracendColors.dark],
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: TodayHero(brief: brief, onSync: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Sync ·'), findsOneWidget);
    });
  });

  group('TodayScreen sync everything', () {
    testWidgets('hero sync refreshes health, brief, and generates decision', (
      tester,
    ) async {
      final health = _FakeHealthRepository(
        status: HealthSyncStatus(
          state: HealthConnectionState.connected,
          lastSuccessfulSync: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );
      final coach = _FakeCoachRepository();
      await tester.pumpWidget(_app(health: health, coach: coach));
      await tester.pumpAndSettle();

      final syncCallsBefore = health.syncCalls;
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();

      expect(health.syncCalls, syncCallsBefore + 1);
      expect(coach.generateCalls, 1);
      expect(find.text('Everything is up to date.'), findsOneWidget);
    });

    testWidgets('keeps the existing decision when it is already for today', (
      tester,
    ) async {
      final health = _FakeHealthRepository(
        status: HealthSyncStatus(
          state: HealthConnectionState.connected,
          lastSuccessfulSync: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );
      final coach = _FakeCoachRepository(
        latest: _decisionFor(_dateKey(DateTime.now())),
      );
      await tester.pumpWidget(_app(health: health, coach: coach));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();

      expect(coach.generateCalls, 0);
      expect(find.text('Everything is up to date.'), findsOneWidget);
    });

    testWidgets('reports partial failure honestly and keeps going', (
      tester,
    ) async {
      final health = _FakeHealthRepository(
        status: HealthSyncStatus(
          state: HealthConnectionState.connected,
          lastSuccessfulSync: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        syncThrows: true,
      );
      final coach = _FakeCoachRepository();
      await tester.pumpWidget(_app(health: health, coach: coach));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();

      expect(coach.generateCalls, 1);
      expect(
        find.text('Synced, but unavailable: Apple Health.'),
        findsOneWidget,
      );
    });

    testWidgets('a sync that reads unavailable counts as a failure', (
      tester,
    ) async {
      final health = _FakeHealthRepository(
        status: HealthSyncStatus(
          state: HealthConnectionState.unavailable,
          lastSuccessfulSync: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );
      final coach = _FakeCoachRepository();
      await tester.pumpWidget(_app(health: health, coach: coach));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();

      expect(health.syncCalls, greaterThan(0));
      expect(coach.generateCalls, 1);
      expect(
        find.text('Synced, but unavailable: Apple Health.'),
        findsOneWidget,
      );
    });

    testWidgets('never prompts for access: unconnected health is skipped', (
      tester,
    ) async {
      final health = _FakeHealthRepository(); // manualOnly, no last sync
      final coach = _FakeCoachRepository();
      await tester.pumpWidget(_app(health: health, coach: coach));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();

      expect(health.syncCalls, 0);
      expect(health.connectCalls, 0);
      expect(coach.generateCalls, 1);
      expect(
        find.text(
          'Synced. Apple Health is not connected — set it up in your profile.',
        ),
        findsOneWidget,
      );
    });
  });

  group('TodayScreen auto health sync on open', () {
    testWidgets('syncs silently when the last sync is older than 30 minutes', (
      tester,
    ) async {
      final health = _FakeHealthRepository(
        status: HealthSyncStatus(
          state: HealthConnectionState.connected,
          lastSuccessfulSync: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );
      await tester.pumpWidget(
        _app(health: health, coach: _FakeCoachRepository()),
      );
      await tester.pumpAndSettle();

      expect(health.syncCalls, 1);
      expect(health.connectCalls, 0);
    });

    testWidgets('skips auto sync when the last sync is recent', (tester) async {
      final health = _FakeHealthRepository(
        status: HealthSyncStatus(
          state: HealthConnectionState.connected,
          lastSuccessfulSync: DateTime.now().subtract(
            const Duration(minutes: 5),
          ),
        ),
      );
      await tester.pumpWidget(
        _app(health: health, coach: _FakeCoachRepository()),
      );
      await tester.pumpAndSettle();

      expect(health.syncCalls, 0);
    });

    testWidgets('never auto-syncs when health was never connected', (
      tester,
    ) async {
      final health = _FakeHealthRepository();
      await tester.pumpWidget(
        _app(health: health, coach: _FakeCoachRepository()),
      );
      await tester.pumpAndSettle();

      expect(health.syncCalls, 0);
      expect(health.connectCalls, 0);
    });

    testWidgets('no auto sync without Supabase configuration', (tester) async {
      final health = _FakeHealthRepository(
        status: HealthSyncStatus(
          state: HealthConnectionState.connected,
          lastSuccessfulSync: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );
      await tester.pumpWidget(
        _app(
          health: health,
          coach: _FakeCoachRepository(),
          environment: _unconfiguredEnvironment,
        ),
      );
      await tester.pumpAndSettle();

      expect(health.syncCalls, 0);
    });
  });
}
