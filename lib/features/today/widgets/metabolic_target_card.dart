import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

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
///
/// Motion: at full motion each ring sweeps in from empty when it first
/// appears (protein 120 ms after calories) and the number inside counts up
/// with it; a later change animates from the old value. Reduced or static
/// motion draws the final state.
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
                amount: _calories,
                target: targets.calories,
                format: groupedThousands,
                color: colors.accentSignalRing,
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
                amount: _protein,
                target: targets.protein,
                format: (value) => '$value',
                color: colors.stateStable,
                unit: 'g',
                label: 'Protein',
                detail: proteinLeft <= 0
                    ? 'Protein target reached'
                    : '${proteinLeft.round()} g left',
                delay: const Duration(milliseconds: 120),
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
/// left below. Past the target the ring closes and a second, deeper lap runs
/// over it (capped at two laps); the text below says "reached".
///
/// At full motion the ring sweeps from empty to its value on first
/// appearance, after [delay], and the number inside counts up in step. When
/// [amount] changes, both run from the shown value to the new one.
class _RingTile extends StatefulWidget {
  const _RingTile({
    required this.semanticLabel,
    required this.amount,
    required this.target,
    required this.format,
    required this.color,
    required this.unit,
    required this.label,
    required this.detail,
    this.delay = Duration.zero,
  });

  final String semanticLabel;
  final double amount;
  final double target;
  final String Function(int value) format;
  final Color color;
  final String unit;
  final String label;
  final String detail;
  final Duration delay;

  @override
  State<_RingTile> createState() => _RingTileState();
}

class _RingTileState extends State<_RingTile>
    with SingleTickerProviderStateMixin {
  static const _sweep = Duration(milliseconds: 900);

  AnimationController? _controller;
  Curve _curve = const _RingSpring();
  double _from = 0;
  double _to = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = TracendMotionScope.of(context) == TracendMotionLevel.full;
    final controller = _controller;
    if (!animate) {
      // Motion was turned off: drop the controller and draw the final state.
      controller?.dispose();
      _controller = null;
      return;
    }
    if (controller != null) return;
    final total = _sweep + widget.delay;
    _curve = Interval(
      widget.delay.inMicroseconds / total.inMicroseconds,
      1,
      curve: const _RingSpring(),
    );
    _from = 0;
    _to = widget.amount;
    _controller = AnimationController(vsync: this, duration: total)..forward();
  }

  @override
  void didUpdateWidget(_RingTile old) {
    super.didUpdateWidget(old);
    final controller = _controller;
    if (controller == null || old.amount == widget.amount) return;
    _from = _shown;
    _to = widget.amount;
    _curve = const _RingSpring();
    controller
      ..duration = _sweep
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// The amount the ring shows right now.
  double get _shown {
    final controller = _controller;
    if (controller == null) return widget.amount;
    final t = _curve.transform(controller.value);
    return _from + (_to - _from) * t;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final controller = _controller;

    Widget ring(BuildContext context, Widget? _) {
      final shown = _shown;
      // The spring settles with a slight overshoot on the arc; the number
      // stays between the old and new values so it never reads past either.
      final low = math.min(_from, _to);
      final high = math.max(_from, _to);
      final number = controller == null
          ? widget.amount
          : shown.clamp(low, high).toDouble();
      final target = widget.target;
      return CustomPaint(
        painter: _RingPainter(
          progress: target <= 0 ? 0 : (shown / target).clamp(0.0, 2.0),
          color: widget.color,
          glow: dark ? 0.42 : 0.14,
          headShadow: dark ? 0.55 : 0.32,
          depth: dark ? 1 : 0.6,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.format(number.round()),
                    style: TracendTheme.numeric(
                      colors,
                      fontSize: 22,
                    ).copyWith(fontWeight: FontWeight.w700, height: 1),
                  ),
                  Text(
                    widget.unit,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: '${widget.semanticLabel}. ${widget.detail}',
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
              child: RepaintBoundary(
                child: controller == null
                    ? ring(context, null)
                    : AnimatedBuilder(animation: controller, builder: ring),
              ),
            ),
            const SizedBox(height: TracendSpacing.sm),
            Text(
              widget.label,
              style: textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              widget.detail,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A lightly under-damped spring (damping ratio 0.8) normalised to settle at
/// t = 1: a quick start, about 1.5% overshoot, then a soft landing.
class _RingSpring extends Curve {
  const _RingSpring();

  static const _zeta = 0.8;
  static const _omega = 8.75;

  @override
  double transformInternal(double t) {
    final damped = _omega * math.sqrt(1 - _zeta * _zeta);
    final decay = math.exp(-_zeta * _omega * t);
    return 1 -
        decay *
            (math.cos(damped * t) +
                _zeta * _omega / damped * math.sin(damped * t));
  }
}

/// An activity ring from 12 o'clock, clockwise.
///
/// [progress] runs to 2: the first lap is a gradient from a deeper tone at
/// the start to a brighter head, with a soft glow under it; past 1 a second,
/// deeper lap runs over the closed ring. The head carries a small bright dot
/// and, as it nears or passes the start, a shadow so the overlap reads.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.glow,
    required this.headShadow,
    required this.depth,
  });

  final double progress;
  final Color color;

  /// Opacity of the blurred glow under the first lap.
  final double glow;

  /// Opacity of the shadow the head casts on the lap beneath it.
  final double headShadow;

  /// How far the deeper tones lean towards black. Light mode ring colours
  /// are already deep, so they take less.
  final double depth;

  static const _stroke = 10.0;
  static const _top = -math.pi / 2;
  static const _black = Color(0xFF000000);
  static const _white = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Thin, low-contrast track: the ring colour at low opacity.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke * 0.42
        ..color = color.withValues(alpha: 0.16),
    );
    if (progress <= 0) return;

    final firstLap = progress.clamp(0.0, 1.0);
    if (glow > 0) {
      canvas.drawArc(
        rect,
        _top,
        math.pi * 2 * firstLap,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = _stroke
          ..color = color.withValues(alpha: glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    _lap(canvas, center, radius, firstLap, _deeper(0.28), _brighter);
    if (progress > 1) {
      _lap(canvas, center, radius, progress - 1, _deeper(0.48), _deeper(0.16));
    }

    // The head, last so it sits over everything it passes.
    final lap = progress > 1 ? progress - 1 : progress;
    final angle = _top + math.pi * 2 * lap;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final head = center + direction * radius;
    final shadow = ((progress - 0.9) / 0.1).clamp(0.0, 1.0) * headShadow;
    if (shadow > 0) {
      // Cast forward along the ring, clipped to the ring's band.
      final forward = Offset(-direction.dy, direction.dx);
      canvas
        ..save()
        ..clipPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addOval(
              Rect.fromCircle(center: center, radius: radius + _stroke / 2),
            )
            ..addOval(
              Rect.fromCircle(center: center, radius: radius - _stroke / 2),
            ),
        )
        ..drawCircle(
          head + forward * (_stroke * 0.3),
          _stroke / 2,
          Paint()
            ..color = _black.withValues(alpha: shadow)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
        )
        ..restore();
    }
    final headColor = progress > 1 ? _deeper(0.16) : _brighter;
    canvas
      ..drawCircle(head, _stroke / 2, Paint()..color = headColor)
      ..drawCircle(
        head,
        _stroke * 0.18,
        Paint()..color = _white.withValues(alpha: 0.92),
      );
  }

  Color _deeper(double amount) => Color.lerp(color, _black, amount * depth)!;

  Color get _brighter => Color.lerp(color, _white, 0.14)!;

  /// One lap of [fraction] (0 to 1) from 12 o'clock: a butt-ended gradient
  /// arc with a round start cap, so the gradient never wraps onto a cap. The
  /// head cap is drawn by the caller.
  void _lap(
    Canvas canvas,
    Offset center,
    double radius,
    double fraction,
    Color start,
    Color end,
  ) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = math.pi * 2 * fraction;
    canvas.drawCircle(
      center + Offset(0, -radius),
      _stroke / 2,
      Paint()..color = start,
    );
    canvas.drawArc(
      rect,
      _top,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt
        ..strokeWidth = _stroke
        ..shader = SweepGradient(
          colors: [start, end],
          stops: [0, fraction.clamp(0.001, 1.0)],
          transform: const GradientRotation(_top),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.glow != glow ||
      old.headShadow != headShadow ||
      old.depth != depth;
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
