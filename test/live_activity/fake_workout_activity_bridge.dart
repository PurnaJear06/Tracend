import 'package:tracend/shared/live_activity/workout_activity_bridge.dart';

/// One call the controller made to the Live Activity.
typedef ActivityCall = ({
  String method,
  DateTime? endsAt,
  String? nextLabel,
  String? exerciseName,
});

/// Records every call instead of showing a Live Activity, tracks the one
/// activity the native side would show, and plays its buttons ([press]).
class FakeWorkoutActivityBridge implements WorkoutActivityBridge {
  final calls = <ActivityCall>[];

  /// The end time of the activity that would be showing, or null.
  DateTime? showingUntil;

  List<String> get methods => [for (final call in calls) call.method];

  /// The open workout's handler for the buttons, or null.
  LiveActivityPressHandler? onPress;

  /// Taps [button] as iOS would: true once an open workout acted on it.
  Future<bool> press(LiveActivityButton button) async {
    final handler = onPress;
    if (handler == null) return false;
    await handler(button);
    return true;
  }

  @override
  Future<void> startRest({
    required DateTime endsAt,
    required String nextLabel,
    required String exerciseName,
  }) async {
    calls.add((
      method: 'startRest',
      endsAt: endsAt,
      nextLabel: nextLabel,
      exerciseName: exerciseName,
    ));
    showingUntil = endsAt;
  }

  @override
  Future<void> updateRest({required DateTime endsAt, String? nextLabel}) async {
    calls.add((
      method: 'updateRest',
      endsAt: endsAt,
      nextLabel: nextLabel,
      exerciseName: null,
    ));
    if (showingUntil != null) showingUntil = endsAt;
  }

  @override
  Future<void> end() async {
    calls.add((
      method: 'end',
      endsAt: null,
      nextLabel: null,
      exerciseName: null,
    ));
    showingUntil = null;
  }

  @override
  Future<void> attachButtons(LiveActivityPressHandler onPress) async {
    this.onPress = onPress;
  }

  @override
  Future<void> detachButtons(LiveActivityPressHandler onPress) async {
    if (this.onPress == onPress) this.onPress = null;
  }
}
