import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Coach perspective (Stitch `today.html`): T-Coach / N-Coach segmented
/// control switching between the decision's real `trainingSummary` and
/// `nutritionSummary`, plus the head-coach final decision.
///
/// Binding contract (plan §4.1):
/// - toggle switches `CoachDecision.trainingSummary` ↔ `nutritionSummary`
/// - confidence ALWAYS from `CoachDecision.confidence` — never hardcoded
/// - no fabricated model version strings (Stitch's "v2.4" is omitted)
///
/// State table:
/// - decision == null → widget is hidden by the caller (fallback card instead)
/// - decision != null → full render
class CoachPerspectiveCard extends StatefulWidget {
  const CoachPerspectiveCard({required this.decision, super.key});

  final CoachDecision decision;

  @override
  State<CoachPerspectiveCard> createState() => _CoachPerspectiveCardState();
}

class _CoachPerspectiveCardState extends State<CoachPerspectiveCard> {
  bool _training = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final decision = widget.decision;
    final summary = _training
        ? decision.trainingSummary
        : decision.nutritionSummary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PerspectiveToggle(
          training: _training,
          onSelect: (training) => setState(() => _training = training),
        ),
        const SizedBox(height: TracendSpacing.sm),
        PremiumGradientCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                decision.finalDecision,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: TracendSpacing.xs),
              Text(
                summary,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w300),
              ),
              const SizedBox(height: TracendSpacing.xs),
              Text(
                decision.reason,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: TracendSpacing.sm),
              Divider(height: 1, color: colors.borderSubtle),
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
        ),
      ],
    );
  }
}

class _PerspectiveToggle extends StatelessWidget {
  const _PerspectiveToggle({required this.training, required this.onSelect});

  final bool training;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border.all(color: colors.borderHairline),
        borderRadius: BorderRadius.circular(TracendRadii.control + 4),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ToggleOption(
              label: 'T-COACH',
              selected: training,
              onTap: () => onSelect(true),
            ),
          ),
          Expanded(
            child: _ToggleOption(
              label: 'N-COACH',
              selected: !training,
              onTap: () => onSelect(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  const _ToggleOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Material(
      color: selected ? colors.canvas : Colors.transparent,
      borderRadius: BorderRadius.circular(TracendRadii.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TracendRadii.control),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontSize: 10,
              letterSpacing: 1.4,
              color: selected ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
