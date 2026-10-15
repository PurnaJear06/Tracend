import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_glass.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// The shell's bottom slot (DESIGN_SYSTEM.md §4). It places whichever bar is
/// showing, the tab capsule or the check-in gate bar, at one floating
/// position above the home indicator, over a fade that softens content
/// passing beneath it.
///
/// The shell's `Scaffold` extends its body under this slot, so inside the
/// body `MediaQuery.paddingOf(context).bottom` is the slot's full height.
/// Scroll views end their content by that padding (`TracendScrollView`), so
/// nothing hides behind either bar and no screen needs its own number.
class FloatingBarFrame extends StatelessWidget {
  const FloatingBarFrame({required this.child, super.key});

  final Widget child;

  /// Widest a bar grows, for iPad and landscape.
  static const maxWidth = 620.0;

  /// The space around the bar.
  ///
  /// Face ID iPhones report a 34pt bottom inset, and the home indicator is a
  /// 5pt bar about 8pt above the screen edge. Lifting the bar to the inset
  /// less 10 (24pt) leaves an 11pt clear gap above the indicator, as the
  /// iOS 26 floating tab bar does, and 20pt sides keep the capsule's 32pt
  /// ends close to concentric with the display's rounded corners. Home-button
  /// iPhones have no inset and square corners, so the bar sits 12pt in.
  static EdgeInsets margins(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final side = padding.bottom > 0 ? 20.0 : 12.0;
    return EdgeInsets.fromLTRB(
      padding.left + side,
      0,
      padding.right + side,
      math.max(padding.bottom - 10, 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canvas = context.tracendColors.canvas;
    return Stack(
      children: [
        // Content scrolling under the bar fades into the canvas beside and
        // below it instead of meeting it at a hard line.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey('bottom-bar-fade'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    canvas.withValues(alpha: 0),
                    canvas.withValues(alpha: 0.55),
                    canvas.withValues(alpha: 0.85),
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: margins(context),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

/// The five primary destinations in one floating glass capsule. A lime-tinted
/// pill sits behind the selected tab and slides to the next one.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const height = 64.0;

  /// Gap between the capsule and the selection pill, so the pill's rounded
  /// ends stay concentric with the capsule's.
  static const _pillInset = 4.0;

  static const items = [
    (
      label: 'Today',
      icon: Icons.wb_sunny_outlined,
      selectedIcon: Icons.wb_sunny_rounded,
    ),
    (
      label: 'Train',
      icon: Icons.fitness_center_rounded,
      selectedIcon: Icons.fitness_center_rounded,
    ),
    (
      label: 'Coach',
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
    ),
    (
      label: 'Nutrition',
      icon: Icons.restaurant_rounded,
      selectedIcon: Icons.restaurant_rounded,
    ),
    (
      label: 'Progress',
      icon: Icons.trending_up_rounded,
      selectedIcon: Icons.trending_up_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highlight = colors.glassHighlight;
    final clearHighlight = highlight.withValues(alpha: 0);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.32 : 0.10),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: TracendGlass(
        key: const ValueKey('tab-capsule'),
        borderRadius: height / 2,
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              // Light catching the top of the glass: a soft sheen over the
              // upper half and a brighter edge along the straight top run.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          highlight.withValues(alpha: highlight.a * 0.35),
                          clearHighlight,
                        ],
                        stops: const [0, 0.55],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: height / 2,
                right: height / 2,
                height: 1,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [clearHighlight, highlight, clearHighlight],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: AnimatedAlign(
                  alignment: AlignmentDirectional(
                    -1 + 2 * selectedIndex / (items.length - 1),
                    0,
                  ),
                  duration: TracendMotionScope.movement(
                    context,
                    TracendMotion.standard,
                  ),
                  curve: TracendMotion.curve,
                  child: FractionallySizedBox(
                    widthFactor: 1 / items.length,
                    heightFactor: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(_pillInset),
                      child: DecoratedBox(
                        key: const ValueKey('tab-selection-pill'),
                        decoration: BoxDecoration(
                          color: colors.accentSignalTint,
                          borderRadius: BorderRadius.circular(
                            height / 2 - _pillInset,
                          ),
                          border: Border.all(
                            color: colors.accentSignalRing.withValues(
                              alpha: 0.22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var index = 0; index < items.length; index++)
                    Expanded(
                      child: _TabItem(
                        item: items[index],
                        selected: selectedIndex == index,
                        onTap: () => onSelected(index),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatefulWidget {
  const _TabItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ({String label, IconData icon, IconData selectedIcon}) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final item = widget.item;
    final selected = widget.selected;
    final tint = selected ? colors.accentSignalInk : colors.textSecondary;
    final fullMotion =
        TracendMotionScope.of(context) == TracendMotionLevel.full;
    return Semantics(
      key: ValueKey('tab-${item.label.toLowerCase()}'),
      selected: selected,
      button: true,
      label: '${item.label} tab',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed && fullMotion ? 0.92 : 1,
          duration: TracendMotion.quick,
          curve: TracendMotion.curve,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: TracendMotionScope.fade(context, TracendMotion.quick),
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  key: ValueKey(selected),
                  size: 23,
                  color: tint,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                // iOS tab bars keep labels near-fixed under Dynamic Type;
                // clamp so the label never overflows the 64pt capsule.
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.3),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
