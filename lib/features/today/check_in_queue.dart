import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  /// The server refused the envelope's pain answers (22023) because they are
  /// older than the day before today, which it records no pain report for. It
  /// stays stored, marked, until the athlete has been told and acknowledges
  /// it ([CheckInQueue.acknowledgeRefusedPain]); a red flag is never dropped
  /// silently.
  painRefused,
}

/// The payload keys that carry the pain check.
const checkInPainKeys = [
  'pain_area',
  'pain_pattern',
  'pain_red_flags',
  'pain_cleared_by_clinician',
  'pain_followups',
];

bool _hasPainCheck(Map<dynamic, dynamic> payload) =>
    checkInPainKeys.any(payload.containsKey);

/// What the stored envelope holds that the athlete should know about.
enum CheckInPainState {
  /// No stored envelope carries a pain check.
  none,

  /// A pain check waits to be sent. The server records one only for today or
  /// yesterday, so it must reach Tracend within a day.
  waiting,

  /// The server refused the pain check as too old; it was not recorded.
  refused,
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
///
/// The envelope is kept per athlete, so a check-in waiting for one account is
/// never sent under another signed in on the same phone, and survives its own
/// athlete's sign-out until they return.
class CheckInQueue {
  CheckInQueue(this._preferences, {String? userId})
    : _key = userId == null ? legacyStorageKey : storageKeyFor(userId);
  final SharedPreferences _preferences;
  final String _key;

  /// Builds before per-athlete envelopes kept one for the device.
  static const legacyStorageKey = 'daily_check_in_pending';

  static String storageKeyFor(String userId) => '$legacyStorageKey.$userId';

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
    await _adoptLegacy();
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
    if (envelope['pain_refused'] == true) {
      return CheckInReplayOutcome.painRefused;
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
    } on PostgrestException catch (error) {
      if (error.code == '22023' && _hasPainCheck(payload)) {
        await _preferences.setString(
          _key,
          jsonEncode({...envelope, 'pain_refused': true}),
        );
        return CheckInReplayOutcome.painRefused;
      }
      return CheckInReplayOutcome.retained;
    } on Exception {
      return CheckInReplayOutcome.retained;
    }
  }

  /// Whether a stored envelope carries a pain check, and what became of it.
  CheckInPainState get painState {
    final stored = _preferences.getString(_key);
    if (stored == null) return CheckInPainState.none;
    try {
      final envelope = jsonDecode(stored);
      if (envelope is! Map) return CheckInPainState.none;
      final payload = envelope['payload'];
      if (payload is! Map || !_hasPainCheck(payload)) {
        return CheckInPainState.none;
      }
      return envelope['pain_refused'] == true
          ? CheckInPainState.refused
          : CheckInPainState.waiting;
    } on FormatException {
      return CheckInPainState.none;
    }
  }

  /// The athlete has read that the server did not record the pain check.
  /// The rest of the check-in is still theirs: it is sent without the pain
  /// answers (which the server would refuse again), or kept for the next try
  /// when that send fails.
  Future<void> acknowledgeRefusedPain(CheckInSend send) async {
    final stored = _preferences.getString(_key);
    if (stored == null) return;
    final Map<String, dynamic> envelope;
    try {
      envelope = Map<String, dynamic>.from(jsonDecode(stored) as Map);
    } on FormatException {
      await _preferences.remove(_key);
      return;
    }
    final payload = envelope['payload'];
    final key = envelope['idempotency_key'];
    final localDate = envelope['local_date'];
    final timezone = envelope['timezone'];
    if (payload is! Map ||
        key is! String ||
        localDate is! String ||
        timezone is! String) {
      await _preferences.remove(_key);
      return;
    }
    final stripped = {
      for (final entry in payload.entries)
        if (!checkInPainKeys.contains(entry.key)) entry.key: entry.value,
    };
    final kept = {
      for (final entry in envelope.entries)
        if (entry.key != 'pain_refused') entry.key: entry.value,
      'payload': stripped,
    };
    await _preferences.setString(_key, jsonEncode(kept));
    try {
      if (await send(
        localDate,
        timezone,
        key,
        Map<String, dynamic>.from(stripped),
      )) {
        await _preferences.remove(_key);
      }
    } on Exception catch (error) {
      debugPrint('Non-critical error: check-in kept without pain: $error');
    }
  }

  /// An envelope from an older build belongs to whoever was signed in then;
  /// the first athlete to open Today takes it, as before.
  Future<void> _adoptLegacy() async {
    if (_key == legacyStorageKey) return;
    final legacy = _preferences.getString(legacyStorageKey);
    if (legacy == null) return;
    if (_preferences.getString(_key) == null) {
      await _preferences.setString(_key, legacy);
    }
    await _preferences.remove(legacyStorageKey);
  }
}
