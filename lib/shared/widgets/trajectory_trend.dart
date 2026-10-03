import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// Which real HealthKit metric the trend plots. Priority order matters:
/// HRV first, then sleep duration, then resting heart rate.
enum TrendMetric { hrv, sleep, restingHeartRate }

String trendMetricLabel(TrendMetric metric) => switch (metric) {
  TrendMetric.hrv => 'Heart rate variability',
  TrendMetric.sleep => 'Sleep',
  TrendMetric.restingHeartRate => 'Resting heart rate',
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
/// state instead of a fabricated chart.
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

/// Today's data moment (DESIGN_SYSTEM.md §5.2): the real 7-day trend of one
/// Apple Health metric, drawn as one column per calendar day.
///
/// - A recorded day grows a rounded graphite column; the latest recorded
///   day's column is lime and carries the app's only idle loop, a soft ring
///   pulse.
/// - An unrecorded day leaves an empty socket on the baseline. Missing days
///   are never interpolated.
/// - Columns are scaled between the series' own minimum and maximum, which
///   hairline rails mark; the caption states that range, the recorded-day
///   count and the as-of date.
/// - Direction is reported neutrally: up or down is fact, not good or bad.
///
/// Motion follows [TracendMotionScope]: full motion grows the columns and
/// pulses the ring, Reduce Motion fades the chart in, static draws it still.
class TrajectoryTrend extends StatefulWidget {
  const TrajectoryTrend({required this.history, this.height = 132, super.key});

  final HealthHistory history;

  /// Plot area height (the day labels and caption sit outside it).
  final double height;

  @override
  State<TrajectoryTrend> createState() => _TrajectoryTrendState();
}

class _TrajectoryTrendState extends State<TrajectoryTrend>
    with TickerProviderStateMixin {
  AnimationController? _reveal;
  AnimationController? _pulse;
  TracendMotionLevel? _level;

  static const _growDuration = Duration(milliseconds: 1100);
  static const _pulsePeriod = Duration(milliseconds: 1600);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final level = TracendMotionScope.of(context);
    if (level == _level) return;
    _level = level;
    _configureMotion();
  }

  @override
  void didUpdateWidget(TrajectoryTrend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_reveal == null) _configureMotion();
  }

  void _configureMotion() {
    final level = _level ?? TracendMotionLevel.full;
    if (trendSeriesFor(widget.history) == null ||
        level == TracendMotionLevel.static) {
      _reveal?.dispose();
      _pulse?.dispose();
      _reveal = null;
      _pulse = null;
      return;
    }
    _reveal ??= AnimationController(
      vsync: this,
      duration: level == TracendMotionLevel.full
          ? _growDuration
          : TracendMotion.standard,
    )..forward();
    if (level == TracendMotionLevel.full) {
      _pulse ??= AnimationController(vsync: this, duration: _pulsePeriod)
        ..repeat(reverse: true);
    } else {
      _pulse?.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _reveal?.dispose();
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final series = trendSeriesFor(widget.history);
    if (series == null) return const _TrendColdStart();

    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final last = series.points.last;
    final label = trendMetricLabel(series.metric);
    final latestText = _formatValue(series.metric, last.value);
    final delta = _deltaText(series);
    final semantics =
        '7-day ${label.toLowerCase()} trend, '
        '${_rangeLabel(series.windowStart, series.windowEnd)}: '
        'range ${_rangeText(series)}, '
        '$latestText latest on ${_dayLabel(last.date)}, '
        '${series.points.length} of 7 days recorded. $delta.';
    final grows = _level == TracendMotionLevel.full;
    final reveal = _reveal;

    Widget chart = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.titleSmall),
        const SizedBox(height: TracendSpacing.xxs),
        Text(
          latestText,
          style: textTheme.displaySmall?.copyWith(
            fontFamily: TracendFonts.numericFamily,
            fontFeatures: const [FontFeature.tabularFigures()],
            height: 1.05,
          ),
        ),
        const SizedBox(height: TracendSpacing.xxs),
        _TrendDelta(series: series, text: delta),
        const SizedBox(height: TracendSpacing.md),
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: _TrendPlot(
            series: series,
            reveal: grows ? reveal : null,
            pulse: _pulse,
          ),
        ),
        const SizedBox(height: TracendSpacing.xs),
        _DayLabels(series: series),
        const SizedBox(height: TracendSpacing.sm),
        Text(
          'Range ${_rangeText(series)} · ${series.points.length} of 7 days '
          'recorded · As of ${_dayLabel(last.date)}, Apple Health',
          style: textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
    if (!grows && reveal != null) {
      // Reduce Motion: the chart crossfades in instead of growing.
      chart = FadeTransition(opacity: reveal, child: chart);
    }
    return PremiumGradientCard(
      child: Semantics(
        label: semantics,
        container: true,
        child: ExcludeSemantics(child: chart),
      ),
    );
  }
}

class _TrendPlot extends StatelessWidget {
  const _TrendPlot({
    required this.series,
    required this.reveal,
    required this.pulse,
  });

  final TrendSeries series;
  final Animation<double>? reveal;
  final Animation<double>? pulse;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reveal = this.reveal;
    final pulse = this.pulse;
    return AnimatedBuilder(
      animation: Listenable.merge([?reveal, ?pulse]),
      builder: (context, _) => CustomPaint(
        key: const ValueKey('trend-plot'),
        painter: _TrendPainter(
          series: series,
          column: colors.textPrimary.withValues(alpha: dark ? 0.34 : 0.22),
          latest: colors.accentSignal,
          ring: colors.accentSignalRing,
          rail: colors.borderHairline,
          socket: colors.borderSubtle,
          progress: reveal == null
              ? 1
              : Curves.easeOutCubic.transform(reveal.value),
          pulse: pulse?.value,
        ),
      ),
    );
  }
}

/// One slot per calendar day. Recorded days grow from the baseline toward
/// their value, staggered west to east; unrecorded days leave an empty
/// socket. Hairline rails mark the series' minimum and maximum.
class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.series,
    required this.column,
    required this.latest,
    required this.ring,
    required this.rail,
    required this.socket,
    required this.progress,
    required this.pulse,
  });

  final TrendSeries series;
  final Color column;

  /// Lime fill for the latest column.
  final Color latest;

  /// Lime stroke (3:1 or better in both themes) that outlines the latest
  /// column, so it holds its shape on a light surface.
  final Color ring;
  final Color rail;
  final Color socket;
  final double progress;

  /// 0–1 ring pulse phase, or null when the ring holds still.
  final double? pulse;

  /// The lowest recorded value still draws this share of the plot, so a
  /// series minimum never reads as zero.
  static const _floor = 0.22;
  static const _topInset = 8.0;
  static const _socketHeight = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || series.points.isEmpty) return;
    final slot = size.width / 7;
    final barWidth = math.min(28.0, slot * 0.62);
    final railPaint = Paint()
      ..color = rail
      ..strokeWidth = 1;
    final topRailY = size.height - _heightFor(_maxOf(series), size);
    final bottomRailY = size.height - _heightFor(_minOf(series), size);
    canvas.drawLine(
      Offset(0, topRailY),
      Offset(size.width, topRailY),
      railPaint,
    );
    if ((bottomRailY - topRailY).abs() > 1) {
      canvas.drawLine(
        Offset(0, bottomRailY),
        Offset(size.width, bottomRailY),
        railPaint,
      );
    }

    final socketPaint = Paint()
      ..color = socket
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final lastDate = series.points.last.date;
    for (var day = 0; day <= 6; day++) {
      final centerX = slot * day + slot / 2;
      final value = _valueOnDay(series, day);
      if (value == null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              centerX - barWidth / 2 + 0.75,
              size.height - _socketHeight + 0.75,
              barWidth - 1.5,
              _socketHeight - 1.5,
            ),
            const Radius.circular(_socketHeight / 2),
          ),
          socketPaint,
        );
        continue;
      }
      final grow = Curves.easeOutCubic.transform(
        ((progress - 0.08 * day) / 0.52).clamp(0.0, 1.0),
      );
      final height = math.max(2.0, _heightFor(value, size) * grow);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(
          centerX - barWidth / 2,
          size.height - height,
          barWidth,
          height,
        ),
        topLeft: Radius.circular(barWidth * 0.32),
        topRight: Radius.circular(barWidth * 0.32),
        bottomLeft: Radius.circular(barWidth * 0.2),
        bottomRight: Radius.circular(barWidth * 0.2),
      );
      final isLatest = _sameDay(_dayAt(series, day), lastDate);
      canvas.drawRRect(rect, Paint()..color = isLatest ? latest : column);
      if (isLatest && ring != latest) {
        canvas.drawRRect(
          rect.deflate(0.5),
          Paint()
            ..color = ring
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      if (isLatest && grow >= 1) {
        final pulse = this.pulse;
        final opacity = pulse == null ? 0.55 : 0.25 + 0.55 * pulse;
        canvas.drawRRect(
          rect.inflate(3.5),
          Paint()
            ..color = ring.withValues(alpha: opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  double _heightFor(double value, Size size) {
    final min = _minOf(series);
    final max = _maxOf(series);
    final span = max - min;
    final normalized = span == 0 ? 0.6 : (value - min) / span;
    final usable = size.height - _topInset;
    return usable * (_floor + (1 - _floor) * normalized);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.pulse != pulse ||
      oldDelegate.series != series ||
      oldDelegate.column != column ||
      oldDelegate.latest != latest ||
      oldDelegate.ring != ring ||
      oldDelegate.rail != rail ||
      oldDelegate.socket != socket;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The calendar date of slot [dayOffset] (calendar arithmetic, so a DST
/// change inside the window never shifts a slot).
DateTime _dayAt(TrendSeries series, int dayOffset) => DateTime(
  series.windowStart.year,
  series.windowStart.month,
  series.windowStart.day + dayOffset,
);

double? _valueOnDay(TrendSeries series, int dayOffset) {
  final date = _dayAt(series, dayOffset);
  for (final point in series.points) {
    if (_sameDay(point.date, date)) return point.value;
  }
  return null;
}

double _minOf(TrendSeries series) =>
    series.points.map((point) => point.value).reduce(math.min);

double _maxOf(TrendSeries series) =>
    series.points.map((point) => point.value).reduce(math.max);

/// "42–53 ms", or "6 h 50 min–7 h 42 min" for sleep.
String _rangeText(TrendSeries series) {
  final min = _minOf(series);
  final max = _maxOf(series);
  if (series.metric == TrendMetric.sleep) {
    return '${_formatMinutes(min.round())}–${_formatMinutes(max.round())}';
  }
  return '${min.round()}–${max.round()} ${trendMetricUnit(series.metric)}';
}

String _formatValue(TrendMetric metric, double value) => switch (metric) {
  TrendMetric.hrv => '${value.round()} ms',
  TrendMetric.sleep => _formatMinutes(value.round()),
  TrendMetric.restingHeartRate => '${value.round()} bpm',
};

String _formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

/// Neutral change from the first to the latest recorded day:
/// "Up 11 ms since 18 Aug", "Down 32 min since 18 Aug", "No change since …".
String _deltaText(TrendSeries series) {
  final first = series.points.first;
  final last = series.points.last;
  final since = 'since ${_dayLabel(first.date)}';
  final change = (last.value - first.value).round();
  if (change == 0) return 'No change $since';
  final amount = series.metric == TrendMetric.sleep
      ? _formatMinutes(change.abs())
      : '${change.abs()} ${trendMetricUnit(series.metric)}';
  return '${change > 0 ? 'Up' : 'Down'} $amount $since';
}

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

class _TrendDelta extends StatelessWidget {
  const _TrendDelta({required this.series, required this.text});

  final TrendSeries series;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final change = (series.points.last.value - series.points.first.value)
        .round();
    final icon = change == 0
        ? CupertinoIcons.arrow_right
        : change > 0
        ? CupertinoIcons.arrow_up_right
        : CupertinoIcons.arrow_down_right;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: TracendSpacing.xxs),
              child: Icon(icon, size: 14, color: colors.textSecondary),
            ),
          ),
          TextSpan(text: text),
        ],
      ),
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
    );
  }
}

/// One label per day slot, centered under its column: the day of the month,
/// with the latest recorded day in lime ink. Unrecorded days are dimmed.
class _DayLabels extends StatelessWidget {
  const _DayLabels({required this.series});

  final TrendSeries series;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final base = TracendTheme.numeric(
      colors,
      fontSize: 12,
      color: colors.textSecondary,
    );
    final latest = series.points.last.date;
    return Row(
      children: [
        for (var day = 0; day <= 6; day++)
          Expanded(
            child: Text(
              '${_dayAt(series, day).day}',
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: _sameDay(_dayAt(series, day), latest)
                  ? base.copyWith(
                      color: colors.accentSignalInk,
                      fontWeight: FontWeight.w800,
                    )
                  : base.copyWith(
                      color: _valueOnDay(series, day) != null
                          ? colors.textSecondary
                          : colors.textTertiary,
                    ),
            ),
          ),
      ],
    );
  }
}

/// Honest cold-start surface: no columns are drawn until at least four
/// recorded days exist in the window (missing data lowers confidence, never
/// faked).
class _TrendColdStart extends StatelessWidget {
  const _TrendColdStart();

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return PremiumGradientCard(
      child: Semantics(
        container: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                CupertinoIcons.chart_bar_alt_fill,
                size: 16,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(width: TracendSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Not enough data yet', style: textTheme.titleSmall),
                  const SizedBox(height: TracendSpacing.xxs),
                  Text(
                    'A 7-day trend appears once at least four days of health '
                    'data exist. Sync Apple Health to start.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
