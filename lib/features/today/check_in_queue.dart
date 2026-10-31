import 'dart:convert';

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

/// A queued check-in the server refused for good: it is dropped, and the
/// athlete is told.
class CheckInRefusal {
  const CheckInRefusal(this.localDate, this.error);

  /// The day the check-in was answered.
  final String localDate;
  final PostgrestException error;
}

/// What one replay did with the queue.
class CheckInReplay {
  const CheckInReplay({
    this.delivered = const [],
    this.retained = const [],
    this.refused = const [],
  });

  /// Days whose check-in the server accepted; each is cleared.
  final List<String> delivered;

  /// Days whose check-in could not be sent (offline, a server error); each
  /// stays queued for the next resume or launch.
  final List<String> retained;

  /// Check-ins the server refused for good; each is dropped.
  final List<CheckInRefusal> refused;

  bool get deliveredAny => delivered.isNotEmpty;
}

/// Pending-check-in replay queue.
///
/// The check-in sheet persists the full check-in envelope to
/// SharedPreferences before attempting the RPC, so a completed check-in
/// survives a lost connection or app restart. Today replays the queue at
/// launch and every time the app comes back to the front.
///
/// The queue is keyed by the answer day's `local_date`: a check-in belongs to
/// the day it was answered, so a replay on a later day never re-dates it to
/// today, and a check-in from Monday waits beside Tuesday's instead of being
/// overwritten by it. Answering the same day again replaces that day's entry.
///
/// The queue is kept per athlete, so a check-in waiting for one account is
/// never sent under another signed in on the same phone, and survives its own
/// athlete's sign-out until they return.
class CheckInQueue {
  CheckInQueue(this._preferences, {String? userId})
    : _key = userId == null ? queueStorageKey : queueStorageKeyFor(userId),
      _singleSlotKeys = [
        if (userId != null) singleSlotKeyFor(userId),
        singleSlotKey,
      ];
  final SharedPreferences _preferences;
  final String _key;

  /// Where earlier builds kept their one envelope: the athlete's own key,
  /// then the device-wide one older builds used.
  final List<String> _singleSlotKeys;

  /// The keyed list for a phone with no signed-in athlete.
  static const queueStorageKey = 'daily_check_in_queue';

  static String queueStorageKeyFor(String userId) => '$queueStorageKey.$userId';

  /// Builds that kept one envelope per device used this key, and one per
  /// athlete used `singleSlotKeyFor`. Both are moved into the keyed list.
  static const singleSlotKey = 'daily_check_in_pending';

  static String singleSlotKeyFor(String userId) => '$singleSlotKey.$userId';

  /// A refusal that retrying cannot change: the server read the check-in and
  /// said no (22023 invalid parameter, 22P02 bad text, 23514 check violation,
  /// P0001 a rule such as the pain-report limit). A lost connection, a server
  /// error or a sign-in that lapsed (42501) is not one.
  static const finalRefusalCodes = {'22023', '22P02', '23514', 'P0001'};

  /// Persist a check-in envelope for possible replay, returning the generated
  /// idempotency key. The same key serves both the immediate save attempt and
  /// any later replay — the server deduplicates on it.
  Future<String> enqueue({
    required Map<String, dynamic> payload,
    required String localDate,
    required String timezone,
  }) async {
    final key = newIdempotencyKey();
    final entries = await _read();
    entries[localDate] = {
      'idempotency_key': key,
      'local_date': localDate,
      'timezone': timezone,
      'payload': payload,
    };
    await _write(entries);
    return key;
  }

  /// Remove the envelope of [localDate] after an immediately-successful inline
  /// save. A newer answer for the same day (another key) stays.
  Future<void> clear({
    required String localDate,
    required String idempotencyKey,
  }) async {
    final entries = await _read();
    final entry = entries[localDate];
    if (entry == null || entry['idempotency_key'] != idempotencyKey) return;
    entries.remove(localDate);
    await _write(entries);
  }

  /// The days with a check-in waiting, oldest first.
  Future<List<String>> pendingDays() async =>
      (await _read()).keys.toList()..sort();

  /// Replay every pending envelope, oldest day first.
  ///
  /// [send] performs the actual `save_daily_check_in` RPC and returns whether
  /// the server accepted the check-in. An accepted one is cleared. A
  /// `PostgrestException` whose code is in [finalRefusalCodes] drops that
  /// envelope and is reported back; any other throw keeps it for the next
  /// resume or launch and stops the replay, since the rest would fail the
  /// same way.
  Future<CheckInReplay> replay(CheckInSend send) async {
    final entries = await _read();
    final days = entries.keys.toList()..sort();
    final delivered = <String>[];
    final retained = <String>[];
    final refused = <CheckInRefusal>[];
    var stopped = false;
    for (final day in days) {
      if (stopped) {
        retained.add(day);
        continue;
      }
      final entry = entries[day]!;
      try {
        final accepted = await send(
          day,
          entry['timezone'] as String,
          entry['idempotency_key'] as String,
          Map<String, dynamic>.from(entry['payload'] as Map),
        );
        if (accepted) {
          delivered.add(day);
          await _drop(day, entry['idempotency_key'] as String);
        } else {
          retained.add(day);
          stopped = true;
        }
      } on PostgrestException catch (error) {
        if (finalRefusalCodes.contains(error.code)) {
          refused.add(CheckInRefusal(day, error));
          await _drop(day, entry['idempotency_key'] as String);
        } else {
          retained.add(day);
          stopped = true;
        }
      } on Exception {
        retained.add(day);
        stopped = true;
      }
    }
    return CheckInReplay(
      delivered: delivered,
      retained: retained,
      refused: refused,
    );
  }

  /// Removes [localDate]'s envelope if it is still the one with [key]; a
  /// newer answer saved while the replay ran stays.
  Future<void> _drop(String localDate, String key) =>
      clear(localDate: localDate, idempotencyKey: key);

  /// The keyed list, after moving any single envelope an earlier build kept
  /// into it. An envelope that cannot be read, or that predates the stored
  /// format, is discarded as stale.
  Future<Map<String, Map<String, dynamic>>> _read() async {
    final entries = _decodeList(_preferences.getString(_key));
    final stored = <String>[];
    for (final oldKey in _singleSlotKeys) {
      final value = _preferences.getString(oldKey);
      if (value == null) continue;
      stored.add(oldKey);
      final entry = _decodeEnvelope(value);
      if (entry != null) {
        entries.putIfAbsent(entry['local_date'] as String, () => entry);
      }
    }
    if (stored.isEmpty) return entries;
    // The keyed list is written first, and the old keys go only once that
    // write succeeded: a failure or an interruption leaves them to be read
    // again, and the move is repeatable.
    if (!await _write(entries)) return entries;
    for (final oldKey in stored) {
      await _preferences.remove(oldKey);
    }
    return entries;
  }

  Future<bool> _write(Map<String, Map<String, dynamic>> entries) =>
      entries.isEmpty
      ? _preferences.remove(_key)
      : _preferences.setString(_key, jsonEncode(entries));

  Map<String, Map<String, dynamic>> _decodeList(String? stored) {
    final entries = <String, Map<String, dynamic>>{};
    if (stored == null) return entries;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return entries;
      for (final entry in decoded.values) {
        final valid = entry is Map ? _validEnvelope(entry) : null;
        if (valid != null) entries[valid['local_date'] as String] = valid;
      }
    } on FormatException {
      return entries;
    }
    return entries;
  }

  Map<String, dynamic>? _decodeEnvelope(String stored) {
    try {
      final decoded = jsonDecode(stored);
      return decoded is Map ? _validEnvelope(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic>? _validEnvelope(Map<dynamic, dynamic> raw) {
    final entry = Map<String, dynamic>.from(raw);
    if (entry['idempotency_key'] is! String ||
        entry['local_date'] is! String ||
        entry['timezone'] is! String ||
        entry['payload'] is! Map) {
      return null;
    }
    return entry;
  }
}
