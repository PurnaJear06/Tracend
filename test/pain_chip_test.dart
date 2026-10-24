import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/readiness/pain_check.dart';
import 'package:tracend/features/readiness/pain_report_queue.dart';
import 'package:tracend/features/readiness/pain_reporting.dart';
import 'package:tracend/features/readiness/safety_acknowledgements.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/workout_draft.dart';
import 'package:tracend/features/train/workout_repository.dart';

import 'day_adjustment_fixtures.dart';
import 'live_activity/fake_workout_activity_bridge.dart';
import 'pain_fakes.dart';

/// "Pain or discomfort" during a workout (UX_FLOWS.md section 6): the three
/// outcomes, the swap it offers without a connection, and a report that
/// cannot be sent yet.

const _plan = PlannedWorkout(
  id: 'w-upper-a',
  name: 'Upper A',
  objective: 'Press.',
  estimatedMinutes: 45,
  exercises: [
    PlannedExercise(
      order: 1,
      name: 'Bench press',
      setCount: 3,
      repMin: 6,
      repMax: 8,
      targetRpe: 8,
      targetLoadKg: 60,
    ),
    PlannedExercise(
      order: 2,
      name: 'Barbell row',
      setCount: 3,
      repMin: 8,
      repMax: 10,
      targetRpe: 8,
      targetLoadKg: 50,
    ),
  ],
);

class _Alerts implements RestAlertScheduler {
  @override
  Future<bool> scheduleRestAlert(int seconds) async => true;

  @override
  Future<void> cancelRestAlert() async {}
}

class _Notifications implements NotificationRepository {
  @override
  Future<NotificationPreferences> load() async => NotificationPreferences(
    authorizationStatus: 'authorized',
    dailyCheckIn: false,
    weeklyReview: false,
    restTimerAlertsEnabled: false,
  );

  @override
  Future<NotificationPreferences> configure({
    required bool dailyCheckIn,
    required bool weeklyReview,
    required bool restTimerAlertsEnabled,
  }) => load();
}

class _Server extends FixtureWorkoutRepository {
  final syncs = <Map<String, dynamic>>[];

  @override
  Future<void> sync(
    String sessionId,
    int revision,
    Map<String, dynamic> draft,
  ) async => syncs.add(draft);
}

/// Today as the server describes it, with a gentler shoulder exercise for the
/// bench press.
Map<String, dynamic> _day({bool withSwap = true}) => {
  ...adjustmentJson(
    kind: 'none',
    status: 'none',
    band: 'green',
    triggers: const [],
    confidence: 'high',
    missing: const [],
    exercises: const [bench, row],
  ),
  'schema_version': '1.1',
  'joint_states': <Object>[],
  'exercise_joint_options': [
    {
      'exercise_order': 1,
      'name': 'Bench press',
      'joint_options': {
        'knee': null,
        'back': null,
        'shoulder': withSwap
            ? {'slug': 'machine-chest-press', 'name': 'Machine chest press'}
            : null,
      },
    },
  ],
};

class _Harness {
  _Harness({bool withSwap = true})
    : readiness = DayAdjustmentController(
        repository: FakeDayAdjustmentRepository(_day(withSwap: withSwap)),
      ) {
    reporting = PainReporting(
      repository: pain,
      readiness: readiness,
      userId: 'athlete-1',
    );
  }

  final server = _Server();
  final pain = FakePainCheckRepository();
  final DayAdjustmentController readiness;
  late final PainReporting reporting;
}

Future<void> _open(WidgetTester tester, _Harness h) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await h.readiness.load(localToday: DateTime(2026, 10, 2));
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: ActiveWorkoutScreen(
        workout: _plan,
        repository: h.server,
        restAlerts: _Alerts(),
        notifications: _Notifications(),
        activity: FakeWorkoutActivityBridge(),
        lockScreenNumbers: () async => false,
        clock: () => DateTime(2026, 10, 2, 9),
        pain: h.reporting,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapLabel(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.bySemanticsLabel(label).first);
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel(label).first);
  await tester.pumpAndSettle();
}

/// Opens the sheet and answers it.
Future<void> _check(
  WidgetTester tester, {
  required String where,
  required int strength,
  bool sharp = false,
  bool numb = false,
}) async {
  await _tapLabel(tester, 'Pain or discomfort');
  await _tapLabel(tester, 'Where?: $where');
  await _tapLabel(tester, 'Pain $strength of 10');
  await _tapLabel(
    tester,
    'Was it sharp or sudden, or did you feel a pop?: ${sharp ? 'Yes' : 'No'}',
  );
  await _tapLabel(tester, 'Any numbness or tingling?: ${numb ? 'Yes' : 'No'}');
  await tester.ensureVisible(find.text('Check this exercise'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Check this exercise'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pain of 1 to 3 says keep it light and continues', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = _Harness();
    await _open(tester, h);
    await _check(tester, where: 'Shoulder', strength: 2);
    expect(find.text('Keep it light'), findsOneWidget);
    expect(
      find.textContaining('Keep going only if it stays at 3 or below'),
      findsOneWidget,
    );
    final report = h.pain.reports.single;
    expect(report.area, PainArea.shoulder);
    expect(report.severity, 2);
    expect(
      report.redFlags,
      isNull,
      reason: 'only two of the ten questions were asked, so none is claimed',
    );
    expect(report.localDate, '2026-10-02', reason: "the server's day");
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Pain noted'), findsOneWidget);
    expect(find.text('Bench press'), findsWidgets);
    handle.dispose();
  });

  testWidgets('pain of 4 to 6 offers the gentler exercise, even offline', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = _Harness();
    h.pain.failure = PainCheckFailure.retry;
    await _open(tester, h);
    await _check(tester, where: 'Shoulder', strength: 5);
    expect(find.text('Stop this exercise for today'), findsOneWidget);
    expect(
      find.text(
        'Try Machine chest press instead, in a range that stays pain-free.',
      ),
      findsOneWidget,
    );
    expect(find.text('Use Machine chest press'), findsOneWidget);
    expect(find.textContaining('Saved on this phone'), findsOneWidget);
    // The report waits on the phone with its idempotency key.
    final waiting = await h.reporting.state();
    expect(waiting.waiting.single.severity, 5);

    await tester.tap(find.text('Use Machine chest press'));
    await tester.pumpAndSettle();
    expect(find.text('Machine chest press'), findsWidgets);
    expect(find.text('Bench press'), findsNothing);
    handle.dispose();
  });

  testWidgets('without a gentler exercise the choice is to skip', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = _Harness(withSwap: false);
    await _open(tester, h);
    await _check(tester, where: 'Shoulder', strength: 4);
    expect(find.text('Skip it for today.'), findsOneWidget);
    expect(find.textContaining('Use '), findsNothing);
    await tester.tap(find.text('Skip this exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Exercise 1 of 2, skipped'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('pain of 7 or more stops the exercise with the referral that '
      'cannot be closed without a choice', (tester) async {
    final handle = tester.ensureSemantics();
    final h = _Harness();
    await _open(tester, h);
    await _check(tester, where: 'Shoulder', strength: 8);
    expect(find.text('Stop this exercise'), findsOneWidget);
    expect(find.text('Get this checked today'), findsOneWidget);
    expect(find.text('Skip this exercise'), findsOneWidget);
    expect(find.text('End workout'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(
      find.textContaining('Use '),
      findsNothing,
      reason: 'no swap offered',
    );
    // The scrim does not close it.
    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();
    expect(find.text('Stop this exercise'), findsOneWidget);

    await tester.tap(find.text('Skip this exercise'));
    await tester.pumpAndSettle();
    // Read here, so Today does not open the same referral again.
    final preferences = await SharedPreferences.getInstance();
    expect(
      SafetyAcknowledgements(preferences, userId: 'athlete-1').isAcknowledged(
        SafetyAcknowledgements.keyOf('2026-10-02', 'clinician_today'),
      ),
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('a yes to either red-flag question routes out at any strength', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = _Harness();
    await _open(tester, h);
    await _check(tester, where: 'Shoulder', strength: 2, numb: true);
    expect(find.text('Stop this exercise'), findsOneWidget);
    expect(h.pain.reports.single.redFlags, ['numb_weak_limb']);
    handle.dispose();
  });

  testWidgets('a red flag that cannot be sent is kept, told and not dropped', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = _Harness();
    h.pain.failure = PainCheckFailure.retry;
    await _open(tester, h);
    await _check(tester, where: 'Shoulder', strength: 3, sharp: true);
    // The referral is worked out on the phone, and the report waits.
    expect(find.text('Get this checked today'), findsOneWidget);
    expect(
      find.textContaining('must be sent today or tomorrow'),
      findsOneWidget,
    );
    expect((await h.reporting.state()).waiting.single.redFlags, [
      'pop_or_sudden',
    ]);

    // Back online, the next drain delivers it once, with its first key.
    final key = (await h.reporting.state()).waiting.single.idempotencyKey;
    h.pain.failure = null;
    await tester.tap(find.text('Skip this exercise'));
    await tester.pumpAndSettle();
    final left = await h.reporting.drain();
    expect(left.isEmpty, isTrue);
    expect(h.pain.reports.last.idempotencyKey, key);
    handle.dispose();
  });

  testWidgets('a report the server refuses is said, not forgotten', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = _Harness();
    h.pain.failure = PainCheckFailure.refused;
    await _open(tester, h);
    await _check(tester, where: 'Shoulder', strength: 6);
    expect(find.textContaining('could not record this report'), findsOneWidget);
    final state = await h.reporting.state();
    expect(state.refused, hasLength(1));
    expect(state.waiting, isEmpty);
    // Kept on the phone as refused, with the report's own answers.
    final preferences = await SharedPreferences.getInstance();
    final stored = jsonDecode(
      preferences.getString(PainReportQueue.storageKeyFor('athlete-1'))!,
    );
    expect((stored as List).single, containsPair('refused', true));
    expect(stored.single, containsPair('severity', 6));
    handle.dispose();
  });

  testWidgets('the sheet will not save an unanswered check', (tester) async {
    final handle = tester.ensureSemantics();
    final h = _Harness();
    await _open(tester, h);
    await _tapLabel(tester, 'Pain or discomfort');
    await tester.ensureVisible(find.text('Check this exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check this exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Answer each question to continue.'), findsOneWidget);
    expect(h.pain.reports, isEmpty);
    handle.dispose();
  });

  group('swapping an exercise during the workout', () {
    test('logs as a substituted performance for pain, with no load', () {
      final draft = ExerciseDraft(_plan.exercises.first);
      expect(draft.swapFields, isEmpty);
      expect(
        draft.swapForPain(
          name: 'Machine chest press',
          slug: 'machine-chest-press',
        ),
        isTrue,
      );
      expect(draft.exercise.name, 'Machine chest press');
      expect(draft.exercise.targetLoadKg, isNull);
      expect(draft.swapFields, {
        'performance_kind': 'substituted',
        'performed_name': 'Machine chest press',
        'substitution_reason': 'pain',
      });
    });

    test('is refused once a set has an entry', () {
      final draft = ExerciseDraft(_plan.exercises.first);
      draft.sets.first.load = '60';
      expect(draft.swapForPain(name: 'Machine chest press'), isFalse);
      expect(draft.exercise.name, 'Bench press');
    });
  });
}
