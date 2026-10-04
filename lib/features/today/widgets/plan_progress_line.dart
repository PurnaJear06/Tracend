import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';

/// Where the active plan stands: its title, "Week 3 of 20" and a thin bar.
/// Past the block it reads "Week 22 · block of 20 done" with a full bar.
class PlanProgressLine extends StatelessWidget {
  const PlanProgressLine({required this.plan, super.key});

  final TodayPlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final done = plan.weekNumber > plan.blockWeeks;
    final week = done
        ? 'Week ${plan.weekNumber} · block of ${plan.blockWeeks} done'
        : 'Week ${plan.weekNumber} of ${plan.blockWeeks}';
    final fraction = done ? 1.0 : plan.weekNumber / plan.blockWeeks;
    return Semantics(
      label: '${plan.title}, $week',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: TracendSpacing.xs,
            children: [
              Text(plan.title, style: textTheme.labelLarge),
              Text(
                week,
                style: TracendTheme.numeric(
                  colors,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.02, 1.0),
              minHeight: 4,
              backgroundColor: colors.surfaceRaised,
              valueColor: AlwaysStoppedAnimation(colors.accentSignalRing),
            ),
          ),
        ],
      ),
    );
  }
}
