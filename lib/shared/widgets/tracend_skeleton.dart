import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

enum _SkeletonShape { line, block, row }

/// A placeholder in the shape of the content that is loading
/// (DESIGN_SYSTEM.md §5.1, skeleton). Use it instead of a page-level spinner
/// or progress bar.
///
/// A soft highlight sweeps across it while it is visible at full motion. The
/// sweep stops when its ticker is muted ([TickerMode] off, such as a tab that
/// is not on screen) and is never started under Reduce Motion or a static
/// [TracendMotionScope]; the shapes then render still.
///
/// Skeletons are hidden from VoiceOver. Give the loading region one label,
/// for example `Semantics(label: 'Loading Train', child: ...)`.
class TracendSkeleton extends StatefulWidget {
  /// A line of text. [widthFactor] of the available width; vary it across
  /// lines so a paragraph reads as text.
  const TracendSkeleton.line({
    this.widthFactor = 1,
    this.height = 14,
    super.key,
  }) : _shape = _SkeletonShape.line,
       radius = TracendRadii.pill,
       lines = 1;

  /// A card or chart standing in for a whole surface.
  const TracendSkeleton.block({
    this.height = 120,
    this.radius = TracendRadii.card,
    super.key,
  }) : _shape = _SkeletonShape.block,
       widthFactor = 1,
       lines = 1;

  /// A list row: a leading tile and [lines] lines of text (1 or 2). Sits
  /// inside a card or grouped list.
  const TracendSkeleton.row({this.lines = 2, super.key})
    : assert(lines == 1 || lines == 2),
      _shape = _SkeletonShape.row,
      widthFactor = 1,
      height = 60,
      radius = 10;

  final _SkeletonShape _shape;
  final double widthFactor;
  final double height;
  final double radius;
  final int lines;

  static const sweep = Duration(milliseconds: 1200);

  @override
  State<TracendSkeleton> createState() => _TracendSkeletonState();
}

class _TracendSkeletonState extends State<TracendSkeleton>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = TracendMotionScope.of(context) == TracendMotionLevel.full;
    if (animate && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: TracendSkeleton.sweep,
      )..repeat();
    } else if (!animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final shapes = switch (widget._shape) {
      _SkeletonShape.line => FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widget.widthFactor,
        child: _Bone(
          height: widget.height,
          radius: widget.radius,
          color: colors.surfaceRaised,
        ),
      ),
      _SkeletonShape.block => _Bone(
        height: widget.height,
        radius: widget.radius,
        color: colors.surface,
      ),
      _SkeletonShape.row => SizedBox(
        height: widget.height,
        child: Row(
          children: [
            _Bone(
              width: 30,
              height: 30,
              radius: widget.radius,
              color: colors.surfaceRaised,
            ),
            const SizedBox(width: TracendSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 0.62,
                    child: _Bone(
                      height: 14,
                      radius: TracendRadii.pill,
                      color: colors.surfaceRaised,
                    ),
                  ),
                  if (widget.lines == 2) ...[
                    const SizedBox(height: TracendSpacing.xs),
                    FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: 0.4,
                      child: _Bone(
                        height: 11,
                        radius: TracendRadii.pill,
                        color: colors.surfaceRaised,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    };
    final controller = _controller;
    final child = controller == null
        ? shapes
        : AnimatedBuilder(
            animation: controller,
            child: shapes,
            builder: (context, child) => ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  colors.shimmer.withValues(alpha: 0),
                  colors.shimmer,
                  colors.shimmer.withValues(alpha: 0),
                ],
                transform: _Sweep(
                  Curves.easeInOut.transform(controller.value) * 2 - 1,
                ),
              ).createShader(bounds),
              child: child,
            ),
          );
    return ExcludeSemantics(child: RepaintBoundary(child: child));
  }
}

class _Bone extends StatelessWidget {
  const _Bone({
    required this.height,
    required this.radius,
    required this.color,
    this.width,
  });

  final double? width;
  final double height;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width ?? double.infinity,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// Slides the highlight from one edge (-1) to the other (1).
class _Sweep extends GradientTransform {
  const _Sweep(this.position);

  final double position;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * position, 0, 0);
}
