import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/shared/widgets/evidence_accordion.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// "Your coaching context" surface (plan §6.2).
///
/// All fields are real: availability, record counts, and latest dates come
/// from `get_my_coach_context_status`. Rows are display-only facts — no dead
/// chevrons or no-op callbacks.
class CoachContextCard extends StatelessWidget {
  const CoachContextCard({
    required this.sources,
    required this.loading,
    super.key,
  });

  final List<CoachContextSource>? sources;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const TracendCard(child: LinearProgressIndicator(minHeight: 3));
    }
    final values = sources ?? const <CoachContextSource>[];
    final available = values.where((source) => source.available).length;
    final missing = values.where((source) => !source.available).toList();
    return TracendCard(
      child: EvidenceAccordion(
        title: 'Your coaching context',
        subtitle:
            '$available of ${values.length} sources available'
            '${missing.isEmpty ? '' : ' · ${missing.length} needs data'}',
        child: Column(
          children: [
            for (final source in values)
              Padding(
                padding: const EdgeInsets.only(bottom: TracendSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      source.available
                          ? CupertinoIcons.check_mark_circled_solid
                          : CupertinoIcons.exclamationmark_circle,
                      size: 18,
                      color: source.available
                          ? context.tracendColors.stateStable
                          : context.tracendColors.stateAttention,
                    ),
                    const SizedBox(width: TracendSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.label,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            source.available
                                ? [
                                    if (source.records > 0)
                                      '${source.records} records',
                                    if (source.latestDate != null)
                                      'latest ${source.latestDate}',
                                  ].join(' · ')
                                : 'No confirmed records yet',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
