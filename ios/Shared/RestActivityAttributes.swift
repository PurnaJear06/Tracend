import ActivityKit
import Foundation

/// The rest between two sets as a Live Activity on the Lock Screen and in the
/// Dynamic Island. Compiled into Runner, which starts, moves and ends it
/// (`WorkoutActivityBridge`), and into TracendWidgets, which draws it.
///
/// Only the end time, the exercise name and the next-set label travel; never
/// a load, reps, effort, heart rate or any other health value
/// (SECURITY_PRIVACY.md §10). The countdown is drawn from `endsAt` with
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

    /// A button was tapped while no workout was open in the app (it had been
    /// closed): the buttons give way to "Open Tracend to continue" until the
    /// app moves or replaces the rest.
    var needsApp: Bool

    init(endsAt: Date, nextLabel: String, exerciseName: String, needsApp: Bool = false) {
      self.endsAt = endsAt
      self.nextLabel = nextLabel
      self.exerciseName = exerciseName
      self.needsApp = needsApp
    }

    private enum CodingKeys: String, CodingKey {
      case endsAt, nextLabel, exerciseName, needsApp
    }

    /// A state stored by an earlier build has no `needsApp`.
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      endsAt = try container.decode(Date.self, forKey: .endsAt)
      nextLabel = try container.decode(String.self, forKey: .nextLabel)
      exerciseName = try container.decode(String.self, forKey: .exerciseName)
      needsApp = try container.decodeIfPresent(Bool.self, forKey: .needsApp) ?? false
    }
  }
}
