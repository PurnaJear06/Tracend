import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// The default content card (DESIGN_SYSTEM.md §3.4): a flat surface with no
/// border, gradient or blur. Grouping comes from the fill against the canvas.
class PremiumGradientCard extends StatelessWidget {
  const PremiumGradientCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(TracendSpacing.md),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.tracendColors.surface,
        borderRadius: BorderRadius.circular(TracendRadii.card),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
