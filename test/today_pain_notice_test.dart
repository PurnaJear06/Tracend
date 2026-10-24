import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/readiness/pain_check.dart';
import 'package:tracend/features/readiness/pain_notice_card.dart';
import 'package:tracend/features/readiness/pain_report_queue.dart';
import 'package:tracend/features/readiness/pain_reporting.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';

import 'day_adjustment_fixtures.dart';
import 'pain_fakes.dart';

/// What Today says about a pain report that has not reached Tracend, and the
/// referral of a day with a safety route: a red flag is never dropped
/// silently, and a referral is shown until it has been acknowledged.

const _live = AppEnvironment(
  name: 'test',
  supabaseUrl: 'https://example.supabase.co',
  supabasePublishableKey: 'sb_publishable_test',
);

final _phone = DateTime(2026, 10, 2, 9);

class _Brief implements DailyBriefRepository {
  @override
  Future<DailyBrief> load(DateTime date) async =>
      DailyBrief(localDate: date.toIso8601String().substring(0, 10));
}

Map<String, dynamic> _quiet({String day = '2026-10-02'}) => adjustmentJson(
  day: day,
  kind: 'none',
  status: 'none',
  band: 'green',
  triggers: const [],
  confidence: 'high',
  missing: const [],
);

Map<String, dynamic> _route(String route, {String day = '2026-10-02'}) => {
  ...adjustmentJson(
    day: day,
    kind: 'none',
    status: 'none',
    band: 'red',
    triggers: const ['red_flag:numb_weak_limb'],
    safetyRoute: route,
  ),
  'schema_version': '1.1',
};

PainReport _report({String key = 'key-1', int severity = 5}) => PainReport(
  localDate: '2026-10-02',
  area: PainArea.knee,
  severity: severity,
  redFlags: const [],
  idempotencyKey: key,
);

class _Harness {
  _Harness(Map<String, dynamic> day, {DateTime? serverDay})
    : repository = FakeDayAdjustmentRepository(day) {
    controller = DayAdjustmentController(
      repository: repository,
      clock: () => _phone,
      serverToday: () async => serverDay ?? DateTime(2026, 10, 2),
    );
    addTearDown(controller.dispose);
    reporting = PainReporting(
      repository: pain,
      readiness: controller,
      userId: 'athlete-1',
    );
  }

  final FakeDayAdjustmentRepository repository;
  final pain = FakePainCheckRepository();
  late final DayAdjustmentController controller;
  late final PainReporting reporting;
}

Future<void> _pump(
  WidgetTester tester,
  _Harness h, {
  CheckInSend? sender,
  AppEnvironment environment = _live,
}) async {
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [TracendColors.dark],
      ),
      home: TodayScreen(
        environment: environment,
        brief: _Brief(),
        queueFactory: () => CheckInQueue(preferences, userId: 'athlete-1'),
        dayAdjustment: h.controller,
        pain: h.reporting,
        userId: 'athlete-1',
        checkInSender: sender ?? (date, zone, key, payload) async => true,
        clock: () => _phone,
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PainNoticeCard', () {
    Future<void> show(
      WidgetTester tester, {
      bool waiting = false,
      bool refused = false,
      List<String>? taps,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [TracendColors.dark],
          ),
          home: Scaffold(
            body: PainNoticeCard(
              waiting: waiting,
              refused: refused,
              onTryAgain: () => taps?.add('again'),
              onReportAgain: () => taps?.add('report'),
              onAcknowledge: () => taps?.add('ack'),
            ),
          ),
        ),
      );
    }

    testWidgets('says nothing when nothing waits', (tester) async {
      await show(tester);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('a waiting report names the one-day limit and retries', (
      tester,
    ) async {
      final taps = <String>[];
      await show(tester, waiting: true, taps: taps);
      expect(find.text('Your pain report is waiting to be sent'), findsOne);
      expect(find.textContaining('today or tomorrow'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(taps, ['again']);
    });

    testWidgets('a refused report says it was not recorded and offers both '
        'ways on', (tester) async {
      final taps = <String>[];
      await show(tester, refused: true, taps: taps);
      expect(find.text('A pain report could not be recorded'), findsOne);
      expect(find.textContaining('see a doctor or physio'), findsOneWidget);
      await tester.tap(find.text('Report it again'));
      await tester.tap(find.text('I understand'));
      expect(taps, ['report', 'ack']);
    });
  });

  group('Today and a pain report that has not arrived', () {
    testWidgets('a waiting report is said and goes when Try again works', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final h = _Harness(_quiet());
      h.pain.failure = PainCheckFailure.retry;
      await h.reporting.submit(_report()).delivery;
      await _pump(tester, h);
      expect(find.text('Your pain report is waiting to be sent'), findsOne);

      h.pain.failure = null;
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Your pain report is waiting to be sent'), findsNothing);
      expect((await h.reporting.state()).isEmpty, isTrue);
    });

    testWidgets('a refused report stays until the athlete has read it', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final h = _Harness(_quiet());
      h.pain.failure = PainCheckFailure.refused;
      await h.reporting.submit(_report(severity: 8)).delivery;
      await _pump(tester, h);
      expect(find.text('A pain report could not be recorded'), findsOne);
      // Leaving and coming back does not lose it.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, h);
      expect(find.text('A pain report could not be recorded'), findsOne);

      await tester.ensureVisible(find.text('I understand'));
      await tester.tap(find.text('I understand'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('A pain report could not be recorded'), findsNothing);
      expect((await h.reporting.state()).isEmpty, isTrue);
    });

    testWidgets('a check-in whose pain answers the server refused is told, '
        'then sent without them', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      await CheckInQueue(preferences, userId: 'athlete-1').enqueue(
        payload: const {
          'energy': 3,
          'pain_severity': 5,
          'pain_area': 'knee',
          'pain_red_flags': <String>[],
        },
        localDate: '2026-09-30',
        timezone: 'Asia/Kolkata',
      );
      final sent = <Map<String, dynamic>>[];
      final h = _Harness(_quiet());
      await _pump(
        tester,
        h,
        sender: (date, zone, key, payload) async {
          sent.add(payload);
          if (payload.containsKey('pain_area')) {
            throw const PostgrestException(message: 'old', code: '22023');
          }
          return true;
        },
      );
      expect(find.text('A pain report could not be recorded'), findsOne);
      expect(sent, hasLength(1), reason: 'not retried every launch');

      await tester.ensureVisible(find.text('I understand'));
      await tester.tap(find.text('I understand'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('A pain report could not be recorded'), findsNothing);
      expect(sent.last.containsKey('pain_area'), isFalse);
      expect(sent.last['energy'], 3);
      expect(
        preferences.getString(CheckInQueue.storageKeyFor('athlete-1')),
        isNull,
      );
    });
  });

  group('the referral of a day with a safety route', () {
    testWidgets('opens once, needs Got it, and is not opened again that day', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final h = _Harness(_route('clinician_today'));
      await _pump(tester, h);
      expect(find.text('Get this checked today'), findsWidgets);
      expect(find.text('Got it'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('Got it'), findsNothing);

      // Reading the day again does not open the sheet again.
      await h.controller.load();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Got it'), findsNothing);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getStringList('safety_acknowledged.athlete-1'), [
        '2026-10-02:clinician_today',
      ]);
    });

    testWidgets('a report just made shows its referral even when that route '
        'was read earlier today', (tester) async {
      final handle = tester.ensureSemantics();
      SharedPreferences.setMockInitialValues({
        'safety_acknowledged.athlete-1': ['2026-10-02:clinician_today'],
      });
      final h = _Harness(_route('clinician_today'));
      await _pump(
        tester,
        h,
        environment: const AppEnvironment(
          name: 'test',
          supabaseUrl: '',
          supabasePublishableKey: '',
        ),
      );
      expect(
        find.text('Got it'),
        findsNothing,
        reason: 'read already: Today does not open it by itself again',
      );

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
      await choose('Pain 8 of 10');
      await choose('Where is it?: Knee');
      await choose('Do any of these apply?: None of these');
      await tester.tap(find.text('Save check-in'));
      await tester.pumpAndSettle();
      expect(find.text('Got it'), findsOneWidget, reason: 'a new report');
      expect(find.text('Get this checked today'), findsWidgets);
      handle.dispose();
    });

    testWidgets('a hold that stands the next day is shown again that day', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'safety_acknowledged.athlete-1': ['2026-10-02:clinician_today'],
      });
      final h = _Harness(
        _route('clinician_today', day: '2026-10-03'),
        serverDay: DateTime(2026, 10, 3),
      );
      await _pump(tester, h);
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('an urgent route cannot be closed without Got it', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final h = _Harness(_route('urgent'));
      await _pump(tester, h);
      expect(find.text('Get medical help now'), findsWidgets);
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(find.text('Got it'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('Got it'), findsNothing);
    });

    testWidgets('a route this build does not know is shown with the '
        'strictest words', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final h = _Harness(_route('a_future_route'));
      await _pump(tester, h);
      expect(find.text('Get medical help now'), findsWidgets);
      expect(find.text('Got it'), findsOneWidget);
    });
  });

  test('a report keeps its idempotency key through the queue', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final queue = PainReportQueue(preferences, userId: 'athlete-1');
    await queue.add(_report(key: 'same'));
    await queue.add(_report(key: 'same'));
    expect(queue.state.waiting, hasLength(1));
  });
}
