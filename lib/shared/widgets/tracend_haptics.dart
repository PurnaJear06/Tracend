import 'package:flutter/services.dart';

/// The app's haptic vocabulary (DESIGN_SYSTEM.md §6). Call the role, never a
/// raw [HapticFeedback] method, so one gesture always feels the same.
///
/// Every call goes through [SystemChannels.platform]; in widget tests the
/// channel has no handler and the call does nothing unless a test mocks it.
abstract final class TracendHaptics {
  /// Moving between options: tabs, segments, the day strip.
  static Future<void> selection() => HapticFeedback.selectionClick();

  /// A small confirmed change: checking a set, flipping a toggle.
  static Future<void> light() => HapticFeedback.lightImpact();

  /// A meaningful moment: starting rest, finishing, a new best.
  static Future<void> medium() => HapticFeedback.mediumImpact();

  /// The one big commitment: Start workout.
  static Future<void> heavy() => HapticFeedback.heavyImpact();

  /// A task completed (system success pattern).
  static Future<void> success() => HapticFeedback.successNotification();

  /// Something needs care before going on: a destructive confirmation, a
  /// blocked action (system warning pattern).
  static Future<void> warning() => HapticFeedback.warningNotification();
}
