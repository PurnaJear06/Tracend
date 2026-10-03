import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:tracend/features/train/muscle_groups.dart';
import 'package:tracend/features/train/train_view_models.dart';
import 'package:tracend/features/train/widgets/muscle_map_geometry.dart';

export 'package:tracend/features/train/widgets/muscle_map_geometry.dart'
    show BodySide;

/// Colours of the muscle map. The screen passes its design tokens; [dark]
/// and [light] carry the owner-approved prototype values.
@immutable
class MuscleMapPalette {
  const MuscleMapPalette({
    required this.base,
    required this.off,
    required this.mainStart,
    required this.mainEnd,
    required this.hatch,
    required this.shadow,
    this.glowOpacity = 0.55,
    this.shading = 1,
  });

  /// The silhouette, which shows through as the separation lines.
  final Color base;

  /// Neutral and unworked muscles.
  final Color off;

  /// The lime gradient of a main muscle, upper left to lower right.
  final Color mainStart;
  final Color mainEnd;

  /// The diagonal hatch on lit muscles, the non-colour cue.
  final Color hatch;

  /// The floor shadow and the edge-on thickness.
  final Color shadow;

  /// Strength of the soft glow around main muscles.
  final double glowOpacity;

  /// Strength of the lighting overlay; lighter themes need less.
  final double shading;

  static const dark = MuscleMapPalette(
    base: Color(0xFF26272A),
    off: Color(0xFF34363A),
    mainStart: Color(0xFFC8F05A),
    mainEnd: Color(0xFFA9D23A),
    hatch: Color(0xFF15170F),
    shadow: Color(0xFF000000),
  );

  static const light = MuscleMapPalette(
    base: Color(0xFFE6E6E1),
    off: Color(0xFFD6D6D0),
    mainStart: Color(0xFFC8F05A),
    mainEnd: Color(0xFFA9D23A),
    hatch: Color(0xFF15170F),
    shadow: Color(0xFF000000),
    glowOpacity: 0.4,
    shading: 0.55,
  );

  /// An `also` muscle: lime at 45% over the off colour.
  Color get also => Color.alphaBlend(mainStart.withValues(alpha: 0.45), off);

  /// The darker slices that read as the body's thickness mid-turn.
  Color get edge => Color.lerp(base, shadow, 0.45)!;

  @override
  bool operator ==(Object other) =>
      other is MuscleMapPalette &&
      other.base == base &&
      other.off == off &&
      other.mainStart == mainStart &&
      other.mainEnd == mainEnd &&
      other.hatch == hatch &&
      other.shadow == shadow &&
      other.glowOpacity == glowOpacity &&
      other.shading == shading;

  @override
  int get hashCode => Object.hash(
    base,
    off,
    mainStart,
    mainEnd,
    hatch,
    shadow,
    glowOpacity,
    shading,
  );
}

/// The accessibility label shared by [MuscleMap] and [MuscleMapPair].
String muscleMapSemanticsLabel(
  Iterable<MuscleGroup> groups, {
  required String showing,
}) {
  final names = groups.map((group) => group.label).toList();
  final worked = names.isEmpty
      ? 'No muscles linked to this workout'
      : 'Muscles worked: ${names.join(', ')}';
  return '$worked. Showing the $showing.';
}

/// A body figure that turns in 3D between front and back, with the
/// workout's muscles lit in lime and the rest graphite.
///
/// The side is controlled: [side] comes from the screen's Front/Back control
/// and a horizontal drag reports the side it snaps to through
/// [onSideChanged]. Without [onSideChanged] the figure does not drag.
class MuscleMap extends StatefulWidget {
  const MuscleMap({
    required this.muscles,
    required this.side,
    required this.palette,
    this.onSideChanged,
    this.onTap,
    this.width = 140,
    this.introAnimation = true,
    super.key,
  });

  /// Worked groups and their tone, in display order (see `muscleTones`).
  final Map<MuscleGroup, MuscleTone> muscles;
  final BodySide side;
  final ValueChanged<BodySide>? onSideChanged;
  final VoidCallback? onTap;
  final MuscleMapPalette palette;

  /// The figure's width; the height is 2.1 times it.
  final double width;

  /// The first appearance sways once and lights the muscles in turn.
  final bool introAnimation;

  @override
  State<MuscleMap> createState() => _MuscleMapState();
}

class _MuscleMapState extends State<MuscleMap> with TickerProviderStateMixin {
  static const _perspective = 0.0015;
  static const _sway = 25 * math.pi / 180;
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 170,
    ratio: 0.74,
  );

  late final AnimationController _turn = AnimationController.unbounded(
    vsync: this,
    value: _angleFor(widget.side),
  );
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );
  late final Listenable _frames = Listenable.merge([_turn, _intro]);

  late BodySide _target;
  bool _reduceMotion = false;
  bool _started = false;
  bool _swayCancelled = false;
  double _dragDx = 0;

  static double _angleFor(BodySide side) => side == BodySide.back ? math.pi : 0;

  @override
  void initState() {
    super.initState();
    _target = widget.side;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_started) return;
    _started = true;
    if (_reduceMotion || !widget.introAnimation) {
      _intro.value = 1;
    } else {
      _intro.forward();
    }
  }

  @override
  void didUpdateWidget(MuscleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A drag already springs toward the side it reports; only a change from
    // outside (the Front/Back control) starts a new turn.
    if (widget.side != _target) _settleTo(widget.side, velocity: 0);
  }

  @override
  void dispose() {
    _turn.dispose();
    _intro.dispose();
    super.dispose();
  }

  void _settleTo(BodySide side, {required double velocity}) {
    _target = side;
    final target = _angleFor(side);
    if (_reduceMotion) {
      _turn.value = target;
      return;
    }
    _turn.animateWith(SpringSimulation(_spring, _turn.value, target, velocity));
  }

  /// The intro sway, 0 → +25° → −25° → 0, over the last two thirds of the
  /// intro.
  double get _swayAngle {
    if (_swayCancelled) return 0;
    final t = ((_intro.value - 0.3) / 0.7).clamp(0.0, 1.0);
    if (t <= 0 || t >= 1) return 0;
    return _sway * math.sin(2 * math.pi * Curves.easeInOutSine.transform(t));
  }

  double get _angle => _turn.value + _swayAngle;

  void _onDragStart(DragStartDetails details) {
    final angle = _angle;
    _swayCancelled = true;
    _turn
      ..stop()
      ..value = angle;
    _dragDx = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? details.delta.dx;
    _dragDx += delta;
    if (_reduceMotion) return;
    _turn.value = (_turn.value + delta / widget.width * math.pi).clamp(
      -math.pi / 4,
      math.pi * 1.25,
    );
  }

  void _onDragEnd(DragEndDetails details) {
    final pixelsPerSecond = details.primaryVelocity ?? 0;
    final BodySide next;
    if (_reduceMotion) {
      final flick =
          pixelsPerSecond.abs() > 300 || _dragDx.abs() > widget.width * 0.25;
      next = flick
          ? (widget.side == BodySide.front ? BodySide.back : BodySide.front)
          : widget.side;
    } else {
      final velocity = pixelsPerSecond / widget.width * math.pi;
      final projected = _turn.value + velocity * 0.18;
      next = projected > math.pi / 2 ? BodySide.back : BodySide.front;
      _settleTo(next, velocity: velocity);
    }
    _target = next;
    if (next != widget.side) {
      HapticFeedback.selectionClick();
      widget.onSideChanged?.call(next);
    }
  }

  Map<MuscleGroup, double> _reveal() {
    final t = _intro.value;
    final groups = widget.muscles.keys.toList();
    return {
      for (var i = 0; i < groups.length; i++)
        groups[i]: Curves.easeOutCubic.transform(
          ((t - 0.04 - i * 0.07) / 0.24).clamp(0.0, 1.0),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
    final height = width * kBodyHeight / kBodyWidth;
    final draggable = widget.onSideChanged != null;
    return Semantics(
      label: muscleMapSemanticsLabel(
        widget.muscles.keys,
        showing: widget.side == BodySide.front ? 'front' : 'back',
      ),
      image: true,
      button: widget.onTap != null,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onHorizontalDragStart: draggable ? _onDragStart : null,
        onHorizontalDragUpdate: draggable ? _onDragUpdate : null,
        onHorizontalDragEnd: draggable ? _onDragEnd : null,
        child: SizedBox(
          width: width,
          height: height,
          child: _reduceMotion
              ? _crossfade(width, height)
              : AnimatedBuilder(
                  animation: _frames,
                  builder: (context, _) => _turned(width, height),
                ),
        ),
      ),
    );
  }

  Widget _face(
    BodySide side, {
    double shade = 0,
    Map<MuscleGroup, double>? reveal,
  }) => CustomPaint(
    size: Size.infinite,
    painter: MuscleFacePainter(
      figure: BodyFigure.of(side),
      tones: widget.muscles,
      palette: widget.palette,
      reveal: reveal ?? _reveal(),
      shade: shade,
    ),
  );

  Widget _crossfade(double width, double height) => Stack(
    fit: StackFit.expand,
    children: [
      _FloorShadow(palette: widget.palette, widthFactor: 1),
      for (final side in BodySide.values)
        AnimatedOpacity(
          opacity: widget.side == side ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: _face(
            side,
            reveal: {for (final g in widget.muscles.keys) g: 1},
          ),
        ),
    ],
  );

  Widget _turned(double width, double height) {
    final angle = _angle;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle).abs();
    final thickness = width * 0.03;
    final showBack = cosA < 0;
    final reveal = _reveal();

    Matrix4 at(double depth, {bool flip = false}) {
      final m = Matrix4.identity()
        ..setEntry(3, 2, _perspective)
        ..rotateY(angle)
        ..translateByDouble(0, 0, depth, 1);
      if (flip) m.rotateY(math.pi);
      return m;
    }

    final layers = <Widget>[];
    if (sinA > 0.04) {
      // The edge-on body: darker silhouettes stacked in depth, far first.
      const slices = 6;
      final depths = [
        for (var i = 1; i <= slices; i++)
          -thickness / 2 + thickness * i / (slices + 1),
      ]..sort((a, b) => (b * cosA).compareTo(a * cosA));
      for (final depth in depths) {
        layers.add(
          Transform(
            alignment: Alignment.center,
            transform: at(depth),
            child: CustomPaint(
              size: Size.infinite,
              painter: _SilhouettePainter(
                color: widget.palette.edge,
                opacity: math.min(1, sinA * 3),
              ),
            ),
          ),
        );
      }
    }
    layers.add(
      Transform(
        alignment: Alignment.center,
        transform: showBack
            ? at(thickness / 2, flip: true)
            : at(-thickness / 2),
        child: _face(
          showBack ? BodySide.back : BodySide.front,
          shade: 1 - cosA.abs(),
          reveal: reveal,
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        _FloorShadow(
          palette: widget.palette,
          widthFactor: 0.32 + 0.68 * cosA.abs(),
        ),
        ...layers,
      ],
    );
  }
}

/// Front and back side by side, not turnable, for the focus-mode page and
/// the muscles sheet. A [selected] group pulses; a tap on a muscle reports
/// its group through [onMuscleTap].
class MuscleMapPair extends StatefulWidget {
  const MuscleMapPair({
    required this.muscles,
    required this.palette,
    this.selected,
    this.onMuscleTap,
    this.figureWidth = 120,
    this.spacing = 20,
    super.key,
  });

  final Map<MuscleGroup, MuscleTone> muscles;
  final MuscleMapPalette palette;
  final MuscleGroup? selected;
  final ValueChanged<MuscleGroup>? onMuscleTap;
  final double figureWidth;
  final double spacing;

  @override
  State<MuscleMapPair> createState() => _MuscleMapPairState();
}

class _MuscleMapPairState extends State<MuscleMapPair>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncPulse();
  }

  @override
  void didUpdateWidget(MuscleMapPair oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _syncPulse();
  }

  void _syncPulse() {
    if (widget.selected == null) {
      _pulse
        ..stop()
        ..value = 0;
    } else if (_reduceMotion) {
      _pulse
        ..stop()
        ..value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _tap(BodySide side, TapUpDetails details) {
    final onTap = widget.onMuscleTap;
    if (onTap == null) return;
    final scale = kBodyWidth / widget.figureWidth;
    final group = BodyFigure.of(side).groupAt(details.localPosition * scale);
    if (group != null) onTap(group);
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.figureWidth;
    final height = width * kBodyHeight / kBodyWidth;
    final reveal = {for (final group in widget.muscles.keys) group: 1.0};
    Widget face(BodySide side) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: widget.onMuscleTap == null ? null : (d) => _tap(side, d),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _FloorShadow(palette: widget.palette, widthFactor: 1),
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: MuscleFacePainter(
                  figure: BodyFigure.of(side),
                  tones: widget.muscles,
                  palette: widget.palette,
                  reveal: reveal,
                  selected: widget.selected,
                  pulse: Curves.easeInOut.transform(_pulse.value),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      label: muscleMapSemanticsLabel(
        widget.muscles.keys,
        showing: 'front and back',
      ),
      image: true,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          face(BodySide.front),
          SizedBox(width: widget.spacing),
          face(BodySide.back),
        ],
      ),
    );
  }
}

/// Paints one side of the figure in its box (200×420 design space).
class MuscleFacePainter extends CustomPainter {
  MuscleFacePainter({
    required this.figure,
    required this.tones,
    required this.palette,
    required this.reveal,
    this.shade = 0,
    this.selected,
    this.pulse = 0,
  });

  final BodyFigure figure;
  final Map<MuscleGroup, MuscleTone> tones;
  final MuscleMapPalette palette;

  /// 0–1 light-up of each worked group.
  final Map<MuscleGroup, double> reveal;

  /// 0–1 darkening as the face turns away from the viewer.
  final double shade;
  final MuscleGroup? selected;
  final double pulse;

  static const _gap = 1.6;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / kBodyWidth, size.height / kBodyHeight);

    canvas.drawPath(figure.silhouette, Paint()..color = palette.base);

    final offPaint = Paint()..color = palette.off;
    final gapPaint = Paint()
      ..color = palette.base
      ..style = PaintingStyle.stroke
      ..strokeWidth = _gap
      ..strokeJoin = StrokeJoin.round;
    final glowing = <BodyPart>[];

    // Paint order: each shape, then its outline in the base colour, so the
    // separation lines show and a covered edge stays covered.
    final recessedPaint = Paint()..color = palette.base;
    for (final part in figure.parts) {
      if (part.recessed) {
        canvas.drawPath(part.path, recessedPaint);
        continue;
      }
      canvas.drawPath(part.path, offPaint);
      final group = part.group;
      final p = group == null || !tones.containsKey(group)
          ? 0.0
          : reveal[group] ?? 0.0;
      if (p > 0) {
        final bounds = part.path.getBounds();
        final paint = Paint();
        if (tones[group] == MuscleTone.main) {
          paint.shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.mainStart.withValues(alpha: p),
              palette.mainEnd.withValues(alpha: p),
            ],
          ).createShader(bounds);
          glowing.add(part);
        } else {
          paint.color = palette.mainStart.withValues(alpha: 0.45 * p);
          if (group == selected) glowing.add(part);
        }
        canvas.drawPath(part.path, paint);
        _hatch(canvas, part.path, bounds, p);
      }
      canvas.drawPath(part.path, gapPaint);
    }

    // A soft lime glow around main muscles, outside their own shape.
    for (final part in glowing) {
      final boost = part.group == selected ? 0.35 * pulse : 0.0;
      final alpha = (palette.glowOpacity + boost) * reveal[part.group]!;
      canvas
        ..save()
        ..clipPath(part.outside)
        ..drawPath(
          part.path,
          Paint()
            ..color = palette.mainStart.withValues(alpha: alpha.clamp(0.0, 1.0))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        )
        ..restore();
    }

    if (selected != null) {
      final ring = Paint()
        ..color = palette.mainStart.withValues(alpha: 0.5 + 0.5 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (final part in figure.parts) {
        if (part.group == selected) canvas.drawPath(part.path, ring);
      }
    }

    _lighting(canvas);
    canvas.restore();
  }

  void _hatch(Canvas canvas, Path path, Rect bounds, double p) {
    final paint = Paint()
      ..color = palette.hatch.withValues(alpha: 0.2 * p)
      ..strokeWidth = 1.1;
    canvas
      ..save()
      ..clipPath(path);
    const spacing = 4.6;
    final span = bounds.width + bounds.height;
    for (var d = 0.0; d < span; d += spacing) {
      canvas.drawLine(
        Offset(bounds.left + d, bounds.top),
        Offset(bounds.left + d - bounds.height, bounds.bottom),
        paint,
      );
    }
    canvas.restore();
  }

  /// One light from the upper left over the whole figure, darker on the
  /// right edge, plus the darkening of a face turned away.
  void _lighting(Canvas canvas) {
    final bounds = figure.silhouette.getBounds();
    canvas
      ..save()
      ..clipPath(figure.silhouette);
    final k = palette.shading;
    // Left to right: lit side, then the darker right edge.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.09 * k),
            const Color(0x00FFFFFF),
            const Color(0x00000000),
            palette.shadow.withValues(alpha: 0.28 * k),
          ],
          stops: const [0, 0.4, 0.58, 1],
        ).createShader(bounds),
    );
    // Top to bottom: the light falls from above.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.07 * k),
            const Color(0x00FFFFFF),
            const Color(0x00000000),
            palette.shadow.withValues(alpha: 0.12 * k),
          ],
          stops: const [0, 0.3, 0.7, 1],
        ).createShader(bounds),
    );
    if (shade > 0) {
      canvas.drawRect(
        bounds,
        Paint()..color = palette.shadow.withValues(alpha: 0.28 * shade),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MuscleFacePainter old) =>
      old.figure != figure ||
      old.palette != palette ||
      old.shade != shade ||
      old.selected != selected ||
      old.pulse != pulse ||
      !_sameMap(old.tones, tones) ||
      !_sameMap(old.reveal, reveal);

  static bool _sameMap<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

class _SilhouettePainter extends CustomPainter {
  _SilhouettePainter({required this.color, required this.opacity});
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / kBodyWidth, size.height / kBodyHeight)
      ..drawPath(
        BodyFigure.front.silhouette,
        Paint()..color = color.withValues(alpha: opacity),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_SilhouettePainter old) =>
      old.color != color || old.opacity != opacity;
}

class _FloorShadow extends StatelessWidget {
  const _FloorShadow({required this.palette, required this.widthFactor});
  final MuscleMapPalette palette;
  final double widthFactor;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.infinite,
    painter: _FloorShadowPainter(palette.shadow, widthFactor),
  );
}

class _FloorShadowPainter extends CustomPainter {
  _FloorShadowPainter(this.color, this.widthFactor);
  final Color color;
  final double widthFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / kBodyWidth;
    final sy = size.height / kBodyHeight;
    final rect = Rect.fromCenter(
      center: Offset(100 * sx, 408 * sy),
      width: 104 * widthFactor * sx,
      height: 12 * sy,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * sy),
    );
  }

  @override
  bool shouldRepaint(_FloorShadowPainter old) =>
      old.color != color || old.widthFactor != widthFactor;
}
