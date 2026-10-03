import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_labels.dart';

/// The structured reasoning a Coach reply returned (`reasoning_chain`), shown
/// inside the reply's evidence disclosure. These are the model's stated
/// steps, never hidden chain-of-thought. Each step reads as a named line: the
/// step in words ("Training experience") over its value. A step's
/// `evidence_id` is an internal code and is not shown; the cited evidence is
/// listed beside these steps.
class ReasoningSteps extends StatelessWidget {
  const ReasoningSteps({required this.chain, super.key});

  final List<Map<String, dynamic>> chain;

  static const _stepIcons = <String, IconData>{
    'goal': CupertinoIcons.flag,
    'training_age': CupertinoIcons.time,
    'current_nutrition': CupertinoIcons.flame,
    'recovery_status': CupertinoIcons.heart,
    'adherence': CupertinoIcons.check_mark_circled,
    'conclusion': CupertinoIcons.lightbulb,
  };

  /// The steps worth showing: those with a value.
  static List<Map<String, dynamic>> visible(List<Map<String, dynamic>> chain) =>
      [
        for (final step in chain)
          if ((step['value'] as String? ?? '').trim().isNotEmpty) step,
      ];

  @override
  Widget build(BuildContext context) {
    final steps = visible(chain);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, step) in steps.indexed) ...[
          if (index > 0) const SizedBox(height: TracendSpacing.sm),
          _ReasoningStep(
            label: coachReasoningStepLabel(step['step'] as String? ?? ''),
            value: (step['value'] as String).trim(),
            icon: _stepIcons[step['step']] ?? CupertinoIcons.circle,
          ),
        ],
      ],
    );
  }
}

class _ReasoningStep extends StatelessWidget {
  const _ReasoningStep({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: colors.textSecondary),
          ),
          const SizedBox(width: TracendSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label.isNotEmpty)
                  Text(
                    label,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  value,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
