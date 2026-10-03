import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/brand/tracend_mark.dart';

/// The launch intro: the mark builds itself over the launch screen's graphite
/// while [child] gets ready beneath it, then fades away to reveal [child].
///
/// The arc draws itself, the dot rides it to the tip, rolls back and settles
/// with a light haptic, the T sweeps in and the wordmark rises: 1.2 seconds,
/// played once per mount and never looped. A tap skips it. Under Reduce
/// Motion the finished mark shows and crossfades away.
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

  @override
  State<TracendIntro> createState() => _TracendIntroState();
}

class _TracendIntroState extends State<TracendIntro>
    with TickerProviderStateMixin {
  static const _markSize = 132.0;
  static const _wordmarkGap = 18.0;
  static const _fade = Duration(milliseconds: 320);
  static const _reducedFade = Duration(milliseconds: 200);
  static const _skipFade = Duration(milliseconds: 160);

  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: TracendIntro.motion,
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: _fade,
  );
  late final CurvedAnimation _exitCurve = CurvedAnimation(
    parent: _exit,
    curve: Curves.easeOut,
  );
  late final Animation<double> _opacity = ReverseAnimation(_exitCurve);

  bool _started = false;
  bool _reduced = false;
  bool _motionDone = false;
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
      if (widget.ready) _exit.forward();
      return;
    }
    _motion
      ..addListener(_onTick)
      ..addStatusListener((status) {
        if (!status.isCompleted) return;
        setState(() => _motionDone = true);
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
    _exitCurve.dispose();
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

  void _skip() {
    if (!_exit.isDismissed) return;
    _motion.stop();
    _exit
      ..duration = _skipFade
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(excluding: !_gone, child: widget.child),
        if (!_gone)
          FadeTransition(
            opacity: _opacity,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.light,
              child: _buildStage(context),
            ),
          ),
      ],
    );
  }

  Widget _buildStage(BuildContext context) {
    final waiting = _motionDone && !widget.ready && _exit.isDismissed;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _motionDone ? null : _skip,
      // The gate has no Scaffold yet: this gives the text its Material.
      child: Material(
        color: TracendBrandColors.graphite,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The mark sits where the launch screen's static mark sits.
            final markTop = (constraints.maxHeight - _markSize) / 2;
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: markTop,
                  child: Center(
                    child: SizedBox.square(
                      dimension: _markSize,
                      child: AnimatedBuilder(
                        animation: _motion,
                        builder: (context, _) => CustomPaint(
                          painter: TracendMarkPainter(
                            frame: _reduced
                                ? TracendMarkFrame.settled
                                : _IntroTimeline.markAt(_elapsedMs),
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
                      AnimatedBuilder(
                        animation: _motion,
                        builder: (context, wordmark) {
                          final rise = _reduced
                              ? 1.0
                              : _IntroTimeline.wordmarkAt(_elapsedMs);
                          return Opacity(
                            opacity: rise,
                            child: Transform.translate(
                              offset: Offset(0, (1 - rise) * 10),
                              child: wordmark,
                            ),
                          );
                        },
                        child: Text(
                          'Tracend',
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            fontFamily: TracendFonts.displayFamily,
                            fontSize: 30,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: TracendBrandColors.chalk,
                          ),
                        ),
                      ),
                      if (waiting) ...[
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
                if (!_motionDone)
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 4,
                    right: 8,
                    child: _SkipButton(onPressed: _skip),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Skip intro',
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        // A 44-point target around the 32-point pill.
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Skip',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9C9D98),
              ),
            ),
          ),
        ),
      ),
    );
  }
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

  /// The wordmark fades up last.
  static const wordStart = 760.0;
  static const wordLength = 400.0;

  static const _dotStartRadius = 22.0;

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
    final drawn = _easeInOut(_clamp(ms / arcDrawn));
    final Offset dot;
    final double radius;
    if (ms < arcDrawn) {
      dot = _pointAt(_line.length * drawn);
      radius = _dotStartRadius;
    } else {
      final back = _clamp((ms - arcDrawn) / rollBack);
      final along =
          _line.length - (_line.length - _restAlong) * _easeOutBack(back);
      final onArc = _pointAt(along);
      final settle = _clamp((ms - dotSettling) / (dotSettled - dotSettling));
      dot = Offset.lerp(onArc, TracendMarkGeometry.dotCenter, settle)!;
      radius =
          _dotStartRadius +
          (TracendMarkGeometry.dotRadius - _dotStartRadius) * _easeOut(back);
    }
    return TracendMarkFrame(
      arcDrawn: drawn,
      letterSwept: _easeOut(_clamp((ms - letterStart) / letterLength)),
      dotCenter: dot,
      dotRadius: radius,
      dotVisible: ms > 30,
    );
  }

  static double wordmarkAt(double ms) =>
      _easeOut(_clamp((ms - wordStart) / wordLength));

  static Offset _pointAt(double along) =>
      _line.getTangentForOffset(along.clamp(0.0, _line.length))!.position;

  static double _clamp(double value) => value.clamp(0.0, 1.0);

  static double _easeOut(double t) => 1 - math.pow(1 - t, 3).toDouble();

  static double _easeInOut(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;

  static double _easeOutBack(double t) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
  }
}
