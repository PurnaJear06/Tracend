import 'dart:async';

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

/// The athlete's day is the server's. When the phone's date differs, a
/// check-in saved under the phone's day would be invisible to the rules that
/// read "today's check-in" and a pain-7 referral would be missed.
/// Replays a queued check-in on launch (a backend is configured).
const _live = AppEnvironment(
  name: 'test',
  supabaseUrl: 'https://example.supabase.co',
  supabasePublishableKey: 'sb_publishable_test',
);

/// No backend: the check-in sheet then needs no Supabase client, and the
/// injected sender stands in for the RPC.
const _offline = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
  authMode: 'owner_email_password',
);

final _phone = DateTime(2026, 10, 1, 23, 50);

class _Brief implements DailyBriefRepository {
  final days = <String>[];
  final gates = <Completer<void>>[];
  bool gated = false;

  @override
  Future<DailyBrief> load(DateTime date) async {
    final day = date.toIso8601String().substring(0, 10);
    days.add(day);
    if (gated) {
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
    }
    return DailyBrief(localDate: day);
  }
}

Map<String, dynamic> _noCheckIn() => adjustmentJson(
  kind: 'none',
  status: 'none',
  band: 'unknown',
  triggers: const ['no_check_in'],
  confidence: null,
);

Map<String, dynamic> _painDay() => adjustmentJson(
  kind: 'none',
  status: 'none',
  band: 'red',
  triggers: const ['pain_severe'],
  safetyRoute: 'pain_referral',
);

Future<void> _settle(WidgetTester tester) async {
  // Bounded pumps: the NOW-dot pulse is an intentional infinite loop.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required _Brief brief,
  required DayAdjustmentController controller,
  CheckInSend? sender,
  SharedPreferences? preferences,
  AppEnvironment environment = _offline,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [TracendColors.dark],
      ),
      home: TodayScreen(
        environment: environment,
        brief: brief,
        queueFactory: () => CheckInQueue(preferences!),
        dayAdjustment: controller,
        checkInSender: sender,
        clock: () => _phone,
      ),
    ),
  );
}

DayAdjustmentController _controller(FakeDayAdjustmentRepository repository) {
  final controller = DayAdjustmentController(
    repository: repository,
    clock: () => _phone,
    serverToday: () async => DateTime(2026, 10, 2),
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _checkInWithPain7(WidgetTester tester) async {
  await tester.tap(find.text('Check in').first);
  await tester.pumpAndSettle();
  Future<void> choose(String label) async {
    final option = find.bySemanticsLabel(label);
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();
  }

  await choose('Pain: Some pain');
  await choose('Pain 7 of 10');
  await tester.tap(find.text('Save check-in'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an online pain-7 check-in is saved under the server day and '
      'shows the referral', (tester) async {
    final handle = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = FakeDayAdjustmentRepository(_noCheckIn());
    final sent = <String>[];
    await _pump(
      tester,
      brief: _Brief(),
      controller: _controller(repository),
      preferences: preferences,
      sender: (localDate, timezone, key, payload) async {
        sent.add(localDate);
        // The server only finds the check-in under the day it counts.
        if (localDate == '2026-10-02') repository.json = _painDay();
        return true;
      },
    );
    await _settle(tester);
    await _checkInWithPain7(tester);
    expect(sent, ['2026-10-02'], reason: "not the phone's 1 October");
    expect(find.text("Don't train through this pain"), findsWidgets);
    expect(find.text('Got it'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a queued pain-7 check-in is stored under the server day and '
      'replays under it', (tester) async {
    final handle = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = FakeDayAdjustmentRepository(_noCheckIn());
    final sent = <String>[];
    var online = false;
    await _pump(
      tester,
      brief: _Brief(),
      controller: _controller(repository),
      preferences: preferences,
      sender: (localDate, timezone, key, payload) async {
        sent.add(localDate);
        if (!online) return false;
        if (localDate == '2026-10-02') repository.json = _painDay();
        return true;
      },
    );
    await _settle(tester);
    await _checkInWithPain7(tester);
    // Offline: queued, with the server's day on the envelope.
    expect(
      preferences.getString('daily_check_in_pending'),
      contains('"local_date":"2026-10-02"'),
    );
    expect(find.text('Got it'), findsNothing);

    // The next launch replays it under that day and says what it found.
    online = true;
    sent.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      brief: _Brief(),
      controller: _controller(repository),
      preferences: preferences,
      environment: _live,
      sender: (localDate, timezone, key, payload) async {
        sent.add(localDate);
        repository.json = _painDay();
        return true;
      },
    );
    await _settle(tester);
    expect(sent, ['2026-10-02']);
    expect(find.text('Got it'), findsOneWidget);
    handle.dispose();
  });

  group('the brief follows the server day in either order', () {
    testWidgets('the day arrives before the brief does', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final brief = _Brief()..gated = true;
      await _pump(
        tester,
        brief: brief,
        controller: _controller(FakeDayAdjustmentRepository(_noCheckIn())),
        preferences: preferences,
      );
      await tester.pump(const Duration(seconds: 1));
      // The first brief (the phone's day) is still on its way.
      expect(brief.days, ['2026-10-01', '2026-10-02']);
      for (final gate in brief.gates) {
        gate.complete();
      }
      await _settle(tester);
      expect(brief.days, ['2026-10-01', '2026-10-02'], reason: 'no more loads');
    });

    testWidgets('the brief arrives before the day does', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final brief = _Brief();
      final repository = FakeDayAdjustmentRepository(_noCheckIn())
        ..loadGate = Completer<void>();
      final controller = _controller(repository);
      await _pump(
        tester,
        brief: brief,
        controller: controller,
        preferences: preferences,
      );
      await tester.pump(const Duration(seconds: 1));
      // The brief for the phone's day is in; the read is still waiting, but the
      // day itself is already known.
      expect(controller.serverDay, '2026-10-02');
      expect(brief.days.first, '2026-10-01');
      repository.loadGate!.complete();
      await _settle(tester);
      expect(brief.days.last, '2026-10-02');
      expect(brief.days, hasLength(2));
    });
  });
}
