import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/workout_draft.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';

/// Reps in reserve as shown on a cell or a logged set: 0 to 4, then "5+".
String rirLabel(int value) =>
    value >= WorkoutSetDraft.maxRir ? '${WorkoutSetDraft.maxRir}+' : '$value';

/// Reps in reserve in plain words.
String rirHint(int value) => switch (value) {
  <= 0 => 'Nothing left',
  1 => '1 rep left',
  >= WorkoutSetDraft.maxRir => '5 or more reps left',
  _ => '$value reps left',
};

/// The reps-left picker for one set, or for filling every logged set of an
/// exercise that has none yet: 0, 1, 2, 3, 4 and 5+ in one row. Blank is
/// allowed: the athlete can close it without choosing.
class RirPicker extends StatelessWidget {
  const RirPicker({
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

  /// Shown when a value is set: makes the reps left blank again.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final current = value;

    Widget cell(int number) {
      final selected = number == current;
      return Expanded(
        child: Semantics(
          selected: selected,
          inMutuallyExclusiveGroup: true,
          child: Pressable(
            semanticLabel: rirHint(number),
            borderRadius: BorderRadius.circular(TracendRadii.control),
            haptic: TracendHaptics.selection,
            onTap: () => onSelected(number),
            child: AnimatedContainer(
              duration: TracendMotion.quick,
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: selected ? colors.actionPrimary : colors.surface,
                borderRadius: BorderRadius.circular(TracendRadii.control),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  rirLabel(number),
                  maxLines: 1,
                  style: TracendTheme.numeric(
                    colors,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? colors.actionOnPrimary
                        : colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

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
                    'How many more reps could you do?',
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TracendSpacing.xs),
              Row(
                children: [
                  for (var n = 0; n <= WorkoutSetDraft.maxRir; n++) ...[
                    if (n > 0) const SizedBox(width: 6),
                    cell(n),
                  ],
                ],
              ),
              const SizedBox(height: TracendSpacing.xxs),
              Text(
                '0 nothing left · 5+ five or more',
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  children: [
                    if (current != null && onClear != null)
                      TextButton(
                        onPressed: onClear,
                        child: const Text('Clear'),
                      ),
                    TextButton(onPressed: onDismiss, child: Text(dismissLabel)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
