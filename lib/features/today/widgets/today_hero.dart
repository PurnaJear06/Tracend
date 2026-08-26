import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/shared/widgets/tracend_glass.dart';

/// Stitch `today.html` hero: confidence pill + sync control, decision
/// headline, reason, and the primary action with its secondary analytics
/// affordance. The 7-day trend lives below in `TrajectoryTrend` (Chunk 6) —
/// the hero stays a decision surface.
///
/// The headline uses the theme's `displaySmall` token unchanged (32pt,
/// DESIGN_SYSTEM §3.2 decision-headline): one primary action per screen, so
/// "View analytics" renders as a compact text affordance, never an equal
/// second button.
///
/// The sync chip is a real button (Chunk 7): tapping it syncs everything —
/// Apple Health (when connected), the daily brief, and today's coaching
/// decision. While running it shows a spinner; the timestamp beside it is
/// the last health sync, never a stale decision time.
class TodayHero extends StatelessWidget {
  const TodayHero({
    required this.brief,
    this.onStartSession,
    this.onViewAnalytics,
    this.onSync,
    this.syncing = false,
    super.key,
  });

  final DailyBrief brief;

  /// Starts the active workout. Null disables the button (no workout today) —
  /// never a no-op handler.
  final VoidCallback? onStartSession;

  /// Navigates to the Progress tab. Null hides the analytics button (no
  /// no-op affordance when the shell doesn't wire tab switching).
  final VoidCallback? onViewAnalytics;

  /// Sync-everything pipeline. Null renders the sync chip as inert text
  /// (only reachable from tests; TodayScreen always wires a pipeline, and in
  /// fixture mode a tap reloads fixtures without touching the network).
  final VoidCallback? onSync;

  /// True while the sync pipeline runs.
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final computed = brief.computed;
    final syncedAt = _syncLabel(brief);
    // At accessibility text sizes the two action labels no longer fit side by
    // side; stack them instead of overflowing (MetricStrip uses the same
    // scaler-threshold idiom).
    final verticalActions = MediaQuery.textScalerOf(context).scale(15) > 17;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: _ConfidencePill(confidence: computed?.dataConfidence),
            ),
            const SizedBox(width: TracendSpacing.xs),
            Flexible(
              child: _SyncChip(
                syncedAt: syncedAt,
                syncing: syncing,
                onTap: onSync,
              ),
            ),
          ],
        ),
        const SizedBox(height: TracendSpacing.md),
        Text(brief.nextAction, style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: TracendSpacing.sm),
        Text(
          brief.reason,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: TracendSpacing.lg),
        if (verticalActions)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: onStartSession,
                child: const Text('Start session'),
              ),
              if (onViewAnalytics != null) ...[
                const SizedBox(height: TracendSpacing.xs),
                TextButton(
                  onPressed: onViewAnalytics,
                  style: _analyticsButtonStyle(context, colors),
                  child: const Text('View analytics'),
                ),
              ],
            ],
          )
        else
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
                TextButton(
                  onPressed: onViewAnalytics,
                  style: _analyticsButtonStyle(context, colors),
                  child: const Text('View analytics'),
                ),
              ],
            ],
          ),
      ],
    );
  }

  ButtonStyle _analyticsButtonStyle(
    BuildContext context,
    TracendColors colors,
  ) => TextButton.styleFrom(
    minimumSize: const Size(44, 44),
    padding: const EdgeInsets.symmetric(horizontal: TracendSpacing.sm),
    foregroundColor: colors.textPrimary,
    textStyle: Theme.of(context).textTheme.labelLarge,
  );

  /// Last health sync time from the brief's health payload. Falls back to
  /// the health summary date; the decision `created_at` is deliberately not
  /// used because a stale decision would misreport the sync state.
  String? _syncLabel(DailyBrief brief) {
    final lastSynced = brief.health?['last_synced_at'] as String?;
    if (lastSynced != null) {
      final parsed = DateTime.tryParse(lastSynced);
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

/// Sync-everything chip. States:
/// - syncing: spinner + 'Syncing'
/// - idle with timestamp: refresh icon + 'Sync · 2:31 PM'
/// - idle without data yet: refresh icon + 'Sync'
/// - onTap null: inert text (no dead-button affordance)
class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.syncedAt, required this.syncing, this.onTap});

  final String? syncedAt;
  final bool syncing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final label = syncing
        ? 'Syncing'
        : syncedAt == null
        ? 'Sync'
        : 'Sync · $syncedAt';
    // Plain bordered capsule on purpose: the glass budget stays at its two
    // sanctioned sites (confidence pill + tab capsule).
    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border.all(color: colors.borderHairline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TracendSpacing.sm,
          vertical: TracendSpacing.xxs + 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (syncing)
              SizedBox(
                width: 10,
                height: 10,
                child: CupertinoActivityIndicator(
                  radius: 5,
                  color: colors.textSecondary,
                ),
              )
            else
              Icon(
                CupertinoIcons.arrow_2_circlepath,
                size: 12,
                color: colors.textSecondary,
              ),
            const SizedBox(width: TracendSpacing.xxs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontFamily: TracendFonts.monoFamily,
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null || syncing) return chip;
    return Semantics(
      label: 'Sync everything: Apple Health, daily brief, and coach decision',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Invisible vertical padding brings the hit area to the 44pt minimum
        // (DESIGN_SYSTEM §3.3) without growing the visible capsule.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: TracendSpacing.xxs + 6),
          child: chip,
        ),
      ),
    );
  }
}

class _ConfidencePill extends StatelessWidget {
  const _ConfidencePill({required this.confidence});
  final String? confidence;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final (label, dot) = switch (confidence) {
      'high' => ('HIGH CONFIDENCE', colors.accentNow),
      'medium' => ('MEDIUM CONFIDENCE', colors.actionPrimary),
      'low' => ('LOW CONFIDENCE', colors.accentAmber),
      _ => ('BUILDING BASELINE', colors.textSecondary),
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
                style: TracendTheme.labelCaps(
                  context,
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
