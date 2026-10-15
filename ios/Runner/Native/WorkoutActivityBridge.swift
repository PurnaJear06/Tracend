import ActivityKit
import Flutter
import Foundation

/// The rest-timer Live Activity behind the `tracend/live_activity` channel
/// (`lib/shared/live_activity/workout_activity_bridge.dart`).
///
/// The countdown runs on its own from the end time, so the app only starts,
/// moves and ends the activity; nothing is pushed. At most one rest activity
/// shows: a new rest moves the running one in place, or replaces every
/// earlier one. When the athlete turned Live Activities off, every call
/// succeeds and shows nothing. Calls run one after another in the order they
/// arrive.
///
/// Its Done, Skip and +30s buttons are `LiveActivityIntent`s
/// (`ios/Shared/RestActivityIntents.swift`) that iOS runs in this process,
/// waking the app in the background; `press` hands each one to the open
/// workout in Dart and waits until the activity is updated. Each press is
/// stamped with its time here (`pressed_at_millis`); Dart drops one older
/// than `pressTimeout`, because by then the card already says "Open Tracend
/// to continue" and applying it late would log the wrong time.
enum WorkoutActivityBridge {
  static let channelName = "tracend/live_activity"

  /// How long a rest that ran out keeps showing "Rest done" when a launch
  /// finds it left from an earlier run of the app.
  static let doneLinger: TimeInterval = 120

  /// How long a press waits for the workout to answer.
  static let pressTimeout: TimeInterval = 8

  @MainActor private static var queue: Task<Void, Never>?
  @MainActor private static var channel: FlutterMethodChannel?

  /// A workout screen is open in Dart and takes the buttons.
  @MainActor private static var buttonsAttached = false

  /// Answers the channel, and first ends the rest activities left from an
  /// earlier launch whose rest is over. A running one stays for the app's
  /// restore to move or end.
  static func register(on messenger: FlutterBinaryMessenger) {
    enqueue { await endFinished() }
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    MainActor.assumeIsolated {
      Self.channel = channel
      buttonsAttached = false
    }
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
        let nextExerciseOrder = (arguments["next_exercise_order"] as? NSNumber)?.intValue
        let nextSetNumber = (arguments["next_set_number"] as? NSNumber)?.intValue
        enqueue {
          result(
            await startRest(
              RestActivityAttributes.ContentState(
                endsAt: endsAt,
                nextLabel: nextLabel,
                exerciseName: exerciseName,
                nextExerciseOrder: nextExerciseOrder,
                nextSetNumber: nextSetNumber
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
      case "attachButtons", "detachButtons":
        let attached = call.method == "attachButtons"
        MainActor.assumeIsolated { buttonsAttached = attached }
        enqueue { result(all.contains(where: isRunning)) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// A button on the activity, from its intent. The open workout acts on it
  /// and drives the activity through the calls above; this waits until those
  /// calls are done, so iOS does not suspend the app halfway. With no
  /// workout open (the app was closed), the activity asks the athlete to
  /// open the app instead. A card left on the Lock Screen past its "Rest
  /// done" time (`doneLinger`) is removed instead: ActivityKit has no timer
  /// of its own, so this is the first moment the app can.
  @MainActor
  static func press(_ button: RestActivityButton) async {
    let pressedAt = Date()
    if await endLingered(now: pressedAt) { return }
    var taken = false
    if buttonsAttached, let channel {
      taken = await send(button, pressedAt: pressedAt, on: channel)
    }
    if !taken {
      enqueue { await showNeedsApp() }
    }
    await drain()
  }

  /// Sends `press` to Dart, stamped with `pressedAt`. True once the workout
  /// answered that it handled it (acted, or ignored it as out of date);
  /// false on any other answer or after `pressTimeout`.
  @MainActor
  private static func send(
    _ button: RestActivityButton,
    pressedAt: Date,
    on channel: FlutterMethodChannel
  ) async -> Bool {
    var arguments = button.channelArguments
    arguments["pressed_at_millis"] = Int((pressedAt.timeIntervalSince1970 * 1000).rounded())
    return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      var answered = false
      let finish: (Bool) -> Void = { taken in
        guard !answered else { return }
        answered = true
        continuation.resume(returning: taken)
      }
      channel.invokeMethod("press", arguments: arguments) { reply in
        finish(reply as? Bool == true)
      }
      let wait = max(0, pressedAt.addingTimeInterval(pressTimeout).timeIntervalSinceNow)
      DispatchQueue.main.asyncAfter(deadline: .now() + wait) { finish(false) }
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

  /// Waits until every queued call, including ones queued meanwhile, is done.
  @MainActor
  private static func drain() async {
    while let current = queue {
      await current.value
      if queue == current { return }
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

  /// Shows a new rest. A running activity (counting down, or "Rest done"
  /// after the last rest) is moved in place, so a Done tapped on the Lock
  /// Screen never needs a new request while the app is in the background;
  /// every other earlier one, an ended one included, is removed. Otherwise a
  /// new activity is requested. Answers whether it shows: false when Live
  /// Activities are off, a fixed error code when iOS refused the request.
  @MainActor
  private static func startRest(_ state: RestActivityAttributes.ContentState) async -> Any {
    let running = all.first(where: isRunning)
    for activity in all
    where activity.activityState != .dismissed && activity.id != running?.id {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    if let running {
      await running.update(ActivityContent(state: state, staleDate: state.endsAt))
      return true
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

  /// Moves the end of the running rest (±15 s, +30 s, Skip, or a rest
  /// resumed after a relaunch). An end in the past makes it read "Rest done"
  /// at once. Without a running rest activity it shows nothing: the athlete
  /// may have dismissed it.
  @MainActor
  private static func updateRest(endsAt: Date, nextLabel: String?) async -> Bool {
    guard let activity = all.first(where: isRunning) else { return false }
    var state = activity.content.state
    state.endsAt = endsAt
    state.needsApp = false
    if let nextLabel {
      state.nextLabel = nextLabel
    }
    await activity.update(ActivityContent(state: state, staleDate: endsAt))
    return true
  }

  /// A button was tapped with no workout open: the running activity swaps
  /// its buttons for "Open Tracend to continue".
  @MainActor
  private static func showNeedsApp() async {
    guard let activity = all.first(where: isRunning) else { return }
    var state = activity.content.state
    state.needsApp = true
    await activity.update(ActivityContent(state: state, staleDate: state.endsAt))
  }

  /// Ends every running rest activity at once: the workout closed, the
  /// "Rest done" time passed, or the athlete signed out.
  @MainActor
  private static func endAll() async {
    for activity in all where isRunning(activity) {
      await activity.end(activity.content, dismissalPolicy: .immediate)
    }
  }

  /// Ends, at once, every running rest activity whose "Rest done" time has
  /// run past `doneLinger`. True when it ended any.
  @MainActor
  private static func endLingered(now: Date) async -> Bool {
    var ended = false
    for activity in all
    where isRunning(activity)
      && activity.content.state.endsAt.addingTimeInterval(doneLinger) <= now {
      await activity.end(activity.content, dismissalPolicy: .immediate)
      ended = true
    }
    return ended
  }

  /// Ends the running rest activities left from an earlier launch whose rest
  /// is over: "Rest done" stays until `doneLinger` after the end.
  @MainActor
  private static func endFinished() async {
    let now = Date()
    for activity in all where isRunning(activity) && activity.content.state.endsAt <= now {
      let lingerUntil = activity.content.state.endsAt.addingTimeInterval(doneLinger)
      await activity.end(
        activity.content,
        dismissalPolicy: lingerUntil > now ? .after(lingerUntil) : .immediate
      )
    }
  }
}
