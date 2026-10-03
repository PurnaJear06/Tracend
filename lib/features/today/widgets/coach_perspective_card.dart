import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/today/widgets/today_hero.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_segmented_control.dart';

/// Today's coach note: one decision with its Training and Food perspectives
/// behind a segmented control, never two separate coaches.
///
/// Binding:
/// - the control switches `CoachDecision.trainingSummary` and
///   `nutritionSummary`
/// - the confidence word comes from `CoachDecision.confidence`, never a
///   hard-coded string
/// - no model version strings
///
/// The caller shows its own fallback when no decision exists.
class CoachPerspectiveCard extends StatefulWidget {
  const CoachPerspectiveCard({required this.decision, super.key});

  final CoachDecision decision;

  @override
  State<CoachPerspectiveCard> createState() => _CoachPerspectiveCardState();
}

enum _Perspective { training, food }

class _CoachPerspectiveCardState extends State<CoachPerspectiveCard> {
  _Perspective _perspective = _Perspective.training;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final decision = widget.decision;
    final summary = _perspective == _Perspective.training
        ? decision.trainingSummary
        : decision.nutritionSummary;

    return PremiumGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(decision.finalDecision, style: textTheme.titleMedium),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            decision.reason,
            style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: TracendSpacing.md),
          TracendSegmentedControl<_Perspective>(
            segments: const [
              (_Perspective.training, 'Training'),
              (_Perspective.food, 'Food'),
            ],
            selected: _perspective,
            onChanged: (value) => setState(() => _perspective = value),
          ),
          const SizedBox(height: TracendSpacing.sm),
          Text(summary, style: textTheme.bodyLarge),
          const SizedBox(height: TracendSpacing.sm),
          Text(
            '${confidenceLabel(decision.confidence)} · '
            '${_ageLabel(decision)}',
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// Honest age of the decision: "decided today", "decided yesterday" or
  /// "decided Sun 23 Aug". A stale decision never passes as today's.
  String _ageLabel(CoachDecision decision) {
    final date = DateTime.tryParse(decision.localDate);
    if (date == null) return 'decided ${decision.localDate}';
    final day = friendlyDate(date);
    return 'decided ${day == 'Today' || day == 'Yesterday' ? day.toLowerCase() : day}';
  }
}
