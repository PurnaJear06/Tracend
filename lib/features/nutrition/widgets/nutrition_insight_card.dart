import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Nutrition coach insight (plan §5.2, Stitch `nutrition.html` hero).
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
      glow: true,
      glowColor: colors.accentAmber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: colors.accentAmber,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: TracendSpacing.xs),
              Text(
                'COACH INSIGHT',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: colors.accentAmber,
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
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: TracendSpacing.sm),
          Divider(height: 1, color: colors.borderHairline),
          const SizedBox(height: TracendSpacing.sm),
          Row(
            children: [
              Icon(
                CupertinoIcons.sparkles,
                size: 14,
                color: colors.textSecondary,
              ),
              const SizedBox(width: TracendSpacing.xxs),
              Text(
                'Confidence: ${decision.confidence}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontFamily: TracendFonts.monoFamily,
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
