import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';

/// Decision freshness (Pass 2.5a): the daily decision generates once, but it
/// can be generated before the morning check-in — in that state the policy
/// permits only gather-data actions and cites `recovery_check_in` as
/// missing, and the card would keep saying "gather data" all day even after
/// the check-in lands. New evidence arriving (the check-in) must refresh a
/// decision that cited it as missing, and must NOT churn decisions that are
/// already current and complete.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const environment = AppEnvironment(
    name: 'test',
    supabaseUrl: 'https://example.supabase.co',
    supabasePublishableKey: 'sb_publishable_test',
  );

  CoachDecision decisionFor(
    String localDate, {
    List<String> missingData = const [],
  }) => CoachDecision(
    id: 'd',
    localDate: localDate,
    trainingAction: 'GATHER_DATA',
    trainingSummary: 'Keep the approved plan available.',
    nutritionAction: 'MAINTAIN_TARGETS',
    nutritionSummary: 'Keep the approved nutrition targets.',
    finalDecision: 'Keep the approved plan and add a check-in.',
    reason: 'There is not enough current evidence for a new coaching decision.',
    confidence: 'low',
    evidence: const [],
    missingData: missingData,
    riskFlags: const [],
    createdAt: DateTime.now(),
  );

  String dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  testWidgets(
    'replayed check-in regenerates a decision that cited it missing',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      await CheckInQueue(preferences).enqueue(
        payload: const {
          'sleep_quality': 3,
          'energy': 4,
          'soreness': 2,
          'hunger': 3,
          'mood': 4,
          'pain_severity': 0,
          'available_to_train': true,
          'note': '',
        },
        localDate: dateKey(DateTime.now()),
        timezone: 'Asia/Kolkata',
      );
      // This morning's sync generated the decision before the check-in
      // existed: the policy permitted only gather-data actions and the
      // decision cites the check-in as missing.
      final coach = _FakeCoachRepository(
        latest: decisionFor(
          dateKey(DateTime.now()),
          missingData: const ['recovery_check_in'],
        ),
      );
      await tester.pumpWidget(
        _wrap(
          TodayScreen(
            environment: environment,
            coach: coach,
            brief: _CountingBriefRepository(),
            queueFactory: () => CheckInQueue(preferences),
            checkInSender: (localDate, timezone, key, payload) async => true,
          ),
        ),
      );
      // Bounded pumps: NOW-dot pulse is an intentional infinite loop.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));

      // The replayed check-in refreshed the stale decision: a new decision
      // was generated with the check-in as evidence.
      expect(coach.generateCalls, 1);
      expect(coach.latest?.missingData, isEmpty);
      expect(coach.latest?.trainingAction, 'PROCEED_AS_PLANNED');
    },
  );

  testWidgets('current decision citing the check-in is kept after replay', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await CheckInQueue(preferences).enqueue(
      payload: const {
        'sleep_quality': 3,
        'energy': 4,
        'soreness': 2,
        'hunger': 3,
        'mood': 4,
        'pain_severity': 0,
        'available_to_train': true,
        'note': '',
      },
      localDate: dateKey(DateTime.now()),
      timezone: 'Asia/Kolkata',
    );
    final coach = _FakeCoachRepository(
      latest: decisionFor(dateKey(DateTime.now())),
    );
    await tester.pumpWidget(
      _wrap(
        TodayScreen(
          environment: environment,
          coach: coach,
          brief: _CountingBriefRepository(),
          queueFactory: () => CheckInQueue(preferences),
          checkInSender: (localDate, timezone, key, payload) async => true,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    // A decision that already saw the check-in is not regenerated.
    expect(coach.generateCalls, 0);
  });
}

class _FakeCoachRepository implements CoachRepository {
  _FakeCoachRepository({this.latest});

  CoachDecision? latest;
  int generateCalls = 0;

  @override
  Future<CoachDecision?> loadLatest() async => latest;

  @override
  Future<CoachDecision> generate() async {
    generateCalls++;
    // The refreshed decision sees the check-in: no missing data, full
    // action space.
    latest = CoachDecision(
      id: 'post-check-in',
      localDate: latest?.localDate ?? '',
      trainingAction: 'PROCEED_AS_PLANNED',
      trainingSummary: 'Train as planned.',
      nutritionAction: 'MAINTAIN_TARGETS',
      nutritionSummary: 'Keep the approved nutrition targets.',
      finalDecision: 'Proceed as planned.',
      reason: 'Check-in is available.',
      confidence: 'medium',
      evidence: const [],
      missingData: const [],
      riskFlags: const [],
      createdAt: DateTime.now(),
    );
    return latest!;
  }

  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
}

class _CountingBriefRepository implements DailyBriefRepository {
  @override
  Future<DailyBrief> load(DateTime date) async =>
      DailyBrief(localDate: date.toIso8601String().substring(0, 10));
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
