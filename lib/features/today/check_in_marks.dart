/// The keys under which this phone remembers the day an athlete checked in,
/// or chose "Not today", for when the server's brief cannot say (offline).
/// Each athlete has their own, so another account on the same phone is never
/// shown as already checked in; sign-out and account deletion remove them.
abstract final class CheckInMarks {
  /// The key an earlier build used for every account on the phone. It is kept
  /// as the key when no athlete is signed in (no backend), and removed
  /// everywhere else.
  static const savedOnKey = 'today_check_in_saved_on';
  static const skippedOnKey = 'today_check_in_skipped_on';

  static String savedOnKeyFor(String? userId) =>
      userId == null ? savedOnKey : '$savedOnKey.$userId';

  static String skippedOnKeyFor(String? userId) =>
      userId == null ? skippedOnKey : '$skippedOnKey.$userId';
}
