import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class ReasoningChainCard extends StatefulWidget {
  const ReasoningChainCard({required this.chain, super.key});

  final List<Map<String, dynamic>> chain;

  @override
  State<ReasoningChainCard> createState() => _ReasoningChainCardState();
}

class _ReasoningChainCardState extends State<ReasoningChainCard> {
  bool _expanded = false;

  static const _stepIcons = <String, IconData>{
    'goal': CupertinoIcons.flag,
    'training_age': CupertinoIcons.time,
    'current_nutrition': CupertinoIcons.flame,
    'recovery_status': CupertinoIcons.heart,
    'adherence': CupertinoIcons.check_mark_circled,
    'conclusion': CupertinoIcons.lightbulb,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    if (widget.chain.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: TracendPill(
              label: _expanded ? 'Hide reasoning' : 'Show reasoning',
              icon: _expanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
              color: colors.textSecondary,
              compact: true,
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: TracendSpacing.xs),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: colors.borderSubtle.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(TracendRadii.control),
            ),
            child: Column(
              children: [
                for (var i = 0; i < widget.chain.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 28),
                      child: Container(
                        height: 1,
                        color: colors.borderSubtle.withValues(alpha: 0.4),
                      ),
                    ),
                  _ReasoningStep(
                    step: widget.chain[i]['step'] as String? ?? 'step',
                    value: widget.chain[i]['value'] as String? ?? '',
                    evidenceId: widget.chain[i]['evidence_id'] as String?,
                    icon: _stepIcons[widget.chain[i]['step']] ??
                        CupertinoIcons.circle,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ReasoningStep extends StatelessWidget {
  const _ReasoningStep({
    required this.step,
    required this.value,
    required this.icon,
    this.evidenceId,
  });

  final String step;
  final String value;
  final IconData icon;
  final String? evidenceId;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TracendSpacing.sm,
        vertical: TracendSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colors.actionPrimary),
          const SizedBox(width: TracendSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.replaceAll('_', ' '),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (evidenceId != null)
                  Text(
                    evidenceId!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
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
