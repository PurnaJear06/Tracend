import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

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
    final colors = context.tracendColors;
    return Semantics(
      label:
          'Trajectory evidence: ${evidence.join(', ')}. Next move: $decision.',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scaledLabelSize = MediaQuery.textScalerOf(context).scale(13);
            final useCompactLayout =
                constraints.maxWidth < 300 || scaledLabelSize > 17;
            return Column(
              children: [
                if (useCompactLayout)
                  _CompactEvidence(colors: colors, evidence: evidence)
                else
                  Row(
                    children: [
                      for (var index = 0; index < evidence.length; index++) ...[
                        Expanded(
                          child: _point(
                            context,
                            evidence[index],
                            index == 0
                                ? colors.stateStable
                                : colors.actionPrimary,
                          ),
                        ),
                        if (index != evidence.length - 1)
                          _line(
                            index == 0
                                ? colors.stateStable
                                : colors.actionPrimary,
                            colors.actionPrimary,
                          ),
                      ],
                    ],
                  ),
                const SizedBox(height: TracendSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'NEXT MOVE · ${decision.toUpperCase()}',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.actionPrimary,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _point(BuildContext context, String label, Color color) {
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: context.tracendColors.surface, width: 3),
          ),
          child: const SizedBox.square(dimension: 14),
        ),
        const SizedBox(height: TracendSpacing.xs),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }

  Widget _line(Color start, Color end) {
    return SizedBox(
      width: 12,
      child: Container(
        height: 3,
        margin: const EdgeInsets.fromLTRB(4, 0, 4, 27),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [start, end]),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _CompactEvidence extends StatelessWidget {
  const _CompactEvidence({required this.colors, required this.evidence});

  final TracendColors colors;
  final List<String> evidence;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < evidence.length; index++) ...[
          _row(
            context,
            evidence[index],
            'Available',
            index == 0 ? colors.stateStable : colors.actionPrimary,
          ),
          if (index != evidence.length - 1)
            const SizedBox(height: TracendSpacing.xs),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, String label, String state, Color color) {
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: 10),
        ),
        const SizedBox(width: TracendSpacing.xs),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(width: TracendSpacing.sm),
        Flexible(
          child: Text(
            state,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
