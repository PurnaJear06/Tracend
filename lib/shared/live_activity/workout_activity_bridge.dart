import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tracend/app/breadcrumbs.dart';

/// The native channel for the rest-timer Live Activity
/// (`ios/Runner/Native/WorkoutActivityBridge.swift`).
const liveActivityChannel = MethodChannel('tracend/live_activity');

/// The workout's Live Activity on the Lock Screen and in the Dynamic Island:
/// a rest countdown that iOS runs from its end time, so it keeps going with
/// the app closed. It is a convenience like the rest alert: the in-app timer
/// works without it, so failures are logged and never thrown.
///
/// Only the end time and the labels travel; never a load, reps, effort or
/// health value.
abstract interface class WorkoutActivityBridge {
  /// Shows a rest that ends at [endsAt], replacing any earlier one.
  /// [nextLabel] says what follows ("Set 3 of Bench press"); [exerciseName]
  /// and [workoutTitle] name what the rest belongs to. Empty labels show
  /// generic text.
  Future<void> startRest({
    required DateTime endsAt,
    required String nextLabel,
    required String exerciseName,
    String workoutTitle = '',
  });

  /// Moves the end of the rest that is showing, and its next label when
  /// given. Shows nothing when no rest activity is running.
  Future<void> updateRest({required DateTime endsAt, String? nextLabel});

  /// Ends the rest activity. Safe to call when there is none.
  Future<void> end();
}

class MethodChannelWorkoutActivityBridge implements WorkoutActivityBridge {
  const MethodChannelWorkoutActivityBridge();

  @override
  Future<void> startRest({
    required DateTime endsAt,
    required String nextLabel,
    required String exerciseName,
    String workoutTitle = '',
  }) => _invoke('startRest', {
    'ends_at_millis': endsAt.millisecondsSinceEpoch,
    'next_label': nextLabel,
    'exercise_name': exerciseName,
    'workout_title': workoutTitle,
  });

  @override
  Future<void> updateRest({required DateTime endsAt, String? nextLabel}) =>
      _invoke('updateRest', {
        'ends_at_millis': endsAt.millisecondsSinceEpoch,
        'next_label': ?nextLabel,
      });

  @override
  Future<void> end() => _invoke('end', null);

  /// Calls the native side and leaves a breadcrumb with the method and
  /// whether a rest activity is showing, never the arguments.
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
