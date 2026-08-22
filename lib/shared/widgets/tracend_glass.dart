import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// Restrained glass surface for chrome only (top app bar, confidence pill,
/// floating tab capsule). See DESIGN_SYSTEM.md §3.4.
///
/// Maximum 2 visible [BackdropFilter] sites app-wide. Content cards and
/// charts must never use this widget — use `PremiumGradientCard` instead.
class TracendGlass extends StatelessWidget {
  const TracendGlass({
    super.key,
    required this.child,
    this.borderRadius = TracendRadii.navigation,
    this.enabled = true,
    this.reduceTransparency = false,
  });

  final Widget child;
  final double borderRadius;

  /// Set false (or pass [reduceTransparency]) to render the opaque fallback.
  final bool enabled;
  final bool reduceTransparency;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final radius = BorderRadius.circular(borderRadius);
    if (!enabled || reduceTransparency) {
      return RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: radius,
            border: Border.all(color: colors.borderSubtle),
          ),
          child: child,
        ),
      );
    }
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.72),
              borderRadius: radius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.35],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
