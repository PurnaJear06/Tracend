import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_glass.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// A short confirmation that drops in at the top of the screen as a glass
/// pill, then leaves on its own (DESIGN_SYSTEM.md §5.1, toast).
///
/// Use it for transient, non-blocking feedback ("Check-in saved"). Anything
/// the athlete must act on belongs in a confirm or a sheet. One toast shows
/// at a time; a new one replaces the current one. Tap or swipe it up to
/// dismiss early. VoiceOver reads it through a live region.
abstract final class TracendToast {
  static const visibleFor = Duration(milliseconds: 2300);

  static final Expando<OverlayEntry> _active = Expando<OverlayEntry>(
    'TracendToast',
  );

  /// Shows [message] with [icon] in the root overlay of [context].
  static void show(
    BuildContext context,
    String message, {
    IconData icon = CupertinoIcons.checkmark_alt,
    Duration duration = visibleFor,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    _remove(overlay);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastHost(
        message: message,
        icon: icon,
        duration: duration,
        onDismissed: () {
          if (identical(_active[overlay], entry)) _active[overlay] = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _active[overlay] = entry;
    overlay.insert(entry);
  }

  /// Removes the visible toast in [context]'s root overlay, if any.
  static void hide(BuildContext context) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay != null) _remove(overlay);
  }

  static void _remove(OverlayState overlay) {
    final current = _active[overlay];
    _active[overlay] = null;
    if (current != null && current.mounted) current.remove();
  }
}

class _ToastHost extends StatefulWidget {
  const _ToastHost({
    required this.message,
    required this.icon,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final IconData icon;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost>
    with SingleTickerProviderStateMixin {
  static const _enter = Duration(milliseconds: 420);
  static const _exit = Duration(milliseconds: 220);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _enter,
    reverseDuration: _exit,
  );
  Timer? _timer;
  TracendMotionLevel _level = TracendMotionLevel.full;
  bool _started = false;
  bool _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _level = TracendMotionScope.of(context);
    if (_started) return;
    _started = true;
    if (_level == TracendMotionLevel.static) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
    _timer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    if (_level != TracendMotionLevel.static) {
      await _controller.reverse();
    }
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final top = MediaQuery.paddingOf(context).top + TracendSpacing.xs;
    final slides = _level == TracendMotionLevel.full;
    final enter = CurvedAnimation(
      parent: _controller,
      curve: TracendMotion.settle,
      reverseCurve: Curves.easeInCubic,
    );
    final pill = Semantics(
      liveRegion: true,
      container: true,
      label: widget.message,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          // A soft lift so the pill separates from glass chrome beneath it.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TracendRadii.pill),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.32
                      : 0.08,
                ),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TracendGlass(
            borderRadius: TracendRadii.pill,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TracendSpacing.md,
                vertical: TracendSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 18, color: colors.textPrimary),
                  const SizedBox(width: TracendSpacing.xs),
                  Flexible(
                    child: Text(
                      widget.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Positioned(
      top: top,
      left: TracendSpacing.md,
      right: TracendSpacing.md,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: GestureDetector(
            onTap: _dismiss,
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < 0) _dismiss();
            },
            child: AnimatedBuilder(
              animation: enter,
              builder: (context, child) {
                final t = enter.value;
                return Opacity(
                  opacity: _controller.value,
                  child: slides
                      ? Transform.translate(
                          offset: Offset(0, (t - 1) * (top + 64)),
                          child: child,
                        )
                      : child,
                );
              },
              child: pill,
            ),
          ),
        ),
      ),
    );
  }
}
