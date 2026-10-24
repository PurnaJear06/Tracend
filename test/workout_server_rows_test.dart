import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/workout_draft.dart';
import 'package:tracend/features/train/workout_repository.dart';

import 'live_activity/fake_workout_activity_bridge.dart';

/// How many sets a started workout has is the server's to say: `start_workout`
/// reads the athlete's accepted same-day answer and creates the set rows. The
/// logger is built from the plan and then follows those rows, so no answer
/// pending on the phone, and no accepted row the phone does not know of,
/// can leave the logger and the server with different sets.

const _plan = PlannedWorkout(
  id: 'upper-a',
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

/// A server whose `start_workout` made [rows] set rows per exercise order.
class _Server extends FixtureWorkoutRepository {
  _Server(this.rows, {this.alreadyStarted = false});

  Map<int, int> rows;
  final bool alreadyStarted;
  var started = false;
  final syncs = <Map<String, dynamic>>[];

  /// Reading the session fails while this is true (offline).
  var failReads = false;

  /// The next sync is refused with 22023, as for a set number with no row.
  var refuseNext = false;

  /// Exercises the server made as a swap for a sore joint, by order: the
  /// name of the gentler exercise and its catalog slug.
  final swaps = <int, ({String name, String slug})>{};

  Map<String, dynamic> _session() => {
    'session_id': 'srv-1',
    'state': 'in_progress',
    'revision': 0,
    'idempotency_key': 'k',
    'local_date': '2026-10-03',
    'actual_started_at': '2026-10-03T09:00:00Z',
    'exercises': [
      for (final exercise in _plan.exercises)
        {
          'performance_id': 'perf-${exercise.order}',
          'order': exercise.order,
          'status': 'unknown',
          if (swaps[exercise.order] case final swap?) ...{
            'performance_kind': 'substituted',
            'performed_name': swap.name,
            'exercise_slug': swap.slug,
            'substitution_reason': 'pain',
          } else
            'performance_kind': 'prescribed',
          'sets': [
            for (var n = 1; n <= (rows[exercise.order] ?? 0); n++)
              {'number': n, 'completed': false},
          ],
        },
    ],
  };

  @override
  Future<String> start(
    PlannedWorkout workout,
    String idempotencyKey, {
    DateTime? localDate,
  }) async {
    started = true;
    return 'srv-1';
  }

  @override
  Future<Map<String, dynamic>?> loadSession(
    PlannedWorkout workout, {
    DateTime? localDate,
  }) async {
    if (started && failReads) throw Exception('offline');
    return started || alreadyStarted ? _session() : null;
  }

  @override
  Future<void> sync(
    String sessionId,
    int revision,
    Map<String, dynamic> draft,
  ) async {
    if (refuseNext) {
      refuseNext = false;
      throw const PostgrestException(message: 'no such set', code: '22023');
    }
    syncs.add(draft);
  }
}

int _benchSets(Map<String, dynamic> draft) =>
    (((draft['exercises'] as List).first as Map)['sets'] as List).length;

Future<void> _tapLabel(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label).first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Logs the current set and skips the rest that follows.
Future<void> _doneSet(WidgetTester tester, int number) async {
  // A note above the set (a swap, a pain-free range) can push it down.
  await tester.ensureVisible(find.text('Done set $number'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Done set $number'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await _tapLabel(tester, 'Skip rest');
}

Future<void> _open(WidgetTester tester, _Server server) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await _mount(tester, server);
}

/// Shows the logger over [server]; the draft it kept is read back.
Future<void> _mount(WidgetTester tester, _Server server) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: ActiveWorkoutScreen(
        workout: _plan,
        repository: server,
        restAlerts: _Alerts(),
        notifications: _Notifications(),
        activity: FakeWorkoutActivityBridge(),
        lockScreenNumbers: () async => false,
        clock: () => DateTime(2026, 10, 3, 9),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a fresh start takes the set rows the server made', (
    tester,
  ) async {
    final server = _Server({1: 2, 2: 3});
    await _open(tester, server);
    expect(server.started, isTrue);
    expect(find.text('Set 1 of 2'), findsOneWidget);
    expect(find.text('Set 1 of 3'), findsNothing);
    final payload = server.syncs.isEmpty ? null : server.syncs.last;
    if (payload != null) {
      final bench = (payload['exercises'] as List).first as Map;
      expect(bench['sets'], hasLength(2));
    }
  });

  testWidgets('a session already on the server opens with its rows', (
    tester,
  ) async {
    await _open(tester, _Server({1: 2, 2: 3}, alreadyStarted: true));
    expect(find.text('Set 1 of 2'), findsOneWidget);
  });

  testWidgets('a server with the plan\'s rows leaves the logger as planned', (
    tester,
  ) async {
    await _open(tester, _Server({1: 3, 2: 3}));
    expect(find.text('Set 1 of 3'), findsOneWidget);
  });

  group('the rows are read before anything is synced', () {
    testWidgets('a failed first read keeps the draft on the phone, then '
        'aligns and syncs', (tester) async {
      final handle = tester.ensureSemantics();
      final server = _Server({1: 2, 2: 3})..failReads = true;
      await _open(tester, server);
      expect(server.started, isTrue);
      // Rows unread: still the plan's sets, and nothing was sent.
      expect(find.text('Set 1 of 3'), findsOneWidget);
      expect(server.syncs, isEmpty);
      await _doneSet(tester, 1);
      expect(server.syncs, isEmpty, reason: 'still unread, still not sent');

      server.failReads = false;
      await tester.tap(find.text('Done set 2'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(server.syncs, isNotEmpty);
      expect(_benchSets(server.syncs.last), 2, reason: "the server's rows");
      handle.dispose();
    });

    testWidgets('a 22023 reads the rows again, aligns and sends once more', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final server = _Server({1: 3, 2: 3});
      await _open(tester, server);
      expect(find.text('Set 1 of 3'), findsOneWidget);
      // The server's rows turn out to be fewer than the phone assumed.
      server.rows = {1: 2, 2: 3};
      server.refuseNext = true;
      server.syncs.clear();
      await _tapLabel(tester, 'More weight');
      expect(server.syncs, hasLength(1));
      expect(_benchSets(server.syncs.single), 2);
      handle.dispose();
    });

    testWidgets('a set with entries that has no row is kept and needs '
        'attention', (tester) async {
      final handle = tester.ensureSemantics();
      final server = _Server({1: 3, 2: 3});
      await _open(tester, server);
      await _doneSet(tester, 1);
      await _doneSet(tester, 2);
      // Set 3 gets an entry, then the server turns out to hold two rows.
      await _tapLabel(tester, 'More weight');
      server.rows = {1: 2, 2: 3};
      server.refuseNext = true;
      server.syncs.clear();
      await _tapLabel(tester, 'One more rep');
      expect(server.syncs, isEmpty, reason: 'nothing is sent for a lost set');
      expect(find.text('Needs attention'), findsWidgets);
      expect(find.text('Set 3 of 3'), findsOneWidget, reason: 'kept');
      handle.dispose();
    });
  });

  group('an exercise the server left out or swapped for a sore joint', () {
    Map<String, dynamic> bench(Map<String, dynamic> draft) =>
        ((draft['exercises'] as List).first as Map).cast<String, dynamic>();

    testWidgets('a row with no sets is left out today: shown so, never '
        'logged, never given plan sets', (tester) async {
      final handle = tester.ensureSemantics();
      final server = _Server({1: 0, 2: 3}, alreadyStarted: true);
      await _open(tester, server);
      // The logger opens on the lift that can be logged, not on the one left
      // out.
      expect(find.text('Barbell row'), findsWidgets);
      expect(find.text('Set 1 of 3'), findsOneWidget);
      await _doneSet(tester, 1);
      expect(server.syncs, isNotEmpty);
      for (final payload in server.syncs) {
        final left = bench(payload);
        expect(left['sets'], isEmpty, reason: 'no set for a row that is not');
        expect(left['status'], 'unknown', reason: 'never inferred as skipped');
      }
      handle.dispose();
    });

    testWidgets('the left-out exercise page says so and offers no set', (
      tester,
    ) async {
      final server = _Server({1: 0, 2: 3}, alreadyStarted: true);
      await _open(tester, server);
      await tester.drag(find.byType(PageView), const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(find.text('Left out today'), findsWidgets);
      expect(find.textContaining('Done set'), findsNothing);
      expect(find.textContaining('Nothing is logged for it'), findsOneWidget);
    });

    testWidgets('a substituted row shows the swap and logs under its name', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final server = _Server({1: 3, 2: 3})
        ..swaps[1] = (name: 'Machine chest press', slug: 'machine-chest-press');
      await _open(tester, server);
      expect(find.text('Machine chest press'), findsWidgets);
      expect(find.text('Bench press'), findsNothing);
      await _doneSet(tester, 1);
      final sent = bench(server.syncs.last);
      expect(sent['performance_kind'], 'substituted');
      expect(sent['performed_name'], 'Machine chest press');
      expect(sent['substitution_reason'], 'pain');
      expect(sent['order'], 1, reason: "the server's own row");
      handle.dispose();
    });

    testWidgets('logged sets and a substitution the server made meanwhile '
        'need attention: no rename, nothing synced', (tester) async {
      final handle = tester.ensureSemantics();
      final server = _Server({1: 3, 2: 3});
      await _open(tester, server);
      await _doneSet(tester, 1);
      server.swaps[1] = (
        name: 'Machine chest press',
        slug: 'machine-chest-press',
      );
      server.refuseNext = true;
      server.syncs.clear();
      await _tapLabel(tester, 'More weight');

      expect(server.syncs, isEmpty, reason: 'nothing under another name');
      expect(find.text('Needs attention'), findsWidgets);
      expect(find.text('Bench press'), findsWidgets, reason: 'not renamed');
      expect(find.text('Machine chest press'), findsNothing);
      handle.dispose();
    });

    testWidgets('a restart with logged sets and a substitution on the server '
        'opens the draft as it was and needs attention', (tester) async {
      final handle = tester.ensureSemantics();
      final server = _Server({1: 3, 2: 3});
      await _open(tester, server);
      await _doneSet(tester, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox.shrink());

      server.swaps[1] = (
        name: 'Machine chest press',
        slug: 'machine-chest-press',
      );
      server.syncs.clear();
      await _mount(tester, server);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Bench press'), findsWidgets);
      expect(find.text('Machine chest press'), findsNothing);
      expect(find.text('Needs attention'), findsWidgets);
      expect(server.syncs, isEmpty, reason: 'the draft was kept, not sent');
      handle.dispose();
    });

    testWidgets('a prescribed row sends no swap', (tester) async {
      final handle = tester.ensureSemantics();
      final server = _Server({1: 3, 2: 3});
      await _open(tester, server);
      await _doneSet(tester, 1);
      final sent = bench(server.syncs.last);
      expect(sent.containsKey('performed_name'), isFalse);
      expect(sent.containsKey('performance_kind'), isFalse);
      handle.dispose();
    });
  });

  group('syncDraft fits the draft to the session before it sends', () {
    Map<String, dynamic> payload(List<Map<String, dynamic>> exercises) => {
      'session_id': 's',
      'exercises': exercises,
    };
    Map<String, dynamic> exercise(int order, List<Map<String, dynamic>> sets) =>
        {'order': order, 'status': 'unknown', 'sets': sets};
    Map<String, dynamic> blank(int number) => {
      'number': number,
      'completed': false,
    };
    Map<String, dynamic> done(int number) => {
      'number': number,
      'completed': true,
      'load_kg': '60',
      'repetitions': '8',
    };

    test('blank sets beyond the rows go; a set with data never does', () {
      final fitted = alignPayloadToRows(
        payload([
          exercise(1, [done(1), blank(2), blank(3)]),
          exercise(2, [done(1), done(2), done(3)]),
        ]),
        [
          {
            'order': 1,
            'sets': [{}, {}],
          },
          {
            'order': 2,
            'sets': [{}, {}],
          },
        ],
      );
      final exercises = (fitted['exercises'] as List).cast<Map>();
      expect(exercises[0]['sets'], hasLength(2));
      expect(exercises[1]['sets'], hasLength(3), reason: 'data is kept');
    });

    test('an exercise left out sends no set, and none with entries goes', () {
      final fitted = alignPayloadToRows(
        payload([
          exercise(1, [blank(1), blank(2), blank(3)]),
          exercise(2, [blank(1)]),
        ]),
        [
          {'order': 1, 'sets': <Object>[]},
          {
            'order': 2,
            'sets': [{}],
          },
        ],
      );
      final exercises = (fitted['exercises'] as List).cast<Map>();
      expect(exercises[0]['sets'], isEmpty);
      expect(exercises[1]['sets'], hasLength(1));
    });

    test('rows that cannot be read still drop trailing blank sets only', () {
      final fitted = alignPayloadToRows(
        payload([
          exercise(1, [done(1), blank(2), blank(3)]),
        ]),
        null,
      );
      expect(
        ((fitted['exercises'] as List).first as Map)['sets'],
        hasLength(1),
      );
    });

    test(
      'reads the rows, then sends the fitted draft and returns it',
      () async {
        final server = _Server({1: 2, 2: 3});
        final sent = await syncDraft(
          server,
          'srv-1',
          4,
          payload([
            exercise(1, [done(1), blank(2), blank(3)]),
            exercise(2, [blank(1), blank(2), blank(3)]),
          ]),
          readRows: () async => (server._session()['exercises'] as List),
        );
        expect(server.syncs, [sent]);
        final exercises = (sent['exercises'] as List).cast<Map>();
        expect(exercises[0]['sets'], hasLength(2));
        expect(exercises[1]['sets'], hasLength(3));
      },
    );

    test('a read that fails still sends, without the blank tail', () async {
      final server = _Server({1: 2, 2: 3});
      final sent = await syncDraft(
        server,
        'srv-1',
        4,
        payload([
          exercise(1, [done(1), blank(2), blank(3)]),
        ]),
        readRows: () async => throw Exception('offline'),
      );
      expect(server.syncs, [sent]);
      expect(((sent['exercises'] as List).first as Map)['sets'], hasLength(1));
    });
  });

  group('aligning an exercise to the server\'s rows', () {
    test('untouched trailing sets go, missing ones come', () {
      final draft = ExerciseDraft(_plan.exercises.first);
      draft.alignTo(2);
      expect(draft.sets, hasLength(2));
      draft.alignTo(4);
      expect(draft.sets, hasLength(4));
    });

    test('a set with something on it is never dropped', () {
      final draft = ExerciseDraft(_plan.exercises.first);
      draft.sets.last.load = '60';
      draft.alignTo(2);
      expect(draft.sets, hasLength(3));
    });

    test('restoring a draft or session follows its rows', () {
      final draft = ExerciseDraft(_plan.exercises.first)
        ..restore({
          'sets': [
            {'number': 1, 'completed': false},
            {'number': 2, 'completed': false},
          ],
        });
      expect(draft.sets, hasLength(2));
    });
  });
}
