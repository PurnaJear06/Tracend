import 'package:tracend/shared/live_activity/workout_activity_bridge.dart';

/// One call the controller made to the Live Activity.
typedef ActivityCall = ({
  String method,
  DateTime? endsAt,
  String? nextLabel,
  String? exerciseName,
});

/// Records every call instead of showing a Live Activity, and tracks the
/// one activity the native side would show.
class FakeWorkoutActivityBridge implements WorkoutActivityBridge {
  final calls = <ActivityCall>[];

  /// The end time of the activity that would be showing, or null.
  DateTime? showingUntil;

  List<String> get methods => [for (final call in calls) call.method];

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
}
