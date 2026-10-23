import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The workout on the Lock Screen and in the Dynamic Island. While a set is in
/// progress it shows the exercise, the set's position, the target when the
/// athlete allows numbers on the Lock Screen, and "Log set". Between sets it
/// shows the rest: the countdown is `Text(timerInterval:)`, which the system
/// runs from the end time with the app closed, and once the end passes the
/// content is stale and every presentation turns into the next set. After the
/// last set it says every set is logged. The Lock Screen and the expanded
/// Dynamic Island carry the buttons: +30s and Skip while the rest runs, "Log
/// set" and "Open" while a set is in progress.
struct RestLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RestActivityAttributes.self) { context in
      RestLockScreenView(rest: RestPresentation(context))
        .activityBackgroundTint(TracendStyle.graphite)
        .activitySystemActionForegroundColor(TracendStyle.textPrimary)
        .widgetURL(TracendLink.workout.url)
    } dynamicIsland: { context in
      let rest = RestPresentation(context)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          RestStatusLabel(rest: rest)
            .font(.system(size: 15, weight: .semibold))
            .padding(.leading, 6)
            .padding(.top, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          RestTrailing(rest: rest, size: rest.phase == .set ? 22 : 34, doneSymbolSize: 28)
            .frame(maxWidth: 112, alignment: .trailing)
            .padding(.trailing, 6)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 10) {
            RestLabels(rest: rest, titleSize: 17, detailSize: 15)
            RestActions(rest: rest, height: 40)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 6)
        }
      } compactLeading: {
        Image(systemName: rest.compactSymbol)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(TracendStyle.lime)
          .accessibilityLabel(rest.status)
      } compactTrailing: {
        RestCompactTrailing(rest: rest)
          .frame(maxWidth: 48)
      } minimal: {
        RestMinimal(rest: rest)
          .minimumScaleFactor(0.7)
          .frame(maxWidth: 36)
      }
      .widgetURL(TracendLink.workout.url)
      .keylineTint(TracendStyle.lime)
    }
  }
}

/// What every presentation shows, with the fallbacks for labels the app did
/// not send.
struct RestPresentation {
  let state: RestActivityAttributes.ContentState
  let phase: RestActivityAttributes.Phase

  init(_ context: ActivityViewContext<RestActivityAttributes>) {
    state = context.state
    phase = context.state.phase(at: .now, isStale: context.isStale)
  }

  var endsAt: Date { state.endsAt }
  var needsApp: Bool { state.needsApp }

  /// The set "Log set" names; nil when the app did not say.
  var nextSet: (exerciseOrder: Int, setNumber: Int)? { state.nextSet }

  /// Whether the card can log the set as shown.
  var canLog: Bool { nextSet != nil && state.nextCanLog }

  /// The exercise: the one resting, the one whose set is next, or the finish.
  var title: String {
    switch phase {
    case .resting: return state.exerciseName.isEmpty ? "Between sets" : state.exerciseName
    case .set: return state.setTitle
    case .finished: return "Finish in Tracend"
    }
  }

  /// The words beside the glyph: "Rest", "Set 2 of 4" or "All sets logged".
  var status: String {
    switch phase {
    case .resting: return "Rest"
    case .set: return state.setPosition
    case .finished: return "All sets logged"
    }
  }

  var statusSymbol: String {
    switch phase {
    case .resting: return "timer"
    case .set: return "figure.strengthtraining.traditional"
    case .finished: return "checkmark.circle.fill"
    }
  }

  /// The Dynamic Island's compact glyph.
  var compactSymbol: String {
    switch phase {
    case .resting: return "timer"
    case .set: return "figure.strengthtraining.traditional"
    case .finished: return "checkmark"
    }
  }

  /// The second line: what follows the rest, or nothing.
  var detail: String? {
    switch phase {
    case .resting: return state.nextLabel.isEmpty ? nil : "Next: \(state.nextLabel)"
    case .set, .finished: return nil
    }
  }

  /// The kg and reps, when the athlete allows numbers on the Lock Screen.
  var target: String? {
    phase == .set && !state.nextTarget.isEmpty ? state.nextTarget : nil
  }

  /// "2/4", or "2" when the app did not say how many sets there are.
  var compactSet: String {
    guard let number = state.nextSetNumber else { return "" }
    guard let count = state.nextSetCount else { return "\(number)" }
    return "\(number)/\(count)"
  }

  /// What a screen reader says for the "Log set" button.
  var logAccessibilityLabel: String {
    let base = "Log set, \(state.setPosition), \(state.setTitle)"
    return target.map { "\(base), \($0)" } ?? base
  }
}

/// The Lock Screen and banner card: the status, exercise and detail on the
/// left, the big lime countdown or target on the right, the buttons
/// underneath.
struct RestLockScreenView: View {
  let rest: RestPresentation

  var body: some View {
    VStack(spacing: 12) {
      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          RestStatusLabel(rest: rest)
            .font(.system(size: 13, weight: .semibold))
          RestLabels(rest: rest, titleSize: 20, detailSize: 15)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        RestTrailing(rest: rest, size: rest.phase == .set ? 28 : 44, doneSymbolSize: 34)
          .frame(maxWidth: rest.phase == .set ? 170 : 132, alignment: .trailing)
      }
      RestActions(rest: rest, height: 44)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }
}

/// The lime glyph and the status.
struct RestStatusLabel: View {
  let rest: RestPresentation

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: rest.statusSymbol)
        .foregroundStyle(TracendStyle.lime)
        .accessibilityHidden(true)
      Text(rest.status)
        .foregroundStyle(TracendStyle.textPrimary)
    }
  }
}

/// The exercise, then the line under it when the card has one.
struct RestLabels: View {
  let rest: RestPresentation
  let titleSize: CGFloat
  let detailSize: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(rest.title)
        .font(TracendStyle.numeric(titleSize))
        .foregroundStyle(TracendStyle.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      if let detail = rest.detail {
        Text(detail)
          .font(.system(size: detailSize))
          .foregroundStyle(TracendStyle.textSecondary)
          .lineLimit(1)
      }
    }
  }
}

/// The right-hand side: the countdown while a rest runs, the target while a
/// set is in progress (only when the app sent one), a lime check once every
/// set is logged.
struct RestTrailing: View {
  let rest: RestPresentation
  let size: CGFloat
  let doneSymbolSize: CGFloat

  var body: some View {
    switch rest.phase {
    case .resting:
      RestCountdown(endsAt: rest.endsAt, size: size)
    case .set:
      if let target = rest.target {
        Text(target)
          .font(TracendStyle.numeric(size))
          .foregroundStyle(TracendStyle.lime)
          .multilineTextAlignment(.trailing)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
    case .finished:
      Image(systemName: "checkmark")
        .font(.system(size: doneSymbolSize, weight: .bold))
        .foregroundStyle(TracendStyle.lime)
        .accessibilityLabel("All sets logged")
    }
  }
}

/// The time left in lime, counted down by the system.
struct RestCountdown: View {
  let endsAt: Date
  let size: CGFloat

  var body: some View {
    let now = Date.now
    Text(
      timerInterval: now...max(now, endsAt),
      countsDown: true,
      showsHours: false
    )
    .font(TracendStyle.numeric(size))
    .foregroundStyle(TracendStyle.lime)
    .multilineTextAlignment(.trailing)
    .lineLimit(1)
  }
}

/// The Dynamic Island's compact trailing side: the countdown, "2/4", or a
/// check.
struct RestCompactTrailing: View {
  let rest: RestPresentation

  var body: some View {
    switch rest.phase {
    case .resting:
      RestCountdown(endsAt: rest.endsAt, size: 16)
    case .set:
      Text(rest.compactSet)
        .font(TracendStyle.numeric(16))
        .foregroundStyle(TracendStyle.lime)
        .lineLimit(1)
        .accessibilityLabel(rest.status)
    case .finished:
      Image(systemName: "checkmark")
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(TracendStyle.lime)
        .accessibilityLabel("All sets logged")
    }
  }
}

/// The Dynamic Island's minimal presentation: the countdown, or a glyph.
struct RestMinimal: View {
  let rest: RestPresentation

  var body: some View {
    switch rest.phase {
    case .resting:
      RestCountdown(endsAt: rest.endsAt, size: 12)
    case .set, .finished:
      Image(systemName: rest.compactSymbol)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(TracendStyle.lime)
        .accessibilityLabel(rest.status)
    }
  }
}

/// The buttons. While a rest runs: +30s and Skip side by side. While a set is
/// in progress: one lime "Log set", the only lime fill because it is the next
/// thing to do, beside "Open"; it names the set the card shows, so the app
/// logs that set only. When a tap found no workout open, or every set is
/// logged, or the app has no reps for the set, a single lime "Open Tracend"
/// takes the athlete to the workout.
struct RestActions: View {
  let rest: RestPresentation
  let height: CGFloat

  var body: some View {
    if rest.needsApp || rest.phase == .finished || (rest.phase == .set && !rest.canLog) {
      OpenLink(height: height, fill: TracendStyle.lime, ink: TracendStyle.onLime)
    } else if rest.phase == .set, let nextSet = rest.nextSet {
      HStack(spacing: 10) {
        Button(
          intent: CompleteSetIntent(
            exerciseOrder: nextSet.exerciseOrder,
            setNumber: nextSet.setNumber
          )
        ) {
          RestButtonLabel(
            title: "Log set",
            symbol: "checkmark",
            height: height,
            fill: TracendStyle.lime,
            ink: TracendStyle.onLime
          )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rest.logAccessibilityLabel)
        OpenLink(
          height: height,
          fill: TracendStyle.raised,
          ink: TracendStyle.textPrimary,
          title: "Open",
          symbol: nil
        )
        .frame(maxWidth: 120)
      }
    } else {
      HStack(spacing: 10) {
        Button(intent: AddRestIntent()) {
          RestButtonLabel(
            title: "+\(RestActivityButton.addRestSeconds)s",
            symbol: nil,
            height: height,
            fill: TracendStyle.raised,
            ink: TracendStyle.textPrimary
          )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(RestActivityButton.addRestSeconds) seconds")
        Button(intent: SkipRestIntent()) {
          RestButtonLabel(
            title: "Skip",
            symbol: "forward.end.fill",
            height: height,
            fill: TracendStyle.raised,
            ink: TracendStyle.textPrimary
          )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip rest")
      }
    }
  }
}

/// A capsule that opens the workout in progress (`tracend://workout`).
struct OpenLink: View {
  let height: CGFloat
  let fill: Color
  let ink: Color
  var title = "Open Tracend"
  var symbol: String? = "arrow.up.forward.app"

  var body: some View {
    Link(destination: TracendLink.workout.url) {
      RestButtonLabel(title: title, symbol: symbol, height: height, fill: fill, ink: ink)
    }
    .accessibilityLabel("Open Tracend")
  }
}

/// A full-width capsule with a word and an optional symbol.
struct RestButtonLabel: View {
  let title: String
  let symbol: String?
  let height: CGFloat
  let fill: Color
  let ink: Color

  var body: some View {
    HStack(spacing: 6) {
      if let symbol {
        Image(systemName: symbol)
          .font(.system(size: 14, weight: .bold))
          .accessibilityHidden(true)
      }
      Text(title)
        .font(.system(size: 16, weight: .semibold))
        .monospacedDigit()
    }
    .foregroundStyle(ink)
    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
    .background(Capsule().fill(fill))
    .contentShape(Capsule())
  }
}
