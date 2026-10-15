import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The rest between sets on the Lock Screen and in the Dynamic Island. The
/// countdown is `Text(timerInterval:)`, which the system runs from the end
/// time with the app closed; once the end passes the content is stale and
/// every presentation reads "Rest done". The Lock Screen and the expanded
/// Dynamic Island carry the buttons: +30s and Skip while the rest runs, Done
/// once it is over.
struct RestLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RestActivityAttributes.self) { context in
      RestLockScreenView(rest: RestPresentation(context))
        .activityBackgroundTint(TracendStyle.graphite)
        .activitySystemActionForegroundColor(TracendStyle.textPrimary)
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
          RestCountdown(rest: rest, size: 34, doneSymbolSize: 28)
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
        Image(systemName: "timer")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(TracendStyle.lime)
          .accessibilityLabel("Rest")
      } compactTrailing: {
        RestCountdown(rest: rest, size: 16, doneSymbolSize: 14)
          .frame(maxWidth: 48)
      } minimal: {
        RestCountdown(rest: rest, size: 12, doneSymbolSize: 14)
          .minimumScaleFactor(0.7)
          .frame(maxWidth: 36)
      }
      .keylineTint(TracendStyle.lime)
    }
  }
}

/// What every presentation shows, with the fallbacks for labels the app did
/// not send.
struct RestPresentation {
  let endsAt: Date
  let isDone: Bool
  let needsApp: Bool
  /// The set the Done button names; nil when the app did not say, and then
  /// there is no Done button.
  let nextSet: (exerciseOrder: Int, setNumber: Int)?
  let title: String
  let nextLabel: String

  init(_ context: ActivityViewContext<RestActivityAttributes>) {
    let state = context.state
    endsAt = state.endsAt
    isDone = context.isStale || state.endsAt <= .now
    needsApp = state.needsApp
    if let order = state.nextExerciseOrder, let number = state.nextSetNumber {
      nextSet = (order, number)
    } else {
      nextSet = nil
    }
    title = state.exerciseName.isEmpty ? "Between sets" : state.exerciseName
    nextLabel = state.nextLabel
  }

  var status: String { isDone ? "Rest done" : "Rest" }
}

/// The Lock Screen and banner card: the status, exercise and next set on the
/// left, the big lime countdown on the right, the buttons underneath.
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
        RestCountdown(rest: rest, size: 44, doneSymbolSize: 34)
          .frame(maxWidth: 132, alignment: .trailing)
      }
      RestActions(rest: rest, height: 44)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }
}

/// The lime timer glyph and "Rest", or a check and "Rest done".
struct RestStatusLabel: View {
  let rest: RestPresentation

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: rest.isDone ? "checkmark.circle.fill" : "timer")
        .foregroundStyle(TracendStyle.lime)
        .accessibilityHidden(true)
      Text(rest.status)
        .foregroundStyle(TracendStyle.textPrimary)
    }
  }
}

/// The exercise, then "Next: …" when the app said what follows.
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
      if !rest.nextLabel.isEmpty {
        Text("Next: \(rest.nextLabel)")
          .font(.system(size: detailSize))
          .foregroundStyle(TracendStyle.textSecondary)
          .lineLimit(1)
      }
    }
  }
}

/// The time left in lime, counted down by the system; a lime check once the
/// rest is over.
struct RestCountdown: View {
  let rest: RestPresentation
  let size: CGFloat
  let doneSymbolSize: CGFloat

  var body: some View {
    if rest.isDone {
      Image(systemName: "checkmark")
        .font(.system(size: doneSymbolSize, weight: .bold))
        .foregroundStyle(TracendStyle.lime)
        .accessibilityLabel("Rest done")
    } else {
      let now = Date.now
      Text(
        timerInterval: now...max(now, rest.endsAt),
        countsDown: true,
        showsHours: false
      )
      .font(TracendStyle.numeric(size))
      .foregroundStyle(TracendStyle.lime)
      .multilineTextAlignment(.trailing)
      .lineLimit(1)
    }
  }
}

/// The buttons: +30s and Skip side by side while the rest runs; one lime
/// Done once it is over, the only lime fill, because it is the next thing to
/// do, and it names the set the card shows, so the app ticks that set only.
/// When a tap found no workout open, or the card has no set to name, a line
/// asks to open the app (a tap on the card does).
struct RestActions: View {
  let rest: RestPresentation
  let height: CGFloat

  var body: some View {
    if rest.needsApp || (rest.isDone && rest.nextSet == nil) {
      Label("Open Tracend to continue", systemImage: "arrow.up.forward.app")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(TracendStyle.textSecondary)
        .frame(maxWidth: .infinity, minHeight: height)
    } else if rest.isDone, let nextSet = rest.nextSet {
      Button(
        intent: CompleteSetIntent(
          exerciseOrder: nextSet.exerciseOrder,
          setNumber: nextSet.setNumber
        )
      ) {
        RestButtonLabel(
          title: "Done set",
          symbol: "checkmark",
          height: height,
          fill: TracendStyle.lime,
          ink: TracendStyle.onLime
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(rest.nextLabel.isEmpty ? "Done set" : "Done, \(rest.nextLabel)")
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
