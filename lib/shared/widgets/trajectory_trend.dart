import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/shared/widgets/micro_motion.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Which real HealthKit metric the trend plots. Priority order matters:
/// HRV first, then sleep duration, then resting heart rate.
enum TrendMetric { hrv, sleep, restingHeartRate }

String trendMetricLabel(TrendMetric metric) => switch (metric) {
  TrendMetric.hrv => 'HRV',
  TrendMetric.sleep => 'Sleep',
  TrendMetric.restingHeartRate => 'Resting HR',
};

String trendMetricUnit(TrendMetric metric) => switch (metric) {
  TrendMetric.hrv => 'ms',
  TrendMetric.sleep => 'min',
  TrendMetric.restingHeartRate => 'bpm',
};

double? _trendValueFor(HealthDay day, TrendMetric metric) => switch (metric) {
  TrendMetric.hrv => day.hrvSdnnMs,
  TrendMetric.sleep => day.sleepMinutes?.toDouble(),
  TrendMetric.restingHeartRate => day.restingHeartRateBpm,
};

/// One real recorded day on the trend. Missing days are simply absent —
/// never interpolated or invented.
@immutable
class TrendPoint {
  const TrendPoint({required this.date, required this.value});

  final DateTime date;
  final double value;
}

/// A plottable 7-day series selected from [HealthHistory].
@immutable
class TrendSeries {
  const TrendSeries({
    required this.metric,
    required this.points,
    required this.windowStart,
    required this.windowEnd,
  });

  final TrendMetric metric;

  /// Recorded points in date order (≥4, all non-null real values).
  final List<TrendPoint> points;

  /// First day of the 7-day window (anchored to the latest stored day).
  final DateTime windowStart;
  final DateTime windowEnd;
}

/// Selects the series to plot: window = the 7 days ending at the latest
/// stored day (anchoring avoids misleading sparse windows), metric priority
/// HRV → sleep → resting HR, first one with ≥4 recorded days wins. Returns
/// null when no honest trend exists — the widget then shows its cold-start
/// state instead of a fabricated curve.
TrendSeries? trendSeriesFor(HealthHistory history) {
  final days = history.days;
  if (days.isEmpty) return null;
  final latest = days.last.date;
  final windowEnd = DateTime(latest.year, latest.month, latest.day);
  final windowStart = windowEnd.subtract(const Duration(days: 6));
  final window = days.where((day) => !day.date.isBefore(windowStart)).toList();

  for (final metric in const [
    TrendMetric.hrv,
    TrendMetric.sleep,
    TrendMetric.restingHeartRate,
  ]) {
    final points = [
      for (final day in window)
        if (_trendValueFor(day, metric) != null)
          TrendPoint(date: day.date, value: _trendValueFor(day, metric)!),
    ];
    if (points.length >= 4) {
      return TrendSeries(
        metric: metric,
        points: points,
        windowStart: windowStart,
        windowEnd: windowEnd,
      );
    }
  }
  return null;
}

/// Real 7-day health trend (Chunk 6, redesigned 2026-09-03 as day columns):
/// plots recorded days from `daily_health_summaries` as magnitude columns on
/// a 7-slot window — one slot per calendar day, gaps left empty — with range
/// rails at the series' own min/max, a day-tick row with month rollover, a
/// calibration strip (range · recorded count · as-of stamp), a grow-on
/// reveal, and the NOW halo on the latest recorded day (the single
/// sanctioned idle loop).
class TrajectoryTrend extends StatefulWidget {
  const TrajectoryTrend({required this.history, this.height = 150, super.key});

  final HealthHistory history;

  /// Plot area height (day ticks and the calibration strip sit outside it).
  final double height;

  @override
  State<TrajectoryTrend> createState() => _TrajectoryTrendState();
}

class _TrajectoryTrendState extends State<TrajectoryTrend>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  static const _drawDuration = Duration(milliseconds: 1500);

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion ||
        _controller != null ||
        trendSeriesFor(widget.history) == null) {
      return;
    }
    _startDraw();
  }

  @override
  void didUpdateWidget(TrajectoryTrend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller == null &&
        !_reduceMotion &&
        trendSeriesFor(widget.history) != null) {
      _startDraw();
    }
  }

  void _startDraw() {
    final controller = AnimationController(vsync: this, duration: _drawDuration)
      ..forward();
    _controller = controller;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final series = trendSeriesFor(widget.history);
    if (series == null) return const _TrendColdStart();

    final colors = context.tracendColors;
    final first = series.points.first.value;
    final last = series.points.last.value;
    final label = trendMetricLabel(series.metric);
    final range = _rangeLabel(series.windowStart, series.windowEnd);
    final semantics =
        '7-day $label trend, $range: '
        '${_rangeText(series)}, '
        '${_formatValue(series.metric, last)} latest on '
        '${_dayLabel(series.points.last.date)}, '
        '${series.points.length} of 7 days recorded.';

    return PremiumGradientCard(
      glow: true,
      // Teal (the card's own tag color), not the default indigo: the
      // recovery readout above already carries the indigo glow, and two
      // same-glow evidence cards fought for the same visual voice.
      glowColor: colors.stateStable,
      child: Semantics(
        label: semantics,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(child: _TrendTag(label: '7-DAY TREND')),
                  const SizedBox(width: TracendSpacing.xs),
                  Flexible(
                    child: Text(
                      '$label · ${trendMetricUnit(series.metric)}',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontFamily: TracendFonts.monoFamily,
                        fontSize: 11,
                        color: colors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TracendSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatValue(series.metric, last),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: TracendFonts.monoFamily,
                      fontSize: 28,
                      letterSpacing: -0.8,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: TracendSpacing.xs),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.borderSubtle.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          child: _TrendDelta(
                            metric: series.metric,
                            first: first,
                            last: last,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TracendSpacing.xs),
              SizedBox(
                height: widget.height,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(constraints.maxWidth, widget.height);
                    final lastDay = series.points.last.date
                        .difference(series.windowStart)
                        .inDays;
                    final nowOffset = Offset(
                      _xInsetFor(size) +
                          (lastDay / 6) * (size.width - 2 * _xInsetFor(size)),
                      _yFor(series, series.points.last.value, size),
                    );
                    return Stack(
                      children: [
                        // Positioned.fill gives the childless CustomPaint
                        // tight constraints; under loose constraints it would
                        // size itself to Size.zero and paint nothing.
                        Positioned.fill(
                          child: _TrendPlot(
                            series: series,
                            controller: _controller,
                          ),
                        ),
                        // The NOW halo sits on the latest recorded day's
                        // column top, lifted off the plot edge.
                        Positioned(
                          left: nowOffset.dx - 5,
                          top: nowOffset.dy - 5,
                          child: MicroMotionPulse(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.accentNow,
                                border: Border.all(
                                  color: colors.canvas,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: colors.accentNow.withValues(
                                      alpha: 0.6,
                                    ),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              _DayTicks(
                windowStart: series.windowStart,
                windowEnd: series.windowEnd,
                recordedDays: {for (final point in series.points) point.date},
              ),
              const SizedBox(height: TracendSpacing.xxs),
              _CalibrationStrip(series: series),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendPlot extends StatelessWidget {
  const _TrendPlot({required this.series, required this.controller});

  final TrendSeries series;
  final AnimationController? controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final controller = this.controller;
    if (controller == null) {
      return CustomPaint(
        key: const ValueKey('trend-plot'),
        painter: _TrendPainter(
          series: series,
          column: colors.actionPrimary,
          terminal: colors.accentNow,
          rail: colors.borderSubtle,
          socket: colors.borderSubtle,
          progress: 1,
        ),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => CustomPaint(
        key: const ValueKey('trend-plot'),
        painter: _TrendPainter(
          series: series,
          column: colors.actionPrimary,
          terminal: colors.accentNow,
          rail: colors.borderSubtle,
          socket: colors.borderSubtle,
          progress: Curves.easeOutCubic.transform(controller.value),
        ),
      ),
    );
  }
}

/// Day-column painter: one slot per calendar day in the 7-day window.
/// Recorded days grow from the bottom rail toward their value; unrecorded
/// days leave a dim socket on the baseline (gaps stay visible, never
/// interpolated). Hairline rails at the series' padded min and max bound the
/// columns so the plot reads as an instrument, not a spreadsheet grid.
class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.series,
    required this.column,
    required this.terminal,
    required this.rail,
    required this.socket,
    required this.progress,
  });

  final TrendSeries series;
  final Color column;
  final Color terminal;
  final Color rail;
  final Color socket;
  final double progress;

  static const _xInset = 16.0;
  static const _columnWidth = 9.0;
  static const _minColumnHeight = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || series.points.isEmpty) return;

    // Range rails at the series' own extremes (padded): the top rail marks
    // the highest recorded value, the bottom rail the floor the columns
    // grow from.
    final topRailY = _yFor(series, _maxOf(series), size);
    final bottomRailY = size.height;
    final railPaint = Paint()
      ..color = rail.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(_xInset, topRailY),
      Offset(size.width - _xInset, topRailY),
      railPaint,
    );
    canvas.drawLine(
      Offset(_xInset, bottomRailY),
      Offset(size.width - _xInset, bottomRailY),
      railPaint,
    );

    // Day sockets for every unrecorded day in the window — the honest
    // marker that no data exists there.
    final socketPaint = Paint()..color = socket.withValues(alpha: 0.55);
    for (var day = 0; day <= 6; day++) {
      if (_valueOnDay(series, day) != null) continue;
      final x = _xInset + (day / 6) * (size.width - 2 * _xInset);
      canvas.drawCircle(Offset(x, size.height), 1.5, socketPaint);
    }

    for (final point in series.points) {
      final day = point.date.difference(series.windowStart).inDays;
      final x = _xInset + (day / 6) * (size.width - 2 * _xInset);
      final topY = _yFor(series, point.value, size);
      final isLast = point == series.points.last;
      final fullHeight = size.height - topY;
      // Grow-on reveal: a west-to-east wave — each column starts rising
      // 0.1 after the previous and every column, including the last,
      // completes exactly as progress reaches 1.
      final height = math.max(
        _minColumnHeight,
        fullHeight *
            Curves.easeOutCubic.transform(
              ((progress - 0.1 * day) / 0.4).clamp(0.0, 1.0),
            ),
      );
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x - _columnWidth / 2,
          size.height - height,
          _columnWidth,
          height,
        ),
        const Radius.circular(_columnWidth / 2),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = isLast
              ? terminal.withValues(alpha: 0.9 * progress)
              : column.withValues(alpha: 0.85 * progress),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.series != series ||
      oldDelegate.column != column ||
      oldDelegate.terminal != terminal ||
      oldDelegate.rail != rail ||
      oldDelegate.socket != socket;
}

/// Y pixel for a column of [value]: values map into the padded range
/// between the top inset and the baseline, so the tallest column clears
/// the plot edge and a series-min column still keeps a visible stub.
double _yFor(TrendSeries series, double value, Size size) {
  const topInset = 12.0;
  final min = _minOf(series);
  final max = _maxOf(series);
  final span = max - min;
  final normalized = span == 0 ? 0.5 : (value - min) / span;
  return size.height - normalized * (size.height - topInset);
}

double? _valueOnDay(TrendSeries series, int dayOffset) {
  for (final point in series.points) {
    if (point.date.difference(series.windowStart).inDays == dayOffset) {
      return point.value;
    }
  }
  return null;
}

double _xInsetFor(Size size) => 16.0;

double _minOf(TrendSeries series) =>
    series.points.map((point) => point.value).reduce((a, b) => a < b ? a : b);

double _maxOf(TrendSeries series) =>
    series.points.map((point) => point.value).reduce((a, b) => a > b ? a : b);

/// Human range text for the calibration strip and semantics label:
/// "54–155 ms" (or "1h 12m–1h 44m" style for sleep).
String _rangeText(TrendSeries series) {
  final min = _formatAxis(_minOf(series));
  final max = _formatAxis(_maxOf(series));
  final unit = trendMetricUnit(series.metric);
  return '$min–$max $unit';
}

String _formatValue(TrendMetric metric, double value) => switch (metric) {
  TrendMetric.hrv => '${value.round()} ms',
  TrendMetric.sleep => _formatMinutes(value.round()),
  TrendMetric.restingHeartRate => '${value.round()} bpm',
};

String _formatAxis(double value) => '${value.round()}';

String _formatMinutes(int minutes) =>
    '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _dayLabel(DateTime date) => '${date.day} ${_months[date.month - 1]}';

String _rangeLabel(DateTime start, DateTime end) => start.month == end.month
    ? '${start.day}–${end.day} ${_months[start.month - 1]}'
    : '${_dayLabel(start)} – ${_dayLabel(end)}';

class _TrendTag extends StatelessWidget {
  const _TrendTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = context.tracendColors.stateStable;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(CupertinoIcons.waveform_path_ecg, size: 13, color: color),
        const SizedBox(width: TracendSpacing.xxs),
        Flexible(
          child: Text(
            label,
            style: TracendTheme.labelCaps(context, color: color),
          ),
        ),
      ],
    );
  }
}

/// Signed change between the first and last recorded day. Direction is
/// reported neutrally — up/down is fact, not good/bad, because the answer
/// differs per metric (lower resting HR is better; higher HRV is better).
class _TrendDelta extends StatelessWidget {
  const _TrendDelta({
    required this.metric,
    required this.first,
    required this.last,
  });

  final TrendMetric metric;
  final double first;
  final double last;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final delta = last - first;
    final text = switch (metric) {
      TrendMetric.hrv => '${_signed(delta.round())} ms',
      TrendMetric.sleep => '${_signed(delta.round())}m',
      TrendMetric.restingHeartRate => '${_signed(delta.round())} bpm',
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (delta != 0)
          Icon(
            delta > 0
                ? CupertinoIcons.arrow_up_right
                : CupertinoIcons.arrow_down_right,
            size: 12,
            color: colors.textSecondary,
          ),
        if (delta != 0) const SizedBox(width: 2),
        Flexible(
          child: Text(
            delta == 0 ? 'no change · 7 days' : '$text vs first day',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontFamily: TracendFonts.monoFamily,
              fontSize: 11,
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  String _signed(int value) => '${value >= 0 ? '+' : ''}$value';
}

/// One tick per calendar day in the 7-day window. The first and last day
/// carry the month on rollover ("27 Aug", "1 Sep"); middle days show the
/// bare number; unrecorded days render dim so gaps stay legible.
class _DayTicks extends StatelessWidget {
  const _DayTicks({
    required this.windowStart,
    required this.windowEnd,
    required this.recordedDays,
  });

  final DateTime windowStart;
  final DateTime windowEnd;
  final Set<DateTime> recordedDays;

  @override
  Widget build(BuildContext context) {
    final color = context.tracendColors.textSecondary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const inset = 16.0;
        final dayTextStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontFamily: TracendFonts.monoFamily,
          fontSize: 9,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        return SizedBox(
          height: 14,
          width: double.infinity,
          child: Stack(
            children: [
              for (var day = 0; day <= 6; day++)
                Positioned(
                  left: inset + (day / 6) * (width - 2 * inset),
                  top: 4,
                  child: Transform.translate(
                    offset: Offset(-_tickAnchor(day) * _tickWidth(day), 0),
                    child: Text(
                      _tickText(day),
                      style: dayTextStyle?.copyWith(
                        color: _isRecorded(day)
                            ? color
                            : color.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static const _first = 0, _last = 6;

  /// Anchor: first day's label grows right from its tick, the last day's
  /// grows left, middle days center.
  double _tickAnchor(int day) => day == _first
      ? 0.0
      : day == _last
      ? 1.0
      : 0.5;

  double _tickWidth(int day) => day == _first || day == _last ? 30 : 10;

  bool _isRecorded(int day) => recordedDays.contains(_dateFor(day));

  DateTime _dateFor(int day) =>
      DateTime(windowStart.year, windowStart.month, windowStart.day + day);

  String _tickText(int day) {
    final date = _dateFor(day);
    final nextMonthRollover =
        day == _first || (day != 0 && date.day == 1) || day == _last;
    return nextMonthRollover
        ? '${date.day} ${_months[date.month - 1]}'
        : '${date.day}';
  }
}

/// Calibration strip under the day ticks: the series' own range, the
/// recorded-day count, and the as-of stamp (latest recorded day) — the
/// trust readout that dates the headline value.
class _CalibrationStrip extends StatelessWidget {
  const _CalibrationStrip({required this.series});

  final TrendSeries series;

  @override
  Widget build(BuildContext context) {
    final color = context.tracendColors.textSecondary;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontFamily: TracendFonts.monoFamily,
      fontSize: 9,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            '${_rangeText(series)} · '
            '${series.points.length} of 7 days',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: TracendSpacing.xs),
        Flexible(
          child: Text(
            'as of ${_dayLabel(series.points.last.date)} · Apple Health',
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// Honest cold-start surface: no curve is drawn until at least four recorded
/// days exist in the window (missing data lowers confidence, never faked).
class _TrendColdStart extends StatelessWidget {
  const _TrendColdStart();

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return PremiumGradientCard(
      child: Semantics(
        label: '7-day trend unavailable. Building baseline.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TrendTag(label: 'TREND'),
            const SizedBox(height: TracendSpacing.sm),
            Text(
              'Building baseline',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              'A 7-day trend appears once at least four days of health data '
              'exist. Sync Apple Health to start.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
