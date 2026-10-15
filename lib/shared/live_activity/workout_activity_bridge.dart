import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tracend/app/breadcrumbs.dart';

/// The native channel for the rest-timer Live Activity
/// (`ios/Runner/Native/WorkoutActivityBridge.swift`). The app calls
/// `startRest`, `updateRest`, `end`, `attachButtons` and `detachButtons`;
/// iOS calls `press` when a button on the activity is tapped.
const liveActivityChannel = MethodChannel('tracend/live_activity');

/// A button tapped on the rest Live Activity (iOS 17 App Intents in
/// `ios/Shared/RestActivityIntents.swift`). The activity never changes the
/// workout itself: each press goes to the open workout, which decides.
sealed class LiveActivityButton {
  const LiveActivityButton();

  /// Reads a `press` call's arguments: `{"button": "done"}`,
  /// `{"button": "skip"}` or `{"button": "add_rest", "seconds": 30}`.
  /// Null for anything else, including seconds outside 1 to 300.
  static LiveActivityButton? fromChannel(Object? arguments) {
    if (arguments is! Map) return null;
    final seconds = arguments['seconds'];
    return switch (arguments['button']) {
      'done' => const DoneSetButton(),
      'skip' => const SkipRestButton(),
      'add_rest' when seconds is int && seconds >= 1 && seconds <= 300 =>
        AddRestButton(seconds),
      _ => null,
    };
  }

  /// The name in breadcrumbs: which button, never a workout value.
  String get name;
}

/// "Done set": the rest is over and the athlete did the set it named.
final class DoneSetButton extends LiveActivityButton {
  const DoneSetButton();

  @override
  String get name => 'done';
}

/// "Skip": the rest ends now.
final class SkipRestButton extends LiveActivityButton {
  const SkipRestButton();

  @override
  String get name => 'skip';
}

/// "+30s": the rest runs [seconds] longer.
final class AddRestButton extends LiveActivityButton {
  const AddRestButton(this.seconds);

  final int seconds;

  @override
  String get name => 'add_rest';
}

/// Acts on a press and completes once the workout has acted on it.
typedef LiveActivityPressHandler =
    Future<void> Function(LiveActivityButton button);

/// The workout's Live Activity on the Lock Screen and in the Dynamic Island:
/// a rest countdown that iOS runs from its end time, so it keeps going with
/// the app closed. It is a convenience like the rest alert: the in-app timer
/// works without it, so failures are logged and never thrown.
///
/// Only the end time, the exercise name and the next-set label travel; never
/// a load, reps, effort or health value (SECURITY_PRIVACY.md §10).
///
/// Lifecycle: `RestTimerController` is the only caller of the rest methods
/// during a workout (start, ±15 and +30, skip, the end, restore after a
/// relaunch, and the screen going away); sign-out and account deletion call
/// [end]; the native side ends the finished ones left from an earlier
/// launch. The open workout screen takes the buttons ([attachButtons]).
abstract interface class WorkoutActivityBridge {
  /// Shows a rest that ends at [endsAt], replacing any earlier one.
  /// [nextLabel] says what follows ("Set 3 of Bench press"); [exerciseName]
  /// names the exercise the rest belongs to. Empty labels show generic text.
  Future<void> startRest({
    required DateTime endsAt,
    required String nextLabel,
    required String exerciseName,
  });

  /// Moves the end of the rest that is showing, and its next label when
  /// given. Shows nothing when no rest activity is running.
  Future<void> updateRest({required DateTime endsAt, String? nextLabel});

  /// Ends the rest activity at once. Safe to call when there is none.
  Future<void> end();

  /// Sends the activity's button presses to [onPress] while a workout is
  /// open, replacing any earlier handler. iOS waits for [onPress] before it
  /// lets the app sleep again.
  Future<void> attachButtons(LiveActivityPressHandler onPress);

  /// Stops sending presses to [onPress] (when it is still the handler; a
  /// tear-off of the same method counts as the same handler). A
  /// press with no workout open asks the athlete to open the app.
  Future<void> detachButtons(LiveActivityPressHandler onPress);
}

class MethodChannelWorkoutActivityBridge implements WorkoutActivityBridge {
  const MethodChannelWorkoutActivityBridge();

  @override
  Future<void> startRest({
    required DateTime endsAt,
    required String nextLabel,
    required String exerciseName,
  }) => _invoke('startRest', {
    'ends_at_millis': endsAt.millisecondsSinceEpoch,
    'next_label': nextLabel,
    'exercise_name': exerciseName,
  });

  @override
  Future<void> updateRest({required DateTime endsAt, String? nextLabel}) =>
      _invoke('updateRest', {
        'ends_at_millis': endsAt.millisecondsSinceEpoch,
        'next_label': ?nextLabel,
      });

  @override
  Future<void> end() => _invoke('end', null);

  /// The open workout's handler. Static because the bridge is a const
  /// value and the channel has one handler per engine.
  static LiveActivityPressHandler? _onPress;

  @override
  Future<void> attachButtons(LiveActivityPressHandler onPress) async {
    _onPress = onPress;
    liveActivityChannel.setMethodCallHandler(_handle);
    await _invoke('attachButtons', null);
  }

  @override
  Future<void> detachButtons(LiveActivityPressHandler onPress) async {
    if (_onPress != onPress) return;
    _onPress = null;
    await _invoke('detachButtons', null);
  }

  /// iOS's `press`: answers true once an open workout acted on it, false
  /// when none took it (the native side then asks the athlete to open the
  /// app). Breadcrumbs name the button only.
  static Future<Object?> _handle(MethodCall call) async {
    if (call.method != 'press') {
      throw MissingPluginException('No ${call.method} on live activity');
    }
    final button = LiveActivityButton.fromChannel(call.arguments);
    if (button == null) {
      throw PlatformException(code: 'invalid_arguments');
    }
    final onPress = _onPress;
    var taken = false;
    if (onPress != null) {
      try {
        await onPress(button);
        taken = true;
      } catch (e) {
        debugPrint('Non-critical error: live activity press failed: $e');
      }
    }
    AppBreadcrumbs.workout(
      'Rest live activity press',
      data: {'button': button.name, 'taken': taken},
    );
    return taken;
  }

  /// Calls the native side and leaves a breadcrumb with the method and
  /// whether a rest activity is showing, never the arguments. A native
  /// error carries a fixed code only (`invalid_arguments`,
  /// `request_failed`), and only the code is logged.
  Future<void> _invoke(String method, Map<String, Object>? arguments) async {
    var showing = false;
    try {
      showing =
          await liveActivityChannel.invokeMethod<bool>(method, arguments) ==
          true;
    } on PlatformException catch (e) {
      debugPrint('Non-critical error: live activity $method failed: ${e.code}');
    } on MissingPluginException {
      debugPrint('Non-critical error: live activity $method unavailable');
    }
    AppBreadcrumbs.workout(
      'Rest live activity $method',
      data: {'showing': showing},
    );
  }
}
