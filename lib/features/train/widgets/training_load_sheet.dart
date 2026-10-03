import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/train_view_models.dart';
import 'package:tracend/features/train/widgets/train_parts.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// Opens the Training load sheet: the verdict, the low/normal/high scale,
/// the last 7 days shaded easy, moderate or hard, one advice line and how
/// it is calculated. Everything comes from [model]; nothing is estimated.
Future<void> showTrainingLoadSheet(
  BuildContext context, {
  required TrainingLoadSheetModel model,
}) => showTracendSheet<void>(
  context,
  title: 'Training load',
  subtitle: 'How much you have trained lately',
  builder: (_) => TrainingLoadSheetBody(model: model),
);

class TrainingLoadSheetBody extends StatefulWidget {
  const TrainingLoadSheetBody({required this.model, super.key});

  final TrainingLoadSheetModel model;

  @override
  State<TrainingLoadSheetBody> createState() => _TrainingLoadSheetBodyState();
}

class _TrainingLoadSheetBodyState extends State<TrainingLoadSheetBody> {
  late int _selected = widget.model.initialSelectedIndex;
  bool _howOpen = false;

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: TracendSpacing.xs),
        Text(model.verdict, style: trainDisplay(context)),
        const SizedBox(height: 6),
        Text(model.subtitle, style: textTheme.bodyMedium),
        const SizedBox(height: TracendSpacing.xs),
        LoadScale(model: model),
        if (model.calibrating) ...[
          const SizedBox(height: 14),
          const TrainNote(
            icon: CupertinoIcons.info,
            text: TrainingLoadSheetModel.calibratingNote,
            raised: true,
          ),
        ],
        const SizedBox(height: 14),
        LoadDayChart(
          days: model.days,
          selected: _selected,
          showCalibratingLegend: model.showCalibratingLegend,
          onSelect: (index) {
            if (index == _selected) return;
            TracendHaptics.selection();
            setState(() => _selected = index);
          },
        ),
        const SizedBox(height: 14),
        TrainNote(
          icon: CupertinoIcons.calendar,
          label: 'What this means',
          text: model.advice,
        ),
        const SizedBox(height: 14),
        _Disclosure(
          title: 'How this is calculated',
          open: _howOpen,
          onToggle: () => setState(() => _howOpen = !_howOpen),
          paragraphs: model.explanation.paragraphs,
        ),
        const SizedBox(height: 14),
        Text(TrainingLoadSheetModel.footnote, style: textTheme.bodySmall),
      ],
    );
  }
}

/// The low / normal / high scale. With a reading, a "You" marker springs
/// from the left edge to the athlete's place; without one the scale dims
/// and no marker is drawn.
class LoadScale extends StatelessWidget {
  const LoadScale({required this.model, super.key});

  final TrainingLoadSheetModel model;

  static const _markerSize = 22.0;

  String get _semantics {
    final zone = model.zone;
    if (!model.hasReading || zone == null) return 'Not enough data yet';
    return 'Your load is in the ${zone.name} range';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: colors.textSecondary,
    );
    final low = TrainingLoadSheetModel.normalStartFraction;
    final normal = TrainingLoadSheetModel.normalEndFraction - low;
    final high = 1 - TrainingLoadSheetModel.normalEndFraction;
    int flex(double fraction) => (fraction * 1000).round();
    final position = model.scalePosition;
    final motion = TracendMotionScope.of(context);
    final track = Opacity(
      opacity: model.hasReading ? 1 : 0.4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: flex(low),
                  child: _Zone(
                    color: colors.textTertiary.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  flex: flex(normal),
                  child: _Zone(color: colors.stateStable),
                ),
                const SizedBox(width: 3),
                Expanded(
                  flex: flex(high),
                  child: _Zone(
                    color: colors.accentAmber.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TracendSpacing.xs),
          Row(
            children: [
              Expanded(
                flex: flex(low),
                child: Text('Low', style: labelStyle),
              ),
              Expanded(
                flex: flex(normal),
                child: Text(
                  'Normal',
                  textAlign: TextAlign.center,
                  style: labelStyle,
                ),
              ),
              Expanded(
                flex: flex(high),
                child: Text(
                  'High',
                  textAlign: TextAlign.right,
                  style: labelStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return Semantics(
      label: _semantics,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 22),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (position == null) return track;
            final width = constraints.maxWidth;
            Widget marker(double fraction) => Positioned(
              left: (fraction * width - _markerSize / 2).clamp(
                0,
                width - _markerSize,
              ),
              top: -22,
              child: Column(
                children: [
                  Text(
                    'You',
                    style: labelStyle?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                    textScaler: MediaQuery.textScalerOf(
                      context,
                    ).clamp(maxScaleFactor: 1.2),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    key: const ValueKey('load-scale-marker'),
                    width: _markerSize,
                    height: _markerSize,
                    decoration: BoxDecoration(
                      color: colors.textPrimary,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.sheet, width: 4),
                    ),
                  ),
                ],
              ),
            );
            return Stack(
              clipBehavior: Clip.none,
              children: [
                track,
                if (motion == TracendMotionLevel.full)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: position),
                    duration: const Duration(milliseconds: 900),
                    curve: const Interval(
                      0.25,
                      1,
                      curve: Cubic(0.3, 1.45, 0.5, 1),
                    ),
                    builder: (context, value, _) => marker(value),
                  )
                else
                  marker(position),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Zone extends StatelessWidget {
  const _Zone({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
    ),
  );
}

/// The last 7 days as bars: easy, moderate and hard are three strengths of
/// one ink; a calibrating day is hatched; a rest day is an empty socket.
/// A tap selects a day and names it below the chart.
class LoadDayChart extends StatelessWidget {
  const LoadDayChart({
    required this.days,
    required this.selected,
    required this.onSelect,
    required this.showCalibratingLegend,
    super.key,
  });

  final List<LoadDayBar> days;
  final int selected;
  final ValueChanged<int> onSelect;
  final bool showCalibratingLegend;

  static const _height = 128.0;
  static const _minBar = 14.0;

  static double opacityFor(LoadBarKind kind) => switch (kind) {
    LoadBarKind.easy => 0.28,
    LoadBarKind.moderate => 0.58,
    _ => 1,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final scale = MediaQuery.textScalerOf(context).scale(12);
    final compactLabels = scale > 16;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(TracendRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('Day by day', style: textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
            child: Text(
              'Last 7 days. Taller means more minutes or harder effort.',
              style: textTheme.bodySmall,
            ),
          ),
          if (days.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 2,
                vertical: TracendSpacing.md,
              ),
              child: Text('Not enough data yet', style: textTheme.bodyMedium),
            )
          else ...[
            SizedBox(
              height: _height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < days.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: _Bar(
                        day: days[i],
                        index: i,
                        selected: i == selected,
                        onTap: () => onSelect(i),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: TracendSpacing.xs),
            ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 0; i < days.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        compactLabels && days[i].isToday
                            ? days[i].date.weekdayLetter
                            : days[i].shortLabel,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: days[i].isToday
                              ? colors.accentSignalInk
                              : colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: TracendSpacing.sm),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                const _Legend(kind: LoadBarKind.easy, label: 'Easy'),
                const _Legend(kind: LoadBarKind.moderate, label: 'Moderate'),
                const _Legend(kind: LoadBarKind.hard, label: 'Hard'),
                if (showCalibratingLegend)
                  const _Legend(
                    kind: LoadBarKind.calibrating,
                    label: 'Calibrating',
                  ),
              ],
            ),
            const SizedBox(height: TracendSpacing.sm),
            Divider(height: 1, thickness: 1, color: colors.borderHairline),
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                days[selected.clamp(0, days.length - 1)].detail,
                key: const ValueKey('load-day-detail'),
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension on DateTime {
  String get weekdayLetter =>
      const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][weekday - 1];
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.day,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final LoadDayBar day;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final motion = TracendMotionScope.of(context);
    final ring = day.isToday
        ? Border.all(color: colors.accentSignalRing, width: 1.5)
        : null;
    final Widget shape;
    if (!day.trained) {
      shape = Container(
        height: 10,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: ring ?? Border.all(color: colors.borderSubtle, width: 1.5),
        ),
      );
    } else {
      final height = (day.heightFraction * (LoadDayChart._height - 6)).clamp(
        LoadDayChart._minBar,
        LoadDayChart._height - 6,
      );
      final radius = const BorderRadius.vertical(
        top: Radius.circular(9),
        bottom: Radius.circular(6),
      );
      final bar = SizedBox(
        width: double.infinity,
        height: height,
        child: day.kind == LoadBarKind.calibrating
            ? CustomPaint(
                painter: HatchPainter(
                  color: colors.textTertiary,
                  radius: radius,
                ),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.textPrimary.withValues(
                    alpha: LoadDayChart.opacityFor(day.kind),
                  ),
                  borderRadius: radius,
                ),
              ),
      );
      final framed = day.isToday
          ? Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: Border.all(color: colors.accentSignalRing, width: 1.5),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(11),
                  bottom: Radius.circular(8),
                ),
              ),
              child: bar,
            )
          : bar;
      shape = motion == TracendMotionLevel.full
          ? TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 620 + index * 45),
              curve: Interval(
                (220 + index * 45) / (620 + index * 45),
                1,
                curve: TracendMotion.settle,
              ),
              builder: (context, value, child) => Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.diagonal3Values(1, value, 1),
                child: child,
              ),
              child: framed,
            )
          : framed;
    }
    return Semantics(
      selected: selected,
      child: Pressable(
        onTap: onTap,
        semanticLabel: day.semanticsLabel,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          alignment: Alignment.bottomCenter,
          constraints: const BoxConstraints(maxWidth: 40),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? colors.textSecondary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: shape,
        ),
      ),
    );
  }
}

/// Diagonal hatching inside a rounded rectangle: the calibrating bar.
class HatchPainter extends CustomPainter {
  const HatchPainter({required this.color, required this.radius});

  final Color color;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = radius.toRRect(Offset.zero & size);
    canvas.save();
    canvas.clipRRect(rrect);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (var x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stroke,
      );
    }
    canvas.restore();
    canvas.drawRRect(
      rrect.deflate(0.75),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(HatchPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.kind, required this.label});

  final LoadBarKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    const radius = BorderRadius.all(Radius.circular(4));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 12,
          child: kind == LoadBarKind.calibrating
              ? CustomPaint(
                  painter: HatchPainter(
                    color: colors.textTertiary,
                    radius: radius,
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.textPrimary.withValues(
                      alpha: LoadDayChart.opacityFor(kind),
                    ),
                    borderRadius: radius,
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Disclosure extends StatelessWidget {
  const _Disclosure({
    required this.title,
    required this.open,
    required this.onToggle,
    required this.paragraphs,
  });

  final String title;
  final bool open;
  final VoidCallback onToggle;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: open,
            child: Pressable(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(14),
              pressedScale: 0.99,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.info,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: TracendSpacing.xs),
                      Expanded(child: Text(title, style: textTheme.titleSmall)),
                      AnimatedRotation(
                        turns: open ? 0.25 : 0,
                        duration: TracendMotionScope.movement(
                          context,
                          TracendMotion.quick,
                        ),
                        child: Icon(
                          CupertinoIcons.chevron_forward,
                          size: 15,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Builder(
            builder: (context) {
              final body = open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final paragraph in paragraphs) ...[
                            Text(
                              paragraph,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: TracendSpacing.xs),
                          ],
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity);
              final duration = TracendMotionScope.movement(
                context,
                TracendMotion.standard,
              );
              if (duration == Duration.zero) return body;
              return AnimatedSize(
                duration: duration,
                curve: TracendMotion.curve,
                alignment: Alignment.topCenter,
                child: body,
              );
            },
          ),
        ],
      ),
    );
  }
}
