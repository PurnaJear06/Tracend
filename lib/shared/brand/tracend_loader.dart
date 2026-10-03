import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:tracend/shared/brand/tracend_mark.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// The brand loading indicator: the mark's arc, with its dot riding along it
/// and back. Under Reduce Motion the dot rests where it sits on the mark.
class TracendLoader extends StatefulWidget {
  const TracendLoader({
    this.size = 28,
    this.semanticLabel = 'Loading',
    this.dotColor,
    this.arcColor,
    super.key,
  });

  final double size;

  /// What VoiceOver reads, such as "Loading your plan".
  final String semanticLabel;

  /// The dot; lime on dark surfaces and a deeper lime on light ones unless
  /// set.
  final Color? dotColor;

  /// The arc behind the dot; a faint tint of the text colour unless set.
  final Color? arcColor;

  @override
  State<TracendLoader> createState() => _TracendLoaderState();
}

class _TracendLoaderState extends State<TracendLoader>
    with SingleTickerProviderStateMixin {
  /// One pass along the arc; the dot then returns the same way.
  static const _pass = Duration(milliseconds: 1000);
  static const _curve = Cubic(0.45, 0, 0.25, 1);

  late final AnimationController _travel = AnimationController(
    vsync: this,
    duration: _pass,
  );
  late final CurvedAnimation _eased = CurvedAnimation(
    parent: _travel,
    curve: _curve,
  );

  /// Reduce Motion or a reduced or static [TracendMotionScope] (as in
  /// tests) rests the dot.
  bool _still(BuildContext context) =>
      TracendMotionScope.of(context) != TracendMotionLevel.full;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _travel.stop();
    } else if (!_travel.isAnimating) {
      _travel.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _eased.dispose();
    _travel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final dotColor =
        widget.dotColor ??
        (dark ? TracendBrandColors.lime : TracendBrandColors.limeOnLight);
    final arcColor =
        widget.arcColor ??
        theme.colorScheme.onSurface.withValues(alpha: dark ? 0.22 : 0.18);
    final still = _still(context);
    return Semantics(
      label: widget.semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: widget.size,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _LoaderPainter(
                travel: still ? null : _eased,
                dotColor: dotColor,
                arcColor: arcColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoaderPainter extends CustomPainter {
  _LoaderPainter({
    required this.travel,
    required this.dotColor,
    required this.arcColor,
  }) : super(repaint: travel);

  /// Where the dot is along its track, or null for the resting dot.
  final Animation<double>? travel;
  final Color dotColor;
  final Color arcColor;

  static const _extent = TracendMarkGeometry.extent;

  /// The dot's track along the arc's spine, in the 1024 design space.
  static final PathMetric _track =
      (Path()
            ..moveTo(355, 790)
            ..quadraticBezierTo(530, 505, 812, 315))
          .computeMetrics()
          .single;

  /// The dot's diameter is 6 of the loader's 28 points.
  static const _dotRadius = _extent * 3 / 28;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _extent;
    canvas
      ..save()
      ..scale(scale)
      ..drawPath(TracendMarkGeometry.swoosh, Paint()..color = arcColor);
    final progress = travel?.value;
    final dot = progress == null
        ? TracendMarkGeometry.dotCenter
        : _track.getTangentForOffset(_track.length * progress)!.position;
    canvas
      ..drawCircle(dot, _dotRadius, Paint()..color = dotColor)
      ..restore();
  }

  @override
  bool shouldRepaint(_LoaderPainter oldDelegate) =>
      oldDelegate.travel != travel ||
      oldDelegate.dotColor != dotColor ||
      oldDelegate.arcColor != arcColor;
}
