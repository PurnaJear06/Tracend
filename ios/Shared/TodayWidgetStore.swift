import Foundation

/// The app group both targets share: the app writes the snapshot here, the
/// widgets read it. A widget runs in another process and cannot reach the
/// app's own storage, so this is the one thing they share.
enum TodayWidgetStore {
  static let appGroup = "group.com.tracend.app"
  static let key = "today_widget_snapshot"

  /// The group's storage; nil when the app group is not part of the build's
  /// signing, and then nothing is shared.
  static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  /// The stored snapshot, or nil when none is stored or it is not one this
  /// build understands.
  static func read() -> TodayWidgetSnapshot? {
    guard let data = defaults?.data(forKey: key) else { return nil }
    return TodayWidgetSnapshot.decode(data)
  }

  /// Stores a snapshot's JSON. False when the app group is unavailable.
  static func write(json: Data) -> Bool {
    guard let defaults else { return false }
    defaults.set(json, forKey: key)
    return true
  }

  static func clear() {
    defaults?.removeObject(forKey: key)
  }
}

/// A tap on a widget opens the app on a tab: `tracend://today` or
/// `tracend://train`. Nothing else is accepted.
enum TracendLink: String {
  case today
  case train

  static let scheme = "tracend"

  var url: URL {
    // Valid by construction: a fixed scheme and one of the cases above.
    URL(string: "\(Self.scheme)://\(rawValue)")!
  }

  init?(url: URL) {
    guard
      url.scheme == Self.scheme,
      let host = url.host,
      let link = TracendLink(rawValue: host)
    else { return nil }
    self = link
  }
}
