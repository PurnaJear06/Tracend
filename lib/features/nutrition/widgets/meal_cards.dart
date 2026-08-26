import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// One row of the confirmed meal schedule. Logged slots get a stable-green
/// check; due/upcoming slots keep the clock glyph. Display-only: logging
/// happens through the schedule card's primary action, not per-row taps.
class ScheduledMealRow extends StatelessWidget {
  const ScheduledMealRow({required this.item, super.key});
  final ScheduledMeal item;
  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final complete = item.status == 'logged';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: complete
                  ? colors.stateStable.withValues(alpha: 0.16)
                  : colors.surfaceRaised,
            ),
            child: Icon(
              complete ? CupertinoIcons.check_mark : CupertinoIcons.clock,
              size: 18,
              color: complete ? colors.stateStable : colors.textSecondary,
            ),
          ),
          const SizedBox(width: TracendSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      item.time,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontFamily: TracendFonts.monoFamily,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: TracendSpacing.xxs),
                Text(
                  item.foods.map((food) => food['name']).join(' · '),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  item.optional ? 'Optional · ${item.status}' : item.status,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirmed-meal timeline card. Status icon reflects the meal's confirmed
/// state; drafts expose a review action, every meal a delete action. Both
/// actions are wired to the repository — no dead affordances.
class MealCard extends StatelessWidget {
  const MealCard({
    required this.meal,
    required this.onReview,
    required this.onDelete,
    super.key,
  });
  final MealEntry meal;
  final VoidCallback? onReview;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final confirmed = meal.status == 'confirmed';
    return PremiumGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                confirmed
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.clock,
                size: 18,
                color: confirmed ? colors.stateStable : colors.textSecondary,
              ),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(
                child: Text(
                  meal.type,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                meal.status,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontFamily: TracendFonts.monoFamily,
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: colors.textSecondary,
                ),
              ),
              IconButton(
                key: ValueKey('delete-meal-${meal.id}'),
                onPressed: onDelete,
                tooltip: 'Delete meal',
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                icon: const Icon(CupertinoIcons.delete),
              ),
            ],
          ),
          if (meal.status == 'draft') ...[
            const SizedBox(height: TracendSpacing.xs),
            OutlinedButton.icon(
              key: ValueKey('review-meal-${meal.id}'),
              onPressed: onReview,
              icon: const Icon(CupertinoIcons.pencil),
              label: const Text('Review & edit draft'),
            ),
          ],
        ],
      ),
    );
  }
}
