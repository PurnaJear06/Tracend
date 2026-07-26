import 'dart:math';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'computed_metrics.dart';

const _kArcStart = 5 * pi / 6;
const _kArcSweep = 4 * pi / 3;
const _kArcStrokeWidth = 12.0;

class RecoveryRing extends StatelessWidget {
  const RecoveryRing({required this.computed, this.size = 200, super.key});

  final ComputedMetrics computed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final score = computed.scores.recovery;
    final breakdown = computed.scores.recoveryBreakdown;
    final hasData = score != null;
    final confidence = computed.dataConfidence;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: hasData
              ? 'Recovery score $score out of 100'
              : 'Recovery score unavailable',
          child: SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: _RecoveryArcPainter(
                score: score,
                hasData: hasData,
                bgArcColor: colors.borderSubtle,
                stableColor: colors.stateStable,
                attentionColor: colors.stateAttention,
                lowConfidence: confidence == 'cold_start' || confidence == 'low',
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasData ? '$score' : '--',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: colors.textPrimary,
                        fontSize: _scoreFontSize(size),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      hasData ? _scoreLabel(score) : 'No data',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: hasData ? _labelColor(colors, score) : colors.textSecondary,
                      ),
                    ),
                    if (hasData && (confidence == 'cold_start' || confidence == 'low'))
                      Padding(
                        padding: const EdgeInsets.only(top: TracendSpacing.xxs),
                        child: Text(
                          'Building baseline',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (breakdown != null) ...[
          const SizedBox(height: TracendSpacing.sm),
          SizedBox(
            width: size,
            child: _DriverBreakdown(breakdown: breakdown),
          ),
        ],
      ],
    );
  }

  double _scoreFontSize(double ringSize) => ringSize * 0.17;

  String _scoreLabel(int score) {
    if (score >= 80) return 'Excellent';
    if (score >= 65) return 'Good';
    if (score >= 50) return 'Moderate';
    if (score >= 35) return 'Low';
    return 'Poor';
  }

  Color _labelColor(TracendColors colors, int score) {
    if (score >= 65) return colors.stateStable;
    if (score >= 50) return const Color(0xFFE2A45C);
    return colors.stateAttention;
  }
}

class _RecoveryArcPainter extends CustomPainter {
  _RecoveryArcPainter({
    required this.score,
    required this.hasData,
    required this.bgArcColor,
    required this.stableColor,
    required this.attentionColor,
    required this.lowConfidence,
  });

  final int? score;
  final bool hasData;
  final Color bgArcColor;
  final Color stableColor;
  final Color attentionColor;
  final bool lowConfidence;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = _kArcStrokeWidth;
    final rect = Rect.fromLTRB(
      stroke / 2,
      stroke / 2,
      size.width - stroke / 2,
      size.height - stroke / 2,
    );

    final bgPaint = Paint()
      ..color = bgArcColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, _kArcStart, _kArcSweep, false, bgPaint);

    if (!hasData) return;

    final value = score!.clamp(0, 100);
    final sweepProgress = _kArcSweep * value / 100;

    final gradient = SweepGradient(
      startAngle: _kArcStart,
      endAngle: _kArcStart + _kArcSweep,
      colors: [
        attentionColor,
        const Color(0xFFE2A45C),
        stableColor,
      ],
    );

    final arcPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, _kArcStart, sweepProgress, false, arcPaint);

    final indicatorAngle = _kArcStart + sweepProgress;
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = (size.width - stroke) / 2;
    final dotX = centerX + radius * cos(indicatorAngle);
    final dotY = centerY + radius * sin(indicatorAngle);

    final dotColor = _interpolateColor(
      attentionColor,
      stableColor,
      value / 100,
    );

    canvas.drawCircle(
      Offset(dotX, dotY),
      5.5,
      Paint()..color = dotColor,
    );

    canvas.drawCircle(
      Offset(dotX, dotY),
      10,
      Paint()
        ..color = dotColor.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
    );

    if (lowConfidence) {
      canvas.drawCircle(
        Offset(dotX, dotY),
        2.5,
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }
  }

  Color _interpolateColor(Color a, Color b, double t) {
    return Color.lerp(a, b, t.clamp(0.0, 1.0))!;
  }

  @override
  bool shouldRepaint(covariant _RecoveryArcPainter oldDelegate) =>
      score != oldDelegate.score ||
      hasData != oldDelegate.hasData ||
      lowConfidence != oldDelegate.lowConfidence;
}

class _DriverBreakdown extends StatelessWidget {
  const _DriverBreakdown({required this.breakdown});

  final RecoveryBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final drivers = [
      ('HRV', breakdown.hrvZ, colors.actionPrimary),
      ('RHR', breakdown.rhrZ, colors.stateStable),
      ('Sleep', breakdown.sleepZ, Colors.deepPurple.shade200),
      ('Resp', breakdown.respRateZ, const Color(0xFFE2A45C)),
      ('Strain', breakdown.prevStrainZ, colors.stateAttention),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recovery drivers',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: TracendSpacing.xs),
        Row(
          children: [
            for (var i = 0; i < drivers.length; i++) ...[
              if (i > 0) const SizedBox(width: TracendSpacing.xxs),
              Expanded(
                child: _DriverBar(
                  label: drivers[i].$1,
                  zScore: drivers[i].$2,
                  color: drivers[i].$3,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _DriverBar extends StatelessWidget {
  const _DriverBar({
    required this.label,
    required this.zScore,
    required this.color,
  });

  final String label;
  final double zScore;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final clamped = zScore.clamp(-2.0, 2.0);
    final filled = (clamped + 2.0) / 4.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 32,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.borderSubtle.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              AnimatedContainer(
                duration: TracendMotion.standard,
                curve: TracendMotion.curve,
                width: 4,
                height: 32 * filled,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: TracendSpacing.xxs),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontSize: 9,
            color: colors.textSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
