import SwiftUI
import WidgetKit

/// The Lock Screen widgets for Today (docs/DESIGN_SYSTEM.md §12): the
/// recovery score (circular), the session, recovery and protein
/// (rectangular), and the session with recovery (inline). They show health
/// numbers only while the athlete chose that in Account: the app leaves the
/// `lock` section out of the snapshot otherwise, and these widgets then show
/// a placeholder. The system draws them in its own tint.
struct LockScreenWidget: Widget {
  static let kind = "TracendLockScreen"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: TodayTimelineProvider()) { entry in
      LockScreenWidgetView(entry: entry)
        .containerBackground(for: .widget) { Color.clear }
    }
    .configurationDisplayName("Today on the Lock Screen")
    .description("Recovery, today's session and protein. Turn the numbers on in Account.")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

private struct LockScreenWidgetView: View {
  let entry: TodayEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    Group {
      switch content {
      case .numbers(let lock): numbers(lock)
      case .hidden: hidden
      case .refresh: refresh
      }
    }
    .widgetURL(link.url)
  }

  private enum Content {
    case numbers(TodayWidgetSnapshot.Lock)
    case hidden
    case refresh
  }

  private var content: Content {
    guard let snapshot = entry.fresh else { return .refresh }
    guard let lock = snapshot.lock else { return .hidden }
    return .numbers(lock)
  }

  /// The rectangular widget showing a session still to do opens Train;
  /// the circular and inline widgets, and every other state, open Today.
  private var link: TracendLink {
    if family == .accessoryRectangular,
      case .numbers(let lock) = content,
      lock.sessionState == "planned" || lock.sessionState == "in_progress"
    {
      return .train
    }
    return .today
  }

  @ViewBuilder
  private func numbers(_ lock: TodayWidgetSnapshot.Lock) -> some View {
    switch family {
    case .accessoryCircular:
      RecoveryGauge(recovery: lock.recovery)
    case .accessoryInline:
      Text(
        lock.recovery.map { "\(lock.session) · Rec \($0)" } ?? lock.session
      )
    default:
      SessionLines(lock: lock)
    }
  }

  @ViewBuilder
  private var hidden: some View {
    switch family {
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        Image(systemName: "lock.fill").font(.system(size: 18))
      }
    case .accessoryInline:
      Text("Tracend · numbers off")
    default:
      VStack(alignment: .leading, spacing: 2) {
        Text("Tracend").font(.headline)
        Text("Lock Screen numbers are off").font(.caption)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var refresh: some View {
    switch family {
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        Image(systemName: "arrow.clockwise").font(.system(size: 18))
      }
    case .accessoryInline:
      Text("Open Tracend to refresh")
    default:
      VStack(alignment: .leading, spacing: 2) {
        Text("Tracend").font(.headline)
        Text("Open Tracend to refresh").font(.caption)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Recovery on a ring: the score in the middle, "REC" above it.
private struct RecoveryGauge: View {
  let recovery: Int?

  var body: some View {
    Gauge(value: Double(recovery ?? 0), in: 0...100) {
      Text("REC")
    } currentValueLabel: {
      Text(recovery.map(String.init) ?? "--")
    }
    .gaugeStyle(.accessoryCircular)
    .accessibilityLabel(recovery.map { "Recovery \($0)" } ?? "Recovery not scored")
  }
}

/// The session, the recovery score and protein against its target.
private struct SessionLines: View {
  let lock: TodayWidgetSnapshot.Lock

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(lock.session)
        .font(.headline)
        .lineLimit(1)
      Text(lock.recovery.map { "Recovery \($0)" } ?? "Recovery not scored")
        .font(.caption)
      if let target = lock.proteinTargetG, target > 0 {
        ProgressView(value: Double(min(lock.proteinG, target)), total: Double(target))
        Text("\(lock.proteinG) / \(target) g protein").font(.caption2)
      } else {
        Text("\(lock.proteinG) g protein").font(.caption2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
