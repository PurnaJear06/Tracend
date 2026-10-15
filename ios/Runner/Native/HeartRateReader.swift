import Flutter
import Foundation
import HealthKit

/// Reads heart-rate samples from Apple Health behind the `tracend/heart_rate`
/// channel (`lib/features/workout_hr/heart_rate_reader.dart`).
///
/// While a Watch workout runs the Watch records about one sample every five
/// seconds; outside one the samples are sparser. Apple Health syncs them to
/// this phone on its own schedule, so the app asks for a window after the
/// workout. The samples go to Dart, which turns them into one summary per set;
/// they never leave the phone. Apple Health does not say whether read access
/// was granted: with no access, or no samples, a read returns an empty list.
enum HeartRateReader {
  static let channelName = "tracend/heart_rate"

  /// The longest window one read covers. A workout lasts at most three hours.
  static let maxWindow: TimeInterval = 4 * 60 * 60

  private static let store = HKHealthStore()

  static func register(on messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestAccess":
        requestAccess(result)
      case "readSamples":
        let arguments = call.arguments as? [String: Any] ?? [:]
        guard
          let start = date(arguments["start_millis"]),
          let end = date(arguments["end_millis"]),
          end > start,
          end.timeIntervalSince(start) <= maxWindow
        else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        readSamples(from: start, to: end, result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static var heartRate: HKQuantityType? {
    HKQuantityType.quantityType(forIdentifier: .heartRate)
  }

  private static func date(_ value: Any?) -> Date? {
    guard let millis = (value as? NSNumber)?.doubleValue else { return nil }
    return Date(timeIntervalSince1970: millis / 1000)
  }

  /// Asks for read access to heart rate. Apple Health shows its sheet only
  /// while the choice is undecided; the answer says the request finished, not
  /// that access was granted.
  private static func requestAccess(_ result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable(), let type = heartRate else {
      result(false)
      return
    }
    store.requestAuthorization(toShare: nil, read: [type]) { finished, _ in
      DispatchQueue.main.async { result(finished) }
    }
  }

  /// The samples that overlap the window, oldest first, as
  /// `{"at_millis": Int, "bpm": Double}`.
  private static func readSamples(
    from start: Date,
    to end: Date,
    _ result: @escaping FlutterResult
  ) {
    guard HKHealthStore.isHealthDataAvailable(), let type = heartRate else {
      result([])
      return
    }
    let unit = HKUnit.count().unitDivided(by: .minute())
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
    let query = HKAnchoredObjectQuery(
      type: type,
      predicate: predicate,
      anchor: nil,
      limit: HKObjectQueryNoLimit
    ) { _, samples, _, _, error in
      DispatchQueue.main.async {
        if error != nil {
          result(FlutterError(code: "read_failed", message: nil, details: nil))
          return
        }
        let rows = (samples as? [HKQuantitySample] ?? [])
          .sorted { $0.startDate < $1.startDate }
          .map { sample -> [String: Any] in
            [
              "at_millis": Int((sample.startDate.timeIntervalSince1970 * 1000).rounded()),
              "bpm": sample.quantity.doubleValue(for: unit),
            ]
          }
        result(rows)
      }
    }
    store.execute(query)
  }
}
