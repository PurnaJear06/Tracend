import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/shared/widgets/expandable_text.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Pinned Head Coach decision (plan §6.2).
///
/// Binding contract:
/// - headline = `CoachDecision.finalDecision`
/// - body = `CoachDecision.reason` (expandable when it exceeds six lines)
/// - confidence ALWAYS from `CoachDecision.confidence` — never hardcoded
/// - evidence rows are display-only facts (no dead chevrons)
///
/// State table:
/// - loading → progress card
/// - decision == null → honest generate prompt
/// - decision != null → full render
class CoachDecisionCard extends StatelessWidget {
  const CoachDecisionCard({
    required this.decision,
    required this.loading,
    required this.generating,
    required this.onGenerate,
    super.key,
  });

  final CoachDecision? decision;
  final bool loading;
  final bool generating;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    if (loading) return const TracendCard(child: LinearProgressIndicator());
    final value = decision;
    if (value == null) {
      return TracendCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No daily decision yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: TracendSpacing.xs),
            const Text(
              'Generate one from your approved plan and latest confirmed evidence.',
            ),
            const SizedBox(height: TracendSpacing.sm),
            FilledButton(
              onPressed: generating ? null : onGenerate,
              child: const Text('Generate today’s decision'),
            ),
          ],
        ),
      );
    }
    final colors = context.tracendColors;
    return PremiumGradientCard(
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: colors.actionPrimary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: TracendSpacing.xs),
              Text(
                'HEAD COACH',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: colors.actionPrimary,
                ),
              ),
              const Spacer(),
              Icon(
                CupertinoIcons.pin_fill,
                size: 14,
                color: colors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.sm),
          ExpandableText(
            text: value.finalDecision,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(letterSpacing: -0.4),
          ),
          const SizedBox(height: TracendSpacing.xs),
          ExpandableText(text: value.reason),
          if (value.evidence.isNotEmpty) ...[
            const SizedBox(height: TracendSpacing.sm),
            for (final item in value.evidence)
              Padding(
                padding: const EdgeInsets.only(bottom: TracendSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      CupertinoIcons.check_mark_circled,
                      size: 14,
                      color: colors.stateStable,
                    ),
                    const SizedBox(width: TracendSpacing.xs),
                    Expanded(
                      child: Text(
                        item['label'] as String,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
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
                'Confidence: ${value.confidence}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontFamily: TracendFonts.monoFamily,
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: generating ? null : onGenerate,
              child: const Text('Refresh decision'),
            ),
          ),
        ],
      ),
    );
  }
}
