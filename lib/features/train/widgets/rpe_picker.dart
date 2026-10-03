import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';

/// The plain words beside a set's effort (RPE): how many reps were left.
String rpeHint(int value) => switch (value) {
  <= 2 => 'Very light',
  <= 4 => 'Light',
  5 => '5 or more reps left',
  6 => '4 reps left',
  7 => '3 reps left',
  8 => '2 reps left',
  9 => '1 rep left',
  _ => 'Nothing left',
};

/// The anchor word for the whole workout's effort (session effort).
String sessionEffortAnchor(int value) => switch (value) {
  <= 2 => 'Very easy',
  <= 4 => 'Easy',
  <= 6 => 'Moderate',
  <= 8 => 'Hard',
  9 => 'Very hard',
  _ => 'Max',
};

/// A grid of the numbers 1 to 10, five to a row, with the chosen one filled.
/// Used for a set's effort and for the whole workout's effort.
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

  /// The words VoiceOver reads after the number ("3 reps left").
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

/// The compact effort picker for one set, or for filling every logged set
/// of an exercise that has no effort yet. Blank is allowed: the athlete can
/// close it without choosing.
class RpePicker extends StatelessWidget {
  const RpePicker({
    required this.title,
    required this.value,
    required this.onSelected,
    required this.dismissLabel,
    required this.onDismiss,
    this.onClear,
    super.key,
  });

  final String title;
  final int? value;
  final ValueChanged<int> onSelected;
  final String dismissLabel;
  final VoidCallback onDismiss;

  /// Shown when a value is set: makes the effort blank again.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final current = value;
    return Semantics(
      container: true,
      label: title,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            TracendSpacing.sm,
            TracendSpacing.sm,
            TracendSpacing.sm,
            TracendSpacing.xxs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: TracendSpacing.xs,
                runSpacing: 2,
                children: [
                  Text(title, style: text.titleSmall),
                  Text(
                    current == null
                        ? 'How many reps were left?'
                        : '$current: ${rpeHint(current)}',
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TracendSpacing.xs),
              EffortScale(
                value: current,
                onSelected: onSelected,
                describe: rpeHint,
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '1 very light · 10 nothing left',
                      style: text.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  if (current != null && onClear != null)
                    TextButton(onPressed: onClear, child: const Text('Clear')),
                  TextButton(onPressed: onDismiss, child: Text(dismissLabel)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
