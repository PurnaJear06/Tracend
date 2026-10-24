import 'dart:async';
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
/// one. Every send, the check-in sheet's too, goes through [replay], so an
/// older envelope never lands after a newer one.
///
/// Every change of what is stored goes through one lock per athlete and
/// changes one envelope by its idempotency key, never by writing back a list
/// read before an await: a check-in saved while a replay waits on the network
/// survives whether that replay lands or is refused. Replays run one after
/// the other.
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

  /// The end of the changes waiting for each athlete's stored envelopes.
  static final _tails = <String, Future<void>>{};

  /// The end of the replays waiting for each athlete.
  static final _replays = <String, Future<void>>{};

  Future<T> _locked<T>(Future<T> Function() action) {
    final done = Completer<T>();
    final before = _tails[_key] ?? Future<void>.value();
    final tail = before.then((_) async {
      try {
        done.complete(await action());
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    _tails[_key] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_tails[_key], tail)) _tails.remove(_key);
      }),
    );
    return done.future;
  }

  /// Persist a check-in envelope for possible replay, returning the generated
  /// idempotency key. The same key serves the send and any later replay — the
  /// server deduplicates on it.
  Future<String> enqueue({
    required Map<String, dynamic> payload,
    required String localDate,
    required String timezone,
  }) => _locked(() async {
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
  });

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

  Map<String, dynamic>? _readCurrent() =>
      _readEnvelope(_preferences.getString(_key));

  Future<void> _writeEarlier(List<Map<String, dynamic>> envelopes) async {
    if (envelopes.isEmpty) {
      await _preferences.remove(_earlierKey);
      return;
    }
    await _preferences.setString(_earlierKey, jsonEncode(envelopes));
  }

  /// Changes the envelope with [idempotencyKey], wherever it is kept, with
  /// [change]; null removes it. Other envelopes are left as they are.
  Future<void> _changeByKey(
    String idempotencyKey,
    Map<String, dynamic>? Function(Map<String, dynamic> envelope) change,
  ) async {
    final current = _readCurrent();
    if (current != null && current['idempotency_key'] == idempotencyKey) {
      final changed = change(current);
      if (changed == null) {
        await _preferences.remove(_key);
      } else {
        await _preferences.setString(_key, jsonEncode(changed));
      }
    }
    final earlier = _readEarlier();
    if (earlier.any((e) => e['idempotency_key'] == idempotencyKey)) {
      await _writeEarlier([
        for (final e in earlier)
          if (e['idempotency_key'] != idempotencyKey) e else ?change(e),
      ]);
    }
  }

  /// Remove the pending envelope with [idempotencyKey], wherever it is kept,
  /// once the server has it. A refused envelope of an earlier check-in for the
  /// same day, still waiting for the athlete to read it, is marked as
  /// superseded: the server counts this one as the day's check-in, and the
  /// older one is not sent after it.
  Future<void> clearDelivered(String idempotencyKey) => _locked(() async {
    final all = _envelopes();
    final delivered = all
        .where((e) => e['idempotency_key'] == idempotencyKey)
        .firstOrNull;
    await _changeByKey(idempotencyKey, (_) => null);
    if (delivered == null) return;
    final earlier = _readEarlier();
    final index = earlier.indexWhere(
      (e) => e['idempotency_key'] == idempotencyKey,
    );
    final before = index < 0 ? earlier : earlier.sublist(0, index);
    final superseded = {
      for (final e in before)
        if (e['pain_refused'] == true &&
            e['local_date'] == delivered['local_date'])
          e['idempotency_key'] as String,
    };
    if (superseded.isEmpty) return;
    await _writeEarlier([
      for (final e in _readEarlier())
        if (superseded.contains(e['idempotency_key']))
          {...e, 'superseded': true}
        else
          e,
    ]);
  });

  /// The server refused the pain answers of the envelope with
  /// [idempotencyKey]: it stays, marked, so the athlete is told and the rest
  /// of the check-in is not lost. [tooOld] says the refusal was for the date.
  Future<void> markPainRefused(String idempotencyKey, {required bool tooOld}) =>
      _locked(
        () => _changeByKey(idempotencyKey, (envelope) {
          return {
            ...envelope,
            'pain_refused': true,
            'pain_refused_too_old': tooOld,
          };
        }),
      );

  /// Replay the pending envelopes, if any: the earlier ones first, in order,
  /// then the latest.
  ///
  /// [send] performs the actual `save_daily_check_in` RPC and returns whether
  /// the server accepted the check-in. Any throw from [send] keeps the
  /// envelope stored for the next launch, and the ones after it wait for it.
  /// A stored envelope that predates this format is discarded as stale.
  /// Replays run one after the other, so one that starts while another waits
  /// on the network sees what that one left.
  Future<CheckInReplayOutcome> replay(CheckInSend send) {
    final done = Completer<CheckInReplayOutcome>();
    final before = _replays[_key] ?? Future<void>.value();
    final run = before.then((_) async {
      try {
        done.complete(await _replay(send));
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    _replays[_key] = run;
    unawaited(
      run.whenComplete(() {
        if (identical(_replays[_key], run)) _replays.remove(_key);
      }),
    );
    return done.future;
  }

  Future<CheckInReplayOutcome> _replay(CheckInSend send) async {
    await _adoptLegacy();
    var delivered = false;
    final tried = <String>{};
    while (true) {
      final next = _nextToSend(tried);
      if (next == null) break;
      final key = next['idempotency_key'] as String;
      tried.add(key);
      final result = await _attempt(next, send);
      switch (result.outcome) {
        case CheckInReplayOutcome.delivered:
          delivered = true;
          await clearDelivered(key);
        case CheckInReplayOutcome.painRefused:
          await markPainRefused(key, tooOld: result.tooOld);
        case CheckInReplayOutcome.retained || CheckInReplayOutcome.none:
          return CheckInReplayOutcome.retained;
      }
    }
    final current = _readCurrent();
    if (current != null && current['pain_refused'] == true) {
      return CheckInReplayOutcome.painRefused;
    }
    if (delivered) return CheckInReplayOutcome.delivered;
    return _readEarlier().any((e) => e['pain_refused'] == true)
        ? CheckInReplayOutcome.painRefused
        : CheckInReplayOutcome.none;
  }

  /// The envelope to send next: the earlier ones in order, then the latest,
  /// leaving out those the server refused and those already tried.
  Map<String, dynamic>? _nextToSend(Set<String> tried) {
    for (final envelope in [..._readEarlier(), ?_readCurrent()]) {
      if (envelope['pain_refused'] == true ||
          tried.contains(envelope['idempotency_key'])) {
        continue;
      }
      return envelope;
    }
    return null;
  }

  /// One send of [envelope]: delivered, retained, or (when the server refused
  /// its pain answers) refused.
  ///
  /// A refusal is a 22023, or the day's limit on pain reports (P0001): neither
  /// is ever accepted as it stands, so the envelope is marked and the ones after
  /// it go on. A duplicate idempotency key (23505) means the server already has
  /// the check-in.
  Future<({CheckInReplayOutcome outcome, bool tooOld})> _attempt(
    Map<String, dynamic> envelope,
    CheckInSend send,
  ) async {
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
        tooOld: false,
      );
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        return (outcome: CheckInReplayOutcome.delivered, tooOld: false);
      }
      final refused =
          error.code == '22023' ||
          (error.code == 'P0001' &&
              error.message.contains('too many pain reports'));
      if (refused && _hasPainCheck(payload)) {
        return (
          outcome: CheckInReplayOutcome.painRefused,
          tooOld: isPainDateRefusal(error),
        );
      }
      return (outcome: CheckInReplayOutcome.retained, tooOld: false);
    } on Object {
      return (outcome: CheckInReplayOutcome.retained, tooOld: false);
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
    ?_readCurrent(),
  ];

  /// The athlete has read that the server did not record the pain check.
  /// The rest of the check-in is still theirs: it is sent without the pain
  /// answers (which the server would refuse again), or kept for the next try
  /// when that send fails. A refused check-in that a newer one for the same
  /// day has replaced on the server is let go instead: sent now, it would
  /// become the day's check-in again.
  Future<void> acknowledgeRefusedPain(CheckInSend send) async {
    await _adoptLegacy();
    await _locked(() async {
      Map<String, dynamic> withoutPain(Map<String, dynamic> envelope) => {
        for (final entry in envelope.entries)
          if (!_markerKeys.contains(entry.key))
            entry.key: entry.key == 'payload'
                ? {
                    for (final item in (entry.value as Map).entries)
                      if (!checkInPainKeys.contains(item.key))
                        item.key: item.value,
                  }
                : entry.value,
      };
      await _writeEarlier([
        for (final e in _readEarlier())
          if (e['pain_refused'] != true)
            e
          else if (e['superseded'] != true)
            withoutPain(e),
      ]);
      final current = _readCurrent();
      if (current != null && current['pain_refused'] == true) {
        await _preferences.setString(_key, jsonEncode(withoutPain(current)));
      }
    });
    // What was kept without its pain answers goes in order.
    await replay(send);
  }

  static const _markerKeys = {
    'pain_refused',
    'pain_refused_too_old',
    'superseded',
  };

  /// An envelope from an older build belongs to whoever was signed in then;
  /// the first athlete to open Today takes it, as before. One that cannot be
  /// read is dropped.
  Future<void> _adoptLegacy() => _locked(() async {
    final legacy = _preferences.getString(legacyStorageKey);
    if (_key != legacyStorageKey && legacy != null) {
      if (_preferences.getString(_key) == null) {
        await _preferences.setString(_key, legacy);
      }
      await _preferences.remove(legacyStorageKey);
    }
    // A stored envelope that predates this format cannot be sent.
    if (_preferences.getString(_key) != null && _readCurrent() == null) {
      await _preferences.remove(_key);
    }
  });
}
