import ActivityKit
import Flutter
import Foundation

/// The workout's Live Activity behind the `tracend/live_activity` channel
/// (`lib/shared/live_activity/workout_activity_bridge.dart`): the set in
/// progress, and the rest between sets.
///
/// The countdown runs on its own from the end time, and the card turns into
/// the set card by itself when the rest ends, so the app only starts, moves
/// and ends the activity; nothing is pushed. At most one activity shows: a
/// new rest or set moves the running one in place, or replaces every earlier
/// one. When the athlete turned Live Activities off, every call succeeds and
/// shows nothing. Calls run one after another in the order they arrive.
///
/// Its "Log set", Skip and +30s buttons are `LiveActivityIntent`s
/// (`ios/Shared/RestActivityIntents.swift`) that iOS runs in this process,
/// waking the app in the background; `press` hands each one to the open
/// workout in Dart and waits until the activity is updated. Each press is
/// stamped with its time here (`pressed_at_millis`); Dart drops one older
/// than `pressTimeout`, because by then the card already says "Open Tracend"
/// and applying it late would log the wrong time.
enum WorkoutActivityBridge {
  static let channelName = "tracend/live_activity"

  /// How long the card that says every set is logged keeps showing when a
  /// launch or a press finds it left from an earlier run of the app.
  static let doneLinger: TimeInterval = 120

  /// How long a card may go without the app moving it before it counts as
  /// left behind: a workout is at most three hours.
  static let abandonedAfter: TimeInterval = 4 * 60 * 60

  /// How long a press waits for the workout to answer.
  static let pressTimeout: TimeInterval = 8

  @MainActor private static var queue: Task<Void, Never>?
  @MainActor private static var channel: FlutterMethodChannel?

  /// A workout screen is open in Dart and takes the buttons.
  @MainActor private static var buttonsAttached = false

  /// Answers the channel, and first ends the activities left from an earlier
  /// launch that are over (`lingerEnd`). One that is still wanted stays for
  /// the app's restore to move or end.
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
        let next = NextSet(arguments)
        enqueue {
          result(
            await show(
              next.applied(
                to: RestActivityAttributes.ContentState(
                  endsAt: endsAt,
                  nextLabel: nextLabel,
                  exerciseName: exerciseName
                )
              ),
              request: true
            )
          )
        }
      case "updateRest":
        guard let endsAt = date(arguments["ends_at_millis"]) else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        let nextLabel = arguments["next_label"] as? String
        let next = NextSet(arguments)
        enqueue {
          result(await updateRest(endsAt: endsAt, nextLabel: nextLabel, next: next))
        }
      case "showSet":
        let next = NextSet(arguments)
        let request = arguments["begin"] as? Bool == true
        enqueue {
          result(
            await show(
              next.applied(
                to: RestActivityAttributes.ContentState(
                  endsAt: Date(),
                  nextLabel: "",
                  exerciseName: next.exerciseName
                )
              ),
              request: request
            )
          )
        }
      case "hideNumbers":
        enqueue {
          await hideNumbers()
          result(false)
        }
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
  /// open the app instead. A card the app left behind (`isOver`) is removed
  /// instead: ActivityKit has no timer of its own, so this is the first
  /// moment the app can.
  @MainActor
  static func press(_ button: RestActivityButton) async {
    let pressedAt = Date()
    if await endOver(now: pressedAt) { return }
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

  /// The set a call names, as `next_*` keys: `next_exercise_order`,
  /// `next_set_number`, `next_set_count`, `next_exercise_name`, `next_target`
  /// and `next_can_log`. Absent when the call names no set. Any key may be
  /// missing: the card then shows what it can.
  struct NextSet: Equatable {
    var present = false
    var exerciseOrder: Int?
    var setNumber: Int?
    var setCount: Int?
    var exerciseName = ""
    var target = ""
    var canLog = true

    init(_ arguments: [String: Any]) {
      let order = (arguments["next_exercise_order"] as? NSNumber)?.intValue
      let number = (arguments["next_set_number"] as? NSNumber)?.intValue
      guard order != nil || number != nil else { return }
      present = true
      exerciseOrder = order
      setNumber = number
      setCount = (arguments["next_set_count"] as? NSNumber)?.intValue
      exerciseName = arguments["next_exercise_name"] as? String ?? ""
      target = arguments["next_target"] as? String ?? ""
      canLog = arguments["next_can_log"] as? Bool ?? true
    }

    /// `state` with this set written into its `next*` fields. Without a set
    /// the fields are cleared when `clearing`, else left as they are.
    func applied(
      to state: RestActivityAttributes.ContentState,
      clearing: Bool = true
    ) -> RestActivityAttributes.ContentState {
      guard present || clearing else { return state }
      var state = state
      state.nextExerciseOrder = exerciseOrder
      state.nextSetNumber = setNumber
      state.nextSetCount = setCount
      state.nextExerciseName = exerciseName
      state.nextTarget = target
      state.nextCanLog = canLog
      return state
    }
  }

  /// The date after which the system marks `state` stale: the end of a
  /// running rest, which redraws the card as the set card. None once no rest
  /// is running.
  private static func staleDate(
    _ state: RestActivityAttributes.ContentState,
    now: Date = Date()
  ) -> Date? {
    state.endsAt > now ? state.endsAt : nil
  }

  /// Shows `state`. A running activity (a rest, or the set in progress) is
  /// moved in place, so a "Log set" tapped on the Lock Screen never needs a
  /// new request while the app is in the background; every other earlier one,
  /// an ended one included, is removed. Otherwise a new activity is requested,
  /// but only when `request` (the workout just opened, a set was logged, a
  /// rest began): a plain update must not bring back a card the athlete
  /// dismissed. Answers whether it shows: false when Live Activities are off
  /// or nothing was requested, a fixed error code when iOS refused the
  /// request.
  @MainActor
  private static func show(
    _ state: RestActivityAttributes.ContentState,
    request: Bool
  ) async -> Any {
    let running = all.first(where: isRunning)
    if request {
      for activity in all
      where activity.activityState != .dismissed && activity.id != running?.id {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
    if let running {
      await running.update(ActivityContent(state: state, staleDate: staleDate(state)))
      return true
    }
    guard request, ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
    do {
      _ = try Activity.request(
        attributes: RestActivityAttributes(),
        content: ActivityContent(state: state, staleDate: staleDate(state)),
        pushType: nil
      )
      return true
    } catch {
      return FlutterError(code: "request_failed", message: nil, details: nil)
    }
  }

  /// Moves the end of the running rest (±15 s, +30 s, Skip, or a rest
  /// resumed after a relaunch), and the set that follows it when given. An
  /// end in the past turns the card into the set card at once. Without a
  /// running activity it shows nothing: the athlete may have dismissed it.
  @MainActor
  private static func updateRest(
    endsAt: Date,
    nextLabel: String?,
    next: NextSet
  ) async -> Bool {
    guard let activity = all.first(where: isRunning) else { return false }
    var state = activity.content.state
    state.endsAt = endsAt
    state.needsApp = false
    if let nextLabel {
      state.nextLabel = nextLabel
    }
    state = next.applied(to: state, clearing: false)
    await activity.update(ActivityContent(state: state, staleDate: staleDate(state)))
    return true
  }

  /// A button was tapped with no workout open: the running activity swaps
  /// its buttons for "Open Tracend".
  @MainActor
  private static func showNeedsApp() async {
    guard let activity = all.first(where: isRunning) else { return }
    var state = activity.content.state
    state.needsApp = true
    await activity.update(ActivityContent(state: state, staleDate: staleDate(state)))
  }

  /// The athlete turned Lock Screen numbers off: the running card loses its
  /// target at once, and shows only the exercise and the set's position.
  @MainActor
  private static func hideNumbers() async {
    for activity in all where isRunning(activity) {
      var state = activity.content.state
      state.nextTarget = ""
      await activity.update(ActivityContent(state: state, staleDate: staleDate(state)))
    }
  }

  /// Ends every running activity at once: the workout closed, or the athlete
  /// signed out.
  @MainActor
  private static func endAll() async {
    for activity in all where isRunning(activity) {
      await activity.end(activity.content, dismissalPolicy: .immediate)
    }
  }

  /// When an activity left on the Lock Screen no longer says anything true,
  /// and must go: the card that says every set is logged, `doneLinger` after
  /// it appeared, or any card the app has not moved for `abandonedAfter`.
  static func lingerEnd(
    of state: RestActivityAttributes.ContentState,
    now: Date
  ) -> Date {
    switch state.phase(at: now) {
    case .finished: return state.endsAt.addingTimeInterval(doneLinger)
    case .set, .resting: return state.endsAt.addingTimeInterval(abandonedAfter)
    }
  }

  /// Ends, at once, every running activity that is over (`lingerEnd` has
  /// passed). True when it ended any.
  @MainActor
  private static func endOver(now: Date) async -> Bool {
    var ended = false
    for activity in all
    where isRunning(activity) && lingerEnd(of: activity.content.state, now: now) <= now {
      await activity.end(activity.content, dismissalPolicy: .immediate)
      ended = true
    }
    return ended
  }

  /// At launch, ends the running activities that are over, and lets the
  /// card that says every set is logged stay until `doneLinger` after it
  /// appeared. A card that is still wanted stays for the app's restore to
  /// move or end.
  @MainActor
  private static func endFinished() async {
    let now = Date()
    for activity in all where isRunning(activity) {
      let state = activity.content.state
      let until = lingerEnd(of: state, now: now)
      if until <= now {
        await activity.end(activity.content, dismissalPolicy: .immediate)
      } else if state.phase(at: now) == .finished {
        await activity.end(activity.content, dismissalPolicy: .after(until))
      }
    }
  }
}
