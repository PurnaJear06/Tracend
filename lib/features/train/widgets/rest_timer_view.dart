import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_glass.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// "1:30", "0:05".
String formatRest(int seconds) {
  final safe = math.max(0, seconds);
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}

/// "1 minute 30 seconds" for VoiceOver.
String spokenRest(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  final parts = [
    if (minutes > 0) '$minutes ${minutes == 1 ? 'minute' : 'minutes'}',
    if (rest > 0 || minutes == 0) '$rest ${rest == 1 ? 'second' : 'seconds'}',
  ];
  return parts.join(' ');
}

/// The lime rest ring: the arc is the rest still to go, so it drains as the
/// rest runs. Between seconds it eases at full motion and steps otherwise.
class RestRing extends StatelessWidget {
  const RestRing({
    required this.remaining,
    required this.size,
    required this.strokeWidth,
    this.child,
    super.key,
  });

  /// Share of the rest still to go, 0 to 1.
  final double remaining;
  final double size;
  final double strokeWidth;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: remaining.clamp(0, 1).toDouble()),
        duration: TracendMotionScope.movement(
          context,
          const Duration(seconds: 1),
        ),
        builder: (context, value, child) => CustomPaint(
          painter: _RingPainter(
            remaining: value,
            strokeWidth: strokeWidth,
            track: colors.surfaceRaised,
            arc: colors.accentSignalRing,
          ),
          child: child,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.remaining,
    required this.strokeWidth,
    required this.track,
    required this.arc,
  });

  final double remaining;
  final double strokeWidth;
  final Color track;
  final Color arc;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = rect.deflate(strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(circle, 0, math.pi * 2, false, paint..color = track);
    if (remaining <= 0) return;
    canvas.drawArc(
      circle,
      -math.pi / 2,
      math.pi * 2 * remaining,
      false,
      paint..color = arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.remaining != remaining ||
      old.strokeWidth != strokeWidth ||
      old.track != track ||
      old.arc != arc;
}

/// A rest button: −15, +15 or Skip.
class _RestButton extends StatelessWidget {
  const _RestButton({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    required this.fill,
    this.height = 44,
    this.minWidth = 52,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final Color fill;
  final double height;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      haptic: TracendHaptics.selection,
      borderRadius: BorderRadius.circular(TracendRadii.pill),
      child: Container(
        constraints: BoxConstraints(minHeight: height, minWidth: minWidth),
        padding: const EdgeInsets.symmetric(horizontal: TracendSpacing.sm),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(TracendRadii.pill),
        ),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            label,
            style: TracendTheme.numeric(
              colors,
              fontSize: height > 48 ? 16 : 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// The rest taking over the exercise: a big lime ring with the time left,
/// what comes next, ±15 s and Skip, and the effort of the set just done.
/// It never traps the athlete: a swipe down or Hide shrinks it to the pill.
class RestTimerOverlay extends StatefulWidget {
  const RestTimerOverlay({
    required this.remainingSeconds,
    required this.remainingShare,
    required this.nextLabel,
    required this.onMinus,
    required this.onPlus,
    required this.onSkip,
    required this.onHide,
    this.effort,
    super.key,
  });

  final int remainingSeconds;
  final double remainingShare;

  /// "Set 3 of Bench press", or the next exercise's name.
  final String nextLabel;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onSkip;
  final VoidCallback onHide;

  /// The effort picker for the set just done.
  final Widget? effort;

  @override
  State<RestTimerOverlay> createState() => _RestTimerOverlayState();
}

class _RestTimerOverlayState extends State<RestTimerOverlay> {
  static const _hideDistance = 90.0;
  static const _hideVelocity = 700.0;
  double _drag = 0;
  bool _dragging = false;

  void _end(DragEndDetails details) {
    final hide =
        _drag > _hideDistance || (details.primaryVelocity ?? 0) > _hideVelocity;
    setState(() {
      _dragging = false;
      _drag = 0;
    });
    if (hide) widget.onHide();
  }

  /// A pull down past the top of the scrolling content hides the rest too:
  /// on iOS the scroll view takes every vertical drag, even when it fits.
  double _pull = 0;
  bool _pulledAway = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final metrics = notification.metrics;
    if (notification is ScrollStartNotification) {
      _pull = 0;
      _pulledAway = false;
    } else if (notification is OverscrollNotification &&
        notification.overscroll < 0 &&
        notification.dragDetails != null) {
      _pull -= notification.overscroll;
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _pull = metrics.minScrollExtent - metrics.pixels;
    }
    if (!_pulledAway && _pull > _hideDistance) {
      _pulledAway = true;
      widget.onHide();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => setState(() => _dragging = true),
      onVerticalDragUpdate: (details) =>
          setState(() => _drag = math.max(0, _drag + details.delta.dy)),
      onVerticalDragEnd: _end,
      child: AnimatedContainer(
        duration: _dragging
            ? Duration.zero
            : TracendMotionScope.movement(context, TracendMotion.standard),
        curve: TracendMotion.curve,
        transform: Matrix4.translationValues(0, _drag, 0),
        color: colors.canvas,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ring = math
                .min(
                  248.0,
                  math.min(
                    constraints.maxWidth - 64,
                    constraints.maxHeight * (scale > 1.4 ? 0.34 : 0.42),
                  ),
                )
                .clamp(140.0, 248.0);
            return NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  TracendSpacing.gutter,
                  TracendSpacing.xs,
                  TracendSpacing.gutter,
                  TracendSpacing.xl,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0, constraints.maxHeight - 40),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Pressable(
                        onTap: widget.onHide,
                        semanticLabel: 'Hide rest timer',
                        borderRadius: BorderRadius.circular(TracendRadii.pill),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.chevron_down,
                                size: 20,
                                color: colors.textSecondary,
                              ),
                              Text(
                                'Swipe down to keep editing',
                                textAlign: TextAlign.center,
                                style: text.labelSmall?.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: TracendSpacing.lg),
                      Semantics(
                        label:
                            'Rest, ${spokenRest(widget.remainingSeconds)} left',
                        excludeSemantics: true,
                        child: RestRing(
                          remaining: widget.remainingShare,
                          size: ring,
                          strokeWidth: 12,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Rest',
                                textScaler: MediaQuery.textScalerOf(
                                  context,
                                ).clamp(maxScaleFactor: 1.3),
                                style: text.labelLarge?.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                              FittedBox(
                                child: Text(
                                  formatRest(widget.remainingSeconds),
                                  style: TracendTheme.numeric(
                                    colors,
                                    fontSize: ring * 0.29,
                                    fontWeight: FontWeight.w800,
                                  ).copyWith(height: 1, letterSpacing: -1.5),
                                  textScaler: TextScaler.noScaling,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: TracendSpacing.lg),
                      Text(
                        'Next',
                        style: text.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.nextLabel,
                        textAlign: TextAlign.center,
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: TracendSpacing.lg),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: TracendSpacing.sm,
                        runSpacing: TracendSpacing.sm,
                        children: [
                          _RestButton(
                            label: '−15',
                            semanticLabel: '15 seconds less rest',
                            onTap: widget.onMinus,
                            fill: colors.surface,
                            height: 52,
                            minWidth: 76,
                          ),
                          _RestButton(
                            label: '+15',
                            semanticLabel: '15 seconds more rest',
                            onTap: widget.onPlus,
                            fill: colors.surface,
                            height: 52,
                            minWidth: 76,
                          ),
                          _RestButton(
                            label: 'Skip',
                            semanticLabel: 'Skip rest',
                            onTap: widget.onSkip,
                            fill: colors.surface,
                            height: 52,
                            minWidth: 76,
                          ),
                        ],
                      ),
                      if (widget.effort != null) ...[
                        const SizedBox(height: TracendSpacing.lg),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: widget.effort,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The rest shrunk to a floating pill so the exercise can be edited. A tap
/// on the ring or the label opens the full rest again.
class RestTimerPill extends StatelessWidget {
  const RestTimerPill({
    required this.remainingSeconds,
    required this.remainingShare,
    required this.nextLabel,
    required this.onMinus,
    required this.onPlus,
    required this.onSkip,
    required this.onExpand,
    super.key,
  });

  final int remainingSeconds;
  final double remainingShare;
  final String nextLabel;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onSkip;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    final roomy = media.size.width >= 360 && media.textScaler.scale(1) <= 1.3;
    // The pill is chrome over the page, like the tab bar: its text grows
    // with Dynamic Type up to 1.5×, and the full rest view has the rest.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: TracendGlass(
        borderRadius: 32,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            TracendSpacing.xs,
            TracendSpacing.xs,
            TracendSpacing.xs,
            TracendSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Pressable(
                  onTap: onExpand,
                  semanticLabel:
                      'Rest, ${spokenRest(remainingSeconds)} left. Next: '
                      '$nextLabel. Show rest timer',
                  borderRadius: BorderRadius.circular(TracendRadii.pill),
                  child: Row(
                    children: [
                      RestRing(
                        remaining: remainingShare,
                        size: 46,
                        strokeWidth: 4,
                        child: Text(
                          formatRest(remainingSeconds),
                          textScaler: TextScaler.noScaling,
                          style: TracendTheme.numeric(
                            colors,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: TracendSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Rest',
                              style: text.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                            Text(
                              'Next: $nextLabel',
                              maxLines: roomy ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (roomy) ...[
                _RestButton(
                  label: '−15',
                  semanticLabel: '15 seconds less rest',
                  onTap: onMinus,
                  fill: colors.surfaceRaised,
                  minWidth: 48,
                ),
                const SizedBox(width: 6),
                _RestButton(
                  label: '+15',
                  semanticLabel: '15 seconds more rest',
                  onTap: onPlus,
                  fill: colors.surfaceRaised,
                  minWidth: 48,
                ),
                const SizedBox(width: 6),
              ],
              _RestButton(
                label: 'Skip',
                semanticLabel: 'Skip rest',
                onTap: onSkip,
                fill: colors.surfaceRaised,
                minWidth: 52,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
