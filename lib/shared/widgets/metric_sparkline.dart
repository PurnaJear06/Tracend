import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

class MetricSparkline extends StatelessWidget {
  const MetricSparkline({required this.values, required this.label, super.key});

  final List<double> values;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 32,
          width: 72,
          child: values.length >= 2
              ? CustomPaint(
                  painter: _SparklinePainter(
                    values: values,
                    line: colors.actionPrimary,
                  ),
                )
              : Center(
                  child: Text(
                    '\u2014',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.values, required this.line});

  final List<double> values;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal).abs() < 0.001 ? 1.0 : maxVal - minVal;

    final dx = size.width / (values.length - 1);
    Offset point(int i) {
      final norm = (values[i] - minVal) / range;
      return Offset(i * dx, size.height - (norm * (size.height - 4)) - 2);
    }

    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      final prev = point(i - 1);
      final curr = point(i);
      final cpDx = (curr.dx - prev.dx) / 2;
      path.cubicTo(
        prev.dx + cpDx,
        prev.dy,
        curr.dx - cpDx,
        curr.dy,
        curr.dx,
        curr.dy,
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final last = point(values.length - 1);
    canvas.drawCircle(last, 2.5, Paint()..color = line);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      values != oldDelegate.values;
}
