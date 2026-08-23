import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';

/// Readiness strip (plan §4.3): three compact tiles — Recovery score + band +
/// driver z-chips, Training strain + ACWR, Nutrition adherence. Mono values,
/// asymmetric internals (big value left, chips right). The existing `onOpen`
/// detail sheet is preserved.
///
/// State table (per tile):
/// - full: real score → value + band + chips
/// - cold_start / null computed: '--' + honest fallback ("Check in"/"Updated",
///   "Rest day"/"Planned", "Up to date"/"Next meal")
class ReadinessStrip extends StatelessWidget {
  const ReadinessStrip({required this.brief, required this.onOpen, super.key});

  final DailyBrief brief;
  final void Function(String title, String detail) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Today’s readiness',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: TracendSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _RecoveryTile(brief: brief, onOpen: onOpen),
            ),
            const SizedBox(width: TracendSpacing.xs),
            Expanded(
              child: _TrainingTile(brief: brief, onOpen: onOpen),
            ),
            const SizedBox(width: TracendSpacing.xs),
            Expanded(
              child: _NutritionTile(brief: brief, onOpen: onOpen),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecoveryTile extends StatelessWidget {
  const _RecoveryTile({required this.brief, required this.onOpen});
  final DailyBrief brief;
  final void Function(String title, String detail) onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final computed = brief.computed;
    final score = computed?.scores.recovery;
    final breakdown = computed?.scores.recoveryBreakdown;

    final value = score != null ? '$score' : '--';
    final Color color;
    final String detail;
    if (score != null) {
      if (score >= 65) {
        detail = 'Good';
        color = colors.stateStable;
      } else if (score >= 50) {
        detail = 'Moderate';
        color = colors.accentAmber;
      } else {
        detail = 'Low';
        color = colors.stateAttention;
      }
    } else {
      detail = brief.checkIn == null ? 'Check in' : 'Updated';
      color = brief.checkIn == null
          ? colors.stateAttention
          : colors.actionPrimary;
    }

    return _ReadinessTile(
      label: 'Recovery',
      value: value,
      detail: detail,
      icon: CupertinoIcons.heart_fill,
      color: color,
      chips: breakdown == null
          ? const []
          : [
              _ZChip(label: 'HRV', z: breakdown.hrvZ),
              _ZChip(label: 'RHR', z: breakdown.rhrZ),
              _ZChip(label: 'SLP', z: breakdown.sleepZ),
            ],
      onTap: () => onOpen(
        'Recovery',
        score != null
            ? 'Recovery score derived from HRV, resting HR, sleep, respiratory rate, and prior strain. Score: $score/100.'
            : brief.checkIn == null
            ? 'Tracend needs today’s energy, sleep, soreness and pain check-in before adapting your session.'
            : 'Today’s user-confirmed recovery check-in is available to the coach.',
      ),
    );
  }
}

class _TrainingTile extends StatelessWidget {
  const _TrainingTile({required this.brief, required this.onOpen});
  final DailyBrief brief;
  final void Function(String title, String detail) onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final computed = brief.computed;
    final acwr = computed?.scores.acwr;
    final strain = computed?.scores.dailyStrain;

    final value = acwr != null ? acwr.toStringAsFixed(2) : '--';
    final Color color;
    final String detail;
    if (acwr != null) {
      if (acwr >= 0.8 && acwr <= 1.3) {
        detail = 'Optimal';
        color = colors.stateStable;
      } else if (acwr < 0.8) {
        detail = 'Low load';
        color = colors.accentAmber;
      } else {
        detail = 'High load';
        color = colors.stateAttention;
      }
    } else {
      detail = brief.workout == null ? 'Rest day' : 'Planned';
      color = brief.workout == null
          ? colors.textSecondary
          : colors.actionPrimary;
    }

    return _ReadinessTile(
      label: 'Load',
      value: value,
      detail: detail,
      icon: CupertinoIcons.bolt_fill,
      color: color,
      chips: strain == null
          ? const []
          : [_ZChip(label: 'STRAIN', z: strain, raw: true)],
      onTap: () => onOpen(
        'Training Load',
        acwr != null
            ? 'Acute:Chronic Workload Ratio (ACWR). ${acwr.toStringAsFixed(2)} — 0.8–1.3 is the optimal training zone.'
            : brief.workout == null
            ? 'Your approved plan has no workout assigned today.'
            : '${brief.workout!['name']} comes from your active approved plan.',
      ),
    );
  }
}

class _NutritionTile extends StatelessWidget {
  const _NutritionTile({required this.brief, required this.onOpen});
  final DailyBrief brief;
  final void Function(String title, String detail) onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final adherence = brief.computed?.scores.macroAdherencePct;

    final value = adherence != null ? '$adherence%' : '--';
    final Color color;
    final String detail;
    if (adherence != null) {
      if (adherence >= 90) {
        detail = 'On track';
        color = colors.stateStable;
      } else if (adherence >= 70) {
        detail = 'Partial';
        color = colors.accentAmber;
      } else {
        detail = 'Off track';
        color = colors.stateAttention;
      }
    } else {
      detail = brief.nextMeal == null ? 'Up to date' : 'Next meal';
      color = brief.nextMeal == null
          ? colors.textSecondary
          : colors.accentAmber;
    }

    return _ReadinessTile(
      label: 'Nutrition',
      value: value,
      detail: detail,
      icon: CupertinoIcons.leaf_arrow_circlepath,
      color: color,
      chips: const [],
      onTap: () => onOpen(
        'Nutrition',
        adherence != null
            ? 'Macro adherence: $adherence%. Protein, carbs, and fat within targets over the last 7 days.'
            : brief.nextMeal == null
            ? 'There is no remaining scheduled meal action right now.'
            : '${brief.nextMeal!['label']} is next at ${brief.nextMeal!['local_time']}.',
      ),
    );
  }
}

class _ReadinessTile extends StatelessWidget {
  const _ReadinessTile({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    required this.chips,
    required this.onTap,
  });

  final String label, value, detail;
  final IconData icon;
  final Color color;
  final List<Widget> chips;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(TracendRadii.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TracendRadii.control),
        child: Padding(
          padding: const EdgeInsets.all(TracendSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: TracendSpacing.xxs),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontSize: 10,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TracendSpacing.xs),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: TracendFonts.monoFamily,
                  fontSize: 20,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: TracendSpacing.xxs),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: TracendSpacing.xs),
                Wrap(
                  spacing: TracendSpacing.xxs,
                  runSpacing: TracendSpacing.xxs,
                  children: chips,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact z-score chip. Positive z (above baseline) reads stable; negative
/// reads attention. `raw` renders a magnitude as-is in a neutral accent —
/// strain is not a signed z-score, so color must not imply good/bad.
class _ZChip extends StatelessWidget {
  const _ZChip({required this.label, required this.z, this.raw = false});

  final String label;
  final double z;
  final bool raw;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final Color accent;
    if (raw) {
      accent = colors.textSecondary;
    } else {
      accent = z >= 0 ? colors.stateStable : colors.stateAttention;
    }
    final text = raw
        ? z.toStringAsFixed(1)
        : '${z >= 0 ? '+' : ''}${z.toStringAsFixed(1)}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          '$label $text',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontFamily: TracendFonts.monoFamily,
            fontSize: 9,
            color: accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
