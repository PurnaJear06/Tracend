import SwiftUI
import WidgetKit

/// The Home Screen widgets for Today (docs/DESIGN_SYSTEM.md §12). Small:
/// today's session and the recovery score. Medium: adds the first
/// exercises with their targets, calories and protein against the plan, and
/// whether the check-in is done. They draw on graphite with lime, in light
/// and dark mode alike, like the rest-timer card.
struct TodayWidget: Widget {
  static let kind = "TracendToday"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: TodayTimelineProvider()) { entry in
      TodayWidgetView(entry: entry)
        .containerBackground(TracendStyle.graphite, for: .widget)
    }
    .configurationDisplayName("Today")
    .description("Today's session, your recovery, and calories and protein against your plan.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

private struct TodayWidgetView: View {
  let entry: TodayEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    Group {
      if let snapshot = entry.fresh {
        switch family {
        case .systemMedium: MediumTodayView(snapshot: snapshot)
        default: SmallTodayView(snapshot: snapshot)
        }
      } else {
        OpenTracendView()
      }
    }
    .widgetURL(TracendLink.today.url)
  }
}

/// A stale, missing or unreadable snapshot: the widget shows no number.
private struct OpenTracendView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: "arrow.clockwise")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(TracendStyle.lime)
      Spacer(minLength: 0)
      Text("Open Tracend to refresh")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(TracendStyle.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}

private struct SmallTodayView: View {
  let snapshot: TodayWidgetSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      TodayHeader(snapshot: snapshot)
      Spacer(minLength: 4)
      Text(snapshot.sessionTitle)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(TracendStyle.textPrimary)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
      Text(snapshot.sessionStatus)
        .font(.system(size: 12))
        .foregroundStyle(TracendStyle.textSecondary)
        .lineLimit(1)
      Spacer(minLength: 6)
      RecoveryReadout(snapshot: snapshot, size: 40)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .privacySensitive()
  }
}

private struct MediumTodayView: View {
  let snapshot: TodayWidgetSnapshot

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 0) {
        Text("TODAY")
          .font(.system(size: 11, weight: .semibold))
          .tracking(0.8)
          .foregroundStyle(TracendStyle.textSecondary)
        Spacer(minLength: 4)
        Text(snapshot.sessionTitle)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(TracendStyle.textPrimary)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
        Text(snapshot.sessionStatus)
          .font(.system(size: 11))
          .foregroundStyle(TracendStyle.textSecondary)
          .lineLimit(1)
        Spacer(minLength: 4)
        RecoveryReadout(snapshot: snapshot, size: 34)
      }
      .frame(width: 98, alignment: .leading)

      VStack(alignment: .leading, spacing: 0) {
        AgeLabel(snapshot: snapshot)
          .frame(maxWidth: .infinity, alignment: .trailing)
        if snapshot.hasSessionToOpen {
          ExerciseList(exercises: snapshot.session.exercises)
            .padding(.top, 2)
        }
        Spacer(minLength: 4)
        HStack(spacing: 10) {
          FuelMeter(
            label: "kcal",
            value: snapshot.nutrition.calories,
            target: snapshot.nutrition.caloriesTarget
          )
          FuelMeter(
            label: "protein",
            value: snapshot.nutrition.proteinG,
            target: snapshot.nutrition.proteinTargetG
          )
        }
        CheckInLine(done: snapshot.checkInDone)
          .padding(.top, 5)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .privacySensitive()
  }
}

/// The first exercises with their targets. A tap on them opens Train.
private struct ExerciseList: View {
  let exercises: [TodayWidgetSnapshot.Exercise]

  var body: some View {
    Link(destination: TracendLink.train.url) {
      VStack(alignment: .leading, spacing: 3) {
        ForEach(Array(exercises.prefix(3).enumerated()), id: \.offset) { _, exercise in
          HStack(spacing: 6) {
            Text(exercise.name)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(TracendStyle.textPrimary)
              .lineLimit(1)
            Spacer(minLength: 0)
            Text(exercise.target)
              .font(.system(size: 11).monospacedDigit())
              .foregroundStyle(TracendStyle.textSecondary)
              .lineLimit(1)
              .fixedSize()
          }
        }
      }
    }
  }
}

private struct TodayHeader: View {
  let snapshot: TodayWidgetSnapshot

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("TODAY")
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.8)
        .foregroundStyle(TracendStyle.textSecondary)
      Spacer(minLength: 4)
      AgeLabel(snapshot: snapshot)
    }
  }
}

/// How old the snapshot is. The system keeps the count running.
private struct AgeLabel: View {
  let snapshot: TodayWidgetSnapshot

  var body: some View {
    Text(snapshot.generatedAt, style: .relative)
      .font(.system(size: 10).monospacedDigit())
      .foregroundStyle(TracendStyle.textSecondary)
      .lineLimit(1)
      .multilineTextAlignment(.trailing)
      .accessibilityLabel("Updated \(snapshot.generatedAt.formatted(.relative(presentation: .named)))")
  }
}

private struct RecoveryReadout: View {
  let snapshot: TodayWidgetSnapshot
  let size: CGFloat

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Text(snapshot.recoveryText)
        .font(TracendStyle.numeric(size))
        .foregroundStyle(snapshot.recovery == nil ? TracendStyle.textSecondary : TracendStyle.lime)
      Text("recovery")
        .font(.system(size: 12))
        .foregroundStyle(TracendStyle.textSecondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      snapshot.recovery.map { "Recovery \($0)" } ?? "Recovery not scored"
    )
  }
}

/// One value against its target: "protein 80 / 160" over a thin bar. Without
/// a target only what was eaten shows.
private struct FuelMeter: View {
  let label: String
  let value: Int
  let target: Int?

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(text)
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(TracendStyle.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      ProgressBar(fraction: fraction)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      target.map { "\(label) \(value) of \($0)" } ?? "\(label) \(value)"
    )
  }

  private var text: String {
    target.map { "\(value)/\($0) \(label)" } ?? "\(value) \(label)"
  }

  private var fraction: Double {
    guard let target, target > 0 else { return 0 }
    return min(1, Double(value) / Double(target))
  }
}

private struct ProgressBar: View {
  let fraction: Double

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(TracendStyle.raised)
        Capsule()
          .fill(TracendStyle.lime)
          .frame(width: max(0, proxy.size.width * fraction))
      }
    }
    .frame(height: 4)
  }
}

private struct CheckInLine: View {
  let done: Bool

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: done ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 11))
        .foregroundStyle(done ? TracendStyle.lime : TracendStyle.textSecondary)
      Text(done ? "Checked in" : "Check-in due")
        .font(.system(size: 11))
        .foregroundStyle(TracendStyle.textSecondary)
    }
  }
}
