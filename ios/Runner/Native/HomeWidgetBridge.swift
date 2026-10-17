import Flutter
import Foundation
import WidgetKit

/// The Home Screen and Lock Screen widgets behind the `tracend/home_widgets`
/// channel (`lib/shared/home_widgets/home_widget_bridge.dart`).
///
/// `write` stores Today's snapshot as a file in the app group's container,
/// excluded from backups (`ios/Shared/TodayWidgetStore.swift`), and asks iOS
/// to redraw the widgets; `clear` removes it. The widgets only read it and never call the network.
/// A tap on a widget arrives as `tracend://today` or `tracend://train`
/// (`open`); the tab is kept for a minute for `takePendingTab`, and a running
/// app is told with `tabRequested`.
enum HomeWidgetBridge {
  static let channelName = "tracend/home_widgets"

  /// How long a tap waits for the app to take it. A tap older than this is
  /// from an earlier visit.
  static let pendingTimeout: TimeInterval = 60

  @MainActor private static var channel: FlutterMethodChannel?
  @MainActor private static var pending: (link: TracendLink, at: Date)?

  static func register(on messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    MainActor.assumeIsolated { Self.channel = channel }
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "write":
        guard TodayWidgetStore.isAvailable else {
          result(FlutterError(code: "no_app_group", message: nil, details: nil))
          return
        }
        guard
          let snapshot = (call.arguments as? [String: Any])?["snapshot"] as? String,
          let data = snapshot.data(using: .utf8),
          TodayWidgetSnapshot.decode(data) != nil
        else {
          result(FlutterError(code: "invalid_snapshot", message: nil, details: nil))
          return
        }
        guard TodayWidgetStore.write(json: data) else {
          result(FlutterError(code: "write_failed", message: nil, details: nil))
          return
        }
        WidgetCenter.shared.reloadAllTimelines()
        result(true)
      case "clear":
        TodayWidgetStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
        result(true)
      case "takePendingTab":
        result(MainActor.assumeIsolated { takePending() })
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// A URL the app was opened with. Anything but a widget link is ignored.
  @MainActor
  static func open(_ url: URL) {
    guard let link = TracendLink(url: url) else { return }
    pending = (link, Date())
    channel?.invokeMethod("tabRequested", arguments: nil)
  }

  @MainActor
  private static func takePending() -> String? {
    defer { pending = nil }
    guard let pending, Date().timeIntervalSince(pending.at) <= pendingTimeout else {
      return nil
    }
    return pending.link.rawValue
  }
}
