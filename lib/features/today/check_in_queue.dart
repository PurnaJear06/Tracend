import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/readiness/pain_check.dart';
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
///
/// A new check-in replaces the envelope that waits, with one exception: an
/// envelope that carries a pain check is never replaced and lost. It moves to
/// a list of earlier envelopes that are sent first, in the order they were
/// made (the server counts the last one sent as the day's check-in), so a red
/// flag in a check-in that never got through is not overwritten by a second
/// one.
class CheckInQueue {
  CheckInQueue(this._preferences, {String? userId})
    : _key = userId == null ? legacyStorageKey : storageKeyFor(userId),
      _earlierKey = userId == null ? earlierKeyFor('') : earlierKeyFor(userId);
  final SharedPreferences _preferences;
  final String _key;
  final String _earlierKey;

  /// Builds before per-athlete envelopes kept one for the device.
  static const legacyStorageKey = 'daily_check_in_pending';

  static String storageKeyFor(String userId) => '$legacyStorageKey.$userId';

  /// The earlier envelopes with a pain check that a newer check-in did not
  /// replace.
  static String earlierKeyFor(String userId) =>
      '$legacyStorageKey.earlier.$userId';

  /// Persist a check-in envelope for possible replay, returning the generated
  /// idempotency key. The same key serves both the immediate save attempt and
  /// any later replay — the server deduplicates on it.
  Future<String> enqueue({
    required Map<String, dynamic> payload,
    required String localDate,
    required String timezone,
  }) async {
    await _keepEarlier();
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

  /// Moves the waiting envelope to the earlier ones when it carries a pain
  /// check, so the one about to be written does not overwrite it.
  Future<void> _keepEarlier() async {
    final waiting = _readEnvelope(_preferences.getString(_key));
    if (waiting == null || !_hasPainCheck(waiting['payload'] as Map)) return;
    final earlier = _readEarlier();
    if (earlier.any(
      (e) => e['idempotency_key'] == waiting['idempotency_key'],
    )) {
      return;
    }
    await _writeEarlier([...earlier, waiting]);
  }

  /// A stored envelope that has all it needs, else null.
  static Map<String, dynamic>? _readEnvelope(Object? stored) {
    try {
      final decoded = stored is String ? jsonDecode(stored) : stored;
      if (decoded is! Map) return null;
      final envelope = Map<String, dynamic>.from(decoded);
      if (envelope['idempotency_key'] is! String ||
          envelope['local_date'] is! String ||
          envelope['timezone'] is! String ||
          envelope['payload'] is! Map) {
        return null;
      }
      return envelope;
    } on FormatException {
      return null;
    }
  }

  List<Map<String, dynamic>> _readEarlier() {
    final stored = _preferences.getString(_earlierKey);
    if (stored == null) return const [];
    try {
      final list = jsonDecode(stored);
      if (list is! List) return const [];
      return [for (final item in list) ?_readEnvelope(item)];
    } on FormatException {
      return const [];
    }
  }

  Future<void> _writeEarlier(List<Map<String, dynamic>> envelopes) async {
    if (envelopes.isEmpty) {
      await _preferences.remove(_earlierKey);
      return;
    }
    await _preferences.setString(_earlierKey, jsonEncode(envelopes));
  }

  /// Remove the pending envelope with [idempotencyKey], wherever it is kept,
  /// once the server has it.
  Future<void> clearDelivered(String idempotencyKey) async {
    final current = _readEnvelope(_preferences.getString(_key));
    if (current != null && current['idempotency_key'] == idempotencyKey) {
      await _preferences.remove(_key);
    }
    final earlier = _readEarlier();
    if (earlier.any((e) => e['idempotency_key'] == idempotencyKey)) {
      await _writeEarlier([
        for (final e in earlier)
          if (e['idempotency_key'] != idempotencyKey) e,
      ]);
    }
  }

  /// The server refused the pain answers of the envelope with
  /// [idempotencyKey] (22023): it stays, marked, so the athlete is told and
  /// the rest of the check-in is not lost. [tooOld] says the refusal was for
  /// the date.
  Future<void> markPainRefused(
    String idempotencyKey, {
    required bool tooOld,
  }) async {
    Map<String, dynamic> marked(Map<String, dynamic> envelope) => {
      ...envelope,
      'pain_refused': true,
      'pain_refused_too_old': tooOld,
    };
    final current = _readEnvelope(_preferences.getString(_key));
    if (current != null && current['idempotency_key'] == idempotencyKey) {
      await _preferences.setString(_key, jsonEncode(marked(current)));
    }
    final earlier = _readEarlier();
    if (earlier.any((e) => e['idempotency_key'] == idempotencyKey)) {
      await _writeEarlier([
        for (final e in earlier)
          if (e['idempotency_key'] == idempotencyKey) marked(e) else e,
      ]);
    }
  }

  /// Replay the pending envelopes, if any: the earlier ones with a pain check
  /// first, in order, then the latest.
  ///
  /// [send] performs the actual `save_daily_check_in` RPC and returns whether
  /// the server accepted the check-in. Any throw from [send] keeps the
  /// envelope stored for the next launch, and the ones after it wait for it.
  /// A stored envelope that predates this format is discarded as stale.
  Future<CheckInReplayOutcome> replay(CheckInSend send) async {
    await _adoptLegacy();
    var earlierDelivered = false;
    var earlier = _readEarlier();
    for (final envelope in List.of(earlier)) {
      if (envelope['pain_refused'] == true) continue;
      final result = await _attempt(envelope, send);
      switch (result.outcome) {
        case CheckInReplayOutcome.delivered:
          earlierDelivered = true;
          earlier = [
            for (final e in earlier)
              if (e['idempotency_key'] != envelope['idempotency_key']) e,
          ];
        case CheckInReplayOutcome.painRefused:
          earlier = [
            for (final e in earlier)
              if (e['idempotency_key'] == envelope['idempotency_key'])
                result.envelope
              else
                e,
          ];
        default:
          await _writeEarlier(earlier);
          return CheckInReplayOutcome.retained;
      }
    }
    await _writeEarlier(earlier);
    final stored = _preferences.getString(_key);
    if (stored == null) {
      return earlierDelivered
          ? CheckInReplayOutcome.delivered
          : CheckInReplayOutcome.none;
    }
    final envelope = _readEnvelope(stored);
    if (envelope == null) {
      await _preferences.remove(_key);
      return earlierDelivered
          ? CheckInReplayOutcome.delivered
          : CheckInReplayOutcome.none;
    }
    if (envelope['pain_refused'] == true) {
      return CheckInReplayOutcome.painRefused;
    }
    final result = await _attempt(envelope, send);
    switch (result.outcome) {
      case CheckInReplayOutcome.delivered:
        await _preferences.remove(_key);
      case CheckInReplayOutcome.painRefused:
        await _preferences.setString(_key, jsonEncode(result.envelope));
      default:
        break;
    }
    return result.outcome;
  }

  /// One send of [envelope]: delivered, retained, or (when the server refused
  /// its pain answers) the envelope marked as refused.
  Future<({CheckInReplayOutcome outcome, Map<String, dynamic> envelope})>
  _attempt(Map<String, dynamic> envelope, CheckInSend send) async {
    final payload = envelope['payload'] as Map;
    try {
      final delivered = await send(
        envelope['local_date'] as String,
        envelope['timezone'] as String,
        envelope['idempotency_key'] as String,
        Map<String, dynamic>.from(payload),
      );
      return (
        outcome: delivered
            ? CheckInReplayOutcome.delivered
            : CheckInReplayOutcome.retained,
        envelope: envelope,
      );
    } on PostgrestException catch (error) {
      if (error.code == '22023' && _hasPainCheck(payload)) {
        return (
          outcome: CheckInReplayOutcome.painRefused,
          envelope: {
            ...envelope,
            'pain_refused': true,
            'pain_refused_too_old': isPainDateRefusal(error),
          },
        );
      }
      return (outcome: CheckInReplayOutcome.retained, envelope: envelope);
    } on Exception {
      return (outcome: CheckInReplayOutcome.retained, envelope: envelope);
    }
  }

  /// Whether a stored envelope carries a pain check, and what became of it.
  CheckInPainState get painState {
    var waiting = false;
    for (final envelope in _envelopes()) {
      if (!_hasPainCheck(envelope['payload'] as Map)) continue;
      if (envelope['pain_refused'] == true) return CheckInPainState.refused;
      waiting = true;
    }
    return waiting ? CheckInPainState.waiting : CheckInPainState.none;
  }

  /// Every pain check the server refused was refused only for its date.
  bool get painRefusedTooOld => _envelopes().every(
    (envelope) =>
        envelope['pain_refused'] != true ||
        envelope['pain_refused_too_old'] != false,
  );

  /// The stored envelopes, the earlier ones first.
  List<Map<String, dynamic>> _envelopes() => [
    ..._readEarlier(),
    ?_readEnvelope(_preferences.getString(_key)),
  ];

  /// The athlete has read that the server did not record the pain check.
  /// The rest of the check-in is still theirs: it is sent without the pain
  /// answers (which the server would refuse again), or kept for the next try
  /// when that send fails.
  Future<void> acknowledgeRefusedPain(CheckInSend send) async {
    await _adoptLegacy();
    Map<String, dynamic> withoutPain(Map<String, dynamic> envelope) => {
      for (final entry in envelope.entries)
        if (entry.key != 'pain_refused' && entry.key != 'pain_refused_too_old')
          entry.key: entry.key == 'payload'
              ? {
                  for (final item in (entry.value as Map).entries)
                    if (!checkInPainKeys.contains(item.key))
                      item.key: item.value,
                }
              : entry.value,
    };
    final earlier = [
      for (final e in _readEarlier())
        if (e['pain_refused'] == true) withoutPain(e) else e,
    ];
    await _writeEarlier(earlier);
    final stored = _preferences.getString(_key);
    if (stored != null && _readEnvelope(stored) == null) {
      await _preferences.remove(_key);
    }
    final current = _readEnvelope(stored);
    if (current != null && current['pain_refused'] == true) {
      await _preferences.setString(_key, jsonEncode(withoutPain(current)));
    }
    // What was kept without its pain answers goes in order.
    await replay(send);
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
