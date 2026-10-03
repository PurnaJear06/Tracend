import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/brand/tracend_mark.dart';

/// The launch intro: the mark builds itself over the launch screen's graphite
/// while [child] gets ready beneath it, then hands over to [child].
///
/// The mark grows from 0.9 as the arc draws itself and the dot rides it,
/// trailing a short fading streak, to the tip. The dot rolls back and lands
/// with a light haptic as the mark swells just past full size and a soft lime
/// bloom rises under it; the T sweeps in and the wordmark rises letter by
/// letter: 1.2 seconds, played once per mount and never looped. The intro
/// then zooms through: the mark grows a little and fades while [child]
/// settles from 0.97 to full size and fades in. Under Reduce Motion the
/// finished mark shows and crossfades away.
///
/// While [ready] is false after the motion, the finished mark stays with a
/// [TracendLoader]. Once [ready] is true the intro leaves as soon as the
/// motion ends, so it never holds back an app that is already loaded.
class TracendIntro extends StatefulWidget {
  const TracendIntro({required this.ready, required this.child, super.key});

  /// Whether [child] is ready to be seen.
  final bool ready;

  /// The app beneath, built (and kept) from the first frame.
  final Widget child;

  /// The length of the motion.
  static const motion = Duration(milliseconds: 1200);

  /// The length of the zoom-through to [child] after the motion.
  static const handOff = Duration(milliseconds: 350);

  @override
  State<TracendIntro> createState() => _TracendIntroState();
}

class _TracendIntroState extends State<TracendIntro>
    with TickerProviderStateMixin {
  static const _markSize = 132.0;
  static const _wordmarkGap = 18.0;
  static const _bloomSize = 320.0;
  static const _reducedFade = Duration(milliseconds: 200);

  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: TracendIntro.motion,
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: TracendIntro.handOff,
  );

  /// The stage fades a little ahead of the app so the two never sit muddled.
  late final CurvedAnimation _stageFade = CurvedAnimation(
    parent: _exit,
    curve: const Interval(0, 0.55, curve: Curves.easeOutCubic),
  );

  /// The app fades in and both zoom along this.
  late final CurvedAnimation _handOff = CurvedAnimation(
    parent: _exit,
    curve: Curves.easeOutCubic,
  );
  late final Animation<double> _stageOpacity = ReverseAnimation(_stageFade);
  late final Animation<double> _stageScale = Tween(
    begin: 1.0,
    end: 1.06,
  ).animate(_handOff);
  late final Animation<double> _appScale = Tween(
    begin: 0.97,
    end: 1.0,
  ).animate(_handOff);

  _WordmarkGlyphs? _glyphs;

  bool _started = false;
  bool _reduced = false;
  bool _motionDone = false;
  bool _held = false;
  bool _settledBuzz = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _exit.addStatusListener((status) {
      if (status.isCompleted) setState(() => _gone = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) {
      _motion.value = 1;
      _motionDone = true;
      _exit.duration = _reducedFade;
      if (widget.ready) {
        _exit.forward();
      } else {
        _held = true;
      }
      return;
    }
    _motion
      ..addListener(_onTick)
      ..addStatusListener((status) {
        if (!status.isCompleted) return;
        setState(() {
          _motionDone = true;
          _held = !widget.ready;
        });
        _leaveIfReady();
      })
      ..forward();
  }

  @override
  void didUpdateWidget(TracendIntro oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready && !oldWidget.ready) _leaveIfReady();
  }

  @override
  void dispose() {
    _glyphs?.dispose();
    _handOff.dispose();
    _stageFade.dispose();
    _exit.dispose();
    _motion.dispose();
    super.dispose();
  }

  /// The dot lands as it finishes growing.
  void _onTick() {
    if (_settledBuzz || _elapsedMs < _IntroTimeline.dotSettled) return;
    _settledBuzz = true;
    unawaited(HapticFeedback.lightImpact());
  }

  double get _elapsedMs =>
      _motion.value * TracendIntro.motion.inMilliseconds.toDouble();

  void _leaveIfReady() {
    if (_motionDone && widget.ready && _exit.isDismissed) _exit.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The graphite stays under the app as it fades in, so the hand-off
        // never dips through black. The slot stays when it empties, so the
        // app below keeps its place, and its state, in the stack.
        if (_gone)
          const SizedBox.shrink()
        else
          const ColoredBox(color: TracendBrandColors.graphite),
        ExcludeSemantics(
          excluding: !_gone,
          child: IgnorePointer(
            ignoring: !_gone,
            child: FadeTransition(
              opacity: _handOff,
              child: ScaleTransition(
                scale: _reduced ? kAlwaysCompleteAnimation : _appScale,
                child: widget.child,
              ),
            ),
          ),
        ),
        if (!_gone)
          FadeTransition(
            opacity: _stageOpacity,
            child: ScaleTransition(
              scale: _reduced ? kAlwaysCompleteAnimation : _stageScale,
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle.light,
                // The gate has no Scaffold yet: this gives the loader its
                // Material.
                child: Material(
                  type: MaterialType.transparency,
                  child: _buildStage(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStage() {
    final glyphs = _glyphs ??= _WordmarkGlyphs();
    return LayoutBuilder(
      builder: (context, constraints) {
        // The mark sits where the launch screen's static mark sits.
        final markTop = (constraints.maxHeight - _markSize) / 2;
        final markCenter = Offset(
          constraints.maxWidth / 2,
          markTop + _markSize / 2,
        );
        // The bloom rises from where the dot lands.
        const designCenter = Offset(
          TracendMarkGeometry.extent / 2,
          TracendMarkGeometry.extent / 2,
        );
        final bloomCenter =
            markCenter +
            (TracendMarkGeometry.dotCenter - designCenter) *
                (_markSize / TracendMarkGeometry.extent);
        return AnimatedBuilder(
          animation: _motion,
          builder: (context, _) {
            final ms = _elapsedMs;
            return Stack(
              children: [
                Positioned(
                  left: bloomCenter.dx - _bloomSize / 2,
                  top: bloomCenter.dy - _bloomSize / 2,
                  width: _bloomSize,
                  height: _bloomSize,
                  child: CustomPaint(
                    painter: _BloomPainter(_IntroTimeline.bloomAt(ms)),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: markTop,
                  height: _markSize,
                  child: Center(
                    child: Transform.scale(
                      scale: _IntroTimeline.markScaleAt(ms),
                      child: SizedBox.square(
                        dimension: _markSize,
                        child: CustomPaint(
                          painter: TracendMarkPainter(
                            frame: _IntroTimeline.markAt(ms),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: markTop + _markSize + _wordmarkGap,
                  child: Column(
                    children: [
                      Semantics(
                        container: true,
                        label: 'Tracend',
                        child: SizedBox(
                          height: glyphs.height,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: _WordmarkPainter(glyphs, ms),
                          ),
                        ),
                      ),
                      if (_held) ...[
                        const SizedBox(height: 32),
                        const TracendLoader(
                          semanticLabel: 'Restoring your session',
                          dotColor: TracendBrandColors.lime,
                          arcColor: Color(0x38F4F4F1),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// A soft lime glow under the mark; [strength] runs from 0 (none) to 1.
class _BloomPainter extends CustomPainter {
  const _BloomPainter(this.strength);

  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 * (0.8 + 0.2 * strength);
    const lime = TracendBrandColors.lime;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [
            lime.withValues(alpha: 0.2 * strength),
            lime.withValues(alpha: 0.07 * strength),
            lime.withValues(alpha: 0),
          ],
          const [0, 0.4, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_BloomPainter oldDelegate) =>
      oldDelegate.strength != strength;
}

/// The wordmark's letters, each laid out alone and placed where it sits in
/// the whole word, so the finished word keeps its kerning.
class _WordmarkGlyphs {
  factory _WordmarkGlyphs() {
    final word = TextPainter(
      text: const TextSpan(text: _word, style: _style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final glyphs = _WordmarkGlyphs._(
      width: word.width,
      height: word.height,
      offsets: [
        for (var index = 0; index < _word.length; index++)
          word.getOffsetForCaret(TextPosition(offset: index), Rect.zero).dx,
      ],
      letters: [
        for (final letter in _word.split(''))
          TextPainter(
            text: TextSpan(text: letter, style: _style),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.noScaling,
          )..layout(),
      ],
    );
    word.dispose();
    return glyphs;
  }

  _WordmarkGlyphs._({
    required this.width,
    required this.height,
    required this.offsets,
    required this.letters,
  });

  static const _word = 'Tracend';
  static const _style = TextStyle(
    fontFamily: TracendFonts.displayFamily,
    fontSize: 30,
    height: 1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    color: TracendBrandColors.chalk,
  );

  final double width;
  final double height;

  /// Each letter's left edge in the whole word.
  final List<double> offsets;
  final List<TextPainter> letters;

  void dispose() {
    for (final letter in letters) {
      letter.dispose();
    }
  }
}

/// Paints the wordmark [ms] into the intro: each letter rises and fades in a
/// beat after the one before, while the tracking closes up into place.
class _WordmarkPainter extends CustomPainter {
  const _WordmarkPainter(this.glyphs, this.ms);

  final _WordmarkGlyphs glyphs;
  final double ms;

  @override
  void paint(Canvas canvas, Size size) {
    final count = glyphs.letters.length;
    final spread = _IntroTimeline.wordmarkSpreadAt(ms);
    final left = (size.width - glyphs.width - spread * (count - 1)) / 2;
    final top = (size.height - glyphs.height) / 2;
    for (var index = 0; index < count; index++) {
      final reveal = _IntroTimeline.letterRevealAt(ms, index);
      if (reveal <= 0) continue;
      final letter = glyphs.letters[index];
      final origin = Offset(
        left + glyphs.offsets[index] + spread * index,
        top + (1 - _IntroTimeline.easeOut(reveal)) * _IntroTimeline.letterRise,
      );
      final opacity = _IntroTimeline.easeOut(math.min(1, reveal / 0.7));
      if (opacity >= 1) {
        letter.paint(canvas, origin);
        continue;
      }
      // Glyphs reach a little past their box; the layer leaves them room.
      final bounds = (origin & letter.size).inflate(letter.height / 2);
      canvas.saveLayer(
        bounds,
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
      letter.paint(canvas, origin);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_WordmarkPainter oldDelegate) =>
      oldDelegate.glyphs != glyphs ||
      _IntroTimeline.wordmarkAt(oldDelegate.ms) !=
          _IntroTimeline.wordmarkAt(ms);
}

/// The intro's choreography, in milliseconds from its start.
abstract final class _IntroTimeline {
  /// The arc draws itself from its foot to its tip.
  static const arcDrawn = 460.0;

  /// The dot then rolls back down the arc, overshooting a little.
  static const rollBack = 440.0;

  /// From here the dot eases off the arc onto its resting place.
  static const dotSettling = 760.0;
  static const dotSettled = arcDrawn + rollBack;

  /// The T sweeps in along the arc's rise.
  static const letterStart = 380.0;
  static const letterLength = 480.0;

  /// The mark grows from [_startScale] to [_peakScale] as the dot lands,
  /// then eases back to full size.
  static const _startScale = 0.9;
  static const _peakScale = 1.03;
  static const _scaleSettle = 260.0;

  /// The bloom swells as the dot lands, then relaxes to a faint glow that
  /// stays under the finished mark.
  static const _bloomStart = 640.0;
  static const _bloomPeak = 940.0;
  static const _bloomRelaxed = 1200.0;
  static const _bloomRest = 0.35;

  /// The dot's trail: where it was over the last few frames.
  static const _trailSamples = 10;
  static const _trailStep = 10.0;

  /// The wordmark's letters rise one after another.
  static const wordStart = 700.0;
  static const _letterStagger = 35.0;
  static const _letterLength = 280.0;
  static const letterRise = 8.0;

  /// The letters start this much further apart and close up.
  static const _startSpread = 2.4;
  static const _spreadLength = 480.0;

  /// When the wordmark's last (seventh) letter and its tracking have settled.
  static const _lastLetterDone = _letterLength + 6 * _letterStagger;
  static const _wordEnd =
      wordStart +
      (_lastLetterDone > _spreadLength ? _lastLetterDone : _spreadLength);

  static const _dotStartRadius = 22.0;
  static const _dotAppears = 30.0;

  static final _line = TracendMarkGeometry.arcLine;

  /// How far along the arc the dot comes to rest: the point nearest its
  /// place on the mark.
  static final double _restAlong = () {
    var best = 0.0;
    var bestDistance = double.infinity;
    for (var along = 0.0; along <= _line.length; along += 2) {
      final point = _line.getTangentForOffset(along)!.position;
      final distance = (point - TracendMarkGeometry.dotCenter).distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = along;
      }
    }
    return best;
  }();

  static TracendMarkFrame markAt(double ms) {
    if (ms >= dotSettled && ms >= letterStart + letterLength) {
      return TracendMarkFrame.settled;
    }
    return TracendMarkFrame(
      arcDrawn: _easeInOut(_clamp(ms / arcDrawn)),
      letterSwept: easeOut(_clamp((ms - letterStart) / letterLength)),
      dotCenter: _dotAt(ms),
      dotRadius: _dotRadiusAt(ms),
      dotVisible: ms > _dotAppears,
      dotTrail: [
        if (ms < dotSettled)
          for (var sample = 1; sample <= _trailSamples; sample++)
            if (ms - sample * _trailStep > _dotAppears)
              _dotAt(ms - sample * _trailStep),
      ],
    );
  }

  static Offset _dotAt(double ms) {
    if (ms < arcDrawn) {
      return _pointAt(_line.length * _easeInOut(_clamp(ms / arcDrawn)));
    }
    final back = _clamp((ms - arcDrawn) / rollBack);
    final along =
        _line.length - (_line.length - _restAlong) * _easeOutBack(back);
    final settle = _clamp((ms - dotSettling) / (dotSettled - dotSettling));
    return Offset.lerp(_pointAt(along), TracendMarkGeometry.dotCenter, settle)!;
  }

  static double _dotRadiusAt(double ms) {
    if (ms < arcDrawn) return _dotStartRadius;
    final back = _clamp((ms - arcDrawn) / rollBack);
    return _dotStartRadius +
        (TracendMarkGeometry.dotRadius - _dotStartRadius) * easeOut(back);
  }

  static double markScaleAt(double ms) {
    if (ms < dotSettled) {
      return _startScale +
          (_peakScale - _startScale) * _easeInOut(_clamp(ms / dotSettled));
    }
    final settle = _clamp((ms - dotSettled) / _scaleSettle);
    return _peakScale + (1 - _peakScale) * _easeInOutSine(settle);
  }

  static double bloomAt(double ms) {
    if (ms < _bloomPeak) {
      return easeOut(_clamp((ms - _bloomStart) / (_bloomPeak - _bloomStart)));
    }
    final relax = _clamp((ms - _bloomPeak) / (_bloomRelaxed - _bloomPeak));
    return 1 + (_bloomRest - 1) * _easeInOutSine(relax);
  }

  /// How far [index]'s letter has risen into place, from 0 to 1.
  static double letterRevealAt(double ms, int index) =>
      _clamp((ms - wordStart - index * _letterStagger) / _letterLength);

  /// The extra space between letters, closing to none.
  static double wordmarkSpreadAt(double ms) =>
      _startSpread * (1 - easeOut(_clamp((ms - wordStart) / _spreadLength)));

  /// [ms] held to the wordmark's own motion: frames outside it look alike.
  static double wordmarkAt(double ms) => ms.clamp(wordStart, _wordEnd);

  static Offset _pointAt(double along) =>
      _line.getTangentForOffset(along.clamp(0.0, _line.length))!.position;

  static double _clamp(double value) => value.clamp(0.0, 1.0);

  static double easeOut(double t) => 1 - math.pow(1 - t, 3).toDouble();

  static double _easeInOut(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;

  static double _easeInOutSine(double t) => (1 - math.cos(math.pi * t)) / 2;

  static double _easeOutBack(double t) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
  }
}
