import Flutter
import UIKit
import UserNotifications

class SceneDelegate: FlutterSceneDelegate {
  private let flutterEngine = FlutterEngine(name: "tracend")
  private let dailyPreferenceKey = "tracend.notifications.daily-check-in"
  private let weeklyPreferenceKey = "tracend.notifications.weekly-review"

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
          let weeklyReview = arguments["weekly_review"] as? Bool
        else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        self.configureReminders(
          dailyCheckIn: dailyCheckIn,
          weeklyReview: weeklyReview,
          result: result
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureReminders(
    dailyCheckIn: Bool,
    weeklyReview: Bool,
    result: @escaping FlutterResult
  ) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      let needsPermission = dailyCheckIn || weeklyReview
      if needsPermission && settings.authorizationStatus == .notDetermined {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
          if granted {
            self.replaceReminders(
              dailyCheckIn: dailyCheckIn,
              weeklyReview: weeklyReview,
              result: result
            )
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
      self.replaceReminders(
        dailyCheckIn: dailyCheckIn,
        weeklyReview: weeklyReview,
        result: result
      )
    }
  }

  private func replaceReminders(
    dailyCheckIn: Bool,
    weeklyReview: Bool,
    result: @escaping FlutterResult
  ) {
    let center = UNUserNotificationCenter.current()
    let identifiers = ["tracend.daily-check-in", "tracend.weekly-review"]
    center.removePendingNotificationRequests(withIdentifiers: identifiers)

    let content = UNMutableNotificationContent()
    content.title = "Tracend reminder"
    content.body = "Open Tracend when convenient."
    content.sound = .default

    let group = DispatchGroup()
    let errorLock = NSLock()
    var schedulingError: Error?
    if dailyCheckIn {
      let trigger = UNCalendarNotificationTrigger(
        dateMatching: DateComponents(hour: 19),
        repeats: true
      )
      group.enter()
      center.add(
        UNNotificationRequest(
          identifier: identifiers[0],
          content: content,
          trigger: trigger
        )
      ) { error in
        errorLock.lock()
        schedulingError = schedulingError ?? error
        errorLock.unlock()
        group.leave()
      }
    }
    if weeklyReview {
      let trigger = UNCalendarNotificationTrigger(
        dateMatching: DateComponents(hour: 18, weekday: 1),
        repeats: true
      )
      group.enter()
      center.add(
        UNNotificationRequest(
          identifier: identifiers[1],
          content: content,
          trigger: trigger
        )
      ) { error in
        errorLock.lock()
        schedulingError = schedulingError ?? error
        errorLock.unlock()
        group.leave()
      }
    }
    group.notify(queue: .main) {
      if schedulingError != nil {
        result(FlutterError(code: "schedule_failed", message: nil, details: nil))
        return
      }
      self.saveReminderPreferences(
        dailyCheckIn: dailyCheckIn,
        weeklyReview: weeklyReview
      )
      self.notificationState(result: result)
    }
  }

  private func notificationState(result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      center.getPendingNotificationRequests { requests in
        let identifiers = Set(requests.map(\.identifier))
        let pendingDaily = identifiers.contains("tracend.daily-check-in")
        let pendingWeekly = identifiers.contains("tracend.weekly-review")
        let preferences = self.reminderPreferences(
          pendingDaily: pendingDaily,
          pendingWeekly: pendingWeekly
        )
        let authorized = [
          UNAuthorizationStatus.authorized,
          .provisional,
          .ephemeral,
        ].contains(settings.authorizationStatus)
        if authorized
          && (preferences.dailyCheckIn != pendingDaily
            || preferences.weeklyReview != pendingWeekly)
        {
          self.replaceReminders(
            dailyCheckIn: preferences.dailyCheckIn,
            weeklyReview: preferences.weeklyReview,
            result: result
          )
          return
        }
        self.complete(result, value: [
          "authorization_status": self.authorizationStatus(settings.authorizationStatus),
          "daily_check_in": preferences.dailyCheckIn,
          "weekly_review": preferences.weeklyReview,
        ])
      }
    }
  }

  private func reminderPreferences(
    pendingDaily: Bool,
    pendingWeekly: Bool
  ) -> (dailyCheckIn: Bool, weeklyReview: Bool) {
    let defaults = UserDefaults.standard
    let hasDailyPreference = defaults.object(forKey: dailyPreferenceKey) != nil
    let hasWeeklyPreference = defaults.object(forKey: weeklyPreferenceKey) != nil
    let daily = hasDailyPreference
      ? defaults.bool(forKey: dailyPreferenceKey)
      : pendingDaily
    let weekly = hasWeeklyPreference
      ? defaults.bool(forKey: weeklyPreferenceKey)
      : pendingWeekly
    if !hasDailyPreference || !hasWeeklyPreference {
      saveReminderPreferences(dailyCheckIn: daily, weeklyReview: weekly)
    }
    return (daily, weekly)
  }

  private func saveReminderPreferences(
    dailyCheckIn: Bool,
    weeklyReview: Bool
  ) {
    let defaults = UserDefaults.standard
    defaults.set(dailyCheckIn, forKey: dailyPreferenceKey)
    defaults.set(weeklyReview, forKey: weeklyPreferenceKey)
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
