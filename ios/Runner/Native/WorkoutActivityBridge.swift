import ActivityKit
import Flutter
import Foundation

/// The rest-timer Live Activity behind the `tracend/live_activity` channel
/// (`lib/shared/live_activity/workout_activity_bridge.dart`).
///
/// The countdown runs on its own from the end time, so the app only starts,
/// moves and ends the activity; nothing is pushed. At most one rest activity
/// shows: starting one removes every earlier one. When the athlete turned
/// Live Activities off, every call succeeds and shows nothing. Calls run one
/// after another in the order they arrive.
enum WorkoutActivityBridge {
  static let channelName = "tracend/live_activity"

  /// How long a rest that ran to its end keeps showing "Rest done" after the
  /// end. A rest ended early (skip, finish, leave) goes at once.
  static let doneLinger: TimeInterval = 120

  @MainActor private static var queue: Task<Void, Never>?

  /// Answers the channel, and first ends the rest activities left from an
  /// earlier launch whose rest is over. A running one stays for the app's
  /// restore to move or end.
  static func register(on messenger: FlutterBinaryMessenger) {
    enqueue { await endFinished() }
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "startRest":
        guard
          let endsAt = date(arguments["ends_at_millis"]),
          let nextLabel = arguments["next_label"] as? String,
          let exerciseName = arguments["exercise_name"] as? String
        else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        enqueue {
          result(
            await startRest(
              RestActivityAttributes.ContentState(
                endsAt: endsAt,
                nextLabel: nextLabel,
                exerciseName: exerciseName
              )
            )
          )
        }
      case "updateRest":
        guard let endsAt = date(arguments["ends_at_millis"]) else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        let nextLabel = arguments["next_label"] as? String
        enqueue { result(await updateRest(endsAt: endsAt, nextLabel: nextLabel)) }
      case "end":
        enqueue {
          await endAll()
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Runs `work` after every earlier call has finished. Flutter delivers
  /// method calls on the main thread, so the queue is extended in arrival
  /// order.
  private static func enqueue(_ work: @escaping @MainActor () async -> Void) {
    MainActor.assumeIsolated {
      let previous = queue
      queue = Task { @MainActor in
        await previous?.value
        await work()
      }
    }
  }

  private static func date(_ value: Any?) -> Date? {
    guard let millis = value as? NSNumber else { return nil }
    return Date(timeIntervalSince1970: millis.doubleValue / 1000)
  }

  private static var all: [Activity<RestActivityAttributes>] {
    Activity<RestActivityAttributes>.activities
  }

  private static func isRunning(_ activity: Activity<RestActivityAttributes>) -> Bool {
    activity.activityState == .active || activity.activityState == .stale
  }

  /// Removes every earlier rest activity, including an ended one still
  /// showing "Rest done", then requests the new one. Answers whether it
  /// shows: false when Live Activities are off, a fixed error code when iOS
  /// refused the request.
  @MainActor
  private static func startRest(_ state: RestActivityAttributes.ContentState) async -> Any {
    for activity in all where activity.activityState != .dismissed {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
    do {
      _ = try Activity.request(
        attributes: RestActivityAttributes(),
        content: ActivityContent(state: state, staleDate: state.endsAt),
        pushType: nil
      )
      return true
    } catch {
      return FlutterError(code: "request_failed", message: nil, details: nil)
    }
  }

  /// Moves the end of the running rest (the ±15 s buttons, or a rest resumed
  /// after a relaunch). Without a running rest activity it shows nothing:
  /// the athlete may have dismissed it.
  @MainActor
  private static func updateRest(endsAt: Date, nextLabel: String?) async -> Bool {
    guard let activity = all.first(where: isRunning) else { return false }
    var state = activity.content.state
    state.endsAt = endsAt
    if let nextLabel {
      state.nextLabel = nextLabel
    }
    await activity.update(ActivityContent(state: state, staleDate: endsAt))
    return true
  }

  /// Ends every running rest activity. One that ran to its end stays as
  /// "Rest done" until `doneLinger` after its end; one ended early goes at
  /// once.
  @MainActor
  private static func endAll() async {
    let now = Date()
    for activity in all where isRunning(activity) {
      await end(activity, finished: activity.content.state.endsAt <= now)
    }
  }

  /// Ends the running rest activities whose rest is over, as `endAll` would.
  @MainActor
  private static func endFinished() async {
    let now = Date()
    for activity in all where isRunning(activity) && activity.content.state.endsAt <= now {
      await end(activity, finished: true)
    }
  }

  @MainActor
  private static func end(_ activity: Activity<RestActivityAttributes>, finished: Bool) async {
    let state = activity.content.state
    let lingerUntil = state.endsAt.addingTimeInterval(doneLinger)
    let policy: ActivityUIDismissalPolicy =
      finished && lingerUntil > Date() ? .after(lingerUntil) : .immediate
    await activity.end(
      ActivityContent(state: state, staleDate: state.endsAt),
      dismissalPolicy: policy
    )
  }
}
