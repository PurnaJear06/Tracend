import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';

/// What a logged set earned against the exercise history.
enum SetMark {
  /// Beats the best set ever logged and every earlier set today.
  newBest,

  /// The first set ever logged for this exercise.
  firstLog,
}

/// The lime "New best" stamp. [large] is the moment on the exercise card;
/// the small one marks the set in the log and on the summary.
class NewBestStamp extends StatelessWidget {
  const NewBestStamp({this.large = false, super.key});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accentSignal,
        borderRadius: BorderRadius.circular(large ? 10 : TracendRadii.pill),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: large ? TracendSpacing.sm : TracendSpacing.xs,
          vertical: large ? 6 : 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.rosette,
              size: large ? 17 : 13,
              color: colors.onAccentSignal,
            ),
            SizedBox(width: large ? 6 : 4),
            Flexible(
              child: Text(
                'New best',
                style: TextStyle(
                  fontFamily: TracendFonts.displayFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: large ? 15 : 12,
                  height: 1.2,
                  color: colors.onAccentSignal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The quiet "First log" tag: an outlined pill, not a celebration.
class FirstLogTag extends StatelessWidget {
  const FirstLogTag({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderSubtle),
        borderRadius: BorderRadius.circular(TracendRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        child: Text(
          'First log',
          style: TextStyle(
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w700,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// One done set in an exercise's log: its number, what was lifted, a mark
/// for a new best or a first log, the set's effort and undo. Without
/// [onUndo] the row is read-only (a finished workout).
class LoggedSetRow extends StatelessWidget {
  const LoggedSetRow({
    required this.number,
    required this.description,
    this.mark,
    this.rpe,
    this.onEffort,
    this.onUndo,
    super.key,
  });

  final int number;

  /// "60 kg × 8" or "12 reps".
  final String description;
  final SetMark? mark;
  final int? rpe;
  final VoidCallback? onEffort;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final compact = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final effortLabel = rpe == null ? 'Add effort' : 'RPE $rpe';
    final markLabel = switch (mark) {
      SetMark.newBest => ', new best',
      SetMark.firstLog => ', first log',
      null => '',
    };

    final summary = Wrap(
      spacing: TracendSpacing.xs,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          description,
          style: TracendTheme.numeric(
            colors,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (mark == SetMark.newBest) const NewBestStamp(),
        if (mark == SetMark.firstLog) const FirstLogTag(),
      ],
    );

    final actions = <Widget>[
      if (onEffort != null)
        Pressable(
          onTap: onEffort,
          semanticLabel: rpe == null
              ? 'Add effort for set $number'
              : 'Effort for set $number: $rpe, change',
          borderRadius: BorderRadius.circular(TracendRadii.pill),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  borderRadius: BorderRadius.circular(TracendRadii.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    effortLabel,
                    style: text.labelMedium?.copyWith(
                      color: rpe == null
                          ? colors.textSecondary
                          : colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        )
      else if (rpe != null)
        Text(
          effortLabel,
          style: text.labelMedium?.copyWith(color: colors.textSecondary),
        ),
      if (onUndo != null)
        Pressable(
          onTap: onUndo,
          haptic: TracendHaptics.light,
          semanticLabel: 'Undo set $number',
          borderRadius: BorderRadius.circular(TracendRadii.control),
          child: SizedBox.square(
            dimension: 44,
            child: Icon(
              CupertinoIcons.arrow_uturn_left,
              size: 18,
              color: colors.textSecondary,
            ),
          ),
        ),
    ];

    final numberLabel = ExcludeSemantics(
      child: SizedBox(
        width: 24,
        child: Text(
          '$number',
          textAlign: TextAlign.center,
          style: TracendTheme.numeric(
            colors,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: colors.textSecondary,
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      label: 'Set $number, $description$markLabel',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              numberLabel,
              const SizedBox(width: TracendSpacing.xs),
              Expanded(
                child: compact && actions.isNotEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ExcludeSemantics(child: summary),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: actions,
                          ),
                        ],
                      )
                    : ExcludeSemantics(child: summary),
              ),
              if (!compact) ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
