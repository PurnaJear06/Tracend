import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/pressable.dart';

/// The morning check-in. Before today's check-in it is a call to action with
/// a lime "Check in" pill; once done it shrinks to a quiet row that reopens
/// the sheet to update it.
class CheckInPromptBar extends StatelessWidget {
  const CheckInPromptBar({
    required this.onCheckIn,
    this.completed = false,
    super.key,
  });

  final VoidCallback onCheckIn;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    if (completed) {
      return TracendGroupedList(
        children: [
          TracendListRow(
            leading: TracendRowIcon(
              icon: CupertinoIcons.checkmark_alt,
              color: colors.stateStable,
            ),
            title: 'Morning check-in',
            subtitle: 'Done. Tap to update it.',
            onTap: onCheckIn,
          ),
        ],
      );
    }
    final textTheme = Theme.of(context).textTheme;
    // At the largest text sizes the pill moves under the copy.
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final badge = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.accentSignalTint,
        shape: BoxShape.circle,
      ),
      child: Icon(
        CupertinoIcons.sun_max_fill,
        size: 20,
        color: colors.accentSignalInk,
      ),
    );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Morning check-in', style: textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(
          "About a minute. It sharpens today's advice.",
          style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
    final pill = ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: colors.accentSignal,
          borderRadius: BorderRadius.circular(TracendRadii.pill),
        ),
        child: Text(
          'Check in',
          style: textTheme.labelLarge?.copyWith(
            color: colors.onAccentSignal,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    return Pressable(
      onTap: onCheckIn,
      pressedScale: 0.98,
      semanticLabel:
          "Morning check-in. About a minute. It sharpens today's advice.",
      borderRadius: BorderRadius.circular(TracendRadii.card),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(TracendRadii.card),
          border: Border.all(color: colors.accentSignalRing, width: 1.5),
        ),
        child: large
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      badge,
                      const SizedBox(width: TracendSpacing.sm),
                      Expanded(child: copy),
                    ],
                  ),
                  const SizedBox(height: TracendSpacing.sm),
                  pill,
                ],
              )
            : Row(
                children: [
                  badge,
                  const SizedBox(width: TracendSpacing.sm),
                  Expanded(child: copy),
                  const SizedBox(width: TracendSpacing.xs),
                  pill,
                ],
              ),
      ),
    );
  }
}
