import Foundation

/// The app group both targets share: the app writes the snapshot here as one
/// file, the widgets read it. A widget runs in another process and cannot
/// reach the app's own storage, so this is the one thing they share.
///
/// The file is excluded from iCloud and Finder backups, so the numbers in it
/// never leave the phone. Its protection is "until first unlock", because the
/// Lock Screen widgets must read it while the phone is locked.
enum TodayWidgetStore {
  static let appGroup = "group.com.tracend.app"
  static let fileName = "today_widget_snapshot.json"

  /// The snapshot file; nil when the app group is not part of the build's
  /// signing, and then nothing is shared.
  static var fileURL: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
      .appendingPathComponent(fileName)
  }

  /// Whether the app group's container exists for this build.
  static var isAvailable: Bool { fileURL != nil }

  /// The stored snapshot, or nil when none is stored, the app group is
  /// unavailable, or it is not one this build understands.
  static func read() -> TodayWidgetSnapshot? {
    guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
    return TodayWidgetSnapshot.decode(data)
  }

  /// Stores a snapshot's JSON, replacing the one before, and keeps the file
  /// out of backups. False when the app group is unavailable or the file
  /// could not be written.
  static func write(json: Data) -> Bool {
    guard var url = fileURL else { return false }
    do {
      try json.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try url.setResourceValues(values)
      return true
    } catch {
      return false
    }
  }

  static func clear() {
    guard let url = fileURL else { return }
    try? FileManager.default.removeItem(at: url)
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
