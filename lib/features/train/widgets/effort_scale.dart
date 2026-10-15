import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';

/// The anchor word for the whole workout's effort (session effort).
String sessionEffortAnchor(int value) => switch (value) {
  <= 2 => 'Very easy',
  <= 4 => 'Easy',
  <= 6 => 'Moderate',
  <= 8 => 'Hard',
  9 => 'Very hard',
  _ => 'Max',
};

/// A grid of the numbers 1 to 10, five to a row, with the chosen one filled:
/// the whole workout's effort.
class EffortScale extends StatelessWidget {
  const EffortScale({
    required this.value,
    required this.onSelected,
    required this.describe,
    this.height = 44,
    this.fontSize = 16,
    super.key,
  });

  final int? value;
  final ValueChanged<int> onSelected;

  /// The words VoiceOver reads after the number ("Hard").
  final String Function(int value) describe;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    Widget cell(int number) {
      final selected = number == value;
      return Expanded(
        child: Semantics(
          selected: selected,
          inMutuallyExclusiveGroup: true,
          child: Pressable(
            semanticLabel: '$number, ${describe(number)}',
            borderRadius: BorderRadius.circular(TracendRadii.control),
            haptic: TracendHaptics.selection,
            onTap: () => onSelected(number),
            child: AnimatedContainer(
              duration: TracendMotion.quick,
              constraints: BoxConstraints(minHeight: height),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? colors.actionPrimary : colors.surface,
                borderRadius: BorderRadius.circular(TracendRadii.control),
              ),
              child: Text(
                '$number',
                style: TracendTheme.numeric(
                  colors,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  color: selected ? colors.actionOnPrimary : colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget row(int from) => Row(
      children: [
        for (var number = from; number < from + 5; number++) ...[
          if (number > from) const SizedBox(width: 6),
          cell(number),
        ],
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [row(1), const SizedBox(height: 6), row(6)],
    );
  }
}
