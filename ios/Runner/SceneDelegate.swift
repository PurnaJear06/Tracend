import Flutter
import UIKit
import UserNotifications

class SceneDelegate: FlutterSceneDelegate {
  private let flutterEngine = FlutterEngine(name: "tracend")
  private let dailyPreferenceKey = "tracend.notifications.daily-check-in"
  private let weeklyPreferenceKey = "tracend.notifications.weekly-review"
  private let restTimerPreferenceKey = "tracend.notifications.rest-timer"
  private let notifications = TracendNotificationScheduler(center: SystemNotificationCenter())

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }

    window = UIWindow(windowScene: windowScene)
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)
    configureNotifications(on: flutterEngine.binaryMessenger)
    configureTimeZone(on: flutterEngine.binaryMessenger)
    registerSceneLifeCycle(with: flutterEngine)

    window?.rootViewController = FlutterViewController(
      engine: flutterEngine,
      nibName: nil,
      bundle: nil
    )
    window?.makeKeyAndVisible()

    super.scene(
      scene,
      willConnectTo: session,
      options: connectionOptions
    )
  }

  override func sceneDidDisconnect(_ scene: UIScene) {
    unregisterSceneLifeCycle(with: flutterEngine)
    super.sceneDidDisconnect(scene)
  }

  /// The device's IANA time zone (for example Asia/Kolkata), which the app
  /// stores on the account so local dates match the athlete's day.
  private func configureTimeZone(on messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.tracend.app/time_zone",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "identifier":
        result(TimeZone.current.identifier)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureNotifications(on messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.tracend.app/notifications",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "status":
        self.notificationState(result: result)
      case "configure":
        guard
          let arguments = call.arguments as? [String: Any],
          let dailyCheckIn = arguments["daily_check_in"] as? Bool,
          let weeklyReview = arguments["weekly_review"] as? Bool,
          let restTimerAlerts = arguments["rest_timer_alerts"] as? Bool
        else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        self.configurePreferences(
          NotificationChoices(
            dailyCheckIn: dailyCheckIn,
            weeklyReview: weeklyReview,
            restTimerAlerts: restTimerAlerts
          ),
          result: result
        )
      case "scheduleRestAlert":
        guard
          let arguments = call.arguments as? [String: Any],
          let seconds = arguments["seconds"] as? Int,
          (1...TracendNotificationScheduler.maxRestSeconds).contains(seconds)
        else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        self.scheduleRestAlert(seconds: seconds, result: result)
      case "cancelRestAlert":
        self.notifications.cancelRestAlert()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configurePreferences(
    _ choices: NotificationChoices,
    result: @escaping FlutterResult
  ) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      let needsPermission = choices.anyEnabled
      if needsPermission && settings.authorizationStatus == .notDetermined {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
          if granted {
            self.applyPreferences(choices, result: result)
          } else {
            self.complete(
              result,
              value: FlutterError(code: "permission_denied", message: nil, details: nil)
            )
          }
        }
        return
      }
      if needsPermission && settings.authorizationStatus == .denied {
        self.complete(
          result,
          value: FlutterError(code: "permission_denied", message: nil, details: nil)
        )
        return
      }
      self.applyPreferences(choices, result: result)
    }
  }

  /// Replaces the daily and weekly reminders and saves all three choices.
  /// Turning rest alerts off is followed by `cancelRestAlert` from Dart.
  private func applyPreferences(
    _ choices: NotificationChoices,
    result: @escaping FlutterResult
  ) {
    notifications.replaceReminders(
      dailyCheckIn: choices.dailyCheckIn,
      weeklyReview: choices.weeklyReview
    ) { error in
      if error != nil {
        result(FlutterError(code: "schedule_failed", message: nil, details: nil))
        return
      }
      self.savePreferences(choices)
      self.notificationState(result: result)
    }
  }

  /// Schedules the rest alert when the athlete turned rest alerts on and iOS
  /// allows alerts. Returns whether an alert is now pending.
  private func scheduleRestAlert(seconds: Int, result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let enabled = UserDefaults.standard.bool(forKey: self.restTimerPreferenceKey)
      guard enabled && self.isAuthorized(settings.authorizationStatus) else {
        self.notifications.cancelRestAlert()
        self.complete(result, value: false)
        return
      }
      self.notifications.scheduleRestAlert(seconds: seconds) { error in
        result(
          error == nil
            ? true
            : FlutterError(code: "schedule_failed", message: nil, details: nil)
        )
      }
    }
  }

  private func notificationState(result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      center.getPendingNotificationRequests { requests in
        let identifiers = Set(requests.map(\.identifier))
        let pendingDaily = identifiers.contains(TracendNotificationID.dailyCheckIn)
        let pendingWeekly = identifiers.contains(TracendNotificationID.weeklyReview)
        let preferences = self.storedPreferences(
          pendingDaily: pendingDaily,
          pendingWeekly: pendingWeekly
        )
        if self.isAuthorized(settings.authorizationStatus)
          && (preferences.dailyCheckIn != pendingDaily
            || preferences.weeklyReview != pendingWeekly)
        {
          self.applyPreferences(preferences, result: result)
          return
        }
        self.complete(result, value: [
          "authorization_status": self.authorizationStatus(settings.authorizationStatus),
          "daily_check_in": preferences.dailyCheckIn,
          "weekly_review": preferences.weeklyReview,
          "rest_timer_alerts": preferences.restTimerAlerts,
        ])
      }
    }
  }

  /// The saved choices. Before a reminder choice was saved, its pending
  /// request stands in for it; rest alerts start off.
  private func storedPreferences(
    pendingDaily: Bool,
    pendingWeekly: Bool
  ) -> NotificationChoices {
    let defaults = UserDefaults.standard
    let hasAll = [dailyPreferenceKey, weeklyPreferenceKey, restTimerPreferenceKey]
      .allSatisfy { defaults.object(forKey: $0) != nil }
    let choices = NotificationChoices(
      dailyCheckIn: defaults.object(forKey: dailyPreferenceKey) != nil
        ? defaults.bool(forKey: dailyPreferenceKey)
        : pendingDaily,
      weeklyReview: defaults.object(forKey: weeklyPreferenceKey) != nil
        ? defaults.bool(forKey: weeklyPreferenceKey)
        : pendingWeekly,
      restTimerAlerts: defaults.bool(forKey: restTimerPreferenceKey)
    )
    if !hasAll {
      savePreferences(choices)
    }
    return choices
  }

  private func savePreferences(_ choices: NotificationChoices) {
    let defaults = UserDefaults.standard
    defaults.set(choices.dailyCheckIn, forKey: dailyPreferenceKey)
    defaults.set(choices.weeklyReview, forKey: weeklyPreferenceKey)
    defaults.set(choices.restTimerAlerts, forKey: restTimerPreferenceKey)
  }

  private func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
    [UNAuthorizationStatus.authorized, .provisional, .ephemeral].contains(status)
  }

  private func authorizationStatus(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "not_determined"
    case .denied: return "denied"
    case .authorized: return "authorized"
    case .provisional: return "provisional"
    case .ephemeral: return "ephemeral"
    @unknown default: return "unknown"
    }
  }

  private func complete(_ result: @escaping FlutterResult, value: Any?) {
    DispatchQueue.main.async {
      result(value)
    }
  }
}

/// The three notification toggles the athlete controls.
private struct NotificationChoices {
  let dailyCheckIn: Bool
  let weeklyReview: Bool
  let restTimerAlerts: Bool

  var anyEnabled: Bool { dailyCheckIn || weeklyReview || restTimerAlerts }
}
