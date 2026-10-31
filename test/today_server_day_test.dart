import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
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
  safetyRoute: 'clinician_today',
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
  await choose('Where is it?: Knee');
  await choose('Do any of these apply?: None of these');
  await tester.tap(find.text('Save check-in'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

String _key(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// Records the day each meals read is for.
class _Nutrition extends FixtureNutritionRepository {
  _Nutrition();

  final mealDays = <String>[];
  final scheduleDays = <String>[];

  @override
  Future<List<MealEntry>> loadMeals(DateTime date) {
    mealDays.add(_key(date));
    return super.loadMeals(date);
  }

  @override
  Future<NutritionSchedule> loadSchedule(DateTime date) {
    scheduleDays.add(_key(date));
    return super.loadSchedule(date);
  }
}

/// A coach whose newest decision is for [day]; a decision it makes is for the
/// day it is asked for (the phone's when it is asked for none), as the
/// server's is.
class _Coach implements CoachRepository {
  _Coach(this.day, {this.missingData = const []});

  String day;
  List<String> missingData;
  final asked = <String?>[];
  int get generated => asked.length;

  @override
  Future<CoachDecision?> loadLatest() async => CoachDecision(
    id: 'd',
    localDate: day,
    trainingAction: 'PROCEED_AS_PLANNED',
    trainingSummary: 'Train as planned.',
    nutritionAction: 'MAINTAIN_TARGETS',
    nutritionSummary: 'Keep the approved nutrition targets.',
    finalDecision: 'Proceed as planned.',
    reason: 'Check-in is available.',
    confidence: 'medium',
    evidence: const [],
    missingData: missingData,
    riskFlags: const [],
    createdAt: _phone,
  );

  @override
  Future<CoachDecision> generate({String? localDate}) async {
    asked.add(localDate);
    day = localDate ?? _key(_phone);
    missingData = const [];
    return (await loadLatest())!;
  }

  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
}

/// Grants AI coaching once Today is up, which makes Today check that the
/// decision it shows is current.
Future<_Coach> _grantAndCheck(
  WidgetTester tester, {
  bool askAgain = false,
  required String decisionDay,
  required DayAdjustmentController controller,
  List<String> missingData = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final coach = _Coach(decisionDay, missingData: missingData);
  final consent = AiCoachingConsentController(
    FixtureAiCoachingConsentRepository(AiCoachingChoice.declined),
    initial: AiCoachingChoice.declined,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [TracendColors.dark],
      ),
      home: TodayScreen(
        environment: _live,
        brief: _Brief(),
        coach: coach,
        aiConsent: consent,
        queueFactory: () => CheckInQueue(preferences),
        dayAdjustment: controller,
        clock: () => _phone,
      ),
    ),
  );
  await _settle(tester);
  expect(coach.generated, 0, reason: 'AI coaching is off until it is granted');
  await consent.record(granted: true);
  await _settle(tester);
  if (askAgain) {
    // Turning AI coaching off and on again checks the decision once more.
    await consent.record(granted: false);
    await consent.record(granted: true);
    await _settle(tester);
  }
  return coach;
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
    expect(find.text('Get this checked today'), findsWidgets);
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
      preferences.getString(CheckInQueue.queueStorageKey),
      contains('"local_date":"2026-10-02"'),
    );
    // The phone works the referral out from the answers and says it at once,
    // without waiting for the connection; it cannot be closed without Got it.
    expect(find.text('Get this checked today'), findsWidgets);
    expect(find.text('Got it'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Got it'), findsNothing);

    // The next launch replays it under that day; the referral already read
    // that day is not opened again.
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
    expect(find.text('Got it'), findsNothing);
    expect(find.text('Get this checked today'), findsWidgets);
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

  group('meals and the decision follow the server day, not the phone', () {
    testWidgets("today's meals are read for the server day once it is known", (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final nutrition = _Nutrition();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [TracendColors.dark],
          ),
          home: TodayScreen(
            environment: _offline,
            brief: _Brief(),
            nutrition: nutrition,
            queueFactory: () => CheckInQueue(preferences),
            dayAdjustment: _controller(
              FakeDayAdjustmentRepository(_noCheckIn()),
            ),
            clock: () => _phone,
          ),
        ),
      );
      await _settle(tester);
      // The phone's day first, then the server's, for the meals and the plan.
      expect(nutrition.mealDays, ['2026-10-01', '2026-10-02']);
      expect(nutrition.scheduleDays, ['2026-10-01', '2026-10-02']);
    });

    testWidgets(
      'meals are not read again when the phone and the server agree',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final nutrition = _Nutrition();
        final controller = DayAdjustmentController(
          repository: FakeDayAdjustmentRepository(_noCheckIn()),
          clock: () => _phone,
          serverToday: () async => DateTime(2026, 10, 1),
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              extensions: const [TracendColors.dark],
            ),
            home: TodayScreen(
              environment: _offline,
              brief: _Brief(),
              nutrition: nutrition,
              queueFactory: () => CheckInQueue(preferences),
              dayAdjustment: controller,
              clock: () => _phone,
            ),
          ),
        );
        await _settle(tester);
        expect(nutrition.mealDays, ['2026-10-01']);
      },
    );

    testWidgets("a decision for the server's day is current, whatever the "
        'phone says', (tester) async {
      final coach = await _grantAndCheck(
        tester,
        decisionDay: '2026-10-02',
        controller: _controller(FakeDayAdjustmentRepository(_noCheckIn())),
      );
      expect(coach.generated, 0, reason: 'already the server day decision');
    });

    testWidgets("a decision for the phone's day is stale once the server has "
        'moved on', (tester) async {
      final coach = await _grantAndCheck(
        tester,
        decisionDay: '2026-10-01',
        controller: _controller(FakeDayAdjustmentRepository(_noCheckIn())),
      );
      expect(coach.generated, 1);
    });

    testWidgets('a server-day decision that cited the check-in missing is '
        'made again', (tester) async {
      final coach = await _grantAndCheck(
        tester,
        decisionDay: '2026-10-02',
        missingData: const ['recovery_check_in'],
        controller: _controller(FakeDayAdjustmentRepository(_noCheckIn())),
      );
      expect(coach.generated, 1);
    });

    testWidgets('until the server day is known the phone day is used', (
      tester,
    ) async {
      final never = DayAdjustmentController(
        repository: FakeDayAdjustmentRepository(_noCheckIn()),
        clock: () => _phone,
        serverToday: () => Completer<DateTime?>().future,
      );
      addTearDown(never.dispose);
      final current = await _grantAndCheck(
        tester,
        decisionDay: '2026-10-01',
        controller: never,
      );
      expect(never.serverDay, isNull);
      expect(current.generated, 0, reason: "the phone's own day is current");
      await tester.pumpWidget(const SizedBox.shrink());
      final stale = await _grantAndCheck(
        tester,
        decisionDay: '2026-09-30',
        controller: never,
      );
      expect(stale.generated, 1);
    });

    testWidgets("the decision is made for the server's day, and once made it "
        'is current: a second check does not make another', (tester) async {
      final coach = await _grantAndCheck(
        tester,
        decisionDay: '2026-10-01',
        askAgain: true,
        controller: _controller(FakeDayAdjustmentRepository(_noCheckIn())),
      );
      expect(coach.asked, ['2026-10-02']);
    });

    testWidgets("a decision made before the server's day is known is for the "
        "phone's day", (tester) async {
      final never = DayAdjustmentController(
        repository: FakeDayAdjustmentRepository(_noCheckIn()),
        clock: () => _phone,
        serverToday: () => Completer<DateTime?>().future,
      );
      addTearDown(never.dispose);
      final coach = await _grantAndCheck(
        tester,
        decisionDay: '2026-09-30',
        askAgain: true,
        controller: never,
      );
      expect(coach.asked, ['2026-10-01']);
    });

    testWidgets('midnight passes while Today is open: one decision for the new '
        'day, none for the old, and none again on the next check', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      var phone = DateTime(2026, 10, 1, 23, 50);
      var serverDay = DateTime(2026, 10, 1);
      final controller = DayAdjustmentController(
        repository: FakeDayAdjustmentRepository(_noCheckIn()),
        clock: () => phone,
        serverToday: () async => serverDay,
      );
      addTearDown(controller.dispose);
      final coach = _Coach('2026-10-01');
      final consent = AiCoachingConsentController(
        FixtureAiCoachingConsentRepository(AiCoachingChoice.declined),
        initial: AiCoachingChoice.declined,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [TracendColors.dark],
          ),
          home: TodayScreen(
            environment: _live,
            brief: _Brief(),
            coach: coach,
            aiConsent: consent,
            queueFactory: () => CheckInQueue(preferences),
            dayAdjustment: controller,
            clock: () => phone,
          ),
        ),
      );
      await _settle(tester);
      await consent.record(granted: true);
      await _settle(tester);
      expect(coach.asked, isEmpty, reason: "the first day's decision stands");

      // Midnight where the athlete is; the app comes back to the front.
      phone = DateTime(2026, 10, 2, 0, 10);
      serverDay = DateTime(2026, 10, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(coach.asked, ['2026-10-02']);

      // The next check finds that decision current.
      await consent.record(granted: false);
      await consent.record(granted: true);
      await _settle(tester);
      expect(coach.asked, ['2026-10-02']);
    });
  });
}
