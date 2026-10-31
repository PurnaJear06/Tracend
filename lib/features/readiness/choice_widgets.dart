import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';

// The pain questions' answer controls, shared by the daily check-in and the
// pain check during a workout: a 1 to 10 chip, and a titled list of choices
// (one answer, or ticks for any number).

/// One level of a 1 to 10 scale.
class SeverityChip extends StatelessWidget {
  const SeverityChip({
    required this.level,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final int level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: 'Pain $level of 10',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!selected) TracendHaptics.selection();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? colors.accentSignal : colors.surfaceRaised,
              borderRadius: BorderRadius.circular(TracendRadii.pill),
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Padding(
                padding: const EdgeInsets.all(TracendSpacing.xs),
                child: Text(
                  '$level',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFamily: TracendFonts.numericFamily,
                    color: selected
                        ? colors.onAccentSignal
                        : colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef Choice = ({String label, bool selected, VoidCallback onTap});

/// A titled single-choice list on one `surface`: rows with hairline
/// separators and a lime check on the selected row.
class ChoiceGroup extends StatelessWidget {
  const ChoiceGroup({
    required this.title,
    required this.options,
    this.exclusive = true,
    super.key,
  });

  final String title;
  final List<Choice> options;

  /// One answer at most (a check), or any number (ticks).
  final bool exclusive;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: TracendSpacing.xs),
          child: Semantics(
            header: true,
            child: Text(title, style: textTheme.titleMedium),
          ),
        ),
        Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(TracendRadii.card),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: TracendSpacing.md),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: colors.borderHairline,
                    ),
                  ),
                ChoiceRow(
                  title: title,
                  choice: options[i],
                  exclusive: exclusive,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    required this.title,
    required this.choice,
    required this.exclusive,
    super.key,
  });

  final String title;
  final Choice choice;
  final bool exclusive;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: choice.selected,
      inMutuallyExclusiveGroup: exclusive,
      label: '$title: ${choice.label}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          if (!choice.selected || !exclusive) TracendHaptics.selection();
          choice.onTap();
        },
        highlightColor: colors.surfaceRaised,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TracendSpacing.md,
              vertical: TracendSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    choice.label,
                    style: choice.selected
                        ? textTheme.titleSmall
                        : textTheme.bodyLarge?.copyWith(fontSize: 15),
                  ),
                ),
                const SizedBox(width: TracendSpacing.sm),
                SizedBox.square(
                  dimension: 20,
                  child: choice.selected
                      ? Icon(
                          CupertinoIcons.checkmark_alt,
                          size: 20,
                          color: colors.accentSignalInk,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
