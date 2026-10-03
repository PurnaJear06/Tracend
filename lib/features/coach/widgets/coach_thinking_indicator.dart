import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// "Coach is thinking": three dots that rise and brighten in turn while a
/// reply is on its way, in the place the reply will appear.
///
/// The dots loop only at full motion ([TracendMotionScope]); under Reduce
/// Motion or a static scope they rest, evenly lit. VoiceOver hears the label
/// once, through a live region.
class CoachThinkingIndicator extends StatefulWidget {
  const CoachThinkingIndicator({super.key});

  static const label = 'Coach is thinking';
  static const cycle = Duration(milliseconds: 1200);

  @override
  State<CoachThinkingIndicator> createState() => _CoachThinkingIndicatorState();
}

class _CoachThinkingIndicatorState extends State<CoachThinkingIndicator>
    with TickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = TracendMotionScope.of(context) == TracendMotionLevel.full;
    if (animate && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: CoachThinkingIndicator.cycle,
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
    final controller = _controller;
    final dots = controller == null
        ? const _Dots(phase: null)
        : AnimatedBuilder(
            animation: controller,
            builder: (context, _) => _Dots(phase: controller.value),
          );
    return Semantics(
      liveRegion: true,
      label: CoachThinkingIndicator.label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 24, child: Center(child: dots)),
            const SizedBox(width: TracendSpacing.xs),
            Flexible(
              child: Text(
                CoachThinkingIndicator.label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.phase});

  /// Position in the loop (0–1), or null when the dots rest.
  final double? phase;

  static const _size = 7.0;
  static const _gap = 5.0;

  @override
  Widget build(BuildContext context) {
    final color = context.tracendColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          _dot(color, _lift(i)),
        ],
      ],
    );
  }

  /// 0 at rest, 1 at the top of a dot's hop. Each dot hops in the first
  /// part of its own third of the cycle, so the wave reads left to right.
  double _lift(int index) {
    final phase = this.phase;
    if (phase == null) return 0;
    final local = (phase - index * 0.18) % 1;
    if (local > 0.5) return 0;
    return math.sin(local / 0.5 * math.pi);
  }

  Widget _dot(Color color, double lift) => Transform.translate(
    offset: Offset(0, -3 * lift),
    child: Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: phase == null ? 0.8 : 0.45 + 0.55 * lift,
        ),
        shape: BoxShape.circle,
      ),
    ),
  );
}
