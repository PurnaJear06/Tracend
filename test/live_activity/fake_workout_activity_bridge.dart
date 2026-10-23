import 'package:tracend/shared/live_activity/workout_activity_bridge.dart';

/// One call the controller made to the Live Activity.
typedef ActivityCall = ({
  String method,
  DateTime? endsAt,
  String? nextLabel,
  String? exerciseName,
  ActivitySet? next,
  bool? begin,
});

/// Records every call instead of showing a Live Activity, tracks the one
/// activity the native side would show, and plays its buttons ([press]).
class FakeWorkoutActivityBridge implements WorkoutActivityBridge {
  FakeWorkoutActivityBridge({this.clock = DateTime.now});

  /// Stamps each press, as the Swift side does.
  final DateTime Function() clock;

  final calls = <ActivityCall>[];

  /// The set the card's "Log set" button carries, or null when the card has
  /// none (every set is logged, or it was never named).
  ({int exerciseOrder, int setNumber})? get card {
    final set = this.set;
    return set == null
        ? null
        : (exerciseOrder: set.exerciseOrder, setNumber: set.setNumber);
  }

  /// The set the card names, with its target as the card would show it.
  ActivitySet? set;

  /// The end time of the rest the activity would show, the moment the set in
  /// progress began once no rest runs, or null when nothing shows.
  DateTime? showingUntil;

  bool get showing => showingUntil != null;

  /// What the card would show now: `rest`, `set`, `finished`, or null.
  String? get phase {
    final until = showingUntil;
    if (until == null) return null;
    if (until.isAfter(clock())) return 'rest';
    return set == null ? 'finished' : 'set';
  }

  /// When set, every start, update and end records its call at once but
  /// finishes only when this completes, as a slow ActivityKit call would;
  /// the activity shows the new state only then.
  Future<void>? hold;

  /// When set, every start, update and end throws it after the hold.
  Object? failWith;

  Future<void> _finish(void Function() show) async {
    final gate = hold;
    if (gate != null) await gate;
    final error = failWith;
    if (error != null) throw error;
    show();
  }

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
    ActivitySet? next,
  }) async {
    calls.add((
      method: 'startRest',
      endsAt: endsAt,
      nextLabel: nextLabel,
      exerciseName: exerciseName,
      next: next,
      begin: null,
    ));
    await _finish(() {
      showingUntil = endsAt;
      set = next;
    });
  }

  @override
  Future<void> updateRest({
    required DateTime endsAt,
    String? nextLabel,
    ActivitySet? next,
  }) async {
    calls.add((
      method: 'updateRest',
      endsAt: endsAt,
      nextLabel: nextLabel,
      exerciseName: null,
      next: next,
      begin: null,
    ));
    await _finish(() {
      if (showingUntil == null) return;
      showingUntil = endsAt;
      if (next != null) set = next;
    });
  }

  @override
  Future<void> showSet(ActivitySet? set, {required bool begin}) async {
    calls.add((
      method: 'showSet',
      endsAt: null,
      nextLabel: null,
      exerciseName: null,
      next: set,
      begin: begin,
    ));
    await _finish(() {
      if (showingUntil == null && !begin) return;
      showingUntil = clock();
      this.set = set;
    });
  }

  @override
  Future<void> hideNumbers() async {
    calls.add((
      method: 'hideNumbers',
      endsAt: null,
      nextLabel: null,
      exerciseName: null,
      next: null,
      begin: null,
    ));
    await _finish(() {
      final shown = set;
      if (shown == null) return;
      set = (
        exerciseOrder: shown.exerciseOrder,
        setNumber: shown.setNumber,
        setCount: shown.setCount,
        exerciseName: shown.exerciseName,
        target: '',
        canLog: shown.canLog,
      );
    });
  }

  @override
  Future<void> end() async {
    calls.add((
      method: 'end',
      endsAt: null,
      nextLabel: null,
      exerciseName: null,
      next: null,
      begin: null,
    ));
    await _finish(() {
      showingUntil = null;
      set = null;
    });
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
