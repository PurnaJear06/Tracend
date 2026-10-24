import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/readiness/safety_copy.dart';

/// What Today says about pain reports that have not reached Tracend. A
/// report waiting on the phone must be sent within a day, because Tracend
/// records a pain report only for today or yesterday; one it refused as too
/// old was not recorded, and the athlete is told so rather than left to
/// assume it was (a red flag is never dropped silently).
class PainNoticeCard extends StatelessWidget {
  const PainNoticeCard({
    required this.waiting,
    required this.refused,
    required this.onTryAgain,
    required this.onReportAgain,
    required this.onAcknowledge,
    this.busy = false,
    super.key,
  });

  /// A pain report waits on this phone.
  final bool waiting;

  /// Tracend refused a pain report as too old; it was not recorded.
  final bool refused;
  final VoidCallback onTryAgain;
  final VoidCallback onReportAgain;
  final VoidCallback onAcknowledge;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (!waiting && !refused) return const SizedBox.shrink();
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: TracendSpacing.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(TracendSpacing.sm),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(TracendRadii.control + 4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (refused) ...[
              Row(
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    size: 17,
                    color: colors.stateDanger,
                  ),
                  const SizedBox(width: TracendSpacing.xs),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        painNotSentTitle,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                painNotSentBody,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: TracendSpacing.sm),
              FilledButton(
                onPressed: busy ? null : onReportAgain,
                child: const Text(painReportAgain),
              ),
              const SizedBox(height: TracendSpacing.xs),
              OutlinedButton(
                onPressed: busy ? null : onAcknowledge,
                child: const Text(painDismissNotSent),
              ),
            ],
            if (refused && waiting) const SizedBox(height: TracendSpacing.md),
            if (waiting) ...[
              Row(
                children: [
                  Icon(
                    CupertinoIcons.cloud_upload,
                    size: 17,
                    color: colors.accentAmber,
                  ),
                  const SizedBox(width: TracendSpacing.xs),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        painWaitingTitle,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                painWaitingBody,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: TracendSpacing.sm),
              OutlinedButton(
                onPressed: busy ? null : onTryAgain,
                child: const Text(painTryAgain),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
