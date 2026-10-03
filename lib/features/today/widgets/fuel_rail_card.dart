import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// Where one meal stands on today's fuel rail.
enum FuelMealState {
  /// A confirmed meal, at the time it was logged.
  logged,

  /// A meal-plan slot still ahead, or inside its hour.
  planned,

  /// A meal-plan slot more than an hour past with nothing logged.
  missed,
}

/// One meal on the rail.
class FuelRailMeal {
  const FuelRailMeal({
    required this.label,
    required this.minute,
    required this.state,
    this.protein,
  });

  final String label;

  /// Minutes after local midnight.
  final int minute;

  final FuelMealState state;

  /// Logged: grams eaten. Planned: the even share of what is left. Null when
  /// unknown (a slot the schedule marks logged without its meal loaded, or
  /// no protein target).
  final double? protein;
}

/// Today's fuel, worked out from confirmed meals, the active meal plan and
/// the protein target. Plain arithmetic; nothing is estimated.
class FuelDay {
  const FuelDay({
    required this.meals,
    required this.nowMinute,
    required this.proteinLeft,
    required this.mealsLeft,
    required this.planLoaded,
    required this.hasPlan,
  });

  /// Builds the day. [schedule] is null when the meal plan did not load, and
  /// has no items when no plan is active. Only confirmed [loggedMeals] count.
  factory FuelDay.from({
    required double proteinEaten,
    required double? proteinTarget,
    required NutritionSchedule? schedule,
    required List<MealEntry> loggedMeals,
    required DateTime now,
  }) {
    final nowMinute = now.hour * 60 + now.minute;
    final slots = schedule?.items ?? const <ScheduledMeal>[];
    final confirmed = [
      for (final meal in loggedMeals)
        if (meal.status == 'confirmed' && meal.loggedAt != null) meal,
    ];
    final filledSlots = {for (final meal in confirmed) meal.scheduleItemId};
    final slotLabels = {for (final slot in slots) slot.id: slot.label};

    final rail = <FuelRailMeal>[
      for (final meal in confirmed)
        FuelRailMeal(
          label: slotLabels[meal.scheduleItemId] ?? _mealTypeLabel(meal.type),
          minute: meal.loggedAt!.hour * 60 + meal.loggedAt!.minute,
          state: FuelMealState.logged,
          protein: meal.protein,
        ),
    ];
    final ahead = <(ScheduledMeal, int)>[];
    for (final slot in slots) {
      if (filledSlots.contains(slot.id)) continue;
      final minute = _clockMinute(slot.time);
      if (minute == null) continue;
      if (slot.status == 'logged') {
        rail.add(
          FuelRailMeal(
            label: slot.label,
            minute: minute,
            state: FuelMealState.logged,
          ),
        );
      } else if (minute + _slotWindow >= nowMinute) {
        ahead.add((slot, minute));
      } else {
        rail.add(
          FuelRailMeal(
            label: slot.label,
            minute: minute,
            state: FuelMealState.missed,
          ),
        );
      }
    }

    final proteinLeft = proteinTarget == null
        ? null
        : math.max(0.0, proteinTarget - proteinEaten);
    final share = proteinLeft == null || ahead.isEmpty
        ? null
        : proteinLeft / ahead.length;
    rail
      ..addAll([
        for (final (slot, minute) in ahead)
          FuelRailMeal(
            label: slot.label,
            minute: minute,
            state: FuelMealState.planned,
            protein: share,
          ),
      ])
      ..sort((a, b) => a.minute.compareTo(b.minute));

    return FuelDay(
      meals: rail,
      nowMinute: nowMinute,
      proteinLeft: proteinLeft,
      mealsLeft: ahead.length,
      planLoaded: schedule != null,
      hasPlan: slots.isNotEmpty,
    );
  }

  /// A slot stays ahead until an hour past its time.
  static const _slotWindow = 60;

  final List<FuelRailMeal> meals;
  final int nowMinute;

  /// Grams of protein still to eat; null without a protein target.
  final double? proteinLeft;

  /// Planned meals still ahead.
  final int mealsLeft;

  /// False when the meal plan failed to load.
  final bool planLoaded;

  /// True when an active meal plan has slots today.
  final bool hasPlan;

  /// The even protein share for each meal left; null when none are left.
  double? get perMeal {
    final left = proteinLeft;
    return left == null || mealsLeft == 0 ? null : left / mealsLeft;
  }

  /// The first minute the rail shows: 6:00, or the hour before an earlier
  /// meal.
  int get startMinute {
    final earliest = [
      nowMinute,
      for (final meal in meals) meal.minute,
    ].reduce(math.min);
    return math.max(0, math.min(6 * 60, (earliest - 45) ~/ 60 * 60));
  }

  /// The last minute the rail shows: 22:00, or the hour after a later meal.
  int get endMinute {
    final latest = [
      nowMinute,
      for (final meal in meals) meal.minute,
    ].reduce(math.max);
    return math.min(24 * 60, math.max(22 * 60, (latest + 104) ~/ 60 * 60));
  }

  static int? _clockMinute(String time) {
    final parts = time.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  static String _mealTypeLabel(String type) =>
      type.isEmpty ? 'Meal' : type[0].toUpperCase() + type.substring(1);
}

/// Today's food as a fuel rail, under the "Food" section label.
///
/// Binding: eaten totals come from `brief.nutrition`
/// (`get_my_daily_nutrition`, confirmed meals only); targets from the active
/// `nutrition_target_sets` row; the rail from `get_my_nutrition_schedule`
/// and today's confirmed `meals`. Nutrition stays the full ledger; this card
/// says what is left and how to spread it.
///
/// State table:
/// - protein left: "92 g protein to go" and "3 meals left, about 31 g each"
///   (the grams left split evenly over the planned meals still ahead)
/// - protein met: "Protein target reached"
/// - no targets: what was eaten, with an honest "no target" note
/// - no plan, or the plan did not load: said in the line under the headline
/// - the rail: logged meals as filled bars at their logged time, sized by
///   protein; planned meals as dashed bars sized by their share (the next
///   one in the accent); missed slots as hollow dots; a "now" needle over a
///   line filled up to now
/// - "Log a meal" opens Nutrition; left out when not wired
///
/// Motion: at full motion the line fills to now, the bars rise in turn, the
/// needle drops in, the labels fade up and the headline counts up. Reduced
/// or static motion draws the final state.
class FuelRailCard extends StatelessWidget {
  const FuelRailCard({
    required this.consumed,
    required this.targets,
    required this.day,
    required this.onLog,
    super.key,
  });

  /// `brief.nutrition` map (calories, protein_g, ...). May be null.
  final Map<String, dynamic>? consumed;

  /// Active nutrition targets. Null when no target set is active.
  final NutritionTargets? targets;

  /// The rail; null while the meal plan and meals load.
  final FuelDay? day;

  /// Opens the Nutrition tab to log a meal.
  final VoidCallback? onLog;

  double get _calories => ((consumed?['calories'] as num?) ?? 0).toDouble();
  double get _protein => ((consumed?['protein_g'] as num?) ?? 0).toDouble();

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final targets = this.targets;
    final day = this.day;
    final large = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final secondary = textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
    );

    final Widget headline;
    final String detail;
    if (targets == null) {
      headline = Text(
        '${groupedThousands(_calories.round())} kcal eaten',
        style: TracendTheme.numeric(colors, fontSize: 24),
      );
      detail = 'No nutrition target is set yet.';
    } else if (targets.protein - _protein <= 0) {
      headline = Text('Protein target reached', style: textTheme.titleLarge);
      detail =
          '${_protein.round()} of ${targets.protein.round()} g protein eaten';
    } else {
      headline = _CountUp(
        value: (targets.protein - _protein).round(),
        suffix: ' g protein to go',
      );
      detail = _planLine(day);
    }

    final calories = targets == null
        ? null
        : '${groupedThousands(_calories.round())} of '
              '${groupedThousands(targets.calories.round())} kcal';
    final onLog = this.onLog;
    final log = onLog == null
        ? null
        : OutlinedButton.icon(
            onPressed: onLog,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(CupertinoIcons.plus, size: 16),
            label: const Text('Log a meal'),
          );

    return PremiumGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          headline,
          const SizedBox(height: TracendSpacing.xxs),
          Text(detail, style: secondary),
          const SizedBox(height: TracendSpacing.md),
          if (day == null)
            const SizedBox(height: _FuelRail.railHeight)
          else
            _FuelRail(day: day),
          if (calories != null || log != null) ...[
            Divider(
              height: TracendSpacing.lg,
              thickness: 1,
              color: colors.borderHairline,
            ),
            if (large) ...[
              if (calories != null) Text(calories, style: secondary),
              if (log != null) ...[
                const SizedBox(height: TracendSpacing.xs),
                log,
              ],
            ] else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      calories ?? '',
                      style: secondary?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  ?log,
                ],
              ),
          ],
        ],
      ),
    );
  }

  static String _planLine(FuelDay? day) {
    if (day == null) return 'Loading your meal plan.';
    if (!day.planLoaded) return 'Your meal plan didn’t load. Pull to refresh.';
    if (!day.hasPlan) return 'No meal plan is set for today.';
    final perMeal = day.perMeal;
    if (perMeal == null) return 'No planned meals left today.';
    if (day.mealsLeft == 1) return '1 meal left, about ${perMeal.round()} g';
    return '${day.mealsLeft} meals left, about ${perMeal.round()} g each';
  }
}

/// The headline number, counting up from zero at full motion.
class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.suffix});

  final int value;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final animate = TracendMotionScope.of(context) == TracendMotionLevel.full;
    Widget line(int shown) => Semantics(
      label: '$value$suffix',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$shown',
              style: TracendTheme.numeric(
                colors,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: colors.accentSignalInk,
              ).copyWith(height: 1.05),
            ),
            TextSpan(text: suffix, style: textTheme.titleMedium),
          ],
        ),
      ),
    );
    if (!animate) return line(value);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, shown, _) => line(shown.round()),
    );
  }
}

/// The day as a line from morning to night: filled up to now, with each meal
/// standing on it and a needle at now. Labels sit under their meal; a label
/// that would overlap the one before it is left out (the rail's semantics
/// still name every meal).
class _FuelRail extends StatefulWidget {
  const _FuelRail({required this.day});

  final FuelDay day;

  /// The painted band: needle label, bars and the line.
  static const railHeight = 54.0;

  @override
  State<_FuelRail> createState() => _FuelRailState();
}

class _FuelRailState extends State<_FuelRail>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 1300);
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = TracendMotionScope.of(context) == TracendMotionLevel.full;
    if (!animate) {
      _controller?.dispose();
      _controller = null;
      return;
    }
    _controller ??= AnimationController(vsync: this, duration: _duration)
      ..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final day = widget.day;
    final controller = _controller;
    final nameStyle = textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
      fontSize: 11,
    );
    final gramStyle = TracendTheme.numeric(
      colors,
      fontSize: 11,
      fontWeight: FontWeight.w500,
    );
    final textScaler = MediaQuery.textScalerOf(context);

    return Semantics(
      label: _semantics(day),
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final rail = _RailScale(day, width);

          final labels = <Widget>[];
          // Names and grams sit on two lines; each line keeps its own edge.
          var nameRight = double.negativeInfinity;
          var gramRight = double.negativeInfinity;
          var labelHeight = 0.0;
          for (final meal in day.meals) {
            final grams = _grams(meal);
            final name = _measure(meal.label, nameStyle, textScaler);
            final gram = grams == null
                ? Size.zero
                : _measure(grams, gramStyle, textScaler);
            final muted = meal.state == FuelMealState.missed;
            final gramText = grams == null
                ? null
                : Text(
                    grams,
                    maxLines: 1,
                    softWrap: false,
                    style: meal.state == FuelMealState.logged
                        ? gramStyle
                        : gramStyle.copyWith(color: colors.textSecondary),
                  );
            double centred(double labelWidth) =>
                (rail.x(meal.minute) - labelWidth / 2)
                    .clamp(0.0, math.max(0.0, width - labelWidth))
                    .toDouble();

            // The name and grams; when that collides, the grams alone on
            // their own line; when that collides too, nothing.
            final fullWidth = math.max(name.width, gram.width) + 1;
            final full = centred(fullWidth);
            final gramLeft = full + (fullWidth - gram.width) / 2;
            labelHeight = math.max(labelHeight, name.height + gram.height + 2);
            if (full >= nameRight + 6 && gramLeft >= gramRight + 6) {
              nameRight = full + fullWidth;
              if (gramText != null) gramRight = gramLeft + gram.width;
              labels.add(
                Positioned(
                  left: full,
                  top: 0,
                  width: fullWidth,
                  child: Column(
                    children: [
                      Text(
                        meal.label,
                        maxLines: 1,
                        softWrap: false,
                        style: muted
                            ? nameStyle?.copyWith(
                                color: colors.textSecondary.withValues(
                                  alpha: 0.6,
                                ),
                              )
                            : nameStyle,
                      ),
                      if (gramText != null) ...[
                        const SizedBox(height: 2),
                        gramText,
                      ],
                    ],
                  ),
                ),
              );
              continue;
            }
            if (gramText == null) continue;
            final gramWidth = gram.width + 1;
            final gramsOnly = centred(gramWidth);
            if (gramsOnly < gramRight + 6) continue;
            gramRight = gramsOnly + gramWidth;
            labels.add(
              Positioned(
                left: gramsOnly,
                top: name.height + 2,
                width: gramWidth,
                child: Center(child: gramText),
              ),
            );
          }

          Widget painted(BuildContext context, Widget? _) => CustomPaint(
            size: Size(width, _FuelRail.railHeight),
            painter: _FuelRailPainter(
              day: day,
              progress: controller?.value ?? 1,
              line: colors.textSecondary.withValues(alpha: 0.22),
              fill: colors.accentSignalRing,
              planned: colors.textSecondary.withValues(alpha: 0.55),
              needle: colors.textPrimary,
              nowStyle: nameStyle?.copyWith(color: colors.textPrimary),
              textScaler: textScaler.clamp(maxScaleFactor: 1.2),
            ),
          );

          final labelBand = SizedBox(
            height: labelHeight,
            child: Stack(clipBehavior: Clip.none, children: labels),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RepaintBoundary(
                child: controller == null
                    ? painted(context, null)
                    : AnimatedBuilder(animation: controller, builder: painted),
              ),
              const SizedBox(height: TracendSpacing.xxs),
              if (controller == null)
                labelBand
              else
                FadeTransition(
                  opacity: CurvedAnimation(
                    parent: controller,
                    curve: const Interval(0.45, 0.9, curve: Curves.easeOut),
                  ),
                  child: labelBand,
                ),
            ],
          );
        },
      ),
    );
  }

  static String? _grams(FuelRailMeal meal) {
    final protein = meal.protein;
    if (protein == null || meal.state == FuelMealState.missed) return null;
    return meal.state == FuelMealState.planned
        ? '~${protein.round()} g'
        : '${protein.round()} g';
  }

  static Size _measure(String text, TextStyle? style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }

  static String _semantics(FuelDay day) {
    if (day.meals.isEmpty) return 'No meals on today’s rail yet.';
    final parts = [
      for (final meal in day.meals)
        switch (meal.state) {
          FuelMealState.logged =>
            meal.protein == null
                ? '${meal.label}, logged'
                : '${meal.label}, logged, '
                      '${meal.protein!.round()} grams protein',
          FuelMealState.planned =>
            meal.protein == null
                ? '${meal.label} at ${_clock(meal.minute)}, planned'
                : '${meal.label} at ${_clock(meal.minute)}, planned, '
                      'about ${meal.protein!.round()} grams protein',
          FuelMealState.missed =>
            '${meal.label} at ${_clock(meal.minute)}, not logged',
        },
    ];
    return 'Meals today. ${parts.join('. ')}.';
  }

  static String _clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:'
      '${(minute % 60).toString().padLeft(2, '0')}';
}

/// Maps a minute of the day to x on a rail [width] wide.
class _RailScale {
  const _RailScale(this.day, this.width);

  final FuelDay day;
  final double width;

  /// Keeps the end bars inside the card.
  static const inset = 12.0;

  double x(int minute) {
    final span = (day.endMinute - day.startMinute).toDouble();
    final t = ((minute - day.startMinute) / span).clamp(0.0, 1.0);
    return inset + (width - inset * 2) * t;
  }
}

/// Paints the rail. [progress] runs 0 to 1 through the entrance: the line
/// fills to now (0 to 0.5), each bar rises in turn (from 0.2, 0.08 apart)
/// and the needle drops in (0.35 to 0.7).
class _FuelRailPainter extends CustomPainter {
  _FuelRailPainter({
    required this.day,
    required this.progress,
    required this.line,
    required this.fill,
    required this.planned,
    required this.needle,
    required this.nowStyle,
    required this.textScaler,
  });

  final FuelDay day;
  final double progress;
  final Color line;
  final Color fill;
  final Color planned;
  final Color needle;
  final TextStyle? nowStyle;
  final TextScaler textScaler;

  static const _baseline = 46.0;
  static const _barWidth = 12.0;
  static const _minBar = 8.0;
  static const _maxBar = 30.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rail = _RailScale(day, size.width);
    const inset = _RailScale.inset;
    double phase(double start, double length) =>
        ((progress - start) / length).clamp(0.0, 1.0);

    canvas.drawLine(
      const Offset(inset, _baseline),
      Offset(size.width - inset, _baseline),
      Paint()
        ..color = line
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    final nowX = rail.x(day.nowMinute);
    final filled =
        inset + (nowX - inset) * Curves.easeOutCubic.transform(phase(0, 0.5));
    if (filled > inset + 0.5) {
      canvas.drawLine(
        const Offset(inset, _baseline),
        Offset(filled, _baseline),
        Paint()
          ..shader = LinearGradient(
            colors: [fill.withValues(alpha: 0.35), fill],
          ).createShader(Rect.fromLTRB(inset, 0, nowX, size.height))
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    final largest = [
      for (final meal in day.meals) meal.protein ?? 0,
    ].fold<double>(1, math.max);
    FuelRailMeal? next;
    for (final meal in day.meals) {
      if (meal.state == FuelMealState.planned) {
        next = meal;
        break;
      }
    }
    var index = 0;
    for (final meal in day.meals) {
      final x = rail.x(meal.minute);
      final rise = Curves.easeOutBack.transform(
        phase(0.2 + index++ * 0.08, 0.35),
      );
      if (rise <= 0) continue;
      if (meal.state == FuelMealState.missed) {
        canvas.drawCircle(
          Offset(x, _baseline),
          3.5 * rise,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = planned.withValues(alpha: 0.7),
        );
        continue;
      }
      final protein = meal.protein;
      final height =
          (protein == null
              ? _minBar
              : _minBar + (_maxBar - _minBar) * (protein / largest)) *
          rise;
      final bar = RRect.fromRectAndCorners(
        Rect.fromLTWH(
          x - _barWidth / 2,
          _baseline - 3 - height,
          _barWidth,
          height,
        ),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
        bottomLeft: const Radius.circular(1.5),
        bottomRight: const Radius.circular(1.5),
      );
      if (meal.state == FuelMealState.logged) {
        canvas.drawRRect(bar, Paint()..color = fill);
      } else {
        _dashed(canvas, bar, identical(meal, next) ? fill : planned);
      }
    }

    final drop = Curves.easeOutCubic.transform(phase(0.35, 0.35));
    if (drop > 0) {
      final top = 16.0 - (1 - drop) * 8;
      final paint = Paint()
        ..color = needle.withValues(alpha: drop)
        ..strokeWidth = 1.3;
      canvas
        ..drawLine(Offset(nowX, top), Offset(nowX, _baseline + 6), paint)
        ..drawCircle(Offset(nowX, top), 2.6, paint);
      final style = nowStyle;
      final label = TextPainter(
        text: TextSpan(
          text: 'now',
          style: style?.copyWith(color: style.color?.withValues(alpha: drop)),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      final labelX = (nowX - label.width / 2)
          .clamp(0.0, math.max(0.0, size.width - label.width))
          .toDouble();
      label
        ..paint(canvas, Offset(labelX, math.max(0.0, top - label.height - 2)))
        ..dispose();
    }
  }

  static void _dashed(Canvas canvas, RRect bar, Color color) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = color;
    final path = Path()..addRRect(bar.deflate(0.65));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 5) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + 2.5, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FuelRailPainter old) =>
      old.day != day ||
      old.progress != progress ||
      old.line != line ||
      old.fill != fill ||
      old.planned != planned ||
      old.needle != needle;
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
