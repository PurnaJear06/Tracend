import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tracend/app/breadcrumbs.dart';

/// The native channel for the workout Live Activity
/// (`ios/Runner/Native/WorkoutActivityBridge.swift`). The app calls
/// `startRest`, `updateRest`, `showSet`, `hideNumbers`, `end`,
/// `attachButtons` and `detachButtons`; iOS calls `press` when a button on
/// the activity is tapped.
const liveActivityChannel = MethodChannel('tracend/live_activity');

/// The set the Live Activity names, and that its "Log set" button logs:
/// [exerciseOrder] and [setNumber] (1-based) say which, [setCount] is how
/// many sets the exercise has, [exerciseName] is shown with them. [target]
/// is the kg and reps the app pre-fills for the set ("82.5 kg × 8"), and is
/// empty unless the athlete allows numbers on the Lock Screen
/// (SECURITY_PRIVACY.md §10). [canLog] is false when the app has no reps for
/// the set, so the card offers "Open" only.
typedef ActivitySet = ({
  int exerciseOrder,
  int setNumber,
  int setCount,
  String exerciseName,
  String target,
  bool canLog,
});

/// The keys a set travels under on the channel.
Map<String, Object> activitySetArguments(ActivitySet set) => {
  'next_exercise_order': set.exerciseOrder,
  'next_set_number': set.setNumber,
  'next_set_count': set.setCount,
  'next_exercise_name': set.exerciseName,
  'next_target': set.target,
  'next_can_log': set.canLog,
};

/// A button tapped on the workout Live Activity (iOS 17 App Intents in
/// `ios/Shared/RestActivityIntents.swift`). The activity never changes the
/// workout itself: each press goes to the open workout, which decides.
sealed class LiveActivityButton {
  const LiveActivityButton(this.pressedAt);

  /// How long iOS waits for the workout to answer a press
  /// (`WorkoutActivityBridge.pressTimeout`). After it the card already shows
  /// "Open Tracend to continue", so a press this old is dropped, never applied.
  static const pressTimeout = Duration(seconds: 8);

  /// Reads a `press` call's arguments, which always carry the Swift-side
  /// press time as `pressed_at_millis`: `{"button": "done", "exercise_order":
  /// 1, "set_number": 3}`, `{"button": "skip"}` or `{"button": "add_rest",
  /// "seconds": 30}`. Null for anything else: no press time, a Done without
  /// the set the card named (an older payload is refused, never applied to
  /// whatever set is current), or seconds outside 1 to 300.
  static LiveActivityButton? fromChannel(Object? arguments) {
    if (arguments is! Map) return null;
    final millis = arguments['pressed_at_millis'];
    if (millis is! int) return null;
    final pressedAt = DateTime.fromMillisecondsSinceEpoch(millis);
    final seconds = arguments['seconds'];
    final order = arguments['exercise_order'];
    final number = arguments['set_number'];
    return switch (arguments['button']) {
      'done' when order is int && number is int && number >= 1 => DoneSetButton(
        pressedAt,
        exerciseOrder: order,
        setNumber: number,
      ),
      'skip' => SkipRestButton(pressedAt),
      'add_rest' when seconds is int && seconds >= 1 && seconds <= 300 =>
        AddRestButton(pressedAt, seconds),
      _ => null,
    };
  }

  /// When the press happened, stamped on the Swift side.
  final DateTime pressedAt;

  /// The moment after which this press is too old to apply.
  DateTime get expiresAt => pressedAt.add(pressTimeout);

  /// The name in breadcrumbs: which button, never a workout value.
  String get name;
}

/// "Log set": the athlete did the set the card named, at the values the card
/// shows. [exerciseOrder] and [setNumber] are that set, as the card showed it.
final class DoneSetButton extends LiveActivityButton {
  const DoneSetButton(
    super.pressedAt, {
    required this.exerciseOrder,
    required this.setNumber,
  });

  final int exerciseOrder;
  final int setNumber;

  @override
  String get name => 'done';
}

/// "Skip": the rest ends now.
final class SkipRestButton extends LiveActivityButton {
  const SkipRestButton(super.pressedAt);

  @override
  String get name => 'skip';
}

/// "+30s": the rest runs [seconds] longer.
final class AddRestButton extends LiveActivityButton {
  const AddRestButton(super.pressedAt, this.seconds);

  final int seconds;

  @override
  String get name => 'add_rest';
}

/// Acts on a press and completes with whether it was handled: true once the
/// workout acted on it or knowingly ignored it as out of date (the card then
/// shows the true state), false when it could not (the card then asks the
/// athlete to open the app).
typedef LiveActivityPressHandler =
    Future<bool> Function(LiveActivityButton button);

/// The workout's Live Activity on the Lock Screen and in the Dynamic Island:
/// the set in progress with "Log set", and between sets a rest countdown that
/// iOS runs from its end time, so it keeps going with the app closed. When
/// the rest ends the card turns into the next set on its own. It is a
/// convenience like the rest alert: the in-app timer and logger work without
/// it, so failures are logged and never thrown.
///
/// Only the exercise name, the set's position, the labels and, when the
/// athlete allows Lock Screen numbers, the set's kg and reps travel; never
/// effort, heart rate or any other health value (SECURITY_PRIVACY.md §10).
///
/// Lifecycle: `RestTimerController` is the only caller of the show, rest and
/// end methods during a workout (the set in progress, start, ±15 and +30,
/// skip, the end, restore after a relaunch, and the screen going away);
/// sign-out and account deletion call [end]; the opt-out of Lock Screen
/// numbers calls [hideNumbers]; the native side ends the cards left from an
/// earlier launch that are over. The open workout screen takes the buttons
/// ([attachButtons]).
abstract interface class WorkoutActivityBridge {
  /// Shows a rest that ends at [endsAt], replacing any earlier one.
  /// [nextLabel] says what follows ("Set 3 of Bench press"); [exerciseName]
  /// names the exercise the rest belongs to. Empty labels show generic text.
  /// [next] is the set that follows: the card turns into it when the rest
  /// ends, and its "Log set" button carries that set back so only it is
  /// logged. Without it the card has no button.
  Future<void> startRest({
    required DateTime endsAt,
    required String nextLabel,
    required String exerciseName,
    ActivitySet? next,
  });

  /// Moves the end of the rest that is showing, its next label when given,
  /// and the set that follows it when given. Shows nothing when no activity
  /// is running.
  Future<void> updateRest({
    required DateTime endsAt,
    String? nextLabel,
    ActivitySet? next,
  });

  /// Shows the set in progress ([set]), or that every set is logged when
  /// [set] is null. A running activity is moved in place. With [begin] a new
  /// one is requested when none runs (the workout opened, a set was logged);
  /// without it nothing appears, so a card the athlete dismissed stays gone.
  Future<void> showSet(ActivitySet? set, {required bool begin});

  /// Removes the kg and reps from the card that is showing (the athlete
  /// turned Lock Screen numbers off).
  Future<void> hideNumbers();

  /// Ends the activity at once. Safe to call when there is none.
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
    ActivitySet? next,
  }) => _invoke('startRest', {
    'ends_at_millis': endsAt.millisecondsSinceEpoch,
    'next_label': nextLabel,
    'exercise_name': exerciseName,
    if (next != null) ...activitySetArguments(next),
  });

  @override
  Future<void> updateRest({
    required DateTime endsAt,
    String? nextLabel,
    ActivitySet? next,
  }) => _invoke('updateRest', {
    'ends_at_millis': endsAt.millisecondsSinceEpoch,
    'next_label': ?nextLabel,
    if (next != null) ...activitySetArguments(next),
  });

  @override
  Future<void> showSet(ActivitySet? set, {required bool begin}) => _invoke(
    'showSet',
    {'begin': begin, if (set != null) ...activitySetArguments(set)},
  );

  @override
  Future<void> hideNumbers() => _invoke('hideNumbers', null);

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

  /// The clock for the age of a press.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// iOS's `press`: answers true once an open workout handled it, false
  /// when none did (the native side then asks the athlete to open the
  /// app). A press older than [LiveActivityButton.pressTimeout] is dropped
  /// unapplied: iOS gave up on it long ago. Breadcrumbs name the button only.
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
    if (clock().isAfter(button.expiresAt)) {
      AppBreadcrumbs.workout(
        'Rest live activity press',
        data: {'button': button.name, 'taken': false, 'late': true},
      );
      return false;
    }
    if (onPress != null) {
      try {
        taken = await onPress(button);
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
