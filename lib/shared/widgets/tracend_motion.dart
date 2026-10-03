import 'package:flutter/widgets.dart';

/// How much motion the shared widgets may use (DESIGN_SYSTEM.md §6).
enum TracendMotionLevel {
  /// Springs, slides, scale on press and the skeleton shimmer.
  full,

  /// Reduce Motion: crossfades instead of slides, no loops, no scale.
  reduced,

  /// No animation at all. Every change lands in one frame.
  static,
}

/// Sets the motion level for the shared widgets below it.
///
/// The effective level is the stricter of this scope and the system Reduce
/// Motion setting ([MediaQuery.disableAnimationsOf]), so a scope can only
/// take motion away. Where no scope is in the tree, [defaultLevel] applies.
class TracendMotionScope extends InheritedWidget {
  const TracendMotionScope({
    required this.level,
    required super.child,
    super.key,
  });

  final TracendMotionLevel level;

  /// The level used where no [TracendMotionScope] is in the tree. The app
  /// leaves it at [TracendMotionLevel.full]; `test/flutter_test_config.dart`
  /// sets it to [TracendMotionLevel.static] so `pumpAndSettle` never waits on
  /// a looping shimmer.
  static TracendMotionLevel defaultLevel = TracendMotionLevel.full;

  /// The effective level for [context].
  static TracendMotionLevel of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<TracendMotionScope>();
    final requested = scope?.level ?? defaultLevel;
    final systemReduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (systemReduced && requested == TracendMotionLevel.full) {
      return TracendMotionLevel.reduced;
    }
    return requested;
  }

  /// [duration] at full motion, zero otherwise. For transitions that only
  /// make sense as movement (scale, slide).
  static Duration movement(BuildContext context, Duration duration) =>
      of(context) == TracendMotionLevel.full ? duration : Duration.zero;

  /// [duration] unless motion is static. Reduce Motion keeps fades, which
  /// read as a change of state rather than movement.
  static Duration fade(BuildContext context, Duration duration) =>
      of(context) == TracendMotionLevel.static ? Duration.zero : duration;

  @override
  bool updateShouldNotify(TracendMotionScope oldWidget) =>
      level != oldWidget.level;
}
