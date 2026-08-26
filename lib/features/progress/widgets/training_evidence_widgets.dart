import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Training evidence section: session adherence and best confirmed strength
/// values from `get_my_training_hub`. Progression values are facts, not
/// navigation — display-only with an honest caption (plan §6.1).
class TrainingEvidenceSection extends StatelessWidget {
  const TrainingEvidenceSection({required this.training, super.key});

  final TrainingHubData? training;

  @override
  Widget build(BuildContext context) {
    final hub = training;
    if (hub == null) {
      return const TracendCard(
        child: Text(
          'Training evidence is unavailable. Measurement and photo review remain available.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TracendCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${hub.completedSessions} of ${hub.plannedSessions} planned sessions completed',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: TracendSpacing.sm),
              LinearProgressIndicator(
                value: hub.plannedSessions == 0
                    ? 0
                    : (hub.completedSessions / hub.plannedSessions)
                          .clamp(0, 1)
                          .toDouble(),
              ),
            ],
          ),
        ),
        const SizedBox(height: TracendSpacing.sm),
        if (hub.progression.isEmpty)
          const TracendCard(
            child: Text(
              'Strength progression appears after completed comparable sets. Planned loads are never charted.',
            ),
          )
        else
          TracendCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in hub.progression)
                  Padding(
                    padding: const EdgeInsets.only(bottom: TracendSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.exercise,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                '${item.sessions} comparable sessions',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          item.bestLoadKg == null
                              ? '${item.bestRepetitions ?? '—'} reps'
                              : '${item.bestLoadKg} kg',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'Best confirmed values · display-only, no detail destination yet',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
