import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

/// Real 7-day health trend (Chunk 6). Replaces the today-only
/// `TrajectoryLens`: plots recorded days from `daily_health_summaries` as a
/// bezier with area fill, real point dots, restrained min/max/date labels, a
/// draw-on reveal, and the NOW pulse on the latest recorded day (the single
/// sanctioned idle loop).
class TrajectoryTrend extends StatefulWidget {
  const TrajectoryTrend({required this.history, this.height = 140, super.key});

  final HealthHistory history;

  /// Plot area height (labels sit outside it).
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
        '${_formatValue(series.metric, first)} to '
        '${_formatValue(series.metric, last)}, '
        '${series.points.length} of 7 days recorded.';

    return PremiumGradientCard(
      glow: true,
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
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
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
                    child: _TrendDelta(
                      metric: series.metric,
                      first: first,
                      last: last,
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
                    final nowOffset = _pixelFor(
                      series,
                      series.points.last,
                      size,
                    );
                    return Stack(
                      children: [
                        _TrendPlot(series: series, controller: _controller),
                        Positioned(
                          left: 0,
                          top: 0,
                          child: _AxisLabel(text: _formatAxis(_maxOf(series))),
                        ),
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: _AxisLabel(text: _formatAxis(_minOf(series))),
                        ),
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
              const SizedBox(height: TracendSpacing.xxs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _AxisLabel(text: _dayLabel(series.windowStart)),
                  _AxisLabel(text: _dayLabel(series.windowEnd)),
                ],
              ),
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
        painter: _TrendPainter(
          series: series,
          line: colors.actionPrimary,
          grid: colors.borderSubtle,
          progress: 1,
        ),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => CustomPaint(
        painter: _TrendPainter(
          series: series,
          line: colors.actionPrimary,
          grid: colors.borderSubtle,
          progress: Curves.easeOutCubic.transform(controller.value),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.series,
    required this.line,
    required this.grid,
    required this.progress,
  });

  final TrendSeries series;
  final Color line;
  final Color grid;
  final double progress;

  static const _xInset = 16.0;
  static const _topInset = 12.0;
  static const _bottomInset = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || series.points.length < 2) return;

    final points = [
      for (final point in series.points) _pixelFor(series, point, size),
    ];

    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.35)
      ..strokeWidth = 0.5;
    for (final point in points) {
      canvas.drawLine(
        Offset(point.dx, _topInset - 4),
        Offset(point.dx, size.height - _bottomInset + 4),
        gridPaint,
      );
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final controlDx = (current.dx - previous.dx) / 2;
      path.cubicTo(
        previous.dx + controlDx,
        previous.dy,
        current.dx - controlDx,
        current.dy,
        current.dx,
        current.dy,
      );
    }

    final fill = Path()
      ..addPath(path, Offset.zero)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            line.withValues(alpha: 0.16 * progress),
            line.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );

    final metric = path.computeMetrics().single;
    final revealed = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      revealed,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < points.length - 1; i++) {
      final threshold = (points[i].dx - _xInset) / (size.width - 2 * _xInset);
      if (progress < threshold) continue;
      canvas.drawCircle(points[i], 2.5, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.series != series ||
      oldDelegate.line != line ||
      oldDelegate.grid != grid;
}

/// Maps a recorded point to pixels: x by day offset inside the 7-day window
/// (gaps stay visible), y by value inside the series min/max with padding.
Offset _pixelFor(TrendSeries series, TrendPoint point, Size size) {
  const xInset = 16.0;
  const topInset = 12.0;
  const bottomInset = 10.0;

  final dayOffset = point.date.difference(series.windowStart).inDays;
  final x = xInset + (dayOffset / 6) * (size.width - 2 * xInset);

  final min = _minOf(series);
  final max = _maxOf(series);
  final span = max - min;
  final normalized = span == 0 ? 0.5 : (point.value - min) / span;
  final y =
      (size.height - bottomInset) -
      normalized * (size.height - topInset - bottomInset);
  return Offset(x, y);
}

double _minOf(TrendSeries series) =>
    series.points.map((point) => point.value).reduce((a, b) => a < b ? a : b);

double _maxOf(TrendSeries series) =>
    series.points.map((point) => point.value).reduce((a, b) => a > b ? a : b);

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
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontSize: 10,
              letterSpacing: 1.4,
              color: color,
            ),
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

class _AxisLabel extends StatelessWidget {
  const _AxisLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      fontFamily: TracendFonts.monoFamily,
      fontSize: 9,
      color: context.tracendColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
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
              'exist. Sync Apple Health below to start.',
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
