import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// Today's food against the active targets, under the "Food" section label.
///
/// Binding: eaten comes from `brief.nutrition` (`get_my_daily_nutrition`,
/// confirmed meals only); targets come from the active
/// `nutrition_target_sets` row.
///
/// State table:
/// - targets: a calories ring (lime) and a protein ring, each with the
///   amount eaten inside and what is left below, then "1,240 of 2,300 kcal
///   eaten"
/// - no targets: what was eaten, with an honest "no target" note and no ring
/// - "Log a meal" opens Nutrition; left out when not wired
class MetabolicTargetCard extends StatelessWidget {
  const MetabolicTargetCard({
    required this.consumed,
    required this.targets,
    required this.onLog,
    super.key,
  });

  /// `brief.nutrition` map (calories, protein_g, ...). May be null.
  final Map<String, dynamic>? consumed;

  /// Active nutrition targets. Null when no target set is active.
  final NutritionTargets? targets;

  /// Opens the Nutrition tab to log a meal.
  final VoidCallback? onLog;

  double get _calories => ((consumed?['calories'] as num?) ?? 0).toDouble();
  double get _protein => ((consumed?['protein_g'] as num?) ?? 0).toDouble();

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final targets = this.targets;
    final eaten = groupedThousands(_calories.round());
    final numberStyle = textTheme.headlineSmall?.copyWith(
      fontFamily: TracendFonts.numericFamily,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final secondary = textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
    );

    final List<Widget> body;
    if (targets == null) {
      body = [
        Text('$eaten kcal eaten', style: numberStyle),
        const SizedBox(height: TracendSpacing.xxs),
        Text('No nutrition target is set yet.', style: secondary),
      ];
    } else {
      final target = groupedThousands(targets.calories.round());
      final caloriesLeft = (targets.calories - _calories).clamp(
        0.0,
        targets.calories,
      );
      final proteinLeft = (targets.protein - _protein).clamp(
        0.0,
        targets.protein,
      );
      body = [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _RingTile(
                semanticLabel: '$eaten of $target kilocalories eaten',
                fraction: targets.calories <= 0
                    ? 0
                    : _calories / targets.calories,
                color: colors.accentSignalRing,
                value: eaten,
                unit: 'kcal',
                label: 'Calories',
                detail: caloriesLeft <= 0
                    ? 'Target reached'
                    : '${groupedThousands(caloriesLeft.round())} kcal left',
              ),
            ),
            const SizedBox(width: TracendSpacing.sm),
            Expanded(
              child: _RingTile(
                semanticLabel:
                    'Protein ${_protein.round()} of '
                    '${targets.protein.round()} grams',
                fraction: targets.protein <= 0 ? 0 : _protein / targets.protein,
                color: colors.stateStable,
                value: '${_protein.round()}',
                unit: 'g',
                label: 'Protein',
                detail: proteinLeft <= 0
                    ? 'Protein target reached'
                    : '${proteinLeft.round()} g left',
              ),
            ),
          ],
        ),
        const SizedBox(height: TracendSpacing.sm),
        Text('$eaten of $target kcal eaten', style: secondary),
      ];
    }

    final onLog = this.onLog;
    return PremiumGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...body,
          if (onLog != null) ...[
            const SizedBox(height: TracendSpacing.md),
            OutlinedButton.icon(
              onPressed: onLog,
              icon: const Icon(CupertinoIcons.plus, size: 18),
              label: const Text('Log a meal'),
            ),
          ],
        ],
      ),
    );
  }
}

/// One food target as a ring: the amount eaten inside, the name and what is
/// left below. The ring never passes full; going over reads "reached".
class _RingTile extends StatelessWidget {
  const _RingTile({
    required this.semanticLabel,
    required this.fraction,
    required this.color,
    required this.value,
    required this.unit,
    required this.label,
    required this.detail,
  });

  final String semanticLabel;
  final double fraction;
  final Color color;
  final String value;
  final String unit;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '$semanticLabel. $detail',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(TracendRadii.control + 4),
        ),
        child: Column(
          children: [
            SizedBox.square(
              dimension: 96,
              child: CustomPaint(
                painter: _RingPainter(
                  fraction: fraction.clamp(0.0, 1.0),
                  track: colors.borderSubtle,
                  fill: color,
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            value,
                            style: TracendTheme.numeric(
                              colors,
                              fontSize: 22,
                            ).copyWith(fontWeight: FontWeight.w700, height: 1),
                          ),
                          Text(
                            unit,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: TracendSpacing.sm),
            Text(
              label,
              style: textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.track,
    required this.fill,
  });

  final double fraction;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (fraction <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * fraction,
      false,
      paint..color = fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.track != track || old.fill != fill;
}

/// "1,240" for 1240. Whole numbers only; the sign is kept.
String groupedThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
