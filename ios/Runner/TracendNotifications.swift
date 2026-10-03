import Foundation
import UserNotifications

/// The parts of `UNUserNotificationCenter` that Tracend's local notifications
/// use, so the scheduling rules can be tested with a recording center.
protocol LocalNotificationCenter: AnyObject {
  func add(_ request: UNNotificationRequest, completion: @escaping @Sendable (Error?) -> Void)
  func removePendingNotificationRequests(withIdentifiers identifiers: [String])
  func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

/// The system notification center.
final class SystemNotificationCenter: LocalNotificationCenter {
  private let center = UNUserNotificationCenter.current()

  func add(_ request: UNNotificationRequest, completion: @escaping @Sendable (Error?) -> Void) {
    center.add(request, withCompletionHandler: completion)
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }
}

enum TracendNotificationID {
  static let dailyCheckIn = "tracend.daily-check-in"
  static let weeklyReview = "tracend.weekly-review"
  static let restTimer = "tracend.rest-timer"

  /// The repeating reminders that reconciliation owns. The rest alert is not
  /// one of them: replacing reminders never touches it.
  static let reminders = [dailyCheckIn, weeklyReview]
}

/// Schedules Tracend's local notifications. Every request has a fixed
/// identifier and generic lock-screen text (SECURITY_PRIVACY.md), and nothing
/// here removes all pending requests.
final class TracendNotificationScheduler {
  /// The longest rest the alert accepts, in seconds.
  static let maxRestSeconds = 3600
  static let restAlertTitle = "Rest timer finished"

  private let center: LocalNotificationCenter

  init(center: LocalNotificationCenter) {
    self.center = center
  }

  /// Removes the daily and weekly reminders and adds back the enabled ones.
  /// `completion` runs on the main queue with the first scheduling error.
  func replaceReminders(
    dailyCheckIn: Bool,
    weeklyReview: Bool,
    completion: @escaping (Error?) -> Void
  ) {
    center.removePendingNotificationRequests(withIdentifiers: TracendNotificationID.reminders)

    let content = UNMutableNotificationContent()
    content.title = "Tracend reminder"
    content.body = "Open Tracend when convenient."
    content.sound = .default

    var requests: [UNNotificationRequest] = []
    if dailyCheckIn {
      requests.append(
        UNNotificationRequest(
          identifier: TracendNotificationID.dailyCheckIn,
          content: content,
          trigger: UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: 19),
            repeats: true
          )
        )
      )
    }
    if weeklyReview {
      requests.append(
        UNNotificationRequest(
          identifier: TracendNotificationID.weeklyReview,
          content: content,
          trigger: UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: 18, weekday: 1),
            repeats: true
          )
        )
      )
    }
    add(requests, completion: completion)
  }

  /// Schedules the one rest alert `seconds` from now. The fixed identifier
  /// means a new alert replaces the earlier one.
  func scheduleRestAlert(seconds: Int, completion: @escaping (Error?) -> Void) {
    let content = UNMutableNotificationContent()
    content.title = Self.restAlertTitle
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: TracendNotificationID.restTimer,
      content: content,
      trigger: UNTimeIntervalNotificationTrigger(
        timeInterval: TimeInterval(seconds),
        repeats: false
      )
    )
    center.removePendingNotificationRequests(withIdentifiers: [TracendNotificationID.restTimer])
    add([request], completion: completion)
  }

  /// Removes the rest alert, pending or already shown, and nothing else.
  func cancelRestAlert() {
    center.removePendingNotificationRequests(withIdentifiers: [TracendNotificationID.restTimer])
    center.removeDeliveredNotifications(withIdentifiers: [TracendNotificationID.restTimer])
  }

  private func add(_ requests: [UNNotificationRequest], completion: @escaping (Error?) -> Void) {
    let group = DispatchGroup()
    let errors = FirstError()
    for request in requests {
      group.enter()
      center.add(request) { error in
        errors.record(error)
        group.leave()
      }
    }
    group.notify(queue: .main) {
      completion(errors.value)
    }
  }
}

/// Keeps the first error reported by concurrent completion handlers.
private final class FirstError: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Error?

  func record(_ error: Error?) {
    guard let error else { return }
    lock.lock()
    if stored == nil { stored = error }
    lock.unlock()
  }

  var value: Error? {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }
}
