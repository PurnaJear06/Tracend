import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_segmented_control.dart';

/// The round check used by choice cards and check rows: a filled lime disc
/// with a check when on, an empty ring when off.
class CheckMark extends StatelessWidget {
  const CheckMark({required this.checked, super.key});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: TracendMotionScope.movement(context, TracendMotion.quick),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: checked ? colors.accentSignal : Colors.transparent,
          border: checked
              ? null
              : Border.all(color: colors.textTertiary, width: 1.5),
        ),
        child: checked
            ? Icon(
                CupertinoIcons.checkmark_alt,
                size: 16,
                color: colors.onAccentSignal,
              )
            : null,
      ),
    );
  }
}

/// One answer from a few short options: a segmented control, or a list of
/// rows once large text would squeeze the segments.
class SingleChoice<T extends Object> extends StatelessWidget {
  const SingleChoice({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final String label;
  final List<(T, String)> options;
  final T? selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
      return Semantics(
        label: label,
        container: true,
        child: TracendSegmentedControl<Object>(
          segments: [for (final (value, text) in options) (value, text)],
          // An unanswered question selects no segment.
          selected: selected ?? const Object(),
          onChanged: (value) => onChanged(value as T),
        ),
      );
    }
    return TracendGroupedList(
      children: [
        for (final (value, text) in options)
          CheckRow(
            title: text,
            checked: value == selected,
            exclusive: true,
            onChanged: (_) => onChanged(value),
          ),
      ],
    );
  }
}

/// A grouped-list row the athlete checks. The whole row is the target, and
/// VoiceOver reads it as a checkbox with its state.
class CheckRow extends StatelessWidget {
  const CheckRow({
    required this.title,
    required this.checked,
    required this.onChanged,
    this.exclusive = false,
    super.key,
  });

  final String title;
  final bool checked;
  final ValueChanged<bool> onChanged;

  /// One of a set where only one can be chosen (read as selected, not
  /// checked).
  final bool exclusive;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    checked: exclusive ? null : checked,
    selected: exclusive ? checked : null,
    inMutuallyExclusiveGroup: exclusive ? true : null,
    button: true,
    label: title,
    excludeSemantics: true,
    child: InkWell(
      onTap: () => onChanged(!checked),
      highlightColor: context.tracendColors.surfaceRaised,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: TracendListRow.minHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TracendListRow.horizontalPadding,
            vertical: 10,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const SizedBox(width: TracendSpacing.sm),
              CheckMark(checked: checked),
            ],
          ),
        ),
      ),
    ),
  );
}
