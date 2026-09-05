import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/train/widgets/week_rail_card.dart';
import 'package:tracend/features/train/workout_repository.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      extensions: const [TracendColors.dark],
    ),
    home: Scaffold(
      body: SingleChildScrollView(child: Center(child: child)),
    ),
  );
}

/// One isolated session so the card sits in the thin-history state.
final _sessionSeed = TrainingSessionSummary(
  name: 'Push day',
  date: DateTime(2026, 8, 18),
  durationSeconds: 2700,
);

ComputedMetrics _computed({
  double? acwr,
  double? dailyStrain,
  double? monotony,
}) => ComputedMetrics(
  scores: ComputedScores(
    acwr: acwr,
    dailyStrain: dailyStrain,
    trainingMonotony: monotony,
  ),
  baselines: const ComputedBaselines(),
  dataConfidence: 'medium',
);

TrainingSessionSummary _session(int day, {int? durationSeconds = 2700}) =>
    TrainingSessionSummary(
      name: 'Session $day',
      date: DateTime(2026, 8, day),
      durationSeconds: durationSeconds,
    );

/// Four or more sessions: the honest floor beneath a ratio verdict (finding
/// #6 — thin-history ACWR is noise). Two keeps the card in the
/// building-baseline state even when computed carries an ACWR value.
final _fullHistory = [
  // Monday 17, Tuesday 18, Wednesday 19, Thursday 20.
  TrainingSessionSummary(
    name: 'Push day',
    date: DateTime(2026, 8, 17),
    durationSeconds: 2700,
  ),
  TrainingSessionSummary(
    name: 'Pull day',
    date: DateTime(2026, 8, 18),
    durationSeconds: 3300,
  ),
  TrainingSessionSummary(
    name: 'Leg day',
    date: DateTime(2026, 8, 19),
    durationSeconds: 1800,
  ),
  TrainingSessionSummary(
    name: 'Push day',
    date: DateTime(2026, 8, 20),
    durationSeconds: 3000,
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  List<TrainingSessionSummary> sessions = const [],
  ComputedMetrics? computed,
  Set<DateTime> plannedDates = const {},
  Set<DateTime> completedDays = const {},
  DateTime? selectedDate,
  DateTime? markedDate,
  VoidCallback? onPreviousWeek,
  VoidCallback? onNextWeek,
}) async {
  await tester.pumpWidget(
    _wrap(
      WeekRailCard(
        selectedDate: selectedDate ?? DateTime(2026, 8, 19),
        onSelectedDate: (_) {},
        sessions: sessions,
        computed: computed,
        completedDays: completedDays,
        plannedDates: plannedDates,
        markedDate: markedDate,
        onPreviousWeek: onPreviousWeek,
        onNextWeek: onNextWeek,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('weekLoadDays', () {
    final weekStart = DateTime(2026, 8, 17);

    test('returns one slot per calendar day of the window', () {
      final days = weekLoadDays(const [], windowStart: weekStart);
      expect(days, hasLength(7));
      expect(days.first.date, weekStart);
      expect(days.last.date, DateTime(2026, 8, 23));
    });

    test('sums training minutes per day across sessions', () {
      final days = weekLoadDays([
        TrainingSessionSummary(
          name: 'Morning',
          date: DateTime(2026, 8, 18, 7, 30),
          durationSeconds: 1800,
        ),
        TrainingSessionSummary(
          name: 'Evening',
          date: DateTime(2026, 8, 18, 19),
          durationSeconds: 1200,
        ),
      ], windowStart: weekStart);
      expect(days[1].hasSession, isTrue);
      expect(days[1].minutes, 50);
      expect(days[0].hasSession, isFalse);
      expect(days[0].minutes, isNull);
    });

    test('marks a day present without minutes when duration is unknown', () {
      final days = weekLoadDays([
        TrainingSessionSummary(name: 'Unknown', date: DateTime(2026, 8, 19)),
      ], windowStart: weekStart);
      expect(days[2].hasSession, isTrue);
      expect(days[2].minutes, isNull);
    });

    test('null duration keeps a day with real minutes unknown too', () {
      // A session without a duration plus one with 30 minutes: the day's
      // total is unknown — never silently dropped to the known half.
      final days = weekLoadDays([
        TrainingSessionSummary(name: 'Unknown', date: DateTime(2026, 8, 19)),
        TrainingSessionSummary(
          name: 'Known',
          date: DateTime(2026, 8, 19, 20),
          durationSeconds: 1800,
        ),
      ], windowStart: weekStart);
      expect(days[2].hasSession, isTrue);
      expect(days[2].minutes, isNull);
    });

    test('ignores sessions outside the 7-day window', () {
      final days = weekLoadDays([
        TrainingSessionSummary(
          name: 'Before',
          date: DateTime(2026, 8, 16),
          durationSeconds: 3600,
        ),
        TrainingSessionSummary(
          name: 'After',
          date: DateTime(2026, 8, 24),
          durationSeconds: 3600,
        ),
      ], windowStart: weekStart);
      expect(days.every((day) => !day.hasSession), isTrue);
    });

    test('handles a 12-row payload by windowing to the current week', () {
      final sessions = [
        for (var i = 0; i < 12; i++)
          TrainingSessionSummary(
            name: 'Old $i',
            date: DateTime(2026, 8, 17).subtract(Duration(days: i * 2 + 1)),
            durationSeconds: 1800,
          ),
      ];
      // Every fixture lands before the window start, so none count.
      final days = weekLoadDays(sessions, windowStart: weekStart);
      expect(days.where((day) => day.hasSession), isEmpty);
    });
  });

  group('LoadBand unified 3-band mapping', () {
    final colors = TracendColors.dark;

    test('null maps to the building-baseline state', () {
      final band = LoadBand.forAcwr(null, colors);
      expect(band.label, 'Building baseline');
      expect(band.color, colors.accentAmber);
    });

    test('below 0.8 is low load', () {
      final band = LoadBand.forAcwr(0.5, colors);
      expect(band.label, 'Low load');
      expect(band.color, colors.accentAmber);
    });

    test('0.8 through 1.3 is optimal', () {
      for (final acwr in [0.8, 1.05, 1.15, 1.3]) {
        final band = LoadBand.forAcwr(acwr, colors);
        expect(band.label, 'Optimal', reason: 'ACWR $acwr');
        expect(band.color, colors.stateStable);
      }
    });

    test('above 1.3 is high load, label never escalates', () {
      for (final acwr in [1.4, 1.8, 2.5]) {
        final band = LoadBand.forAcwr(acwr, colors);
        expect(band.label, 'High load', reason: 'ACWR $acwr');
        expect(band.color, colors.stateAttention);
      }
    });
  });

  group('WeekRailCard verdict and band chip', () {
    testWidgets('shows the band chip and matches-normal copy at 1.15', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions: _fullHistory,
        computed: _computed(acwr: 1.15),
      );
      expect(find.text('Optimal'), findsOneWidget);
      expect(
        find.text('This week’s training matches your normal.'),
        findsOneWidget,
      );
    });

    testWidgets('below 0.8 reads as lighter', (tester) async {
      await _pump(
        tester,
        sessions: _fullHistory,
        computed: _computed(acwr: 0.5),
      );
      expect(find.text('Low load'), findsOneWidget);
      expect(
        find.text('This week is running lighter than your normal training.'),
        findsOneWidget,
      );
    });

    testWidgets('1.4 stays high load with the workable-range copy', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions: _fullHistory,
        computed: _computed(acwr: 1.4),
      );
      expect(find.text('High load'), findsOneWidget);
      expect(
        find.text(
          'This week is running heavier than your normal — still in a '
          'workable range.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('above 1.5 escalates the copy, never the label', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions: _fullHistory,
        computed: _computed(acwr: 1.8),
      );
      expect(find.text('High load'), findsOneWidget);
      expect(
        find.text(
          'This week is running much heavier than your normal — scale back '
          'to protect progress.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('thin history gates the verdict even when ACWR exists', (
      tester,
    ) async {
      // Finding #6: ACWR from a thin window is noise. Two sessions must
      // render the honest baseline state, never a ratio verdict.
      await _pump(
        tester,
        sessions: [
          TrainingSessionSummary(
            name: 'Push day',
            date: DateTime(2026, 8, 18),
            durationSeconds: 2700,
          ),
          TrainingSessionSummary(
            name: 'Pull day',
            date: DateTime(2026, 8, 20),
            durationSeconds: 3000,
          ),
        ],
        computed: _computed(acwr: 1.15),
      );
      expect(find.text('Building baseline'), findsOneWidget);
      expect(
        find.text(
          'Follow the plan as written — your load reading builds as you '
          'train.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Ratio'), findsNothing);
    });

    testWidgets('full history without ACWR still builds baseline', (
      tester,
    ) async {
      await _pump(tester, sessions: _fullHistory, computed: _computed());
      expect(find.text('Building baseline'), findsOneWidget);
      expect(
        find.text('Your load reading will appear as training is logged.'),
        findsOneWidget,
      );
    });

    testWidgets('null computed hides the verdict block entirely', (
      tester,
    ) async {
      await _pump(tester, sessions: _fullHistory);
      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(find.text('Building baseline'), findsNothing);
      // No verdict sentence anywhere — the block waits for the brief.
      expect(find.textContaining('load reading'), findsNothing);
    });
  });

  group('WeekRailCard chart', () {
    testWidgets('draws one column per session day plus dim sockets', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions: [
          _session(17, durationSeconds: 1800),
          _session(19, durationSeconds: 2700),
          _session(20, durationSeconds: 3300),
        ],
      );
      expect(find.byKey(const ValueKey('week-rail-plot')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('week-rail-plot')),
        paintsExactlyCountTimes(#drawRRect, 3),
      );
      // Four session-less unplanned days draw 1.5pt sockets.
      expect(
        find.byKey(const ValueKey('week-rail-plot')),
        paintsExactlyCountTimes(#drawCircle, 4),
      );
    });

    testWidgets('marks missed planned days with an amber dot', (tester) async {
      // Monday is planned but empty, so the FIRST circle painted is the
      // amber miss dot (the paints matcher requires the first circle to
      // match its arguments).
      await _pump(
        tester,
        sessions: [_session(19), _session(20)],
        plannedDates: {DateTime(2026, 8, 17)},
      );
      expect(
        find.byKey(const ValueKey('week-rail-plot')),
        paints..circle(radius: 3.5),
      );
      // Five session-less days total: one miss dot + four 1.5pt sockets.
      expect(
        find.byKey(const ValueKey('week-rail-plot')),
        paintsExactlyCountTimes(#drawCircle, 5),
      );
    });

    testWidgets('session-less unplanned days draw dim sockets', (tester) async {
      await _pump(tester, sessions: [_session(17), _session(19)]);
      expect(
        find.byKey(const ValueKey('week-rail-plot')),
        paints..circle(radius: 1.5),
      );
    });

    testWidgets('unknown-duration session day draws no column', (tester) async {
      // Sessions every day of the week; only Wednesday carries no duration,
      // so the ONLY circle painted is its enlarged baseline socket.
      await _pump(
        tester,
        sessions: [
          _session(17),
          _session(18),
          _session(19, durationSeconds: null),
          _session(20),
          _session(21),
          _session(22),
          _session(23),
        ],
      );
      // Six columns only — the duration-less Wednesday never invents height.
      expect(
        find.byKey(const ValueKey('week-rail-plot')),
        paintsExactlyCountTimes(#drawRRect, 6),
      );
      // It reads as one enlarged socket on the baseline instead.
      expect(
        find.byKey(const ValueKey('week-rail-plot')),
        paints..circle(radius: 3),
      );
      expect(
        find.byKey(const ValueKey('week-rail-plot')),
        paintsExactlyCountTimes(#drawCircle, 1),
      );
    });

    testWidgets('no halo without sessions; halo rides the terminal column', (
      tester,
    ) async {
      await _pump(tester, sessions: const []);
      expect(find.byKey(const ValueKey('week-rail-now-halo')), findsNothing);

      await _pump(tester, sessions: [_session(17), _session(20)]);
      expect(find.byKey(const ValueKey('week-rail-now-halo')), findsOneWidget);
    });

    testWidgets('terminal session without duration draws no halo', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions: [_session(17), _session(20, durationSeconds: null)],
      );
      expect(find.byKey(const ValueKey('week-rail-now-halo')), findsNothing);
    });
  });

  group('WeekRailCard calibration and mix advice', () {
    testWidgets('calibration strip reports range, count, and as-of date', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions: [
          _session(17, durationSeconds: 1800), // 30 min
          _session(19, durationSeconds: 2700), // 45 min
          _session(20, durationSeconds: 3960), // 66 min
        ],
      );
      expect(find.text('30–66 min · 3 of 7 days'), findsOneWidget);
      expect(find.text('as of 20 Aug · Tracend sessions'), findsOneWidget);
    });

    testWidgets('cold week reports no sessions logged', (tester) async {
      await _pump(tester, sessions: const []);
      expect(find.text('0 of 7 days'), findsOneWidget);
      expect(find.text('no sessions logged'), findsOneWidget);
    });

    testWidgets('low monotony shows the good-mix advice', (tester) async {
      await _pump(
        tester,
        sessions: _fullHistory,
        computed: _computed(acwr: 1.15, monotony: 1.8),
      );
      expect(find.text('Good mix of hard and easy days'), findsOneWidget);
      expect(
        find.byIcon(CupertinoIcons.check_mark_circled_solid),
        findsOneWidget,
      );
    });

    testWidgets('high monotony shows the vary-intensity advice', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions: _fullHistory,
        computed: _computed(acwr: 1.15, monotony: 2.5),
      );
      expect(
        find.text('Days are too similar — vary intensity'),
        findsOneWidget,
      );
      expect(
        find.byIcon(CupertinoIcons.exclamationmark_triangle_fill),
        findsOneWidget,
      );
    });

    testWidgets('monotony advice is gated on load history', (tester) async {
      await _pump(
        tester,
        sessions: [_sessionSeed],
        computed: _computed(acwr: 1.15, monotony: 2.5),
      );
      expect(find.textContaining('Days are too similar'), findsNothing);
    });

    testWidgets('ratio and day load render as one quiet mono line', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions: _fullHistory,
        computed: _computed(acwr: 1.15, dailyStrain: 42.0, monotony: 1.8),
      );
      expect(find.text('Ratio 1.15 · Day load 42.0'), findsOneWidget);
    });

    testWidgets(
      'full load strip never overflows at phone width (owner QA 2026-09-04)',
      (tester) async {
        // The one-row variant bled off the card on the owner's iPhone: the
        // advice + stats row only fit wide test surfaces. Reproduce the
        // worst case at real phone width — warning advice, ratio, and day
        // load all present at 390pt — and assert no layout exception.
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _pump(
          tester,
          sessions: _fullHistory,
          computed: _computed(
            acwr: 1.15,
            dailyStrain: 42.0,
            monotony: 2.5, // warning advice — the longest copy
          ),
        );
        expect(
          find.text('Days are too similar — vary intensity'),
          findsOneWidget,
        );
        expect(find.text('Ratio 1.15 · Day load 42.0'), findsOneWidget);
        final exception = tester.takeException();
        final detail = exception is FlutterError
            ? exception.toStringDeep()
            : exception?.toString();
        expect(exception, isNull, reason: 'phone-width overflow:\n$detail');
      },
    );

    testWidgets('thin history shows day load without the ratio', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions: [_sessionSeed],
        computed: _computed(dailyStrain: 42.0),
      );
      expect(find.text('Day load 42.0'), findsOneWidget);
      expect(find.textContaining('Ratio'), findsNothing);
    });

    testWidgets('empty scores hide the whole load strip', (tester) async {
      await _pump(tester, sessions: [_sessionSeed], computed: _computed());
      expect(find.textContaining('Ratio'), findsNothing);
      expect(find.textContaining('Day load'), findsNothing);
    });

    testWidgets('footnote explains the ratio only when it is shown', (
      tester,
    ) async {
      await _pump(
        tester,
        sessions: _fullHistory,
        computed: _computed(acwr: 1.15),
      );
      expect(
        find.text(
          'The ratio compares this week’s training load with your typical '
          'week. 1.0 means unchanged.',
        ),
        findsOneWidget,
      );

      await _pump(tester, sessions: [_sessionSeed], computed: _computed());
      expect(
        find.text(
          'The load ratio fills in as more weeks of training are logged.',
        ),
        findsOneWidget,
      );
    });
  });

  group('WeekRailCard day selection and slot markers', () {
    testWidgets('keeps the date-pill keys and reports the picked date', (
      tester,
    ) async {
      DateTime? picked;
      await tester.pumpWidget(
        _wrap(
          WeekRailCard(
            selectedDate: DateTime(2026, 8, 19),
            onSelectedDate: (date) => picked = date,
            sessions: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var day = 17; day <= 23; day++) {
        expect(find.byKey(ValueKey('date-pill-2026-08-$day')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('date-pill-2026-08-21')));
      expect(picked, DateTime(2026, 8, 21));
    });

    testWidgets('chevrons appear only when callbacks are provided', (
      tester,
    ) async {
      await _pump(tester, sessions: const []);
      expect(find.byKey(const ValueKey('date-strip-previous')), findsNothing);
      expect(find.byKey(const ValueKey('date-strip-next')), findsNothing);

      await _pump(
        tester,
        sessions: const [],
        onPreviousWeek: () {},
        onNextWeek: () {},
      );
      expect(find.byKey(const ValueKey('date-strip-previous')), findsOneWidget);
      expect(find.byKey(const ValueKey('date-strip-next')), findsOneWidget);
    });

    testWidgets('slots expose completed, planned, and marked semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        sessions: const [],
        completedDays: {DateTime(2026, 8, 18)},
        plannedDates: {DateTime(2026, 8, 20)},
        markedDate: DateTime(2026, 8, 17),
      );
      expect(find.bySemanticsLabel('Monday 17, highlighted'), findsOneWidget);
      expect(find.bySemanticsLabel('Tuesday 18, completed'), findsOneWidget);
      expect(find.bySemanticsLabel('Thursday 20, planned'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Wednesday 19, selected')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
