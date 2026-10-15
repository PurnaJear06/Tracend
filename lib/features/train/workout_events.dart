/// What happens during an active workout, as events, and what the Live
/// Activity may ask of it, as commands (coaching platform Contract 3).
///
/// The logging screen is the only writer of sets. Listeners (the Live
/// Activity, the heart-rate reader) read [WorkoutEventHub.events] and never
/// write sets; the Live Activity's buttons arrive as [WorkoutCommand]s.
library;

import 'dart:async';

/// Something that happened in the active workout. [at] is when it happened,
/// which can be earlier than the moment the event is published: a set's
/// start is known only once the athlete touches or ticks it.
sealed class WorkoutEvent {
  const WorkoutEvent({required this.at});

  final DateTime at;
}

/// A set began: the rest before it ended, or the athlete first edited it.
/// It is never withdrawn: when the phone's clock moved back so that the
/// tick comes before this start, the set is stored with no start. Listeners
/// that need a set's window read the stored times.
final class SetStarted extends WorkoutEvent {
  const SetStarted({
    required super.at,
    required this.exerciseOrder,
    required this.setNumber,
  });

  final int exerciseOrder;
  final int setNumber;
}

/// A set was ticked, with what was logged at that moment.
final class SetCompleted extends WorkoutEvent {
  const SetCompleted({
    required super.at,
    required this.exerciseOrder,
    required this.setNumber,
    this.reps,
    this.loadKg,
    this.rir,
  });

  final int exerciseOrder;
  final int setNumber;
  final int? reps;
  final double? loadKg;

  /// Reps in reserve, 0 to 5 (5 means 5 or more); usually picked later.
  final int? rir;
}

/// A rest of [seconds] began; it ends at [endsAt], then [nextLabel] follows
/// ("Set 2 of Bench press" or the next exercise's name).
final class RestStarted extends WorkoutEvent {
  const RestStarted({
    required super.at,
    required this.seconds,
    required this.endsAt,
    required this.nextLabel,
  });

  final int seconds;
  final DateTime endsAt;
  final String nextLabel;
}

/// The running rest now ends at [endsAt]: ±15 s, +30 s from the Live
/// Activity, or Skip (then [endsAt] is the moment of the skip).
final class RestAdjusted extends WorkoutEvent {
  const RestAdjusted({required super.at, required this.endsAt});

  final DateTime endsAt;
}

/// The exercise on screen changed.
final class ExerciseAdvanced extends WorkoutEvent {
  const ExerciseAdvanced({
    required super.at,
    required this.exerciseOrder,
    required this.name,
  });

  final int exerciseOrder;
  final String name;
}

/// The workout closed: finished ([completed]), or discarded or left.
final class WorkoutEnded extends WorkoutEvent {
  const WorkoutEnded({required super.at, required this.completed});

  final bool completed;
}

/// A request to the active workout from outside the logging screen.
sealed class WorkoutCommand {
  const WorkoutCommand();
}

/// Ticks the current set with the kg and reps the screen suggests.
final class CompleteCurrentSet extends WorkoutCommand {
  const CompleteCurrentSet();
}

/// Ends the running rest now.
final class SkipRest extends WorkoutCommand {
  const SkipRest();
}

/// Adds [seconds] to the running rest (+30 from the Live Activity).
final class AddRest extends WorkoutCommand {
  const AddRest(this.seconds);

  final int seconds;
}

/// One event stream and one command sink per active workout.
class WorkoutEventHub {
  final StreamController<WorkoutEvent> _events =
      StreamController<WorkoutEvent>.broadcast();
  final StreamController<WorkoutCommand> _commands =
      StreamController<WorkoutCommand>();

  /// Events in the order they happened in the workout.
  Stream<WorkoutEvent> get events => _events.stream;

  /// Where the Live Activity sends its buttons. A command sent after the
  /// workout closed is dropped.
  late final Sink<WorkoutCommand> commands = _CommandSink(_commands);

  /// The commands, for the logging screen only (single subscription).
  Stream<WorkoutCommand> get incomingCommands => _commands.stream;

  /// Publishes [event]; nothing after [close].
  void emit(WorkoutEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// Ends both streams; the logging screen calls it when it goes away.
  void close() {
    unawaited(_commands.close());
    unawaited(_events.close());
  }
}

class _CommandSink implements Sink<WorkoutCommand> {
  _CommandSink(this._controller);

  final StreamController<WorkoutCommand> _controller;

  @override
  void add(WorkoutCommand data) {
    if (!_controller.isClosed) _controller.add(data);
  }

  /// The hub closes the stream; a sender cannot.
  @override
  void close() {}
}
