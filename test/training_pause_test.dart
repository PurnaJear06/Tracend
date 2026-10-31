import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/training_pause_repository.dart';
import 'package:tracend/features/train/widgets/break_widgets.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/training_availability.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

import 'day_adjustment_fixtures.dart';
import 'train_fixtures.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

Map<String, dynamic> _pauseJson({
  String start = '2026-10-01',
  String end = '2026-10-05',
  bool running = true,
}) => {
  'id': 'pause-1',
  'start_date': start,
  'end_date': end,
  'reason': 'rest',
  'note': null,
  'source': 'athlete',
  'running': running,
};

Map<String, dynamic> _availabilityJson({
  String status = 'available',
  bool unavailable = false,
  bool paused = false,
  Map<String, dynamic>? pause,
  Map<String, dynamic>? returning,
  bool offer = false,
}) => {
  'schema_version': '1.0',
  'local_date': '2026-10-02',
  'status': status,
  'unavailable_today': unavailable,
  'safety_route': null,
  'paused': paused,
  'pause': pause,
  'return_from_pause': returning,
  'offer_break': offer,
};

class _Pauses implements TrainingPauseRepository {
  _Pauses({this.refuseFirst});

  /// The first start is refused with this; later ones are set.
  PauseRefusal? refuseFirst;
  final starts = <(DateTime, DateTime)>[];
  final ends = <String>[];

  @override
  Future<PauseStartResult> start({
    required DateTime startDate,
    required DateTime endDate,
    String? note,
  }) async {
    starts.add((startDate, endDate));
    final refusal = refuseFirst;
    if (refusal != null) {
      refuseFirst = null;
      return PauseStartResult.refused(
        refusal,
        startDate: startDate,
        endDate: endDate,
      );
    }
    return PauseStartResult.started(
      pauseId: 'pause-new',
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  Future<PauseEndResult> end(String pauseId) async {
    ends.add(pauseId);
    return PauseEndResult(status: 'ended', endedOn: trainToday);
  }
}

class _Brief implements DailyBriefRepository {
  _Brief(this.availability, {this.todaySession, this.week = const []});

  TrainingAvailability availability;
  TodaySession? todaySession;
  List<TodayWeekDay> week;
  int loads = 0;

  @override
  Future<DailyBrief> load(DateTime date) async {
    loads++;
    return DailyBrief(
      localDate: '2026-10-02',
      workout: const {
        'id': 'w-upper-a',
        'name': 'Upper body A',
        'estimated_minutes': 48,
        'exercises': [
          {'order': 1, 'name': 'Bench press', 'set_count': 3},
        ],
      },
      availability: availability,
      todaySession: todaySession,
      week: week,
    );
  }
}

Future<void> _pumpToday(
  WidgetTester tester, {
  required _Brief brief,
  required _Pauses pauses,
  DayAdjustmentController? dayAdjustment,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    TracendMotionScope(
      level: TracendMotionLevel.static,
      child: MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: TodayScreen(
            environment: _environment,
            brief: brief,
            nutrition: const FixtureNutritionRepository(),
            onOpenNutrition: () {},
            onOpenTrain: () {},
            pauses: pauses,
            clock: trainNow,
            dayAdjustment: dayAdjustment,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TrainingHubData _hub({
  TrainingAvailability availability = TrainingAvailability.available,
  Set<DateTime> paused = const {},
  Set<DateTime> unavailable = const {},
}) {
  final base = trainHub();
  return TrainingHubData(
    planTitle: base.planTitle,
    plan: base.plan,
    localToday: base.localToday,
    workouts: base.workouts,
    recentSessions: base.recentSessions,
    completedSessions: base.completedSessions,
    plannedSessions: base.plannedSessions,
    progression: base.progression,
    completedDays: base.completedDays,
    dailyLoad: base.dailyLoad,
    load: base.load,
    availability: availability,
    pausedDays: paused,
    unavailableDays: unavailable,
  );
}

Future<void> _pumpTrain(
  WidgetTester tester, {
  required TrainingHubData hub,
  required _Pauses pauses,
}) async {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    TracendMotionScope(
      level: TracendMotionLevel.static,
      child: MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: TrainScreen(
            repository: TrainFixtureRepository(hub: hub),
            brief: TrainBriefRepository(computed: trainComputed()),
            coach: const TrainCoachRepository(),
            now: trainNow,
            pauses: pauses,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('TrainingAvailability parser', () {
    test('an older payload without availability reads as a normal day', () {
      final none = TrainingAvailability.fromJson(null);
      expect(none.status, AvailabilityStatus.available);
      expect(none.paused, isFalse);
      expect(none.pause, isNull);
      expect(none.offerBreak, isFalse);
      final brief = DailyBrief.fromJson({
        'schema_version': '1.8',
        'local_date': '2026-10-02',
      });
      expect(brief.availability.status, AvailabilityStatus.available);
    });

    test('a running break, a return and the offer are read', () {
      final paused = TrainingAvailability.fromJson(
        _availabilityJson(status: 'paused', paused: true, pause: _pauseJson()),
      );
      expect(paused.status, AvailabilityStatus.paused);
      expect(paused.runningPause!.endDate, DateTime(2026, 10, 5));
      expect(paused.runningPause!.resumesOn, DateTime(2026, 10, 6));
      expect(paused.upcomingPause, isNull);

      final upcoming = TrainingAvailability.fromJson(
        _availabilityJson(
          pause: _pauseJson(start: '2026-10-04', running: false),
        ),
      );
      expect(upcoming.upcomingPause!.startDate, DateTime(2026, 10, 4));
      expect(upcoming.runningPause, isNull);

      final back = TrainingAvailability.fromJson(
        _availabilityJson(
          returning: {'pause_id': 'pause-1', 'last_paused_day': '2026-10-01'},
          unavailable: true,
          status: 'unavailable_today',
          offer: true,
        ),
      );
      expect(back.returnFromPause!.lastPausedDay, DateTime(2026, 10, 1));
      expect(back.unavailableToday, isTrue);
      expect(back.status, AvailabilityStatus.unavailableToday);
      expect(back.offerBreak, isTrue);
    });

    test(
      'an unknown status (a Coach-only safety route) reads as available',
      () {
        final route = TrainingAvailability.fromJson(
          _availabilityJson(status: 'safety_route'),
        );
        expect(route.status, AvailabilityStatus.available);
      },
    );

    test('a break with its last day before its first is not read', () {
      expect(
        TrainingPause.fromJson(
          _pauseJson(start: '2026-10-05', end: '2026-10-01'),
        ),
        isNull,
      );
    });

    test('the hub reads paused days and paused sessions', () {
      final hub = TrainingHubData.fromHubJson({
        'schema_version': '1.10',
        'local_today': '2026-10-02',
        'adherence': {
          'completed_sessions': 2,
          'planned_sessions': 3,
          'paused_sessions': 2,
        },
        'paused_days': ['2026-10-01', '2026-10-02', 'not a date'],
        'availability': _availabilityJson(
          status: 'paused',
          paused: true,
          pause: _pauseJson(),
        ),
      });
      expect(hub.pausedDays, {DateTime(2026, 10, 1), DateTime(2026, 10, 2)});
      expect(hub.isDayPaused(DateTime(2026, 10, 2, 15)), isTrue);
      expect(hub.isDayPaused(DateTime(2026, 10, 3)), isFalse);
      expect(hub.pausedSessions, 2);
      expect(hub.plannedSessions, 3);
      expect(hub.unavailableDays, isEmpty);

      final unavailable = TrainingHubData.fromHubJson({
        'schema_version': '1.10',
        'local_today': '2026-10-02',
        'adherence': {
          'completed_sessions': 1,
          'planned_sessions': 2,
          'paused_sessions': 0,
          'unavailable_sessions': 1,
        },
        'unavailable_days': ['2026-09-30'],
      });
      expect(unavailable.unavailableSessions, 1);
      expect(unavailable.isRestChosen(DateTime(2026, 9, 30, 8)), isTrue);
      expect(unavailable.isDayPaused(DateTime(2026, 9, 30)), isFalse);
      expect(hub.availability.paused, isTrue);

      final older = TrainingHubData.fromHubJson({
        'schema_version': '1.9',
        'local_today': '2026-10-02',
      });
      expect(older.pausedDays, isEmpty);
      expect(older.pausedSessions, 0);
      expect(older.availability.status, AvailabilityStatus.available);
    });

    test('break ranges and start answers', () {
      final now = DateTime(2026, 11, 1);
      expect(
        breakRangeLabel(
          DateTime(2026, 11, 1),
          DateTime(2026, 11, 15),
          now: now,
        ),
        '1–15 Nov',
      );
      expect(
        breakRangeLabel(
          DateTime(2026, 10, 28),
          DateTime(2026, 11, 3),
          now: now,
        ),
        '28 Oct – 3 Nov',
      );
      final refused = parsePauseStart(
        {'status': 'refused', 'refusal': 'pause_overlaps', 'pause_id': null},
        startDate: now,
        endDate: now,
      );
      expect(refused.started, isFalse);
      expect(refused.refusal, PauseRefusal.overlaps);
      final started = parsePauseStart(
        {
          'status': 'started',
          'pause_id': 'p',
          'start_date': '2026-11-01',
          'end_date': '2026-11-15',
        },
        startDate: now,
        endDate: now,
      );
      expect(started.started, isTrue);
      expect(started.endDate, DateTime(2026, 11, 15));
      expect(PauseRefusal.parse('something new'), PauseRefusal.unknown);
    });
  });

  group('Break sheet', () {
    Future<PauseStartResult?> open(WidgetTester tester, _Pauses pauses) async {
      PauseStartResult? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showTakeBreakSheet(
                  context,
                  today: DateTime(2026, 10, 2),
                  repository: pauses,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('starts today to the day after, ends within 42 days', (
      tester,
    ) async {
      final pauses = _Pauses();
      await open(tester, pauses);
      expect(find.byKey(const ValueKey('break-start-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('break-start-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('break-start-3')), findsNothing);
      expect(find.text('Break · 2–8 Oct'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('break-start-1')));
      await tester.pumpAndSettle();
      expect(find.text('Break · 3–8 Oct'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('break-end-row')));
      await tester.pumpAndSettle();
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.firstDate, DateTime(2026, 10, 3));
      expect(picker.lastDate, DateTime(2026, 11, 13));
    });

    testWidgets('a refusal is shown in plain words, then Confirm sets it', (
      tester,
    ) async {
      final pauses = _Pauses(refuseFirst: PauseRefusal.overlaps);
      PauseStartResult? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showTakeBreakSheet(
                  context,
                  today: DateTime(2026, 10, 2),
                  repository: pauses,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('break-confirm')));
      await tester.pumpAndSettle();
      expect(
        find.text('A break already covers some of those days.'),
        findsOneWidget,
      );
      expect(result, isNull);

      await tester.tap(find.byKey(const ValueKey('break-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('break-confirm')), findsNothing);
      expect(result!.started, isTrue);
      expect(pauses.starts.last, (
        DateTime(2026, 10, 2),
        DateTime(2026, 10, 8),
      ));
    });
  });

  group('Today', () {
    testWidgets(
      'a running break replaces the session; End break early ends it',
      (tester) async {
        final brief = _Brief(
          TrainingAvailability.fromJson(
            _availabilityJson(
              status: 'paused',
              paused: true,
              pause: _pauseJson(),
            ),
          ),
        );
        final pauses = _Pauses();
        await _pumpToday(tester, brief: brief, pauses: pauses);

        expect(find.text('On a break until Mon 5 Oct'), findsOneWidget);
        expect(find.text('Upper body A'), findsNothing);
        expect(find.byKey(const ValueKey('take-break')), findsNothing);

        brief.availability = TrainingAvailability.available;
        final loadsBefore = brief.loads;
        await tester.ensureVisible(find.byKey(const ValueKey('break-end')));
        await tester.tap(find.byKey(const ValueKey('break-end')));
        await tester.pumpAndSettle();
        expect(find.text('End your break now?'), findsOneWidget);
        await tester.tap(find.text('End break'));
        await tester.pumpAndSettle();

        expect(pauses.ends, ['pause-1']);
        expect(brief.loads, greaterThan(loadsBefore));
        expect(find.text('On a break until Mon 5 Oct'), findsNothing);
        expect(find.text('Upper body A'), findsOneWidget);
      },
    );

    testWidgets('a safety referral on the card stays above a running break', (
      tester,
    ) async {
      final brief = _Brief(
        TrainingAvailability.fromJson(
          _availabilityJson(
            status: 'paused',
            paused: true,
            pause: _pauseJson(),
          ),
        ),
      );
      final controller = DayAdjustmentController(
        repository: FakeDayAdjustmentRepository(
          adjustmentJson(
            kind: 'none',
            status: 'none',
            band: 'red',
            triggers: const ['pain_severe', 'paused'],
            safetyRoute: 'pain_referral',
          ),
        ),
        serverToday: () async => DateTime(2026, 10, 2),
        clock: () => DateTime(2026, 10, 2, 9),
      );
      await _pumpToday(
        tester,
        brief: brief,
        pauses: _Pauses(),
        dayAdjustment: controller,
      );

      expect(find.text('Your safety first'), findsOneWidget);
      expect(find.text('On a break until Mon 5 Oct'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Your safety first')).dy,
        lessThan(tester.getTopLeft(find.text('On a break until Mon 5 Oct')).dy),
      );
    });

    testWidgets('a session logged on a break day stays visible on Today', (
      tester,
    ) async {
      final brief = _Brief(
        TrainingAvailability.fromJson(
          _availabilityJson(
            status: 'paused',
            paused: true,
            pause: _pauseJson(),
          ),
        ),
        todaySession: const TodaySession(
          state: 'completed',
          completedSets: {1: 3},
        ),
      );
      await _pumpToday(tester, brief: brief, pauses: _Pauses());

      expect(find.text('On a break until Mon 5 Oct'), findsOneWidget);
      expect(find.text('Upper body A'), findsOneWidget);
    });

    testWidgets(
      'the week counts a break day as planned only when it was trained',
      (tester) async {
        final brief = _Brief(
          TrainingAvailability.available,
          week: [
            for (var i = 0; i < 7; i++)
              TodayWeekDay.fromJson({
                'local_date': const [
                  '2026-09-28',
                  '2026-09-29',
                  '2026-09-30',
                  '2026-10-01',
                  '2026-10-02',
                  '2026-10-03',
                  '2026-10-04',
                ][i],
                // Monday was a break day the athlete trained on; Tuesday a break day they rested.
                'paused': i < 2,
                'planned': i != 1,
                'trained': i == 0,
              }),
          ],
        );
        expect(brief.week[1].paused, isTrue);
        expect(brief.week[1].planned, isFalse);
        expect(
          TodayWeekDay.fromJson({'local_date': '2026-10-02'}).paused,
          isFalse,
        );
        await _pumpToday(tester, brief: brief, pauses: _Pauses());
        expect(find.textContaining('1 of 6'), findsWidgets);
      },
    );

    testWidgets('a "can\'t train" check-in makes today a rest day', (
      tester,
    ) async {
      final brief = _Brief(
        TrainingAvailability.fromJson(
          _availabilityJson(status: 'unavailable_today', unavailable: true),
        ),
      );
      await _pumpToday(tester, brief: brief, pauses: _Pauses());
      expect(find.byKey(const ValueKey('today-unavailable')), findsOneWidget);
      expect(find.text('Upper body A'), findsNothing);
      expect(find.byKey(const ValueKey('take-break')), findsOneWidget);
    });

    testWidgets('two "can\'t train" days offer a break the athlete taps', (
      tester,
    ) async {
      final brief = _Brief(
        TrainingAvailability.fromJson(
          _availabilityJson(
            status: 'unavailable_today',
            unavailable: true,
            offer: true,
          ),
        ),
      );
      final pauses = _Pauses();
      await _pumpToday(tester, brief: brief, pauses: pauses);
      expect(find.text('Taking a few days off?'), findsOneWidget);
      expect(pauses.starts, isEmpty);

      await tester.tap(find.byKey(const ValueKey('break-offer-set')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('break-confirm')), findsOneWidget);
      expect(pauses.starts, isEmpty);

      brief.availability = TrainingAvailability.fromJson(
        _availabilityJson(
          status: 'paused',
          paused: true,
          pause: {
            ..._pauseJson(start: '2026-10-02', end: '2026-10-08'),
            'id': 'pause-new',
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('break-confirm')));
      await tester.pumpAndSettle();
      expect(pauses.starts, hasLength(1));
      expect(find.text('On a break until Thu 8 Oct'), findsOneWidget);
      // Set a moment ago: the card offers Undo, which asks nothing.
      expect(find.text('Undo'), findsOneWidget);
      brief.availability = TrainingAvailability.available;
      await tester.ensureVisible(find.text('Undo'));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(pauses.ends, ['pause-new']);
      expect(find.text('On a break until Thu 8 Oct'), findsNothing);
    });

    testWidgets('an upcoming break and the first day back are shown', (
      tester,
    ) async {
      final brief = _Brief(
        TrainingAvailability.fromJson(
          _availabilityJson(
            pause: _pauseJson(start: '2026-10-04', running: false),
            returning: {'pause_id': 'pause-0', 'last_paused_day': '2026-09-30'},
          ),
        ),
      );
      await _pumpToday(tester, brief: brief, pauses: _Pauses());
      expect(find.text('Break starts Sun 4 Oct'), findsOneWidget);
      expect(find.text('Cancel break'), findsOneWidget);
      expect(find.byKey(const ValueKey('first-day-back')), findsOneWidget);
      expect(find.text('Upper body A'), findsOneWidget);
    });
  });

  group('Train', () {
    testWidgets('paused days are paused, never due; End break early works', (
      tester,
    ) async {
      final pauses = _Pauses();
      await _pumpTrain(
        tester,
        hub: _hub(
          availability: TrainingAvailability.fromJson(
            _availabilityJson(
              status: 'paused',
              paused: true,
              pause: _pauseJson(),
            ),
          ),
          paused: {for (var d = 1; d <= 5; d++) DateTime(2026, 10, d)},
        ),
        pauses: pauses,
      );

      expect(
        find.bySemanticsLabel(RegExp(r'^Friday 2 October, on a break, today$')),
        findsOneWidget,
      );
      expect(find.text('On a break until Mon 5 Oct'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);
      expect(find.byKey(const ValueKey('take-break')), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('break-end')));
      await tester.tap(find.byKey(const ValueKey('break-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End break'));
      await tester.pumpAndSettle();
      expect(pauses.ends, ['pause-1']);
    });

    testWidgets(
      'a can\'t-train day is not due or counted, and its workout can still start',
      (tester) async {
        final base = _hub();
        final today = DateTime(2026, 10, 2);
        await _pumpTrain(
          tester,
          hub: _hub(
            availability: TrainingAvailability.fromJson(
              _availabilityJson(status: 'unavailable_today', unavailable: true),
            ),
            unavailable: {today},
          ),
          pauses: _Pauses(),
        );
        const weekday = 'Friday 2 October';
        // The day reads as a rest day, not a planned one.
        expect(
          find.bySemanticsLabel(RegExp('^$weekday, (?!.*planned).*today\$')),
          findsOneWidget,
        );
        // The athlete may change their mind: the workout still opens.
        if (base.workoutForWeekday(today.weekday) != null) {
          expect(find.text('Start workout'), findsOneWidget);
        }
      },
    );

    testWidgets('a normal day offers Taking a break', (tester) async {
      await _pumpTrain(tester, hub: _hub(), pauses: _Pauses());
      expect(find.byKey(const ValueKey('take-break')), findsOneWidget);
    });
  });
}
