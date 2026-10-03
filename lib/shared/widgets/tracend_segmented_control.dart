import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// Pill segmented control (DESIGN_SYSTEM.md §5.1): a `surfaceRaised` track with
/// the selected segment as a `surface` pill that slides between options.
/// The control is 44pt tall, labels scale with Dynamic Type, and a change
/// plays the selection haptic.
class TracendSegmentedControl<T extends Object> extends StatelessWidget {
  const TracendSegmentedControl({
    required this.segments,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  /// Ordered value → label pairs.
  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = Theme.of(
      context,
    ).textTheme.labelLarge!.copyWith(fontSize: 15);
    final count = segments.length;
    final index = segments.indexWhere((segment) => segment.$1 == selected);
    final pill = BorderRadius.circular(TracendRadii.pill);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: pill,
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Stack(
          children: [
            if (index >= 0)
              Positioned.fill(
                child: AnimatedAlign(
                  duration: TracendMotionScope.movement(
                    context,
                    TracendMotion.standard,
                  ),
                  curve: TracendMotion.curve,
                  alignment: Alignment(
                    count == 1 ? 0 : -1 + 2 * index / (count - 1),
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / count,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: pill,
                        border: dark
                            ? Border.all(color: colors.glassEdge)
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: dark ? 0.32 : 0.08,
                            ),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                for (final (value, label) in segments)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: value == selected,
                      inMutuallyExclusiveGroup: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (value == selected) return;
                          TracendHaptics.selection();
                          onChanged(value);
                        },
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 38),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: TracendSpacing.xs,
                                vertical: TracendSpacing.xxs,
                              ),
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                style: style.copyWith(
                                  color: value == selected
                                      ? colors.textPrimary
                                      : colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
