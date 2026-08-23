import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// One row of the [IntensityBar]: a planned target RPE plus the optional
/// recorded RPE actually logged for that movement.
class IntensityBarEntry {
  const IntensityBarEntry({
    required this.name,
    required this.targetRpe,
    this.recordedRpe,
  });

  final String name;

  /// Planned `planned_exercises.target_rpe` (0–10).
  final num targetRpe;

  /// Average RPE recorded across the movement's logged sets. Null when the
  /// session has no recorded RPE for this movement (no marker is drawn).
  final double? recordedRpe;
}

/// Per-exercise intensity readout (plan §5.1, master plan P1).
///
/// Binding contract — every mark traces to real data:
/// - bar fill = `planned_exercises.target_rpe` (0–10 scale)
/// - marker = recorded set RPE from the logged session draft (never the
///   hardcoded `session_effort = 8` written on save)
/// - context line = `computed.scores.dailyStrain`
///
/// State table:
/// - no entries: honest cold start ("Log a session to see intensity") —
///   bars are never invented
/// - entries, no recorded RPE: planned bars only, no marker
/// - entries + recorded RPE: planned bar + recorded marker
/// - dailyStrain null: context line hidden
class IntensityBar extends StatelessWidget {
  const IntensityBar({required this.entries, this.dailyStrain, super.key});

  final List<IntensityBarEntry> entries;
  final double? dailyStrain;

  static const _maxRpe = 10.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    if (entries.isEmpty) {
      return PremiumGradientCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IntensityTag(),
            const SizedBox(height: TracendSpacing.sm),
            Text(
              'Log a session to see intensity',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              'Planned RPE and recorded effort appear once a workout is assigned and logged.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return PremiumGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _IntensityTag()),
              if (dailyStrain != null)
                Text(
                  'STRAIN ${dailyStrain!.toStringAsFixed(1)}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontFamily: TracendFonts.monoFamily,
                    fontSize: 10,
                    letterSpacing: 0.8,
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: TracendSpacing.md),
          for (var i = 0; i < entries.length; i++) ...[
            _IntensityRow(entry: entries[i]),
            if (i < entries.length - 1)
              const SizedBox(height: TracendSpacing.sm),
          ],
          const SizedBox(height: TracendSpacing.sm),
          Row(
            children: [
              _LegendDot(color: colors.actionPrimary, label: 'Planned RPE'),
              const SizedBox(width: TracendSpacing.sm),
              _LegendDot(color: colors.stateStable, label: 'Recorded'),
            ],
          ),
        ],
      ),
    );
  }
}

class _IntensityTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.speed_rounded, size: 13, color: colors.actionPrimary),
        const SizedBox(width: TracendSpacing.xxs),
        Flexible(
          child: Text(
            'INTENSITY',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontSize: 10,
              letterSpacing: 1.4,
              color: colors.actionPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _IntensityRow extends StatelessWidget {
  const _IntensityRow({required this.entry});
  final IntensityBarEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final target = (entry.targetRpe.toDouble() / IntensityBar._maxRpe).clamp(
      0.0,
      1.0,
    );
    final recorded = entry.recordedRpe == null
        ? null
        : (entry.recordedRpe! / IntensityBar._maxRpe).clamp(0.0, 1.0);
    final label = entry.recordedRpe == null
        ? 'RPE ${_formatRpe(entry.targetRpe)}'
        : 'RPE ${_formatRpe(entry.targetRpe)} · logged '
              '${entry.recordedRpe!.toStringAsFixed(1)}';
    return Semantics(
      label:
          '${entry.name}, planned RPE ${_formatRpe(entry.targetRpe)}'
          '${entry.recordedRpe == null ? '' : ', recorded RPE ${entry.recordedRpe!.toStringAsFixed(1)}'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: TracendSpacing.sm),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontFamily: TracendFonts.monoFamily,
                  fontSize: 10,
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.xxs),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return SizedBox(
                height: 8,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: colors.borderSubtle.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: target,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colors.actionPrimary.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    if (recorded != null)
                      Positioned(
                        left: (recorded * width).clamp(0.0, width - 4),
                        top: -2,
                        bottom: -2,
                        child: Container(
                          width: 4,
                          decoration: BoxDecoration(
                            color: colors.stateStable,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static String _formatRpe(num value) =>
      value is int ? '$value' : value.toStringAsFixed(1);
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
      const SizedBox(width: TracendSpacing.xxs),
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: 10,
          color: context.tracendColors.textSecondary,
        ),
      ),
    ],
  );
}
