import AppIntents
import Foundation

/// The workout Live Activity's buttons. Compiled into TracendWidgets, which
/// draws them with `Button(intent:)`, and into Runner: a `LiveActivityIntent`
/// runs in the app's process (iOS wakes the app in the background), where
/// `RestActivityButtons.handler` sends the press to the open workout. The
/// activity never changes the workout itself.
enum RestActivityButton: Equatable {
  /// "Log set" for the set the card named: exercise order and set number.
  case done(exerciseOrder: Int, setNumber: Int)
  case skip
  case addRest(seconds: Int)

  /// What "+30s" adds, in seconds.
  static let addRestSeconds = 30

  /// The `press` call's arguments on `tracend/live_activity`, without the
  /// press time, which the bridge stamps (`pressed_at_millis`).
  var channelArguments: [String: Any] {
    switch self {
    case .done(let exerciseOrder, let setNumber):
      return ["button": "done", "exercise_order": exerciseOrder, "set_number": setNumber]
    case .skip: return ["button": "skip"]
    case .addRest(let seconds): return ["button": "add_rest", "seconds": seconds]
    }
  }
}

/// Where the app's process takes a press. Runner's `AppDelegate` sets it at
/// launch; it stays nil in the widget extension, which never runs an intent.
@MainActor
enum RestActivityButtons {
  static var handler: ((RestActivityButton) async -> Void)?

  static func press(_ button: RestActivityButton) async {
    await handler?(button)
  }
}

/// "Log set": ticks the set the activity names, with the kg and reps the
/// app pre-fills for it (the ones the card shows), but only if the app still
/// has that set as the current one. The card builds the intent with the set it
/// shows, so a stale or repeated press names a set the app no longer expects
/// and ticks nothing.
struct CompleteSetIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Log set"
  static let description = IntentDescription("Logs the set Tracend's workout card names.")
  static let isDiscoverable = false

  @Parameter(title: "Exercise order")
  var exerciseOrder: Int

  @Parameter(title: "Set number")
  var setNumber: Int

  init() {}

  init(exerciseOrder: Int, setNumber: Int) {
    self.exerciseOrder = exerciseOrder
    self.setNumber = setNumber
  }

  func perform() async throws -> some IntentResult {
    await RestActivityButtons.press(.done(exerciseOrder: exerciseOrder, setNumber: setNumber))
    return .result()
  }
}

/// "Skip": ends the rest now.
struct SkipRestIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Skip rest"
  static let description = IntentDescription("Ends the running rest.")
  static let isDiscoverable = false

  func perform() async throws -> some IntentResult {
    await RestActivityButtons.press(.skip)
    return .result()
  }
}

/// "+30s": the rest runs 30 seconds longer.
struct AddRestIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Add 30 seconds"
  static let description = IntentDescription("Adds 30 seconds to the running rest.")
  static let isDiscoverable = false

  func perform() async throws -> some IntentResult {
    await RestActivityButtons.press(.addRest(seconds: RestActivityButton.addRestSeconds))
    return .result()
  }
}
