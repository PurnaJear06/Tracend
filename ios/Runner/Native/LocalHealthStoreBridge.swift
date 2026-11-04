import Flutter
import Foundation
import os

/// The folder where the app keeps what it caches of an athlete's health:
/// pain reports, check-ins, workout drafts, the plan and the Coach's last
/// thread (`lib/shared/local_health_store.dart`).
///
/// It sits in Application Support and is excluded from iCloud and computer
/// backups, so none of it leaves the phone that way. Each file is written
/// with protection "until first unlock", not complete protection: the Live
/// Activity's "Log set" button runs in the app's process with the phone
/// locked, and the workout draft it saves must not fail then.
enum LocalHealthStoreFiles {
  static let directoryName = "TracendHealthCache"

  /// Set once this run has found the folder excluded from backups.
  private static let verified = OSAllocatedUnfairLock(initialState: false)

  /// The folder, created when missing. Its exclusion from backups is set and
  /// checked once per run, and nothing is stored in it while that has not
  /// succeeded: every call tries again until it does.
  static func directory() throws -> URL {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    var folder = support.appendingPathComponent(directoryName, isDirectory: true)
    if verified.withLock({ $0 }) { return folder }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try folder.setResourceValues(values)
    // A new URL, because the first one remembers the value it was given.
    let stored = URL(fileURLWithPath: folder.path, isDirectory: true)
    guard try stored.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    else { throw CocoaError(.fileWriteUnknown) }
    verified.withLock { $0 = true }
    return stored
  }

  /// A plain file name made by the app: no folders, nothing hidden.
  static func isValid(name: String) -> Bool {
    !name.isEmpty && !name.hasPrefix(".") && !name.contains("/")
  }

  /// Stores [contents] in the file [name], replacing the one before in one
  /// step.
  static func write(name: String, contents: String) throws {
    guard isValid(name: name) else { throw CocoaError(.fileWriteInvalidFileName) }
    let url = try directory().appendingPathComponent(name)
    try Data(contents.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}

/// The `tracend/local_health_store` channel: `directory` answers the folder's
/// path, and `write` stores one file in it. Reading, listing and deleting are
/// done by Dart in the same folder.
enum LocalHealthStoreBridge {
  static let channelName = "tracend/local_health_store"

  static func register(on messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "directory":
        guard let folder = try? LocalHealthStoreFiles.directory() else {
          result(FlutterError(code: "unavailable", message: nil, details: nil))
          return
        }
        result(folder.path)
      case "write":
        guard
          let arguments = call.arguments as? [String: Any],
          let name = arguments["name"] as? String,
          let contents = arguments["contents"] as? String,
          LocalHealthStoreFiles.isValid(name: name)
        else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        do {
          try LocalHealthStoreFiles.write(name: name, contents: contents)
          result(true)
        } catch {
          result(FlutterError(code: "write_failed", message: nil, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
