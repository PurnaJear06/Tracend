import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/shared/diagnostics.dart';

/// Today when the app comes back to the front: last night's Apple Health
/// data, and check-ins that waited for a connection.
const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: 'https://test.supabase.co',
  supabasePublishableKey: 'test-key',
);

const _payload = {
  'sleep_quality': 3,
  'energy': 2,
  'soreness': 4,
  'hunger': 3,
  'mood': 3,
  'pain_severity': 0,
  'available_to_train': false,
  'note': '',
};

class _Health implements HealthRepository {
  _Health(this.clock);

  final DateTime Function() clock;
  DateTime? lastSync;
  int syncCalls = 0;
  int historyCalls = 0;

  @override
  Future<HealthSyncStatus> loadStatus() async => HealthSyncStatus(
    state: HealthConnectionState.connected,
    lastSuccessfulSync: lastSync,
  );

  @override
  Future<HealthHistory> loadHistory() async {
    historyCalls++;
    return const HealthHistory([]);
  }

  @override
  Future<HealthSyncStatus> connectAndSync() => loadStatus();

  @override
  Future<HealthSyncStatus> sync() async {
    syncCalls++;
    lastSync = clock();
    return loadStatus();
  }
}

void main() {
  late DateTime now;
  late _Health health;
  late SharedPreferences preferences;
  final sent = <String>[];
  Object? sendError;

  setUp(() async {
    now = DateTime(2026, 10, 2, 22);
    health = _Health(() => now);
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    sent.clear();
    sendError = null;
  });

  Future<void> pumpToday(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [TracendColors.dark],
        ),
        home: Scaffold(
          body: TodayScreen(
            environment: _environment,
            health: health,
            coach: const FixtureCoachRepository(),
            brief: const FixtureDailyBriefRepository(),
            clock: () => now,
            queueFactory: () => CheckInQueue(preferences),
            checkInSender: (localDate, timezone, key, payload) async {
              sent.add(localDate);
              final error = sendError;
              if (error != null) throw error;
              return true;
            },
          ),
        ),
      ),
    );
    // Bounded pumps: the NOW dot pulses forever.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
  }

  group('Apple Health', () {
    testWidgets('resume syncs when the last sync is over thirty minutes old', (
      tester,
    ) async {
      health.lastSync = now.subtract(const Duration(hours: 9));
      await pumpToday(tester);
      expect(health.syncCalls, 1);

      now = now.add(const Duration(minutes: 10));
      await resume(tester);
      expect(health.syncCalls, 1, reason: 'throttled');

      now = now.add(const Duration(hours: 9));
      await resume(tester);
      expect(health.syncCalls, 2);
    });

    testWidgets('resume loads the health history again with a stale brief', (
      tester,
    ) async {
      health.lastSync = now;
      await pumpToday(tester);
      final history = health.historyCalls;

      now = now.add(const Duration(minutes: 5));
      await resume(tester);
      expect(health.historyCalls, history, reason: 'fresh');

      health.lastSync = now.add(const Duration(minutes: 40));
      now = now.add(const Duration(minutes: 40));
      await resume(tester);
      expect(health.historyCalls, greaterThan(history));
    });

    testWidgets('a never-connected Apple Health is not synced on resume', (
      tester,
    ) async {
      await pumpToday(tester);
      await resume(tester);
      expect(health.syncCalls, 0);
    });
  });

  group('queued check-ins', () {
    testWidgets('resume delivers check-ins queued after launch, oldest day '
        'first, each under its own day', (tester) async {
      await pumpToday(tester);
      expect(sent, isEmpty);
      final queue = CheckInQueue(preferences);
      await queue.enqueue(
        payload: _payload,
        localDate: '2026-10-02',
        timezone: 'Asia/Kolkata',
      );
      await queue.enqueue(
        payload: _payload,
        localDate: '2026-10-01',
        timezone: 'Asia/Kolkata',
      );

      await resume(tester);

      expect(sent, ['2026-10-01', '2026-10-02']);
      expect(await queue.pendingDays(), isEmpty);
    });

    testWidgets('a connection that is down keeps every day for the next '
        'resume', (tester) async {
      await pumpToday(tester);
      final queue = CheckInQueue(preferences);
      for (final day in ['2026-10-01', '2026-10-02']) {
        await queue.enqueue(
          payload: _payload,
          localDate: day,
          timezone: 'Asia/Kolkata',
        );
      }
      sendError = Exception('offline');
      await resume(tester);
      expect(await queue.pendingDays(), ['2026-10-01', '2026-10-02']);

      sendError = null;
      sent.clear();
      await resume(tester);
      expect(sent, ['2026-10-01', '2026-10-02']);
      expect(await queue.pendingDays(), isEmpty);
    });

    testWidgets('a final refusal drops the day, tells the athlete and '
        'reaches Sentry by its code', (tester) async {
      final reported = <NonCriticalFailure>[];
      final previous = failureSink;
      failureSink = (failure, _) => reported.add(failure);
      addTearDown(() => failureSink = previous);
      await pumpToday(tester);
      final queue = CheckInQueue(preferences);
      await queue.enqueue(
        payload: _payload,
        localDate: '2026-09-28',
        timezone: 'Asia/Kolkata',
      );
      sendError = PostgrestException(
        message: 'a pain check is for today or yesterday',
        code: '22023',
      );

      await resume(tester);

      expect(await queue.pendingDays(), isEmpty);
      expect(
        find.textContaining('could not be saved and was dropped'),
        findsOne,
      );
      expect(reported.single.what, 'Queued check-in refused');
      expect(reported.single.detail, 'PostgrestException 22023');
    });
  });
}
