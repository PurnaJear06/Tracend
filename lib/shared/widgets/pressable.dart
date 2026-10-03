import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// Makes cards, rows and pills tappable the iOS way: the child scales to
/// [pressedScale] while the finger is down, with no ripple or highlight
/// (DESIGN_SYSTEM.md §6).
///
/// It is a button to VoiceOver. Pass [semanticLabel] when the child's text
/// alone does not say what the tap does; the label then replaces the
/// child's semantics. Reduce Motion keeps the tap and drops the scale.
class Pressable extends StatefulWidget {
  const Pressable({
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.haptic,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(TracendRadii.card),
    ),
    this.pressedScale = 0.97,
    super.key,
  });

  final Widget child;

  /// Null disables the press: no scale, and VoiceOver reads it as dimmed.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  /// A [TracendHaptics] role played on tap, such as `TracendHaptics.light`.
  final Future<void> Function()? haptic;

  /// The shape of the keyboard focus highlight.
  final BorderRadius borderRadius;
  final double pressedScale;

  static const pressDuration = Duration(milliseconds: 120);

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    widget.haptic?.call();
    widget.onTap?.call();
  }

  @override
  void didUpdateWidget(Pressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final duration = TracendMotionScope.movement(
      context,
      Pressable.pressDuration,
    );
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      onTap: widget.semanticLabel != null && widget.onTap != null
          ? _handleTap
          : null,
      child: AnimatedScale(
        scale: _pressed && duration != Duration.zero ? widget.pressedScale : 1,
        duration: duration,
        curve: TracendMotion.curve,
        child: InkWell(
          onTap: widget.onTap == null ? null : _handleTap,
          onLongPress: widget.onLongPress,
          onHighlightChanged: _enabled ? _setPressed : null,
          borderRadius: widget.borderRadius,
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: colors.accentSignalTint,
          child: widget.child,
        ),
      ),
    );
  }
}
