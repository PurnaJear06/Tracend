import UserNotifications
import XCTest

@testable import Runner

/// Records what the scheduler asks of the notification center.
private final class RecordingCenter: LocalNotificationCenter {
  var added: [UNNotificationRequest] = []
  var removedPending: [[String]] = []
  var removedDelivered: [[String]] = []

  func add(_ request: UNNotificationRequest, completion: @escaping @Sendable (Error?) -> Void) {
    added.append(request)
    completion(nil)
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    removedPending.append(identifiers)
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    removedDelivered.append(identifiers)
  }
}

class RunnerTests: XCTestCase {
  private func replaceReminders(
    _ scheduler: TracendNotificationScheduler,
    dailyCheckIn: Bool,
    weeklyReview: Bool
  ) {
    let done = expectation(description: "reminders replaced")
    scheduler.replaceReminders(dailyCheckIn: dailyCheckIn, weeklyReview: weeklyReview) { error in
      XCTAssertNil(error)
      done.fulfill()
    }
    wait(for: [done], timeout: 1)
  }

  private func scheduleRest(_ scheduler: TracendNotificationScheduler, seconds: Int) {
    let done = expectation(description: "rest alert scheduled")
    scheduler.scheduleRestAlert(seconds: seconds) { error in
      XCTAssertNil(error)
      done.fulfill()
    }
    wait(for: [done], timeout: 1)
  }

  func testReminderReconciliationLeavesTheRestAlertAlone() {
    let center = RecordingCenter()
    let scheduler = TracendNotificationScheduler(center: center)
    scheduleRest(scheduler, seconds: 90)
    center.removedPending = []

    replaceReminders(scheduler, dailyCheckIn: true, weeklyReview: false)
    replaceReminders(scheduler, dailyCheckIn: false, weeklyReview: false)

    let removed = center.removedPending.flatMap { $0 }
    XCTAssertFalse(removed.contains(TracendNotificationID.restTimer))
    XCTAssertEqual(Set(removed), Set(TracendNotificationID.reminders))
    XCTAssertTrue(center.removedDelivered.isEmpty)
    XCTAssertEqual(
      center.added.map(\.identifier),
      [TracendNotificationID.restTimer, TracendNotificationID.dailyCheckIn]
    )
  }

  func testSchedulingTwiceReplacesTheOneRestAlert() {
    let center = RecordingCenter()
    let scheduler = TracendNotificationScheduler(center: center)

    scheduleRest(scheduler, seconds: 90)
    scheduleRest(scheduler, seconds: 120)

    XCTAssertEqual(
      center.added.map(\.identifier),
      [TracendNotificationID.restTimer, TracendNotificationID.restTimer]
    )
    XCTAssertEqual(
      center.removedPending,
      [[TracendNotificationID.restTimer], [TracendNotificationID.restTimer]]
    )
    let trigger = center.added.last?.trigger as? UNTimeIntervalNotificationTrigger
    XCTAssertEqual(trigger?.timeInterval, 120)
    XCTAssertEqual(trigger?.repeats, false)
  }

  func testRestAlertTextIsGeneric() {
    let center = RecordingCenter()
    let scheduler = TracendNotificationScheduler(center: center)

    scheduleRest(scheduler, seconds: 60)

    let content = center.added.first?.content
    XCTAssertEqual(content?.title, "Rest timer finished")
    XCTAssertEqual(content?.body, "")
    XCTAssertEqual(content?.subtitle, "")
  }

  func testCancellingRemovesOnlyTheRestAlert() {
    let center = RecordingCenter()
    let scheduler = TracendNotificationScheduler(center: center)

    scheduler.cancelRestAlert()

    XCTAssertEqual(center.removedPending, [[TracendNotificationID.restTimer]])
    XCTAssertEqual(center.removedDelivered, [[TracendNotificationID.restTimer]])
  }
}
