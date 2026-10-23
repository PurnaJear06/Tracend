import ActivityKit
import Foundation

/// The workout on the Lock Screen and in the Dynamic Island: the rest between
/// two sets, and the set in progress. Compiled into Runner, which starts,
/// moves and ends it (`WorkoutActivityBridge`), and into TracendWidgets,
/// which draws it. (The name is from when it showed only the rest.)
///
/// What travels is bounded by SECURITY_PRIVACY.md §10: the exercise name, the
/// set's position (order, number, how many) and the labels; never effort,
/// heart rate or any other health value. The set's target ("82.5 kg × 8") is
/// in `nextTarget` only while the athlete chose Lock Screen numbers; it is
/// empty otherwise. The countdown is drawn from `endsAt` with
/// `Text(timerInterval:)`, so it keeps running with the app closed, and the
/// card turns into the set card on its own when `endsAt` passes.
struct RestActivityAttributes: ActivityAttributes {
  /// What the card is showing.
  enum Phase: Equatable {
    /// A rest is counting down to `endsAt`.
    case resting
    /// No rest is running and a set is next: "Log set" names it.
    case set
    /// No rest is running and no set is left.
    case finished
  }

  struct ContentState: Codable, Hashable {
    /// When the rest ends. A time that has passed (or a stale card) means no
    /// rest is running: the card shows the set in progress, or that every set
    /// is logged. It is also the content's stale date while a rest runs.
    var endsAt: Date

    /// What follows the rest, for example "Set 3 of Bench press". Empty when
    /// the app did not say.
    var nextLabel: String

    /// The exercise the rest belongs to. Empty when the app did not say.
    var exerciseName: String

    /// The set "Log set" logs: the exercise's order and the set's number in
    /// the workout (1-based). The button carries them back so the app logs
    /// that set only if it is still the current one; without them the card
    /// has no button.
    var nextExerciseOrder: Int?
    var nextSetNumber: Int?

    /// How many sets that exercise has, and its name. The name is empty when
    /// the app did not say; the card then falls back to `exerciseName`.
    var nextSetCount: Int?
    var nextExerciseName: String

    /// The kg and reps "Log set" logs, as the app shows them ("82.5 kg × 8").
    /// Empty when the athlete keeps Lock Screen numbers off.
    var nextTarget: String

    /// The app can log the set as shown (it has reps for it). When false the
    /// card offers "Open" only.
    var nextCanLog: Bool

    /// A button was tapped while no workout was open in the app (it had been
    /// closed): the buttons give way to "Open Tracend" until the app moves or
    /// replaces the card.
    var needsApp: Bool

    init(
      endsAt: Date,
      nextLabel: String,
      exerciseName: String,
      nextExerciseOrder: Int? = nil,
      nextSetNumber: Int? = nil,
      nextSetCount: Int? = nil,
      nextExerciseName: String = "",
      nextTarget: String = "",
      nextCanLog: Bool = true,
      needsApp: Bool = false
    ) {
      self.endsAt = endsAt
      self.nextLabel = nextLabel
      self.exerciseName = exerciseName
      self.nextExerciseOrder = nextExerciseOrder
      self.nextSetNumber = nextSetNumber
      self.nextSetCount = nextSetCount
      self.nextExerciseName = nextExerciseName
      self.nextTarget = nextTarget
      self.nextCanLog = nextCanLog
      self.needsApp = needsApp
    }

    private enum CodingKeys: String, CodingKey {
      case endsAt, nextLabel, exerciseName, nextExerciseOrder, nextSetNumber
      case nextSetCount, nextExerciseName, nextTarget, nextCanLog, needsApp
    }

    /// A state stored by an earlier build lacks the newer keys.
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      endsAt = try container.decode(Date.self, forKey: .endsAt)
      nextLabel = try container.decode(String.self, forKey: .nextLabel)
      exerciseName = try container.decode(String.self, forKey: .exerciseName)
      nextExerciseOrder = try container.decodeIfPresent(Int.self, forKey: .nextExerciseOrder)
      nextSetNumber = try container.decodeIfPresent(Int.self, forKey: .nextSetNumber)
      nextSetCount = try container.decodeIfPresent(Int.self, forKey: .nextSetCount)
      nextExerciseName =
        try container.decodeIfPresent(String.self, forKey: .nextExerciseName) ?? ""
      nextTarget = try container.decodeIfPresent(String.self, forKey: .nextTarget) ?? ""
      nextCanLog = try container.decodeIfPresent(Bool.self, forKey: .nextCanLog) ?? true
      needsApp = try container.decodeIfPresent(Bool.self, forKey: .needsApp) ?? false
    }

    /// The set the card names, when the app said which.
    var nextSet: (exerciseOrder: Int, setNumber: Int)? {
      guard let order = nextExerciseOrder, let number = nextSetNumber else { return nil }
      return (order, number)
    }

    /// What the card shows at `now`. A stale card counts as a rest that is
    /// over: the system marks it stale at `endsAt`, which redraws the views.
    func phase(at now: Date, isStale: Bool = false) -> Phase {
      if !isStale && endsAt > now { return .resting }
      return nextSet == nil ? .finished : .set
    }

    /// The exercise of the set in progress.
    var setTitle: String {
      if !nextExerciseName.isEmpty { return nextExerciseName }
      return exerciseName.isEmpty ? "Next set" : exerciseName
    }

    /// "Set 2 of 4", or "Set 2" when the app did not say how many.
    var setPosition: String {
      guard let number = nextSetNumber else { return "Next set" }
      guard let count = nextSetCount else { return "Set \(number)" }
      return "Set \(number) of \(count)"
    }
  }
}
