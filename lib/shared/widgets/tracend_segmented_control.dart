import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// iOS sliding segmented control in Tracend tokens. Each segment keeps a
/// 44pt touch target; labels scale with Dynamic Type.
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
    final style = Theme.of(context).textTheme.labelLarge;
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<T>(
        groupValue: selected,
        backgroundColor: dark ? colors.surface : colors.borderHairline,
        thumbColor: dark ? colors.borderSubtle : colors.surface,
        padding: const EdgeInsets.all(3),
        onValueChanged: (value) {
          if (value != null && value != selected) onChanged(value);
        },
        children: {
          for (final (value, label) in segments)
            value: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 38),
              child: Center(
                child: Text(
                  label,
                  style: style?.copyWith(
                    color: value == selected
                        ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                ),
              ),
            ),
        },
      ),
    );
  }
}
