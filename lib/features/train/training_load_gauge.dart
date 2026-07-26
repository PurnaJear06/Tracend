import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

class TrainingLoadGauge extends StatelessWidget {
  const TrainingLoadGauge({required this.computed, super.key});

  final ComputedMetrics computed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final acwr = computed.scores.acwr;
    final monotony = computed.scores.trainingMonotony;
    final strain = computed.scores.dailyStrain;

    return TracendCard(
      raised: true,
      padding: const EdgeInsets.all(TracendSpacing.md),
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
            Divider(height: 1, color: colors.borderSubtle),
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
          child: const Icon(Icons.speed_rounded, size: 20, color: Color(0xFF59D6C7)),
        ),
        const SizedBox(width: TracendSpacing.sm),
        Column(
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
                Text(
                  displayAcwr != null ? 'ACWR $displayAcwr' : 'No data',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: acwr != null ? colors.textPrimary : colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.actionPrimary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _AcwrBar extends StatelessWidget {
  const _AcwrBar({required this.acwr});

  final double? acwr;

  static const _zones = [
    _Zone(0.0, 0.8, Color(0xFFAAB5C5), 'Undertraining'),
    _Zone(0.8, 1.1, Color(0xFF59D6C7), 'Optimal'),
    _Zone(1.1, 1.5, Color(0xFFE2A45C), 'Elevated'),
    _Zone(1.5, 2.2, Color(0xFFFF887D), 'High risk'),
  ];

  static const _maxDisplay = 2.2;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final barW = _barWidth(context);
    final a = acwr;
    final indicatorLeft = a != null
        ? (a.clamp(0, _maxDisplay) / _maxDisplay * barW)
            .clamp(2.0, barW - 2.0)
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
                    for (final zone in _zones)
                      Expanded(
                        flex: ((zone.end - zone.start) * 100).round(),
                        child: Container(color: zone.color.withValues(alpha: 0.35)),
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
              for (final zone in _zones)
                Text(
                  zone.start.toStringAsFixed(1),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 8,
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  double _barWidth(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return (size.width - TracendSpacing.md * 2 - TracendSpacing.gutter * 2).clamp(0, 400);
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
    final zone = _AcwrBar._zones.firstWhere(
      (z) => acwr >= z.start && acwr < z.end,
      orElse: () => _AcwrBar._zones.last,
    );

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: zone.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: TracendSpacing.xs),
        Text(
          zone.label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: zone.color,
          ),
        ),
        const Spacer(),
        Text(
          '${zone.start.toStringAsFixed(1)}\u2013${zone.end.toStringAsFixed(1)}',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.textSecondary,
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
          isHigh ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
          size: 16,
          color: isHigh ? colors.stateAttention : colors.stateStable,
        ),
        const SizedBox(width: TracendSpacing.xs),
        Text(
          'Monotony: ${monotony.toStringAsFixed(1)}',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(width: TracendSpacing.xs),
        Text(
          isHigh ? '(High \u2014 vary intensity)' : '(Balanced)',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
