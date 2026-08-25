import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/shared/widgets/tracend_glass.dart';

/// Stitch `today.html` hero: confidence pill + sync time, decision headline,
/// reason, and the two primary actions. The 7-day trend lives below in
/// `TrajectoryTrend` (Chunk 6) — the hero stays a decision surface.
class TodayHero extends StatelessWidget {
  const TodayHero({
    required this.brief,
    this.onStartSession,
    this.onViewAnalytics,
    super.key,
  });

  final DailyBrief brief;

  /// Starts the active workout. Null disables the button (no workout today) —
  /// never a no-op handler.
  final VoidCallback? onStartSession;

  /// Navigates to the Progress tab. Null hides the analytics button (no
  /// no-op affordance when the shell doesn't wire tab switching).
  final VoidCallback? onViewAnalytics;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final computed = brief.computed;
    final syncedAt = _syncLabel(brief);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: _ConfidencePill(confidence: computed?.dataConfidence),
            ),
            if (syncedAt != null) ...[
              const SizedBox(width: TracendSpacing.xs),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.arrow_2_circlepath,
                      size: 13,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: TracendSpacing.xxs),
                    Flexible(
                      child: Text(
                        syncedAt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontFamily: TracendFonts.monoFamily,
                              fontSize: 11,
                              color: colors.textSecondary,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: TracendSpacing.md),
        Text(
          brief.nextAction,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontSize: 42,
            height: 1.05,
            letterSpacing: -1.26,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: TracendSpacing.sm),
        Text(
          brief.reason,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: TracendSpacing.lg),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: onStartSession,
                child: const Text('Start session'),
              ),
            ),
            if (onViewAnalytics != null) ...[
              const SizedBox(width: TracendSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: onViewAnalytics,
                  child: const Text('View analytics'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Sync timestamp from the coaching decision `created_at`, falling back to
  /// the health summary `local_date`. Hidden when neither exists.
  String? _syncLabel(DailyBrief brief) {
    final createdAt = brief.decision?['created_at'] as String?;
    if (createdAt != null) {
      final parsed = DateTime.tryParse(createdAt);
      if (parsed != null) return _timeOfDay(parsed.toLocal());
    }
    final healthDate = brief.health?['local_date'] as String?;
    if (healthDate != null) return healthDate;
    return null;
  }

  String _timeOfDay(DateTime value) {
    final hour24 = value.hour;
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $suffix';
  }
}

class _ConfidencePill extends StatelessWidget {
  const _ConfidencePill({required this.confidence});
  final String? confidence;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final (label, dot) = switch (confidence) {
      'high' => ('High confidence', colors.accentNow),
      'medium' => ('Medium confidence', colors.actionPrimary),
      'low' => ('Low confidence', colors.accentAmber),
      _ => ('Building baseline', colors.textSecondary),
    };

    return TracendGlass(
      borderRadius: 999,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TracendSpacing.sm,
          vertical: TracendSpacing.xxs + 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
            ),
            const SizedBox(width: TracendSpacing.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
