import SwiftUI
import WidgetKit

/// One drawing of a Today widget: the snapshot read from the app group, and
/// the moment it is drawn for. A missing, unreadable or stale snapshot is not
/// drawn at all; every family asks the athlete to open the app instead.
struct TodayEntry: TimelineEntry {
  let date: Date
  /// Nil when none is stored or it is not one this build understands.
  let snapshot: TodayWidgetSnapshot?

  /// The snapshot to draw, or nil when the widget must say "Open Tracend to
  /// refresh".
  var fresh: TodayWidgetSnapshot? {
    guard let snapshot, !snapshot.isStale(at: date) else { return nil }
    return snapshot
  }
}

/// Reads the shared snapshot and never goes anywhere else: no network, no
/// calculation. The app asks for a new timeline whenever it writes a
/// snapshot, so this one only schedules the moment the snapshot turns stale.
struct TodayTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> TodayEntry {
    TodayEntry(date: .now, snapshot: .sample)
  }

  func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
    completion(
      TodayEntry(date: .now, snapshot: context.isPreview ? .sample : TodayWidgetStore.read())
    )
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
    let now = Date.now
    let snapshot = TodayWidgetStore.read()
    var entries = [TodayEntry(date: now, snapshot: snapshot)]
    if let snapshot, !snapshot.isStale(at: now) {
      entries.append(TodayEntry(date: snapshot.staleDate(), snapshot: snapshot))
    }
    completion(Timeline(entries: entries, policy: .never))
  }
}

extension TodayWidgetSnapshot {
  /// Gallery and placeholder content, never read from the app group.
  static let sample = TodayWidgetSnapshot(
    schemaVersion: supportedSchemaVersion,
    staleAfterSeconds: 43_200,
    generatedAtMillis: Int64(Date.now.timeIntervalSince1970 * 1000),
    localDate: localDateText(.now),
    session: Session(
      state: "planned",
      name: "Push day",
      setsLogged: 0,
      setsTotal: 14,
      exercises: [
        Exercise(name: "Bench press", target: "4 × 6–8 · 80 kg"),
        Exercise(name: "Overhead press", target: "3 × 8–10 · 45 kg"),
        Exercise(name: "Incline dumbbell press", target: "3 × 10–12 · 24 kg"),
      ]
    ),
    recovery: 72,
    nutrition: Nutrition(calories: 1240, caloriesTarget: 2400, proteinG: 80, proteinTargetG: 160),
    checkInDone: true,
    lock: Lock(
      session: "Push day",
      sessionState: "planned",
      recovery: 72,
      proteinG: 80,
      proteinTargetG: 160
    )
  )

  /// "Rest day" or the plan's session name.
  var sessionTitle: String { session.name ?? "Rest day" }

  /// Where the session stands, in a few words.
  var sessionStatus: String {
    switch session.state {
    case "rest": return "Nothing planned"
    case "in_progress": return "\(session.setsLogged) of \(session.setsTotal) sets"
    case "completed": return "Done · \(session.setsLogged) sets"
    default: return "Not started"
    }
  }

  /// A session still to do or under way; a tap on it opens Train.
  var hasSessionToOpen: Bool {
    session.state == "planned" || session.state == "in_progress"
  }

  /// The recovery score as text, or "--" when it was not scored.
  var recoveryText: String { recovery.map(String.init) ?? "--" }
}
