import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

class DatedTrendValue {
  const DatedTrendValue(this.date, this.value);
  final DateTime date;
  final double value;
}

/// A computed regression overlay segment in chart date/value space.
///
/// The feature engine reports weight trends as OLS slopes in kg/day
/// (`ALGORITHMS.md` §5): a 7-day window (target−6…target) and a 28-day
/// window (target−27…target). R² exists ONLY for the 28-day window
/// (`weight_trend_r2_28d`) and must never gate the 7-day line.
class TrendOverlay {
  const TrendOverlay({
    required this.windowDays,
    required this.slopeKgPerDay,
    required this.start,
    required this.end,
    required this.lowConfidence,
  });

  final int windowDays;
  final double slopeKgPerDay;
  final DatedTrendValue start;
  final DatedTrendValue end;
  final bool lowConfidence;

  String get label => '$windowDays-day trend';
}

/// R² at or above this marks the 28-day fit trustworthy. Matches the
/// nutrition-change gate "28-day OLS R2 ≥ 0.3" (`ALGORITHMS.md` §7).
/// Below it — or when R² is missing — the 28-day line renders dashed and
/// labeled "low confidence". Never applied to the 7-day window, which has
/// no R² in the feature engine.
const lowConfidenceR2Threshold = 0.3;

/// Deterministically derives a trend-line segment from a server slope.
///
/// A slope alone has no intercept, so the line is anchored to the actual
/// confirmed measurements: it passes through the centroid (mean date, mean
/// weight) of the measurements inside the applicable window — the geometric
/// property of the OLS fit — and is drawn only within that window, clipped to
/// the chart range. No intercept is invented and nothing is extrapolated
/// beyond the window. Returns null when the window holds no measurement
/// evidence to anchor to.
///
/// Disclosed anchoring nuances (deliberate, no fabrication):
/// - The window ends at the LATEST CHART MEASUREMENT, not the brief's
///   `target_date`. When the most recent weigh-in predates the target date,
///   the drawn segment covers `[lastWeighIn−(windowDays−1), lastWeighIn]`
///   while the slope value describes `[target−(windowDays−1), target]`
///   (`ALGORITHMS.md` §5). The segment is shifted earlier, never invented.
/// - The centroid uses the displayed `body_measurements` dots only. The
///   server fit may additionally merge HealthKit weights from
///   `daily_health_summaries` for dates without a manual measurement, so the
///   drawn line can carry a small parallel offset from the exact server fit
///   while keeping the correct slope and real-data anchor.
///
/// [lowConfidence] is decided by the caller from the verified algorithm
/// semantics: only the 28-day window has an R² to gate on.
TrendOverlay? deriveTrendOverlay(
  List<DatedTrendValue> orderedValues, {
  required int windowDays,
  required double slopeKgPerDay,
  bool lowConfidence = false,
}) {
  if (orderedValues.isEmpty) return null;
  final chartStart = orderedValues.first.date;
  final windowEnd = orderedValues.last.date;
  final windowStart = windowEnd.subtract(Duration(days: windowDays - 1));
  final inWindow = orderedValues
      .where((value) => !value.date.isBefore(windowStart))
      .toList();
  if (inWindow.isEmpty) return null;

  var sumDays = 0.0;
  var sumWeight = 0.0;
  for (final value in inWindow) {
    sumDays += value.date.difference(chartStart).inDays.toDouble();
    sumWeight += value.value;
  }
  final centroidDays = sumDays / inWindow.length;
  final centroidWeight = sumWeight / inWindow.length;

  double weightAt(double days) =>
      centroidWeight + slopeKgPerDay * (days - centroidDays);

  final startDays = math.max(
    0.0,
    windowStart.difference(chartStart).inDays.toDouble(),
  );
  final endDays = windowEnd.difference(chartStart).inDays.toDouble();
  if (endDays <= 0) return null;

  return TrendOverlay(
    windowDays: windowDays,
    slopeKgPerDay: slopeKgPerDay,
    start: DatedTrendValue(
      chartStart.add(Duration(days: startDays.round())),
      weightAt(startDays),
    ),
    end: DatedTrendValue(windowEnd, weightAt(endDays)),
    lowConfidence: lowConfidence,
  );
}

class EvidenceTrendChart extends StatelessWidget {
  const EvidenceTrendChart({
    required this.values,
    required this.unit,
    required this.semanticLabel,
    this.average,
    this.compact = false,
    this.trendSlope7d,
    this.trendSlope28d,
    this.trendR2,
    super.key,
  });

  final List<DatedTrendValue> values;
  final String unit;
  final String semanticLabel;
  final double? average;
  final bool compact;

  /// OLS slope in kg/day for the 7-day window (feature engine §5).
  /// No R² exists for this window; it is never confidence-gated by [trendR2].
  final double? trendSlope7d;

  /// OLS slope in kg/day for the 28-day window (feature engine §5).
  final double? trendSlope28d;

  /// R² of the 28-day window ONLY (`weight_trend_r2_28d`). Gates only the
  /// 28-day overlay: below 0.3 (or missing) the line renders dashed and is
  /// labeled "low confidence".
  final double? trendR2;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final ordered = [...values]..sort((a, b) => a.date.compareTo(b.date));
    final latest = ordered.last;
    final colors = context.tracendColors;
    final overlays = <TrendOverlay>[
      if (trendSlope7d != null)
        ?deriveTrendOverlay(
          ordered,
          windowDays: 7,
          slopeKgPerDay: trendSlope7d!,
        ),
      if (trendSlope28d != null)
        ?deriveTrendOverlay(
          ordered,
          windowDays: 28,
          slopeKgPerDay: trendSlope28d!,
          lowConfidence: trendR2 == null || trendR2! < lowConfidenceR2Threshold,
        ),
    ].whereType<TrendOverlay>().toList();

    final overlayDescription = overlays.isEmpty
        ? ''
        : ' Computed overlays: ${overlays.map(_overlaySpeech).join('; ')}. '
              'Dots are measured evidence; lines are computed models.';

    return Semantics(
      label: '$semanticLabel$overlayDescription',
      child: ExcludeSemantics(
        child: Column(
          children: [
            SizedBox(
              height: compact ? 116 : 164,
              width: double.infinity,
              child: ClipRect(
                child: CustomPaint(
                  painter: _EvidenceTrendPainter(
                    values: ordered,
                    line: colors.actionPrimary,
                    grid: colors.borderSubtle,
                    text: colors.textSecondary,
                    average: average,
                    unit: unit,
                    overlays: overlays,
                    overlay7dColor: colors.stateStable,
                    overlay28dColor: colors.accentAmber,
                  ),
                ),
              ),
            ),
            const SizedBox(height: TracendSpacing.xs),
            if (overlays.isNotEmpty) ...[
              _TrendLegend(overlays: overlays),
              const SizedBox(height: TracendSpacing.xs),
            ],
            Row(
              children: [
                Text(_date(ordered.first.date)),
                const Spacer(),
                Text(
                  '${_number(latest.value)} $unit · ${_date(latest.date)}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: context.tracendColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _overlaySpeech(TrendOverlay overlay) =>
      '${overlay.label} ${overlay.slopeKgPerDay.toStringAsFixed(3)} kg/day'
      '${overlay.lowConfidence ? ' (low confidence)' : ''}';

  static String _date(DateTime date) => '${date.day}/${date.month}';
  static String _number(double value) =>
      value >= 100 ? value.round().toString() : value.toStringAsFixed(1);
}

class _TrendLegend extends StatelessWidget {
  const _TrendLegend({required this.overlays});
  final List<TrendOverlay> overlays;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(fontSize: 11);
    return Wrap(
      spacing: TracendSpacing.md,
      runSpacing: TracendSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors.actionPrimary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: TracendSpacing.xxs),
            Text('Measured', style: style),
          ],
        ),
        for (final overlay in overlays)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 2,
                child: CustomPaint(
                  painter: _LegendLinePainter(
                    color: overlay.windowDays == 7
                        ? colors.stateStable
                        : colors.accentAmber,
                    dashed: overlay.lowConfidence,
                  ),
                ),
              ),
              const SizedBox(width: TracendSpacing.xxs),
              Text(
                overlay.lowConfidence
                    ? '${overlay.label} · low confidence'
                    : overlay.label,
                style: style,
              ),
            ],
          ),
      ],
    );
  }
}

class _LegendLinePainter extends CustomPainter {
  const _LegendLinePainter({required this.color, required this.dashed});
  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 3, size.width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LegendLinePainter old) =>
      old.color != color || old.dashed != dashed;
}

class _EvidenceTrendPainter extends CustomPainter {
  const _EvidenceTrendPainter({
    required this.values,
    required this.line,
    required this.grid,
    required this.text,
    required this.unit,
    required this.overlays,
    required this.overlay7dColor,
    required this.overlay28dColor,
    this.average,
  });
  final List<DatedTrendValue> values;
  final Color line, grid, text;
  final String unit;
  final double? average;
  final List<TrendOverlay> overlays;
  final Color overlay7dColor;
  final Color overlay28dColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 48.0, top = 14.0, right = 8.0, bottom = 12.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    var rawMin = values.map((item) => item.value).reduce(math.min);
    var rawMax = values.map((item) => item.value).reduce(math.max);
    for (final overlay in overlays) {
      rawMin = math.min(
        rawMin,
        math.min(overlay.start.value, overlay.end.value),
      );
      rawMax = math.max(
        rawMax,
        math.max(overlay.start.value, overlay.end.value),
      );
    }
    final naturalRange = math.max(rawMax - rawMin, unit == 'kg' ? 2.0 : 2000.0);
    final minY = math.max(0, rawMin - naturalRange * .18);
    final maxY = rawMax + naturalRange * .18;
    final firstDate = values.first.date;
    final totalDays = math.max(
      1,
      values.last.date.difference(firstDate).inDays,
    );

    Offset point(DatedTrendValue item) => Offset(
      plot.left +
          plot.width * item.date.difference(firstDate).inDays / totalDays,
      plot.bottom - plot.height * (item.value - minY) / (maxY - minY),
    );

    for (var i = 0; i < 3; i++) {
      final fraction = i / 2;
      final y = plot.bottom - plot.height * fraction;
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..color = grid
          ..strokeWidth = 1,
      );
      final value = minY + (maxY - minY) * fraction;
      _label(
        canvas,
        '${value >= 100 ? value.round() : value.toStringAsFixed(1)}',
        Offset(0, y - 7),
      );
    }
    if (average != null && average! >= minY && average! <= maxY) {
      final y = plot.bottom - plot.height * (average! - minY) / (maxY - minY);
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..color = line.withValues(alpha: .42)
          ..strokeWidth = 1.5,
      );
      _label(canvas, 'avg', Offset(plot.right - 24, y - 16));
    }

    for (final overlay in overlays) {
      final color = overlay.windowDays == 7 ? overlay7dColor : overlay28dColor;
      final start = point(overlay.start);
      final end = point(overlay.end);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      if (overlay.lowConfidence) {
        _drawDashed(canvas, start, end, paint);
      } else {
        canvas.drawLine(start, end, paint);
      }
    }

    if (values.length == 1) {
      canvas.drawCircle(point(values.first), 5, Paint()..color = line);
      return;
    }
    final path = Path()..moveTo(point(values.first).dx, point(values.first).dy);
    for (final value in values.skip(1)) {
      final p = point(value);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final value in values) {
      final p = point(value);
      canvas.drawCircle(p, 7, Paint()..color = line.withValues(alpha: .14));
      canvas.drawCircle(p, 3.5, Paint()..color = line);
    }
  }

  void _drawDashed(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dash = 6.0, gap = 4.0;
    final vector = end - start;
    final distance = vector.distance;
    if (distance == 0) return;
    final unit = vector / distance;
    var travelled = 0.0;
    while (travelled < distance) {
      final segmentEnd = math.min(travelled + dash, distance);
      canvas.drawLine(
        start + unit * travelled,
        start + unit * segmentEnd,
        paint,
      );
      travelled = segmentEnd + gap;
    }
  }

  void _label(Canvas canvas, String value, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: text,
          fontSize: 10,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 44);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _EvidenceTrendPainter old) =>
      old.values != values ||
      old.line != line ||
      old.grid != grid ||
      old.average != average ||
      old.overlays != overlays;
}
