import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';

/// The offline check-in promise, made whole: a check-in saved while offline
/// ("It will need a connection to sync") is delivered by the next Today
/// launch, with its original answer day — and the brief reloads once it
/// lands, because the check-in now colors today's coaching context.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const payload = {
    'sleep_quality': 3,
    'energy': 2,
    'soreness': 4,
    'hunger': 3,
    'mood': 3,
    'pain_severity': 0,
    'available_to_train': false,
    'note': 'Sore legs',
  };

  testWidgets('TodayScreen replays a pending check-in on launch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await CheckInQueue(preferences).enqueue(
      payload: payload,
      localDate: '2026-09-05',
      timezone: 'Asia/Kolkata',
    );
    var briefLoads = 0;
    final sentDates = <String>[];
    await tester.pumpWidget(
      _wrap(
        TodayScreen(
          environment: const AppEnvironment(
            name: 'test',
            supabaseUrl: 'https://example.supabase.co',
            supabasePublishableKey: 'sb_publishable_test',
          ),
          brief: _CountingBriefRepository(onLoad: () => briefLoads++),
          queueFactory: () => CheckInQueue(preferences),
          checkInSender: (localDate, timezone, key, payload) async {
            sentDates.add(localDate);
            return true;
          },
        ),
      ),
    );
    // Bounded pumps: NOW-dot pulse is an intentional infinite loop.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    expect(sentDates, ['2026-09-05']);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'daily_check_in_pending',
      ),
      isNull,
    );
    // The brief was loaded once at init and once more after delivery.
    expect(briefLoads, 2);
  });

  testWidgets('failed replay retains the envelope for the next launch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await CheckInQueue(preferences).enqueue(
      payload: payload,
      localDate: '2026-09-05',
      timezone: 'Asia/Kolkata',
    );
    var briefLoads = 0;
    await tester.pumpWidget(
      _wrap(
        TodayScreen(
          environment: const AppEnvironment(
            name: 'test',
            supabaseUrl: 'https://example.supabase.co',
            supabasePublishableKey: 'sb_publishable_test',
          ),
          brief: _CountingBriefRepository(onLoad: () => briefLoads++),
          queueFactory: () => CheckInQueue(preferences),
          checkInSender: (localDate, timezone, key, payload) async => false,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    expect(
      (await SharedPreferences.getInstance()).getString(
        'daily_check_in_pending',
      ),
      isNotNull,
    );
    // No delivery -> no extra brief load beyond init.
    expect(briefLoads, 1);
  });

  testWidgets('nothing pending: no send, no extra brief load', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var briefLoads = 0;
    var sends = 0;
    await tester.pumpWidget(
      _wrap(
        TodayScreen(
          environment: const AppEnvironment(
            name: 'test',
            supabaseUrl: 'https://example.supabase.co',
            supabasePublishableKey: 'sb_publishable_test',
          ),
          brief: _CountingBriefRepository(onLoad: () => briefLoads++),
          queueFactory: () => CheckInQueue(preferences),
          checkInSender: (localDate, timezone, key, payload) async {
            sends++;
            return true;
          },
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    expect(sends, 0);
    expect(briefLoads, 1);
  });
}

class _CountingBriefRepository implements DailyBriefRepository {
  _CountingBriefRepository({required this.onLoad});
  final VoidCallback onLoad;
  @override
  Future<DailyBrief> load(DateTime date) async {
    onLoad();
    return DailyBrief(localDate: date.toIso8601String().substring(0, 10));
  }
}

Widget _wrap(Widget child) {
  // TodayScreen is itself a scroll view (TracendScrollView); mounting it
  // directly as home gives it the bounded screen height it needs.
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      extensions: const [TracendColors.dark],
    ),
    home: child,
  );
}
