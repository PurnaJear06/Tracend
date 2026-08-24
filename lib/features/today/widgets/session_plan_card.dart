import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Session Plan readout (Stitch `today.html` training module). Binds to the
/// brief's `today_workout` map — name, objective, movement/set counts folded
/// from the real `exercises` array (same pattern as train_screen.dart).
///
/// State table:
/// - full: name + objective + `N MVMT · M SETS · ~X MIN`, chevron opens detail
/// - null workout: "No session planned" (honest, no fabricated counts)
class SessionPlanCard extends StatelessWidget {
  const SessionPlanCard({
    required this.workout,
    required this.onOpen,
    super.key,
  });

  final Map<String, dynamic>? workout;
  final VoidCallback onOpen;

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
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontSize: 10,
            letterSpacing: 1.4,
            color: color,
          ),
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
