import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// A compact signal rail. It communicates which current facts shaped an action;
/// it is not a progress indicator and never repeats the action itself.
class TrajectoryLens extends StatelessWidget {
  const TrajectoryLens({
    this.decision = 'Maintain approved plan',
    this.evidence = const ['Approved plan'],
    super.key,
  });
  final String decision;
  final List<String> evidence;

  @override
  Widget build(BuildContext context) {
    final labels = evidence.take(3).toList();
    return Semantics(
      label: 'Signals shaping this action: ${labels.join(', ')}. $decision',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.tracendColors.surfaceRaised,
            borderRadius: BorderRadius.circular(TracendRadii.card),
            border: Border.all(color: context.tracendColors.borderSubtle),
          ),
          child: Padding(
            padding: const EdgeInsets.all(TracendSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.waveform_path_ecg,
                      size: 16,
                      color: context.tracendColors.stateStable,
                    ),
                    const SizedBox(width: TracendSpacing.xs),
                    Expanded(
                      child: Text(
                        'Signals shaping this · ${evidence.length}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: TracendSpacing.xs),
                Wrap(
                  spacing: TracendSpacing.xs,
                  runSpacing: TracendSpacing.xs,
                  children: [
                    for (final label in labels) _SignalChip(label: label),
                    if (evidence.length > labels.length)
                      _SignalChip(label: '+${evidence.length - labels.length}'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.tracendColors.actionPrimary.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: context.tracendColors.actionPrimary,
        ),
      ),
    ),
  );
}
