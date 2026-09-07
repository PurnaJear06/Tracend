import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/features/train/workout_repository.dart';

/// Performs the `save_daily_check_in` RPC for a replayed envelope.
typedef CheckInSend =
    Future<bool> Function(
      String localDate,
      String timezone,
      String idempotencyKey,
      Map<String, dynamic> payload,
    );

/// Outcome of a replay attempt.
enum CheckInReplayOutcome {
  /// Nothing was pending (or the stored envelope was too old to parse) —
  /// nothing was sent and nothing remains stored.
  none,

  /// A pending envelope was delivered and cleared.
  delivered,

  /// A pending envelope exists but delivery failed; it stays stored for the
  /// next launch.
  retained,
}

/// Pending-check-in replay queue.
///
/// The check-in sheet persists the full check-in envelope to
/// SharedPreferences before attempting the RPC, so a completed check-in
/// survives a lost connection or app restart. Until this queue existed that
/// envelope was written and never read again: the sheet's promise "It will
/// need a connection to sync" was never kept, and the check-in was silently
/// lost once the sheet closed.
///
/// The envelope stores the answer day's `local_date` and `timezone` next to
/// the payload: a check-in belongs to the day it was answered, so a replay on
/// a later launch must never re-date it to today.
class CheckInQueue {
  CheckInQueue(this._preferences);
  final SharedPreferences _preferences;

  static const _key = 'daily_check_in_pending';

  /// Persist a check-in envelope for possible replay, returning the generated
  /// idempotency key. The same key serves both the immediate save attempt and
  /// any later replay — the server deduplicates on it.
  Future<String> enqueue({
    required Map<String, dynamic> payload,
    required String localDate,
    required String timezone,
  }) async {
    final key = newIdempotencyKey();
    await _preferences.setString(
      _key,
      jsonEncode({
        'idempotency_key': key,
        'local_date': localDate,
        'timezone': timezone,
        'payload': payload,
      }),
    );
    return key;
  }

  /// Remove the pending envelope after an immediately-successful inline save.
  Future<void> clear() => _preferences.remove(_key);

  /// Replay the pending envelope, if any.
  ///
  /// [send] performs the actual `save_daily_check_in` RPC and returns whether
  /// the server accepted the check-in. Any throw from [send] keeps the
  /// envelope stored for the next launch. A stored envelope that predates
  /// this format is discarded as stale.
  Future<CheckInReplayOutcome> replay(CheckInSend send) async {
    final stored = _preferences.getString(_key);
    if (stored == null) return CheckInReplayOutcome.none;
    final Map<String, dynamic> envelope;
    try {
      envelope = Map<String, dynamic>.from(jsonDecode(stored) as Map);
    } on FormatException {
      await _preferences.remove(_key);
      return CheckInReplayOutcome.none;
    }
    final key = envelope['idempotency_key'];
    final localDate = envelope['local_date'];
    final timezone = envelope['timezone'];
    final payload = envelope['payload'];
    if (key is! String ||
        localDate is! String ||
        timezone is! String ||
        payload is! Map) {
      await _preferences.remove(_key);
      return CheckInReplayOutcome.none;
    }
    try {
      final delivered = await send(
        localDate,
        timezone,
        key,
        Map<String, dynamic>.from(payload),
      );
      if (delivered) {
        await _preferences.remove(_key);
        return CheckInReplayOutcome.delivered;
      }
      return CheckInReplayOutcome.retained;
    } on Exception {
      return CheckInReplayOutcome.retained;
    }
  }
}
