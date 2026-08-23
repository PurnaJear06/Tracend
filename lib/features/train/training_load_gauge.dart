import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Training load gauge (Phase 4, real ACWR/monotony/strain) restyled into
/// the Precision Pro surface. Zone colors come from theme tokens.
class TrainingLoadGauge extends StatelessWidget {
  const TrainingLoadGauge({required this.computed, super.key});

  final ComputedMetrics computed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final acwr = computed.scores.acwr;
    final monotony = computed.scores.trainingMonotony;
    final strain = computed.scores.dailyStrain;

    return PremiumGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GaugeHeader(acwr: acwr, strain: strain),
          const SizedBox(height: TracendSpacing.md),
          _AcwrBar(acwr: acwr),
          if (acwr != null) ...[
            const SizedBox(height: TracendSpacing.sm),
            _ZoneLabel(acwr: acwr),
          ],
          if (monotony != null) ...[
            const SizedBox(height: TracendSpacing.md),
            Divider(height: 1, color: colors.borderHairline),
            const SizedBox(height: TracendSpacing.sm),
            _MonotonyRow(monotony: monotony),
          ],
        ],
      ),
    );
  }
}

class _GaugeHeader extends StatelessWidget {
  const _GaugeHeader({required this.acwr, required this.strain});

  final double? acwr;
  final double? strain;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final displayAcwr = acwr?.toStringAsFixed(2);
    final displayStrain = strain?.toStringAsFixed(1);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.stateStable.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(TracendRadii.control),
          ),
          child: Icon(Icons.speed_rounded, size: 20, color: colors.stateStable),
        ),
        const SizedBox(width: TracendSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TRAINING LOAD',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.stateStable,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: TracendSpacing.xxs),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayAcwr != null ? 'ACWR $displayAcwr' : 'No data',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontFamily: TracendFonts.monoFamily,
                            color: acwr != null
                                ? colors.textPrimary
                                : colors.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ),
                  if (strain != null) ...[
                    const SizedBox(width: TracendSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: TracendSpacing.xs,
                        vertical: TracendSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: colors.actionPrimary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Strain ${displayStrain!}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontFamily: TracendFonts.monoFamily,
                              color: colors.actionPrimary,
                              fontSize: 10,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AcwrBar extends StatelessWidget {
  const _AcwrBar({required this.acwr});

  final double? acwr;

  static const _maxDisplay = 2.2;

  static List<_Zone> _zones(TracendColors colors) => [
    _Zone(0.0, 0.8, colors.textSecondary, 'Undertraining'),
    _Zone(0.8, 1.1, colors.stateStable, 'Optimal'),
    _Zone(1.1, 1.5, colors.accentAmber, 'Elevated'),
    _Zone(1.5, 2.2, colors.stateAttention, 'High risk'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final zones = _zones(colors);
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth;
        final a = acwr;
        final indicatorLeft = a != null
            ? (a.clamp(0, _maxDisplay) / _maxDisplay * barWidth).clamp(
                2.0,
                barWidth - 2.0,
              )
            : null;
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 14,
                child: Stack(
                  children: [
                    Row(
                      children: [
                        for (final zone in zones)
                          Expanded(
                            flex: ((zone.end - zone.start) * 100).round(),
                            child: Container(
                              color: zone.color.withValues(alpha: 0.35),
                            ),
                          ),
                      ],
                    ),
                    if (indicatorLeft != null)
                      Positioned(
                        left: indicatorLeft,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 3,
                          decoration: BoxDecoration(
                            color: colors.textPrimary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (acwr != null) ...[
              const SizedBox(height: TracendSpacing.xxs),
              Row(
                children: [
                  for (final zone in zones)
                    Expanded(
                      child: Text(
                        zone.start.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontSize: 8,
                              fontFamily: TracendFonts.monoFamily,
                              color: colors.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Zone {
  final double start;
  final double end;
  final Color color;
  final String label;

  const _Zone(this.start, this.end, this.color, this.label);
}

class _ZoneLabel extends StatelessWidget {
  const _ZoneLabel({required this.acwr});

  final double acwr;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final zone = _AcwrBar._zones(colors).firstWhere(
      (z) => acwr >= z.start && acwr < z.end,
      orElse: () => _AcwrBar._zones(colors).last,
    );

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: zone.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: TracendSpacing.xs),
        Text(
          zone.label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: zone.color),
        ),
        const Spacer(),
        Text(
          '${zone.start.toStringAsFixed(1)}\u2013${zone.end.toStringAsFixed(1)}',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontFamily: TracendFonts.monoFamily,
            color: colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _MonotonyRow extends StatelessWidget {
  const _MonotonyRow({required this.monotony});

  final double monotony;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final isHigh = monotony > 2.0;

    return Row(
      children: [
        Icon(
          isHigh
              ? Icons.warning_amber_rounded
              : Icons.check_circle_outline_rounded,
          size: 16,
          color: isHigh ? colors.stateAttention : colors.stateStable,
        ),
        const SizedBox(width: TracendSpacing.xs),
        Text(
          'Monotony: ${monotony.toStringAsFixed(1)}',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontFamily: TracendFonts.monoFamily,
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: TracendSpacing.xs),
        Flexible(
          child: Text(
            isHigh ? '(High \u2014 vary intensity)' : '(Balanced)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}
