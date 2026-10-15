import 'package:tracend/shared/live_activity/workout_activity_bridge.dart';

/// One call the controller made to the Live Activity.
typedef ActivityCall = ({
  String method,
  DateTime? endsAt,
  String? nextLabel,
  String? exerciseName,
  int? nextExerciseOrder,
  int? nextSetNumber,
});

/// Records every call instead of showing a Live Activity, tracks the one
/// activity the native side would show, and plays its buttons ([press]).
class FakeWorkoutActivityBridge implements WorkoutActivityBridge {
  FakeWorkoutActivityBridge({this.clock = DateTime.now});

  /// Stamps each press, as the Swift side does.
  final DateTime Function() clock;

  final calls = <ActivityCall>[];

  /// The set the card's Done button carries (from the last `startRest`),
  /// or null when the card has none.
  ({int exerciseOrder, int setNumber})? card;

  /// The end time of the activity that would be showing, or null.
  DateTime? showingUntil;

  List<String> get methods => [for (final call in calls) call.method];

  /// The open workout's handler for the buttons, or null.
  LiveActivityPressHandler? onPress;

  /// Taps [button] as iOS would: true once an open workout handled it.
  Future<bool> press(LiveActivityButton button) async {
    final handler = onPress;
    if (handler == null) return false;
    return handler(button);
  }

  /// Taps Done on the card as it shows now, or on the set named by
  /// [exerciseOrder] and [setNumber] (a card drawn earlier). [at] is the
  /// press time (default: now).
  Future<bool> pressDone({int? exerciseOrder, int? setNumber, DateTime? at}) =>
      press(
        DoneSetButton(
          at ?? clock(),
          exerciseOrder: exerciseOrder ?? card!.exerciseOrder,
          setNumber: setNumber ?? card!.setNumber,
        ),
      );

  Future<bool> pressSkip({DateTime? at}) =>
      press(SkipRestButton(at ?? clock()));

  Future<bool> pressAdd(int seconds, {DateTime? at}) =>
      press(AddRestButton(at ?? clock(), seconds));

  @override
  Future<void> startRest({
    required DateTime endsAt,
    required String nextLabel,
    required String exerciseName,
    int? nextExerciseOrder,
    int? nextSetNumber,
  }) async {
    calls.add((
      method: 'startRest',
      endsAt: endsAt,
      nextLabel: nextLabel,
      exerciseName: exerciseName,
      nextExerciseOrder: nextExerciseOrder,
      nextSetNumber: nextSetNumber,
    ));
    showingUntil = endsAt;
    card = nextExerciseOrder == null || nextSetNumber == null
        ? null
        : (exerciseOrder: nextExerciseOrder, setNumber: nextSetNumber);
  }

  @override
  Future<void> updateRest({required DateTime endsAt, String? nextLabel}) async {
    calls.add((
      method: 'updateRest',
      endsAt: endsAt,
      nextLabel: nextLabel,
      exerciseName: null,
      nextExerciseOrder: null,
      nextSetNumber: null,
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
      nextExerciseOrder: null,
      nextSetNumber: null,
    ));
    showingUntil = null;
    card = null;
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
