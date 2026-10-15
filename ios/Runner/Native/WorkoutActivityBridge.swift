import ActivityKit
import Flutter
import Foundation

/// The rest-timer Live Activity behind the `tracend/live_activity` channel
/// (`lib/shared/live_activity/workout_activity_bridge.dart`).
///
/// The countdown runs on its own from the end time, so the app only starts,
/// moves and ends the activity; nothing is pushed. At most one rest activity
/// exists: starting one ends any earlier one. When the athlete turned Live
/// Activities off, every call succeeds and shows nothing. Calls run one after
/// another in the order they arrive.
enum WorkoutActivityBridge {
  static let channelName = "tracend/live_activity"

  /// How long a rest that ran to its end keeps showing "Rest done" after the
  /// end. A rest ended early (skip, finish, leave) goes at once.
  static let doneLinger: TimeInterval = 120

  @MainActor private static var queue: Task<Void, Never>?

  static func register(on messenger: FlutterBinaryMessenger) {
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
        let workoutTitle = arguments["workout_title"] as? String ?? ""
        enqueue(result) {
          await startRest(
            RestActivityAttributes.ContentState(
              endsAt: endsAt,
              nextLabel: nextLabel,
              exerciseName: exerciseName
            ),
            workoutTitle: workoutTitle
          )
        }
      case "updateRest":
        guard let endsAt = date(arguments["ends_at_millis"]) else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        let nextLabel = arguments["next_label"] as? String
        enqueue(result) { await updateRest(endsAt: endsAt, nextLabel: nextLabel) }
      case "end":
        enqueue(result) { await endAll() }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Runs `work` after every earlier call has finished and answers Dart on
  /// the main thread with its result: whether a rest activity is showing.
  /// Flutter delivers method calls on the main thread, so the queue is
  /// extended in arrival order.
  private static func enqueue(
    _ result: @escaping FlutterResult,
    _ work: @escaping @MainActor () async -> Bool
  ) {
    MainActor.assumeIsolated {
      let previous = queue
      queue = Task { @MainActor in
        await previous?.value
        result(await work())
      }
    }
  }

  private static func date(_ value: Any?) -> Date? {
    guard let millis = value as? NSNumber else { return nil }
    return Date(timeIntervalSince1970: millis.doubleValue / 1000)
  }

  private static var running: [Activity<RestActivityAttributes>] {
    Activity<RestActivityAttributes>.activities.filter {
      $0.activityState == .active || $0.activityState == .stale
    }
  }

  @MainActor
  private static func startRest(
    _ state: RestActivityAttributes.ContentState,
    workoutTitle: String
  ) async -> Bool {
    _ = await endAll()
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
    do {
      _ = try Activity.request(
        attributes: RestActivityAttributes(workoutTitle: workoutTitle),
        content: ActivityContent(state: state, staleDate: state.endsAt),
        pushType: nil
      )
      return true
    } catch {
      return false
    }
  }

  /// Moves the end of the running rest (the ±15 s buttons, or a rest resumed
  /// after a relaunch). Without a running rest activity it shows nothing:
  /// the athlete may have dismissed it.
  @MainActor
  private static func updateRest(endsAt: Date, nextLabel: String?) async -> Bool {
    guard let activity = running.first else { return false }
    var state = activity.content.state
    state.endsAt = endsAt
    if let nextLabel {
      state.nextLabel = nextLabel
    }
    await activity.update(ActivityContent(state: state, staleDate: endsAt))
    return true
  }

  /// Ends every rest activity. One that ran to its end stays as "Rest done"
  /// until `doneLinger` after its end; one ended early goes at once.
  @MainActor
  private static func endAll() async -> Bool {
    let now = Date()
    for activity in running {
      let state = activity.content.state
      let policy: ActivityUIDismissalPolicy =
        state.endsAt <= now
        ? .after(state.endsAt.addingTimeInterval(doneLinger))
        : .immediate
      await activity.end(
        ActivityContent(state: state, staleDate: state.endsAt),
        dismissalPolicy: policy
      )
    }
    return false
  }
}
