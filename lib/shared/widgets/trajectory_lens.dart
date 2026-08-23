import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/micro_motion.dart';

/// One plotted signal on the trajectory. [value] is a 0–100 score that maps
/// directly to a `ComputedScores` field — never invented, never normalized by
/// a made-up constant.
@immutable
class TrajectoryPoint {
  const TrajectoryPoint({required this.label, required this.value});

  /// Caps label shown above the lens (e.g. `SLEEP`).
  final String label;

  /// 0–100 score traced to a real computed field.
  final double value;
}

/// Luminous trajectory lens (Stitch `today.html`). Draws a bezier through the
/// real signal scores with a draw-on reveal and a pulsing NOW marker.
///
/// Data contract (plan §4.1): every point binds to a `ComputedScores` field.
/// When fewer than two scores exist (cold start / null), it falls back to the
/// original signal chip rail so the surface never renders a fabricated curve.
class TrajectoryLens extends StatefulWidget {
  const TrajectoryLens({
    this.points = const [],
    this.decision = 'Maintain approved plan',
    this.evidence = const ['Approved plan'],
    this.height = 120,
    super.key,
  });

  /// Real scored signals, in plot order. Must be ≥2 to draw the bezier.
  final List<TrajectoryPoint> points;
  final String decision;

  /// Chip-rail fallback content (cold start) and semantics source.
  final List<String> evidence;
  final double height;

  @override
  State<TrajectoryLens> createState() => _TrajectoryLensState();
}

class _TrajectoryLensState extends State<TrajectoryLens>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  static const _drawDuration = Duration(milliseconds: 1500);
  static const _inset = 0.05;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion || _controller != null || widget.points.length < 2) {
      return;
    }
    _startDraw();
  }

  @override
  void didUpdateWidget(TrajectoryLens oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller == null && !_reduceMotion && widget.points.length >= 2) {
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

  /// Points in unit space (0–1). Shared by the painter and the NOW overlay so
  /// both agree on the terminal marker position.
  List<Offset> _unitPoints() {
    final n = widget.points.length;
    return [
      for (var i = 0; i < n; i++)
        Offset(
          _inset + (i * (1 - 2 * _inset)) / (n - 1),
          0.9 - (widget.points[i].value.clamp(0, 100) / 100) * 0.8,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.length < 2) return _ChipRail(widget: widget);

    final colors = context.tracendColors;
    final units = _unitPoints();
    final now = units.last;
    final semantics =
        'Trajectory of today’s signals: '
        '${widget.points.map((p) => '${p.label} ${p.value.round()}').join(', ')}. '
        '${widget.decision}';

    return Semantics(
      label: semantics,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TracendSpacing.xxs,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final point in widget.points)
                    Text(
                      point.label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontSize: 11,
                        letterSpacing: 1.6,
                        color: point == widget.points.last
                            ? colors.accentNow
                            : colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: TracendSpacing.xs),
            SizedBox(
              height: widget.height,
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, widget.height);
                  return Stack(
                    children: [
                      _TrajectoryPath(
                        units: units,
                        controller: _controller,
                        line: colors.actionPrimary,
                        grid: colors.borderSubtle,
                        dot: colors.actionPrimary,
                      ),
                      Positioned(
                        left: now.dx * size.width - 5,
                        top: now.dy * size.height - 5,
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
          ],
        ),
      ),
    );
  }
}

class _TrajectoryPath extends StatelessWidget {
  const _TrajectoryPath({
    required this.units,
    required this.controller,
    required this.line,
    required this.grid,
    required this.dot,
  });

  final List<Offset> units;
  final AnimationController? controller;
  final Color line;
  final Color grid;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) {
      return CustomPaint(
        painter: _TrajectoryPainter(
          units: units,
          line: line,
          grid: grid,
          dot: dot,
          progress: 1,
        ),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => CustomPaint(
        painter: _TrajectoryPainter(
          units: units,
          line: line,
          grid: grid,
          dot: dot,
          progress: Curves.easeOutCubic.transform(controller.value),
        ),
      ),
    );
  }
}

class _TrajectoryPainter extends CustomPainter {
  _TrajectoryPainter({
    required this.units,
    required this.line,
    required this.grid,
    required this.dot,
    required this.progress,
  });

  final List<Offset> units;
  final Color line;
  final Color grid;
  final Color dot;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (units.length < 2) return;
    if (size.isEmpty) return;

    final points = [
      for (final unit in units)
        Offset(unit.dx * size.width, unit.dy * size.height),
    ];

    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;
    for (final point in points) {
      canvas.drawLine(
        Offset(point.dx, 0),
        Offset(point.dx, size.height),
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

    final metric = path.computeMetrics().single;
    final revealed = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      revealed,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < points.length - 1; i++) {
      final threshold = i / (points.length - 1);
      if (progress < threshold) continue;
      canvas.drawCircle(points[i], 3, Paint()..color = dot);
    }
  }

  @override
  bool shouldRepaint(covariant _TrajectoryPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      !_sameUnits(oldDelegate.units, units) ||
      oldDelegate.line != line ||
      oldDelegate.grid != grid ||
      oldDelegate.dot != dot;

  static bool _sameUnits(List<Offset> a, List<Offset> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Cold-start / low-data fallback: the original signal chip rail. Kept so the
/// lens never draws a curve it has no real scores for.
class _ChipRail extends StatelessWidget {
  const _ChipRail({required this.widget});
  final TrajectoryLens widget;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final labels = widget.evidence.take(3).toList();
    return Semantics(
      label:
          'Signals shaping this action: ${labels.join(', ')}. ${widget.decision}',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: BorderRadius.circular(TracendRadii.card),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Padding(
            padding: const EdgeInsets.all(TracendSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.waveform_path_ecg,
                      size: 16,
                      color: colors.stateStable,
                    ),
                    const SizedBox(width: TracendSpacing.xs),
                    Expanded(
                      child: Text(
                        'Signals shaping this · ${widget.evidence.length}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: TracendSpacing.xs),
                Wrap(
                  spacing: TracendSpacing.xs,
                  runSpacing: TracendSpacing.xs,
                  children: [
                    for (final label in labels) _SignalChip(label: label),
                    if (widget.evidence.length > labels.length)
                      _SignalChip(
                        label: '+${widget.evidence.length - labels.length}',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.tracendColors.actionPrimary.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: context.tracendColors.actionPrimary,
        ),
      ),
    ),
  );
}
