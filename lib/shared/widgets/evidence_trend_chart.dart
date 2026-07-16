import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

class DatedTrendValue {
  const DatedTrendValue(this.date, this.value);
  final DateTime date;
  final double value;
}

class EvidenceTrendChart extends StatelessWidget {
  const EvidenceTrendChart({
    required this.values,
    required this.unit,
    required this.semanticLabel,
    this.average,
    this.compact = false,
    super.key,
  });

  final List<DatedTrendValue> values;
  final String unit;
  final String semanticLabel;
  final double? average;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final ordered = [...values]..sort((a, b) => a.date.compareTo(b.date));
    final latest = ordered.last;
    return Semantics(
      label: semanticLabel,
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
                    line: context.tracendColors.actionPrimary,
                    grid: context.tracendColors.borderSubtle,
                    text: context.tracendColors.textSecondary,
                    average: average,
                    unit: unit,
                  ),
                ),
              ),
            ),
            const SizedBox(height: TracendSpacing.xs),
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

  static String _date(DateTime date) => '${date.day}/${date.month}';
  static String _number(double value) =>
      value >= 100 ? value.round().toString() : value.toStringAsFixed(1);
}

class _EvidenceTrendPainter extends CustomPainter {
  const _EvidenceTrendPainter({
    required this.values,
    required this.line,
    required this.grid,
    required this.text,
    required this.unit,
    this.average,
  });
  final List<DatedTrendValue> values;
  final Color line, grid, text;
  final String unit;
  final double? average;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 48.0, top = 14.0, right = 8.0, bottom = 12.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final rawMin = values.map((item) => item.value).reduce(math.min);
    final rawMax = values.map((item) => item.value).reduce(math.max);
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
      old.average != average;
}
