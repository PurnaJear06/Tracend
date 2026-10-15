import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Set before any scene connects: iOS may launch the app in the background
    // just to run a Live Activity button, and then no scene (and no Flutter
    // engine) exists; the bridge answers that press itself.
    RestActivityButtons.handler = { await WorkoutActivityBridge.press($0) }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
