import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/shared/widgets/trajectory_trend.dart';

Widget _wrap(Widget child, {bool reduceMotion = false}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      extensions: const [TracendColors.dark],
    ),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: SizedBox(width: 340, child: child),
          ),
        ),
      ),
    ),
  );
}

HealthDay _day(DateTime date, {double? hrv, int? sleep, double? rhr}) =>
    HealthDay(
      date: date,
      presentMetrics: {
        if (hrv != null) HealthMetric.hrvSdnn,
        if (sleep != null) HealthMetric.sleep,
        if (rhr != null) HealthMetric.restingHeartRate,
      },
      hrvSdnnMs: hrv,
      sleepMinutes: sleep,
      restingHeartRateBpm: rhr,
    );

/// Builds a history of [days.length] consecutive days ending 2026-08-24.
HealthHistory _history(List<(double?, int?, double?)> days) {
  return HealthHistory([
    for (var i = 0; i < days.length; i++)
      _day(
        DateTime(2026, 8, 24).subtract(Duration(days: days.length - 1 - i)),
        hrv: days[i].$1,
        sleep: days[i].$2,
        rhr: days[i].$3,
      ),
  ]);
}

void main() {
  group('trendSeriesFor', () {
    test('returns null for an empty history', () {
      expect(trendSeriesFor(const HealthHistory([])), isNull);
    });

    test('returns null with fewer than four recorded days', () {
      final history = _history([
        (42, null, null),
        (45, null, null),
        (44, null, null),
      ]);
      expect(trendSeriesFor(history), isNull);
    });

    test('selects HRV with four or more recorded days', () {
      final history = _history([
        (42, 460, 58),
        (45, 455, 57),
        (44, 470, 59),
        (48, 462, 56),
        (47, 468, 57),
        (51, 472, 55),
        (53, 480, 54),
      ]);
      final series = trendSeriesFor(history)!;
      expect(series.metric, TrendMetric.hrv);
      expect(series.points, hasLength(7));
      expect(series.windowStart, DateTime(2026, 8, 18));
      expect(series.windowEnd, DateTime(2026, 8, 24));
    });

    test('falls back to sleep when HRV is sparse', () {
      final history = _history([
        (42, 460, null),
        (null, 455, null),
        (null, 470, null),
        (null, 462, null),
        (null, 468, null),
        (null, 472, null),
        (null, 480, null),
      ]);
      final series = trendSeriesFor(history)!;
      expect(series.metric, TrendMetric.sleep);
      expect(series.points, hasLength(7));
    });

    test('falls back to resting HR when HRV and sleep are sparse', () {
      final history = _history([
        (42, 460, 58),
        (null, null, 57),
        (null, null, 59),
        (null, null, 56),
        (null, null, 57),
        (null, null, 55),
        (null, null, 54),
      ]);
      final series = trendSeriesFor(history)!;
      expect(series.metric, TrendMetric.restingHeartRate);
      expect(series.points, hasLength(7));
    });

    test('anchors the window to the latest stored day', () {
      // Six old HRV days, then six empty days: the 7-day window ending at the
      // latest stored day holds no HRV at all, so no trend may be drawn even
      // though the history has plenty of HRV overall.
      final history = _history([
        (42, null, null),
        (45, null, null),
        (44, null, null),
        (48, null, null),
        (47, null, null),
        (51, null, null),
        (null, null, null),
        (null, null, null),
        (null, null, null),
        (null, null, null),
        (null, null, null),
        (null, null, null),
      ]);
      expect(trendSeriesFor(history), isNull);
    });

    test('keeps real gaps instead of inventing missing days', () {
      final history = _history([
        (42, null, null),
        (45, null, null),
        (null, null, null),
        (48, null, null),
        (null, null, null),
        (null, null, null),
        (53, null, null),
      ]);
      final series = trendSeriesFor(history)!;
      expect(series.points, hasLength(4));
      expect(series.points.map((p) => p.date.day), [18, 19, 21, 24]);
    });
  });

  group('TrajectoryTrend', () {
    final fullHistory = _history([
      (42, null, null),
      (45, null, null),
      (44, null, null),
      (48, null, null),
      (47, null, null),
      (51, null, null),
      (53, null, null),
    ]);

    testWidgets('draws a 7-day HRV trend with real labels', (tester) async {
      await tester.pumpWidget(_wrap(TrajectoryTrend(history: fullHistory)));
      // Bounded pumps: the NOW-dot pulse is an intentional infinite loop.
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('7-DAY TREND'), findsOneWidget);
      expect(find.text('HRV · ms'), findsOneWidget);
      expect(find.text('53 ms'), findsOneWidget);
      expect(find.text('+11 ms vs first day'), findsOneWidget);
      expect(find.text('18 Aug'), findsOneWidget);
      expect(find.text('24 Aug'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('shows the cold-start state with fewer than four days', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(TrajectoryTrend(history: _history([(42, null, null)]))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Building baseline'), findsOneWidget);
      expect(
        find.text(
          'A 7-day trend appears once at least four days of health data '
          'exist. Sync Apple Health to start.',
        ),
        findsOneWidget,
      );
      expect(find.text('7-DAY TREND'), findsNothing);
    });

    testWidgets('shows the cold-start state for an empty history', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const TrajectoryTrend(history: HealthHistory([]))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Building baseline'), findsOneWidget);
    });

    testWidgets('renders statically under Reduce Motion', (tester) async {
      await tester.pumpWidget(
        _wrap(TrajectoryTrend(history: fullHistory), reduceMotion: true),
      );
      // pumpAndSettle completes only when nothing animates idle.
      await tester.pumpAndSettle();

      expect(find.text('7-DAY TREND'), findsOneWidget);
      expect(find.text('53 ms'), findsOneWidget);
    });

    testWidgets('exposes a semantics label describing the trend', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(TrajectoryTrend(history: fullHistory)));
      // Bounded pumps: the NOW-dot pulse is an intentional infinite loop.
      await tester.pump(const Duration(seconds: 2));

      expect(
        find.bySemanticsLabel(RegExp('7-day HRV trend, 18–24 Aug')),
        findsOneWidget,
      );
    });
  });
}
