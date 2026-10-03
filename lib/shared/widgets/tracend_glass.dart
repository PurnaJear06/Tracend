import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// Translucent chrome (DESIGN_SYSTEM.md §3.4): the tab bar, the toast and the
/// collapsed large-title bar. Content cards and charts never use it; they
/// are flat `surface` fills.
///
/// The fill is the [TracendColors.glass] token over a background blur, with a
/// [TracendColors.glassEdge] hairline. [enabled] false or
/// [reduceTransparency] renders an opaque `sheet` fill with no blur.
class TracendGlass extends StatelessWidget {
  const TracendGlass({
    super.key,
    required this.child,
    this.borderRadius = TracendRadii.navigation,
    this.border,
    this.enabled = true,
    this.reduceTransparency = false,
  });

  final Widget child;
  final double borderRadius;

  /// The edge stroke. Defaults to a [TracendColors.glassEdge] hairline on all
  /// sides; a bar passes only its bottom edge.
  final BoxBorder? border;

  /// Set false (or pass [reduceTransparency]) to render the opaque fallback.
  final bool enabled;
  final bool reduceTransparency;

  static const blurSigma = 20.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    // A one-sided border cannot carry a radius, so square chrome passes none.
    final radius = borderRadius > 0
        ? BorderRadius.circular(borderRadius)
        : null;
    final edge = border ?? Border.all(color: colors.glassEdge);
    if (!enabled || reduceTransparency) {
      return RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.sheet,
            borderRadius: radius,
            border: edge,
          ),
          child: child,
        ),
      );
    }
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: radius ?? BorderRadius.zero,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.glass,
              borderRadius: radius,
              border: edge,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
