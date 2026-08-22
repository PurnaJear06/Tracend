import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Motion helpers for the "Precision Pro" system (DESIGN_SYSTEM.md §6).
///
/// All motion is motivated (entrance, feedback, state change), gated on
/// Reduce Motion (`MediaQuery.disableAnimationsOf` — iOS Reduce Motion maps
/// to this flag in the engine), and nothing animates idle except the single
/// sanctioned pulse ([MicroMotionPulse], used by the NOW dot only).
abstract final class MicroMotion {
  static const springStiffness = 100.0;
  static const springDamping = 20.0;

  static SpringDescription get spring => SpringDescription(
    mass: 1,
    stiffness: springStiffness,
    damping: springDamping,
  );

  /// Per-index stagger delay for scroll/list entrances (max 60ms per index).
  static Duration stagger(int index) =>
      Duration(milliseconds: index.clamp(0, 8) * 60);

  /// Exits run 25% faster than entries.
  static Duration exitDuration(Duration entry) =>
      Duration(milliseconds: (entry.inMilliseconds * 0.75).round());
}

/// Spring entrance: fades and rises the child once on mount.
/// Reduce Motion renders the child statically (no controller is created).
class MicroMotionEntrance extends StatefulWidget {
  const MicroMotionEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.rise = 12.0,
  });

  final Widget child;
  final Duration delay;
  final double rise;

  @override
  State<MicroMotionEntrance> createState() => _MicroMotionEntranceState();
}

class _MicroMotionEntranceState extends State<MicroMotionEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion || _controller != null) return;
    final controller = AnimationController.unbounded(vsync: this);
    _controller = controller;
    Future<void>.delayed(widget.delay).then((_) {
      if (!mounted) return;
      controller.animateWith(SpringSimulation(MicroMotion.spring, 0, 1, 0));
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.rise),
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// The single sanctioned idle loop: a gentle opacity pulse (NOW dot).
/// Reduce Motion renders the child statically (no controller is created).
class MicroMotionPulse extends StatefulWidget {
  const MicroMotionPulse({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 1600),
    this.minOpacity = 0.55,
  });

  final Widget child;
  final Duration period;
  final double minOpacity;

  @override
  State<MicroMotionPulse> createState() => _MicroMotionPulseState();
}

class _MicroMotionPulseState extends State<MicroMotionPulse>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion || _controller != null) return;
    final controller = AnimationController(vsync: this, duration: widget.period)
      ..repeat(reverse: true);
    _controller = controller;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final opacity =
            widget.minOpacity + (1 - widget.minOpacity) * controller.value;
        return Opacity(opacity: opacity, child: widget.child);
      },
    );
  }
}
