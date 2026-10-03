import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_labels.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/shared/widgets/evidence_accordion.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_skeleton.dart';

/// "Your coaching context" surface (plan §6.2).
///
/// All fields are real: availability, record counts, and latest dates come
/// from `get_my_coach_context_status`. Rows are display-only facts, with no
/// chevrons or no-op callbacks. Dates read as words ("latest yesterday").
class CoachContextCard extends StatelessWidget {
  const CoachContextCard({
    required this.sources,
    required this.loading,
    this.now,
    super.key,
  });

  final List<CoachContextSource>? sources;
  final bool loading;

  /// The reference for "today" and "yesterday"; the clock when null.
  final DateTime? now;

  static const title = 'Your coaching context';

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Semantics(
        label: 'Loading your coaching context',
        child: const TracendCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TracendSkeleton.line(widthFactor: 0.55, height: 17),
              SizedBox(height: TracendSpacing.xs),
              TracendSkeleton.line(widthFactor: 0.4),
            ],
          ),
        ),
      );
    }
    final values = sources ?? const <CoachContextSource>[];
    final connected = values.where((source) => source.available).length;
    return TracendCard(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.md,
        TracendSpacing.xs,
        TracendSpacing.md,
        TracendSpacing.xs,
      ),
      child: EvidenceAccordion(
        title: title,
        subtitle: '$connected of ${values.length} sources connected',
        child: Padding(
          padding: const EdgeInsets.only(
            top: TracendSpacing.xs,
            bottom: TracendSpacing.xs,
          ),
          child: Column(
            children: [
              for (final (index, source) in values.indexed) ...[
                if (index > 0) const SizedBox(height: TracendSpacing.sm),
                _SourceRow(source: source, now: now),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.now});

  final CoachContextSource source;
  final DateTime? now;

  String get _detail {
    if (!source.available) return 'No confirmed records yet';
    final parts = [
      if (source.records > 0)
        source.records == 1 ? '1 record' : '${source.records} records',
      if (source.latestDate != null)
        coachLatestLabel(source.latestDate!, now: now),
    ];
    return parts.isEmpty ? 'Connected' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              source.available
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              size: 18,
              color: source.available
                  ? colors.stateStable
                  : colors.textSecondary,
            ),
          ),
          const SizedBox(width: TracendSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(source.label, style: textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  _detail,
                  style: textTheme.bodySmall?.copyWith(
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
