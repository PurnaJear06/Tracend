import 'package:flutter/cupertino.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';

/// The morning check-in row. Opens the check-in sheet; the copy says
/// whether today's check-in already exists.
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
    return TracendGroupedList(
      children: [
        TracendListRow(
          leading: completed
              ? TracendRowIcon(
                  icon: CupertinoIcons.checkmark_alt,
                  color: colors.stateStable,
                )
              : const TracendRowIcon(icon: CupertinoIcons.sun_max_fill),
          title: 'Morning check-in',
          subtitle: completed
              ? 'Done. Tap to update it.'
              : 'About a minute. It sharpens today\'s advice.',
          onTap: onCheckIn,
        ),
      ],
    );
  }
}
