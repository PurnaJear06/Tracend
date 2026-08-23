import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Check-in prompt bar (Stitch `today.html`). Opens the real check-in sheet.
/// Always present (plan §4.1 binding table); copy reflects whether today's
/// check-in already exists.
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCheckIn,
        borderRadius: BorderRadius.circular(TracendRadii.control + 4),
        child: PremiumGradientCard(
          padding: const EdgeInsets.symmetric(
            horizontal: TracendSpacing.md,
            vertical: TracendSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                  border: Border.all(color: colors.borderHairline),
                ),
                child: Icon(
                  completed
                      ? CupertinoIcons.check_mark
                      : CupertinoIcons.chat_bubble,
                  size: 15,
                  color: completed ? colors.stateStable : colors.textSecondary,
                ),
              ),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(
                child: Text(
                  completed
                      ? 'Morning status recorded'
                      : 'Update morning status?',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
              Text(
                completed ? 'EDIT' : 'CHECK-IN',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: colors.actionPrimary,
                ),
              ),
              const SizedBox(width: TracendSpacing.xxs),
              Icon(
                CupertinoIcons.arrow_right,
                size: 16,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
