import Foundation

/// What the Today and Lock Screen widgets show, as the app writes it
/// (`lib/shared/home_widgets/today_widget_snapshot.dart`) into the app
/// group. Compiled into Runner, which checks a snapshot before it stores it,
/// and into TracendWidgets, which draws it. The widgets never call the
/// network and calculate nothing: every number is one Today already showed.
///
/// No free text travels (SECURITY_PRIVACY.md §10): the session and exercise
/// names are the plan's own. `lock` is present only while the athlete chose
/// to show health numbers on the Lock Screen; Lock Screen widgets read
/// nothing else.
struct TodayWidgetSnapshot: Codable, Equatable {
  /// The only shape version this build draws. A snapshot of another version
  /// is refused, and the widgets ask the athlete to open the app.
  static let supportedSchemaVersion = 1

  struct Session: Codable, Equatable {
    /// `rest`, `planned`, `in_progress` or `completed`.
    var state: String
    /// Nil on a rest day.
    var name: String?
    var setsLogged: Int
    var setsTotal: Int
    var exercises: [Exercise]
  }

  struct Exercise: Codable, Equatable {
    var name: String
    /// For example "4 × 6–8 · 82.5 kg".
    var target: String
  }

  struct Nutrition: Codable, Equatable {
    var calories: Int
    var caloriesTarget: Int?
    var proteinG: Int
    var proteinTargetG: Int?
  }

  /// What a Lock Screen widget may show.
  struct Lock: Codable, Equatable {
    /// The session's name, or "Rest day".
    var session: String
    var sessionState: String
    var recovery: Int?
    var proteinG: Int
    var proteinTargetG: Int?
  }

  var schemaVersion: Int
  var staleAfterSeconds: Int
  var generatedAtMillis: Int64
  /// The brief's local date, `YYYY-MM-DD`.
  var localDate: String
  var session: Session
  /// Today's recovery score; nil when it was not scored.
  var recovery: Int?
  var nutrition: Nutrition
  var checkInDone: Bool
  var lock: Lock?

  var generatedAt: Date {
    Date(timeIntervalSince1970: TimeInterval(generatedAtMillis) / 1000)
  }

  /// Reads a snapshot, or nil for anything this build does not understand:
  /// not JSON, a missing field, or another schema version.
  static func decode(_ data: Data) -> TodayWidgetSnapshot? {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard
      let snapshot = try? decoder.decode(TodayWidgetSnapshot.self, from: data),
      snapshot.schemaVersion == supportedSchemaVersion
    else { return nil }
    return snapshot
  }

  /// Whether the widgets must ask the athlete to open the app instead of
  /// showing it: the snapshot is `staleAfterSeconds` old or older, it is
  /// from another day than `now`'s, or it claims to come from the future.
  /// Stale from `staleDate()` on, that moment included: the timeline's last
  /// entry is drawn at exactly that moment and nothing redraws it after.
  func isStale(at now: Date, calendar: Calendar = .current) -> Bool {
    let age = now.timeIntervalSince(generatedAt)
    if age >= TimeInterval(staleAfterSeconds) || age < -300 { return true }
    return localDate != Self.localDateText(now, calendar: calendar)
  }

  /// The first moment `isStale` turns true: 12 hours after the snapshot, or
  /// the start of the next day, whichever is first.
  func staleDate(calendar: Calendar = .current) -> Date {
    let byAge = generatedAt.addingTimeInterval(TimeInterval(staleAfterSeconds))
    let parts = localDate.split(separator: "-").compactMap { Int($0) }
    guard
      parts.count == 3,
      let day = calendar.date(
        from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
      ),
      let nextDay = calendar.date(byAdding: .day, value: 1, to: day)
    else { return byAge }
    return min(byAge, nextDay)
  }

  /// `YYYY-MM-DD` of `date` in `calendar`, the brief's `local_date` format.
  static func localDateText(_ date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      parts.year ?? 0,
      parts.month ?? 0,
      parts.day ?? 0
    )
  }
}
