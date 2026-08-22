import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// Solid tonal-gradient content card — the default evidence/content surface
/// (DESIGN_SYSTEM.md §3.4). Zero blur: never contains a [BackdropFilter].
class PremiumGradientCard extends StatelessWidget {
  const PremiumGradientCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(TracendSpacing.md),
    this.glow = false,
    this.glowColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Optional decorative corner glow (paint-only radial gradient, no blur).
  final bool glow;
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final radius = BorderRadius.circular(TracendRadii.card);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: colors.borderHairline),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.surface.withValues(alpha: 0.80),
            colors.canvas.withValues(alpha: 0.90),
          ],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: glow
              ? RadialGradient(
                  center: Alignment.topRight,
                  radius: 0.9,
                  colors: [
                    (glowColor ?? colors.actionPrimary).withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.6],
                )
              : null,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
