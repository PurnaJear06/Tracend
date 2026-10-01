import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// "High confidence" for `high`; any other value is shown as given.
String confidenceLabel(String confidence) => switch (confidence) {
  'high' => 'High confidence',
  'medium' => 'Medium confidence',
  'low' => 'Low confidence',
  _ => 'Confidence: $confidence',
};

/// Nutrition coach insight, shown below the day timeline as secondary
/// guidance (plan §5.2).
///
/// Binding contract:
/// - headline = `CoachDecision.nutritionAction`
/// - body = `CoachDecision.nutritionSummary`
/// - confidence ALWAYS from `CoachDecision.confidence` — never hardcoded
///
/// State table:
/// - decision == null → widget is hidden by the caller (never faked)
/// - decision != null → full render
class NutritionInsightCard extends StatelessWidget {
  const NutritionInsightCard({required this.decision, super.key});

  final CoachDecision decision;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return PremiumGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.chat_bubble_text_fill,
                size: 16,
                color: colors.accentAmber,
              ),
              const SizedBox(width: TracendSpacing.xs),
              Expanded(
                child: Text(
                  'COACH',
                  style: TracendTheme.labelCaps(
                    context,
                    color: colors.accentAmber,
                  ),
                ),
              ),
              Text(
                confidenceLabel(decision.confidence),
                style: TracendTheme.labelCaps(
                  context,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.sm),
          Text(
            decision.nutritionAction,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(letterSpacing: -0.4),
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            decision.nutritionSummary,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
