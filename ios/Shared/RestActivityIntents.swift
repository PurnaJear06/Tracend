import AppIntents
import Foundation

/// The rest Live Activity's buttons. Compiled into TracendWidgets, which
/// draws them with `Button(intent:)`, and into Runner: a `LiveActivityIntent`
/// runs in the app's process (iOS wakes the app in the background), where
/// `RestActivityButtons.handler` sends the press to the open workout. The
/// activity never changes the workout itself.
enum RestActivityButton: Equatable {
  case done
  case skip
  case addRest(seconds: Int)

  /// What "+30s" adds, in seconds.
  static let addRestSeconds = 30

  /// The `press` call's arguments on `tracend/live_activity`.
  var channelArguments: [String: Any] {
    switch self {
    case .done: return ["button": "done"]
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

/// "Done set": ticks the set the activity names, with the kg and reps the
/// app suggests.
struct CompleteSetIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Done set"
  static let description = IntentDescription("Logs the set Tracend's rest card names.")
  static let isDiscoverable = false

  func perform() async throws -> some IntentResult {
    await RestActivityButtons.press(.done)
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
