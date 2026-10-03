import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

/// The Tracend brand colours. They are fixed: the mark looks the same in
/// light and dark mode, on the app icon and on the launch screen.
abstract final class TracendBrandColors {
  /// The icon and launch background.
  static const graphite = Color(0xFF0C0D0E);

  /// The T.
  static const chalk = Color(0xFFF4F4F1);

  /// The trajectory arc and its dot.
  static const lime = Color(0xFFC8F05A);

  /// The dot of the loader on light surfaces, where [lime] is too faint.
  static const limeOnLight = Color(0xFF7FA51A);
}

/// The mark's shapes in its 1024 × 1024 design space: the T, the trajectory
/// arc ("swoosh") and the dot resting on it.
abstract final class TracendMarkGeometry {
  static const double extent = 1024;

  static final Path letter = Path()
    ..moveTo(252, 348)
    ..lineTo(308, 240)
    ..lineTo(812, 240)
    ..lineTo(630, 348)
    ..lineTo(580, 348)
    ..lineTo(527, 497)
    ..lineTo(368, 621)
    ..lineTo(441, 383)
    ..lineTo(530, 350)
    ..close();

  static final Path swoosh = Path()
    ..moveTo(272, 783)
    ..quadraticBezierTo(500, 480, 803, 323)
    ..quadraticBezierTo(560, 520, 440, 783)
    ..close();

  static const Offset dotCenter = Offset(623, 472);
  static const double dotRadius = 36;

  /// The line the arc is drawn along when it draws itself, and that the dot
  /// rides in the intro.
  static final PathMetric arcLine =
      (Path()
            ..moveTo(300, 860)
            ..quadraticBezierTo(520, 520, 860, 290))
          .computeMetrics()
          .single;

  /// The width of the stroke along [arcLine] that reveals the arc.
  static const double arcRevealWidth = 210;

  /// The angle of the edge that sweeps the T in, matching the arc's rise.
  static const double letterSweepAngle = -38 * math.pi / 180;
}

/// One frame of the mark: how much of the arc and the T is drawn and where
/// the dot is. [TracendMarkFrame.settled] is the finished mark.
@immutable
class TracendMarkFrame {
  const TracendMarkFrame({
    required this.arcDrawn,
    required this.letterSwept,
    required this.dotCenter,
    required this.dotRadius,
    required this.dotVisible,
    this.dotTrail = const [],
  });

  static const settled = TracendMarkFrame(
    arcDrawn: 1,
    letterSwept: 1,
    dotCenter: TracendMarkGeometry.dotCenter,
    dotRadius: TracendMarkGeometry.dotRadius,
    dotVisible: true,
  );

  /// The share of the arc drawn, from its foot (0) to its tip (1).
  final double arcDrawn;

  /// How far the sweeping edge has crossed the T: 0 hides it, 1 shows it.
  final double letterSwept;

  /// The dot's centre and radius in the 1024 design space.
  final Offset dotCenter;
  final double dotRadius;
  final bool dotVisible;

  /// Where the dot just was, newest first: a short trail that fades and
  /// thins toward its end. Empty when the dot is still.
  final List<Offset> dotTrail;

  @override
  bool operator ==(Object other) =>
      other is TracendMarkFrame &&
      other.arcDrawn == arcDrawn &&
      other.letterSwept == letterSwept &&
      other.dotCenter == dotCenter &&
      other.dotRadius == dotRadius &&
      other.dotVisible == dotVisible &&
      listEquals(other.dotTrail, dotTrail);

  @override
  int get hashCode => Object.hash(
    arcDrawn,
    letterSwept,
    dotCenter,
    dotRadius,
    dotVisible,
    Object.hashAll(dotTrail),
  );
}

/// Paints the mark, scaled to fit and centred in its size. [background]
/// fills the whole area first (the app icon); leave it null to paint on
/// whatever is beneath.
class TracendMarkPainter extends CustomPainter {
  const TracendMarkPainter({
    this.frame = TracendMarkFrame.settled,
    this.letterColor = TracendBrandColors.chalk,
    this.arcColor = TracendBrandColors.lime,
    this.dotColor = TracendBrandColors.lime,
    this.background,
  });

  final TracendMarkFrame frame;
  final Color letterColor;
  final Color arcColor;
  final Color dotColor;
  final Color? background;

  static const _extent = TracendMarkGeometry.extent;
  static const _design = Rect.fromLTWH(0, 0, _extent, _extent);

  @override
  void paint(Canvas canvas, Size size) {
    if (background case final fill?) {
      canvas.drawRect(Offset.zero & size, Paint()..color = fill);
    }
    final scale = size.shortestSide / _extent;
    canvas
      ..save()
      ..translate(
        (size.width - _extent * scale) / 2,
        (size.height - _extent * scale) / 2,
      )
      ..scale(scale);
    _paintLetter(canvas);
    _paintArc(canvas);
    if (frame.dotVisible) _paintTrail(canvas);
    if (frame.dotVisible) {
      canvas.drawCircle(
        frame.dotCenter,
        frame.dotRadius,
        Paint()..color = dotColor,
      );
    }
    canvas.restore();
  }

  void _paintLetter(Canvas canvas) {
    final paint = Paint()..color = letterColor;
    if (frame.letterSwept >= 1) {
      canvas.drawPath(TracendMarkGeometry.letter, paint);
      return;
    }
    // A wide band, tilted to the arc's rise, whose leading edge moves across
    // the T from its lower-left tip to its upper-right corner.
    const center = Offset(_extent / 2, _extent / 2);
    const angle = TracendMarkGeometry.letterSweepAngle;
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(angle)
      ..translate(-center.dx, -center.dy)
      ..clipRect(
        Rect.fromLTWH(-_extent, -_extent, 1300 + 700 * frame.letterSwept, 3072),
      )
      ..translate(center.dx, center.dy)
      ..rotate(-angle)
      ..translate(-center.dx, -center.dy)
      ..drawPath(TracendMarkGeometry.letter, paint)
      ..restore();
  }

  void _paintArc(Canvas canvas) {
    final paint = Paint()..color = arcColor;
    if (frame.arcDrawn >= 1) {
      canvas.drawPath(TracendMarkGeometry.swoosh, paint);
      return;
    }
    if (frame.arcDrawn <= 0) return;
    // The drawn length of a thick stroke along the arc's spine masks the
    // arc: the second layer keeps the arc only where the stroke is.
    final line = TracendMarkGeometry.arcLine;
    canvas
      ..saveLayer(_design, Paint())
      ..drawPath(
        line.extractPath(0, line.length * frame.arcDrawn),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = TracendMarkGeometry.arcRevealWidth
          ..color = const Color(0xFFFFFFFF),
      )
      ..saveLayer(_design, Paint()..blendMode = BlendMode.srcIn)
      ..drawPath(TracendMarkGeometry.swoosh, paint)
      ..restore()
      ..restore();
  }

  void _paintTrail(Canvas canvas) {
    final trail = frame.dotTrail;
    if (trail.isEmpty) return;
    // Each ghost lightens rather than adds, so where they overlap the trail
    // stays one smooth taper. The layer screens onto the mark: a faint lime
    // streak on graphite, a brighter one over the lime arc.
    canvas.saveLayer(_design, Paint()..blendMode = BlendMode.screen);
    final count = trail.length;
    for (var index = count - 1; index >= 0; index--) {
      final fade = 1 - (index + 1) / (count + 1);
      canvas.drawCircle(
        trail[index],
        frame.dotRadius * (0.4 + 0.6 * fade),
        Paint()
          ..blendMode = BlendMode.lighten
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
          ..color = dotColor.withValues(alpha: 0.85 * fade * fade),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(TracendMarkPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.letterColor != letterColor ||
      oldDelegate.arcColor != arcColor ||
      oldDelegate.dotColor != dotColor ||
      oldDelegate.background != background;
}

/// The finished Tracend mark: a chalk T with the lime trajectory arc and dot.
///
/// The colours are the brand's, not the theme's. On a light surface pass a
/// dark [letterColor], since the chalk T is drawn for graphite.
class TracendMark extends StatelessWidget {
  const TracendMark({
    this.size = 48,
    this.letterColor = TracendBrandColors.chalk,
    this.semanticLabel = 'Tracend',
    super.key,
  });

  final double size;
  final Color letterColor;

  /// Read by VoiceOver; null when a visible "Tracend" already names it.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: TracendMarkPainter(letterColor: letterColor)),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: mark);
    return Semantics(image: true, label: label, child: mark);
  }
}
