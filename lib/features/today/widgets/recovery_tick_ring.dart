import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// One recovery driver's share of the lit ticks.
@immutable
class RingSegment {
  const RingSegment({required this.color, required this.weight});

  final Color color;

  /// The driver's weight in the recovery composite; segments share the lit
  /// ticks in proportion to it.
  final double weight;
}

/// The recovery score as a ring of ticks. The lit ticks run clockwise from
/// 12 o'clock to the score and are split between the drivers that counted
/// today, each in its own colour (lime when the driver is normal or better,
/// amber when it pulls the score down), with a one-tick gap between drivers.
/// A taller head tick and a dot mark where the score lands. Unlit ticks are
/// a quiet track.
///
/// [focus] dims every segment but one. The score counts up and the ticks
/// light in turn at full motion; reduced or static motion draws the final
/// state.
class RecoveryTickRing extends StatefulWidget {
  const RecoveryTickRing({
    required this.score,
    required this.segments,
    required this.center,
    this.focus,
    this.size = 248,
    super.key,
  });

  /// 0 to 100, or null when recovery was not scored.
  final int? score;
  final List<RingSegment> segments;

  /// The index into [segments] to keep bright; null keeps all bright.
  final int? focus;
  final double size;

  /// Builds the centre from the score shown right now (it counts up).
  final Widget Function(int shown) center;

  @override
  State<RecoveryTickRing> createState() => _RecoveryTickRingState();
}

class _RecoveryTickRingState extends State<RecoveryTickRing>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 1200);
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
  void didUpdateWidget(RecoveryTickRing old) {
    super.didUpdateWidget(old);
    if (old.score != widget.score) _controller?.forward(from: 0);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final controller = _controller;
    Widget frame(BuildContext context, Widget? _) {
      final t = controller == null
          ? 1.0
          : Curves.easeOutCubic.transform(controller.value);
      final score = widget.score ?? 0;
      return SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _TickRingPainter(
            score: widget.score,
            progress: t,
            segments: widget.segments,
            focus: widget.focus,
            track: colors.textSecondary.withValues(alpha: 0.2),
            hairline: colors.borderHairline,
            head: colors.textPrimary,
          ),
          child: Center(child: widget.center((score * t).round())),
        ),
      );
    }

    return RepaintBoundary(
      child: controller == null
          ? frame(context, null)
          : AnimatedBuilder(animation: controller, builder: frame),
    );
  }
}

class _TickRingPainter extends CustomPainter {
  _TickRingPainter({
    required this.score,
    required this.progress,
    required this.segments,
    required this.focus,
    required this.track,
    required this.hairline,
    required this.head,
  });

  final int? score;
  final double progress;
  final List<RingSegment> segments;
  final int? focus;
  final Color track;
  final Color hairline;
  final Color head;

  static const _ticks = 112;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 256;
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2 - 10 * unit;
    canvas.drawCircle(
      center,
      outer - 36 * unit,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = hairline,
    );

    final lit = score == null || segments.isEmpty
        ? 0
        : (_ticks * score!.clamp(0, 100) / 100).round();
    final shown = (lit * progress).floor();
    final owners = _owners(lit);

    for (var i = 0; i < _ticks; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / _ticks;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final isLit = i < shown;
      final owner = i < lit ? owners[i] : -1;
      // A one-tick gap where one driver's ticks give way to the next.
      if (i > 0 && i < lit && owners[i - 1] != owner) continue;
      final isHead = isLit && i == shown - 1;
      final double length;
      final Color color;
      if (isLit) {
        length = isHead
            ? 32 * unit
            : (19 + 7 * math.sin(math.pi * i / math.max(1, lit))) * unit;
        final base = segments[owner].color;
        final dimmed = focus != null && focus != owner;
        final ramp = 0.42 + 0.58 * (i / math.max(1, lit));
        color = base.withValues(alpha: dimmed ? 0.14 : ramp);
      } else {
        length = 11 * unit;
        color = track;
      }
      canvas.drawLine(
        center + direction * (outer - length),
        center + direction * outer,
        Paint()
          ..color = color
          ..strokeWidth = (isHead ? 4.2 : 3) * unit
          ..strokeCap = StrokeCap.round,
      );
      if (isHead) {
        canvas.drawCircle(
          center + direction * (outer + 7 * unit),
          3.2 * unit,
          Paint()..color = head,
        );
      }
    }
  }

  /// Which segment owns each lit tick, in proportion to the weights.
  List<int> _owners(int lit) {
    if (lit == 0) return const [];
    final total = segments.fold<double>(0, (sum, s) => sum + s.weight);
    final owners = <int>[];
    for (var s = 0; s < segments.length; s++) {
      final count = total <= 0 ? 0 : (lit * segments[s].weight / total).round();
      for (var k = 0; k < count && owners.length < lit; k++) {
        owners.add(s);
      }
    }
    while (owners.length < lit) {
      owners.add(segments.length - 1);
    }
    return owners;
  }

  @override
  bool shouldRepaint(_TickRingPainter old) =>
      old.score != score ||
      old.progress != progress ||
      old.focus != focus ||
      old.track != track ||
      old.hairline != hairline ||
      old.head != head ||
      !_sameSegments(old.segments, segments);

  static bool _sameSegments(List<RingSegment> a, List<RingSegment> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].color != b[i].color || a[i].weight != b[i].weight) return false;
    }
    return true;
  }
}

/// The score inside the ring: "Recovery", the number, the band pill and
/// the change from yesterday.
class RingCenter extends StatelessWidget {
  const RingCenter({
    required this.shown,
    required this.band,
    required this.bandColor,
    required this.onBand,
    this.delta,
    this.scale = 1,
    super.key,
  });

  /// The score shown right now, or null for "not scored".
  final int? shown;
  final String band;
  final Color bandColor;
  final Color onBand;

  /// "+6 from yesterday"; null when yesterday was not scored.
  final String? delta;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final secondary = textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Recovery', style: secondary),
          Text(
            shown == null ? '--' : '$shown',
            style: TracendTheme.numeric(
              colors,
              fontSize: 64 * scale,
              fontWeight: FontWeight.w700,
            ).copyWith(height: 1.05, letterSpacing: -1.5),
          ),
          const SizedBox(height: TracendSpacing.xxs),
          DecoratedBox(
            decoration: BoxDecoration(
              color: bandColor,
              borderRadius: BorderRadius.circular(TracendRadii.pill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Text(
                band,
                style: textTheme.labelSmall?.copyWith(
                  color: onBand,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (delta != null) ...[
            const SizedBox(height: 6),
            Text(delta!, style: secondary),
          ],
        ],
      ),
    );
  }
}
