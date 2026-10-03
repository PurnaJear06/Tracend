import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/micro_motion.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// The "Today" verdict card: the recovery score in Archivo with its band
/// chip, the confidence word as small text, the readiness sentence (the
/// brief's next action and its reason), and the sync control.
///
/// It is a decision surface only. The workout, the check-in and the evidence
/// sit below it on Today; nothing here is a disabled button.
///
/// Score states:
/// - score present: the number, `/ 100`, and the band chip
///   (Excellent/Good/Moderate/Low/Poor)
/// - computed present but score null: `--` with honest next-step copy
/// - no computed block (older or fixture brief): the score area is left out
///
/// The sync row runs the sync-everything pipeline (Apple Health when
/// connected, the brief and today's decision). Its time is the last Apple
/// Health sync, written for people ("Today, 9:05 AM"), never an ISO date.
class TodayHero extends StatelessWidget {
  const TodayHero({
    required this.brief,
    this.onSync,
    this.syncing = false,
    this.syncIssue,
    super.key,
  });

  final DailyBrief brief;

  /// Sync-everything pipeline. Null renders the sync status as plain text.
  final VoidCallback? onSync;

  /// True while the sync pipeline runs.
  final bool syncing;

  /// What the last sync could not refresh, kept on screen until a sync
  /// succeeds, so the toast that reported it is never the only copy.
  final String? syncIssue;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final computed = brief.computed;
    final score = computed?.scores.recovery;
    final issue = syncIssue;

    return PremiumGradientCard(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.md,
        TracendSpacing.md,
        TracendSpacing.md,
        TracendSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A wrap, so the band chip drops under the label instead of
          // breaking mid-word at the largest text sizes.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: TracendSpacing.xs,
              runSpacing: TracendSpacing.xs,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Today',
                    style: textTheme.titleSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                if (score != null) _BandChip(score: score),
              ],
            ),
          ),
          if (computed != null) ...[
            const SizedBox(height: TracendSpacing.xxs),
            _Score(score: score),
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              score == null
                  ? 'Not enough data yet for a recovery score. Sync Apple '
                        'Health and check in to build your baseline.'
                  : 'Recovery score · '
                        '${confidenceLabel(computed.dataConfidence)}',
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: TracendSpacing.lg),
          ] else
            const SizedBox(height: TracendSpacing.sm),
          Text(brief.nextAction, style: textTheme.headlineSmall),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            brief.reason,
            style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: TracendSpacing.md),
          Divider(height: 1, thickness: 1, color: colors.borderHairline),
          _SyncControl(
            label: _syncLabel(context),
            syncing: syncing,
            onTap: onSync,
          ),
          if (issue != null)
            Padding(
              padding: const EdgeInsets.only(bottom: TracendSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      CupertinoIcons.exclamationmark_circle_fill,
                      size: 15,
                      color: colors.accentAmber,
                    ),
                  ),
                  const SizedBox(width: TracendSpacing.xs),
                  Expanded(
                    child: Text(
                      issue,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The last Apple Health sync from the brief's health payload, as
  /// "Today, 9:05 AM". Falls back to the health summary's day ("Mon 24
  /// Aug"); the decision time is never used, because a stale decision would
  /// misreport the sync state.
  String? _syncLabel(BuildContext context) {
    final lastSynced = brief.health?['last_synced_at'] as String?;
    final parsed = lastSynced == null ? null : DateTime.tryParse(lastSynced);
    if (parsed != null) {
      final local = parsed.toLocal();
      final time = MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(local),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
      return '${friendlyDate(local)}, $time';
    }
    final healthDate = brief.health?['local_date'] as String?;
    final day = healthDate == null ? null : DateTime.tryParse(healthDate);
    return day == null ? null : friendlyDate(day);
  }
}

/// "High confidence", "Medium confidence", "Low confidence", or "Building
/// baseline" for a cold start, from the brief's `data_confidence`.
String confidenceLabel(String? confidence) => switch (confidence) {
  'high' => 'High confidence',
  'medium' => 'Medium confidence',
  'low' => 'Low confidence',
  _ => 'Building baseline',
};

/// The recovery band word, its status tone and icon. Bands follow the
/// recovery score scale (DESIGN_SYSTEM.md §5.2).
(String, StatusTone, IconData) recoveryBand(int score) {
  if (score >= 80) {
    return ('Excellent', StatusTone.good, CupertinoIcons.checkmark_circle_fill);
  }
  if (score >= 65) {
    return ('Good', StatusTone.good, CupertinoIcons.checkmark_circle_fill);
  }
  if (score >= 50) {
    return ('Moderate', StatusTone.caution, CupertinoIcons.minus_circle_fill);
  }
  if (score >= 35) {
    return ('Low', StatusTone.low, CupertinoIcons.exclamationmark_circle_fill);
  }
  return ('Poor', StatusTone.low, CupertinoIcons.exclamationmark_circle_fill);
}

class _BandChip extends StatelessWidget {
  const _BandChip({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final (label, tone, icon) = recoveryBand(score);
    return Semantics(
      label: 'Recovery band: $label',
      excludeSemantics: true,
      child: StatusChip(label: label, icon: icon, tone: tone),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.score});

  final int? score;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final scoreStyle = textTheme.displayLarge?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final score = this.score;
    return Semantics(
      label: score == null
          ? 'Recovery score unavailable'
          : 'Recovery score $score out of 100',
      excludeSemantics: true,
      // The number scales down rather than overflow at the largest sizes.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (score == null)
              Text('--', style: scoreStyle)
            else
              MicroMotionCountUp(
                value: score,
                builder: (context, value) => Text('$value', style: scoreStyle),
              ),
            const SizedBox(width: TracendSpacing.xxs),
            Text(
              '/ 100',
              style: textTheme.titleMedium?.copyWith(
                fontFamily: TracendFonts.numericFamily,
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sync row at the foot of the card. States:
/// - syncing: spinner + "Syncing"
/// - idle with a time: refresh icon + "Sync · Today, 9:05 AM"
/// - idle without a time: refresh icon + "Sync"
/// - [onTap] null: the same text, not tappable
class _SyncControl extends StatelessWidget {
  const _SyncControl({
    required this.label,
    required this.syncing,
    required this.onTap,
  });

  final String? label;
  final bool syncing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final text = syncing
        ? 'Syncing'
        : label == null
        ? 'Sync'
        : 'Sync · $label';
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 16,
            child: syncing
                ? CupertinoActivityIndicator(
                    radius: 7,
                    color: colors.textSecondary,
                  )
                : Icon(
                    CupertinoIcons.arrow_2_circlepath,
                    size: 16,
                    color: colors.textSecondary,
                  ),
          ),
          const SizedBox(width: TracendSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
    if (onTap == null || syncing) return row;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel:
          '$text. Syncs Apple Health, the daily brief and the coach decision',
      borderRadius: BorderRadius.circular(TracendRadii.control),
      child: row,
    );
  }
}
