import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Session Plan readout (Stitch `today.html` training module). Binds to the
/// brief's `today_workout` map — name, objective, movement/set counts folded
/// from the real `exercises` array (same pattern as train_screen.dart) — plus
/// an optional display-only load row carrying the real ACWR from
/// `ComputedScores.acwr` (Chunk 6; hidden when null, never fabricated).
///
/// State table:
/// - full: name + objective + `N MVMT · M SETS · ~X MIN`, chevron opens detail
/// - acwr present: load row `LOAD · 1.05 · Optimal` (0.8–1.3 optimal zone)
/// - null workout: "No session planned" (honest, no fabricated counts)
class SessionPlanCard extends StatelessWidget {
  const SessionPlanCard({
    required this.workout,
    required this.onOpen,
    this.acwr,
    super.key,
  });

  final Map<String, dynamic>? workout;
  final VoidCallback onOpen;

  /// Acute:Chronic Workload Ratio from computed scores. Null hides the row.
  final double? acwr;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    if (workout == null) {
      return PremiumGradientCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTag(label: 'SESSION PLAN', color: colors.stateStable),
            const SizedBox(height: TracendSpacing.sm),
            Text(
              'No session planned',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              'Your approved plan has no workout assigned today.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    final exercises = (workout!['exercises'] as List? ?? const []).length;
    final sets = (workout!['exercises'] as List? ?? const []).fold<int>(
      0,
      (sum, item) =>
          sum +
          ((item is Map ? item['set_count'] as num? : null)?.toInt() ?? 0),
    );
    final minutes = (workout!['estimated_minutes'] as num?)?.toInt();

    return PremiumGradientCard(
      glow: true,
      glowColor: colors.stateStable,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(TracendRadii.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CardTag(
                          label: 'SESSION PLAN',
                          color: colors.stateStable,
                        ),
                        const SizedBox(height: TracendSpacing.sm),
                        Text(
                          workout!['name'] as String? ?? 'Training session',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontSize: 22, letterSpacing: -0.4),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: TracendSpacing.xs),
              Text(
                workout!['objective'] as String? ??
                    'Complete the approved working sets.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: TracendSpacing.sm),
              Wrap(
                spacing: TracendSpacing.sm,
                runSpacing: TracendSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatChip(text: '$exercises MVMT'),
                  _Dot(),
                  _StatChip(text: '$sets SETS'),
                  if (minutes != null) ...[
                    _Dot(),
                    _StatChip(text: '~$minutes MIN'),
                  ],
                ],
              ),
              if (acwr != null) ...[
                const SizedBox(height: TracendSpacing.sm),
                _LoadRow(acwr: acwr!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CardTag extends StatelessWidget {
  const _CardTag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(CupertinoIcons.flag_fill, size: 13, color: color),
      const SizedBox(width: TracendSpacing.xxs),
      Flexible(
        child: Text(
          label,
          style: TracendTheme.labelCaps(context, color: color),
        ),
      ),
    ],
  );
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      fontFamily: TracendFonts.monoFamily,
      fontSize: 12,
      color: context.tracendColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

class _Dot extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 3,
    height: 3,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: context.tracendColors.borderHairline,
    ),
  );
}

/// Display-only training load row: real ACWR value + zone. Zone thresholds
/// match the sports-science convention used elsewhere in the app:
/// 0.8–1.3 optimal, below = low load, above = high load.
class _LoadRow extends StatelessWidget {
  const _LoadRow({required this.acwr});

  final double acwr;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final (zone, color) = acwr >= 0.8 && acwr <= 1.3
        ? ('Optimal', colors.stateStable)
        : acwr < 0.8
        ? ('Low load', colors.accentAmber)
        : ('High load', colors.stateAttention);

    return Semantics(
      label: 'Training load, ACWR ${acwr.toStringAsFixed(2)}, $zone',
      excludeSemantics: true,
      // container: the row sits inside the card's InkWell semantic boundary;
      // without an explicit container the label would merge into the button
      // node and VoiceOver would not read the row as its own element.
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: TracendSpacing.sm,
          vertical: TracendSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(TracendRadii.control),
        ),
        child: Row(
          children: [
            Text(
              'LOAD',
              style: TracendTheme.labelCaps(
                context,
                color: colors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              acwr.toStringAsFixed(2),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontFamily: TracendFonts.monoFamily,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: TracendSpacing.xs),
            Text(
              zone,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontSize: 11, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
