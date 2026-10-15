import ActivityKit
import Foundation

/// The rest between two sets as a Live Activity on the Lock Screen and in the
/// Dynamic Island. Compiled into Runner, which starts, moves and ends it
/// (`WorkoutActivityBridge`), and into TracendWidgets, which draws it.
///
/// Only the end time and two labels travel: never a load, reps, effort, heart
/// rate or any other health value. The countdown is drawn from `endsAt` with
/// `Text(timerInterval:)`, so it keeps running with the app closed.
struct RestActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    /// When the rest ends. It is also the content's stale date, so the
    /// activity reads "Rest done" once it passes.
    var endsAt: Date

    /// What follows the rest, for example "Set 3 of Bench press". Empty when
    /// the app did not say.
    var nextLabel: String

    /// The exercise the rest belongs to. Empty when the app did not say.
    var exerciseName: String
  }

  /// The workout's name, fixed for the activity's life. Empty when the app
  /// did not say.
  var workoutTitle: String
}
