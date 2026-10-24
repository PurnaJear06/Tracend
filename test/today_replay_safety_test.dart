import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';

import 'day_adjustment_fixtures.dart';

/// A check-in saved offline that says "pain 8" is delivered by the next launch.
/// The athlete must then be told what an online save would have told them: the
/// referral sheet, once, with no training choice.
class _Brief implements DailyBriefRepository {
  final days = <String>[];

  @override
  Future<DailyBrief> load(DateTime date) async {
    final day = date.toIso8601String().substring(0, 10);
    days.add(day);
    return DailyBrief(localDate: day);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const payload = {
    'sleep_quality': 3,
    'energy': 2,
    'soreness': 4,
    'hunger': 3,
    'mood': 3,
    'pain_severity': 8,
    'available_to_train': true,
    'note': '',
  };

  Future<(FakeDayAdjustmentRepository, int Function())> pump(
    WidgetTester tester, {
    required bool delivered,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await CheckInQueue(preferences).enqueue(
      payload: payload,
      localDate: '2026-10-02',
      timezone: 'Asia/Kolkata',
    );
    var sends = 0;
    // Before the replay the server has no check-in; after it, the pain routes
    // the day out.
    final repository = FakeDayAdjustmentRepository(
      adjustmentJson(
        kind: 'none',
        status: 'none',
        band: 'unknown',
        triggers: const ['no_check_in'],
        confidence: null,
      ),
    );
    final controller = DayAdjustmentController(
      repository: repository,
      clock: () => DateTime(2026, 10, 2, 9),
      serverToday: () async => DateTime(2026, 10, 2),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [TracendColors.dark],
        ),
        home: TodayScreen(
          environment: const AppEnvironment(
            name: 'test',
            supabaseUrl: 'https://example.supabase.co',
            supabasePublishableKey: 'sb_publishable_test',
          ),
          brief: _Brief(),
          queueFactory: () => CheckInQueue(preferences),
          dayAdjustment: controller,
          checkInSender: (localDate, timezone, key, payload) async {
            sends++;
            if (delivered) {
              repository.json = adjustmentJson(
                kind: 'none',
                status: 'none',
                band: 'red',
                triggers: const ['pain_severe'],
                safetyRoute: 'pain_referral',
              );
            }
            return delivered;
          },
        ),
      ),
    );
    // Bounded pumps: the NOW-dot pulse is an intentional infinite loop.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    return (repository, () => sends);
  }

  testWidgets('a replayed severe-pain check-in opens the referral sheet', (
    tester,
  ) async {
    final (_, sends) = await pump(tester, delivered: true);
    expect(sends(), 1);
    expect(find.text("Don't train through this pain"), findsWidgets);
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('Train as planned'), findsNothing);
    await tester.tap(find.text('Got it'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Got it'), findsNothing);
  });

  testWidgets('a replay that did not land shows no sheet', (tester) async {
    await pump(tester, delivered: false);
    expect(find.text('Got it'), findsNothing);
  });

  testWidgets('the brief follows the server\'s day when the phone differs', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final brief = _Brief();
    final controller = DayAdjustmentController(
      repository: FakeDayAdjustmentRepository(adjustmentJson()),
      clock: () => DateTime(2026, 10, 1, 23, 50),
      serverToday: () async => DateTime(2026, 10, 2),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [TracendColors.dark],
        ),
        home: TodayScreen(
          environment: const AppEnvironment(
            name: 'test',
            supabaseUrl: 'https://example.supabase.co',
            supabasePublishableKey: 'sb_publishable_test',
          ),
          brief: brief,
          queueFactory: () => CheckInQueue(preferences),
          dayAdjustment: controller,
          clock: () => DateTime(2026, 10, 1, 23, 50),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(brief.days.first, '2026-10-01');
    expect(brief.days.last, '2026-10-02');
  });
}
