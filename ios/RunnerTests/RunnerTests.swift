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

/// The snapshot the app writes for the widgets, read from the same fixture
/// the Flutter contract test pins (`test/contract/today_widget_snapshot_contract_test.dart`).
final class TodayWidgetSnapshotTests: XCTestCase {
  /// The fixture is a resource of the test bundle (it also runs on a
  /// device, where the source tree is not there).
  private func fixture() throws -> Data {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "today_widget_snapshot_v1", withExtension: "json")
    )
    return try Data(contentsOf: url)
  }

  private func utc() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  /// 2026-10-18 07:30 UTC, when the fixture was made.
  private let generated = Date(timeIntervalSince1970: 1_792_308_600)

  func testTheFixtureDecodes() throws {
    let snapshot = try XCTUnwrap(TodayWidgetSnapshot.decode(fixture()))

    XCTAssertEqual(snapshot.localDate, "2026-10-18")
    XCTAssertEqual(snapshot.session.state, "in_progress")
    XCTAssertEqual(snapshot.session.name, "Push day")
    XCTAssertEqual(snapshot.session.setsLogged, 2)
    XCTAssertEqual(snapshot.session.setsTotal, 7)
    XCTAssertEqual(snapshot.session.exercises.count, 2)
    XCTAssertEqual(snapshot.session.exercises.first?.target, "4 × 6–8 · 82.5 kg")
    XCTAssertEqual(snapshot.recovery, 72)
    XCTAssertEqual(snapshot.nutrition.caloriesTarget, 2400)
    XCTAssertEqual(snapshot.nutrition.proteinG, 80)
    XCTAssertEqual(snapshot.nutrition.proteinTargetG, 160)
    XCTAssertTrue(snapshot.checkInDone)
    XCTAssertEqual(snapshot.lock?.session, "Push day")
    XCTAssertEqual(snapshot.lock?.recovery, 72)
    XCTAssertEqual(snapshot.generatedAt, generated)
  }

  func testHiddenLockScreenNumbersDecodeAsNoLockSection() throws {
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: fixture()) as? [String: Any]
    )
    json["lock"] = NSNull()
    let data = try JSONSerialization.data(withJSONObject: json)

    XCTAssertNil(try XCTUnwrap(TodayWidgetSnapshot.decode(data)).lock)
  }

  func testAnUnscoredDayDecodesWithNoRecovery() throws {
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: fixture()) as? [String: Any]
    )
    json["recovery"] = NSNull()

    let data = try JSONSerialization.data(withJSONObject: json)
    XCTAssertNil(try XCTUnwrap(TodayWidgetSnapshot.decode(data)).recovery)
  }

  func testAnotherSchemaVersionIsRefused() throws {
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: fixture()) as? [String: Any]
    )
    json["schema_version"] = 2
    let data = try JSONSerialization.data(withJSONObject: json)

    XCTAssertNil(TodayWidgetSnapshot.decode(data))
  }

  func testGarbageIsRefused() {
    XCTAssertNil(TodayWidgetSnapshot.decode(Data("not json".utf8)))
    XCTAssertNil(TodayWidgetSnapshot.decode(Data("{}".utf8)))
  }

  /// A write cut short leaves a hidden temporary file; clearing takes it,
  /// and nothing else in the directory.
  func testLeftoverTemporaryFilesAreRemoved() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("widget-store-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let leftover = directory.appendingPathComponent(
      ".\(TodayWidgetStore.fileName).\(UUID().uuidString).tmp")
    let other = directory.appendingPathComponent("other.json")
    try Data("{}".utf8).write(to: leftover)
    try Data("{}".utf8).write(to: other)

    XCTAssertTrue(TodayWidgetStore.removeLeftovers(in: directory))

    XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
  }

  /// A cleared snapshot that could not be removed is an empty file; the
  /// widgets read it as no data, so they ask the athlete to open the app.
  func testAnEmptyFileIsNoData() {
    XCTAssertNil(TodayWidgetSnapshot.decode(Data()))
  }

  func testFreshWithinTwelveHoursOnTheSameDay() throws {
    let snapshot = try XCTUnwrap(TodayWidgetSnapshot.decode(fixture()))

    XCTAssertFalse(snapshot.isStale(at: generated, calendar: utc()))
    XCTAssertFalse(
      snapshot.isStale(at: generated.addingTimeInterval(3 * 3600), calendar: utc())
    )
  }

  func testStaleAfterTwelveHours() throws {
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: fixture()) as? [String: Any]
    )
    // Made at 00:30, so twelve hours later is still the same day and only
    // its age turns it stale.
    json["generated_at_millis"] = 1_792_308_600_000 - 7 * 3600 * 1000
    let snapshot = try XCTUnwrap(
      TodayWidgetSnapshot.decode(JSONSerialization.data(withJSONObject: json))
    )
    let made = snapshot.generatedAt

    XCTAssertFalse(snapshot.isStale(at: made.addingTimeInterval(11 * 3600), calendar: utc()))
    XCTAssertFalse(snapshot.isStale(at: made.addingTimeInterval(12 * 3600 - 1), calendar: utc()))
    // Exactly twelve hours is stale: the timeline's last entry is drawn then.
    XCTAssertTrue(snapshot.isStale(at: made.addingTimeInterval(12 * 3600), calendar: utc()))
    XCTAssertTrue(snapshot.isStale(at: made.addingTimeInterval(12 * 3600 + 1), calendar: utc()))
  }

  func testTheStaleMomentItselfIsStale() throws {
    let snapshot = try XCTUnwrap(TodayWidgetSnapshot.decode(fixture()))
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: fixture()) as? [String: Any]
    )
    json["generated_at_millis"] = 1_792_308_600_000 + 13 * 3600 * 1000
    let evening = try XCTUnwrap(
      TodayWidgetSnapshot.decode(JSONSerialization.data(withJSONObject: json))
    )

    // By age (07:30 + 12 h) and by midnight (made at 20:30).
    for made in [snapshot, evening] {
      let moment = made.staleDate(calendar: utc())
      XCTAssertFalse(made.isStale(at: moment.addingTimeInterval(-1), calendar: utc()))
      XCTAssertTrue(made.isStale(at: moment, calendar: utc()))
    }
  }

  func testStaleOnAnotherDay() throws {
    let snapshot = try XCTUnwrap(TodayWidgetSnapshot.decode(fixture()))
    let nextMorning = generated.addingTimeInterval(17 * 3600)  // 00:30 on the 19th, UTC

    XCTAssertTrue(snapshot.isStale(at: nextMorning, calendar: utc()))
  }

  func testStaleWhenItClaimsToComeFromTheFuture() throws {
    let snapshot = try XCTUnwrap(TodayWidgetSnapshot.decode(fixture()))

    XCTAssertTrue(snapshot.isStale(at: generated.addingTimeInterval(-3600), calendar: utc()))
  }

  func testTheStaleMomentIsTheEarlierOfAgeAndMidnight() throws {
    let snapshot = try XCTUnwrap(TodayWidgetSnapshot.decode(fixture()))

    // Made at 07:30: twelve hours is 19:30, before midnight.
    XCTAssertEqual(
      snapshot.staleDate(calendar: utc()),
      generated.addingTimeInterval(12 * 3600)
    )

    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: fixture()) as? [String: Any]
    )
    // Made at 20:30: midnight comes first.
    json["generated_at_millis"] = 1_792_308_600_000 + 13 * 3600 * 1000
    let evening = try XCTUnwrap(
      TodayWidgetSnapshot.decode(JSONSerialization.data(withJSONObject: json))
    )
    XCTAssertEqual(
      evening.staleDate(calendar: utc()),
      Date(timeIntervalSince1970: 1_792_368_000)  // 2026-10-19 00:00 UTC
    )
  }

  func testOnlyWidgetLinksOpenATab() {
    XCTAssertEqual(TracendLink(url: URL(string: "tracend://today")!), .today)
    XCTAssertEqual(TracendLink(url: URL(string: "tracend://train")!), .train)
    XCTAssertEqual(TracendLink(url: URL(string: "tracend://workout")!), .workout)
    XCTAssertNil(TracendLink(url: URL(string: "tracend://settings")!))
    XCTAssertNil(TracendLink(url: URL(string: "https://example.com/train")!))
    XCTAssertEqual(TracendLink.train.url.absoluteString, "tracend://train")
    XCTAssertEqual(TracendLink.workout.url.absoluteString, "tracend://workout")
  }
}

/// The workout Live Activity's content: what an earlier build stored, what the
/// card shows when, and what the channel's set keys turn into.
final class WorkoutActivityStateTests: XCTestCase {
  private typealias State = RestActivityAttributes.ContentState
  private let now = Date(timeIntervalSince1970: 1_792_308_600)

  private func set(
    endsAt: Date,
    target: String = "82.5 kg × 8",
    canLog: Bool = true
  ) -> State {
    State(
      endsAt: endsAt,
      nextLabel: "Set 2 of Bench press",
      exerciseName: "Bench press",
      nextExerciseOrder: 1,
      nextSetNumber: 2,
      nextSetCount: 4,
      nextExerciseName: "Bench press",
      nextTarget: target,
      nextCanLog: canLog
    )
  }

  func testAStateFromAnEarlierBuildStillDecodes() throws {
    // D1's keys only: no set count, name, target, can-log.
    let json = """
      {"endsAt": 782000000, "nextLabel": "Set 2 of Bench press", "exerciseName": "Bench press",
       "nextExerciseOrder": 1, "nextSetNumber": 2, "needsApp": false}
      """
    let state = try JSONDecoder().decode(State.self, from: Data(json.utf8))
    XCTAssertEqual(state.nextSet?.exerciseOrder, 1)
    XCTAssertEqual(state.nextSet?.setNumber, 2)
    XCTAssertNil(state.nextSetCount)
    XCTAssertEqual(state.nextExerciseName, "")
    XCTAssertEqual(state.nextTarget, "")
    XCTAssertTrue(state.nextCanLog)
    XCTAssertEqual(state.setTitle, "Bench press")
    XCTAssertEqual(state.setPosition, "Set 2")
  }

  func testTheNewKeysSurviveEncoding() throws {
    let state = set(endsAt: now)
    let again = try JSONDecoder().decode(State.self, from: JSONEncoder().encode(state))
    XCTAssertEqual(again, state)
    XCTAssertEqual(again.setPosition, "Set 2 of 4")
    XCTAssertEqual(again.nextTarget, "82.5 kg × 8")
  }

  func testARunningRestShowsTheRestAndTheSameCardTurnsIntoTheSetWhenItEnds() {
    let state = set(endsAt: now.addingTimeInterval(60))
    XCTAssertEqual(state.phase(at: now), .resting)
    XCTAssertEqual(state.phase(at: now.addingTimeInterval(60)), .set)
    // The system marks the card stale at its end, before the clock shows it.
    XCTAssertEqual(state.phase(at: now, isStale: true), .set)
  }

  func testAPassedEndWithoutASetMeansEverySetIsLogged() {
    var state = set(endsAt: now.addingTimeInterval(-1))
    state.nextExerciseOrder = nil
    state.nextSetNumber = nil
    XCTAssertEqual(state.phase(at: now), .finished)
    // A rest that still runs with no set named (an older card) is a rest.
    state.endsAt = now.addingTimeInterval(30)
    XCTAssertEqual(state.phase(at: now), .resting)
  }

  func testTheTitleFallsBackToTheRestsExercise() {
    var state = set(endsAt: now)
    state.nextExerciseName = ""
    XCTAssertEqual(state.setTitle, "Bench press")
    state.exerciseName = ""
    XCTAssertEqual(state.setTitle, "Next set")
  }

  func testTheChannelNamesTheSetByItsKeys() {
    let next = WorkoutActivityBridge.NextSet([
      "next_exercise_order": 2, "next_set_number": 3, "next_set_count": 5,
      "next_exercise_name": "Squat", "next_target": "100 kg × 5", "next_can_log": false,
    ])
    XCTAssertTrue(next.present)
    let state = next.applied(to: State(endsAt: now, nextLabel: "", exerciseName: ""))
    XCTAssertEqual(state.nextExerciseOrder, 2)
    XCTAssertEqual(state.nextSetNumber, 3)
    XCTAssertEqual(state.nextSetCount, 5)
    XCTAssertEqual(state.nextExerciseName, "Squat")
    XCTAssertEqual(state.nextTarget, "100 kg × 5")
    XCTAssertFalse(state.nextCanLog)
  }

  func testNoSetKeysClearTheSetForAShowSetAndKeepItForAnUpdate() {
    let none = WorkoutActivityBridge.NextSet([:])
    XCTAssertFalse(none.present)
    let cleared = none.applied(to: set(endsAt: now))
    XCTAssertNil(cleared.nextSet)
    XCTAssertEqual(cleared.nextTarget, "")
    let kept = none.applied(to: set(endsAt: now), clearing: false)
    XCTAssertEqual(kept.nextSet?.setNumber, 2)
    XCTAssertEqual(kept.nextTarget, "82.5 kg × 8")
  }

  func testTheCardThatSaysEverySetIsLoggedGoesAfterTwoMinutes() {
    var done = set(endsAt: now)
    done.nextExerciseOrder = nil
    done.nextSetNumber = nil
    XCTAssertEqual(
      WorkoutActivityBridge.lingerEnd(of: done, now: now.addingTimeInterval(1)),
      now.addingTimeInterval(WorkoutActivityBridge.doneLinger)
    )
  }

  func testASetOrRestCardStaysUntilItIsLeftBehind() {
    let state = set(endsAt: now)
    XCTAssertEqual(
      WorkoutActivityBridge.lingerEnd(of: state, now: now.addingTimeInterval(1)),
      now.addingTimeInterval(WorkoutActivityBridge.abandonedAfter)
    )
    // Long enough for any workout, so a set can wait for the athlete.
    XCTAssertGreaterThan(WorkoutActivityBridge.abandonedAfter, 3 * 60 * 60)
    let resting = set(endsAt: now.addingTimeInterval(90))
    XCTAssertGreaterThan(WorkoutActivityBridge.lingerEnd(of: resting, now: now), now)
  }

  func testLogSetCarriesTheSetTheCardShows() {
    let button = RestActivityButton.done(exerciseOrder: 1, setNumber: 2)
    XCTAssertEqual(
      button.channelArguments as? [String: AnyHashable],
      ["button": "done", "exercise_order": 1, "set_number": 2]
    )
  }
}
