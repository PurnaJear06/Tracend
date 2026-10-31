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

/// A queued check-in the server refused for good: it is dropped, and the
/// athlete is told.
class CheckInRefusal {
  const CheckInRefusal(this.localDate, this.error);

  /// The day the check-in was answered.
  final String localDate;
  final PostgrestException error;
}

/// What became of one envelope in a replay.
enum CheckInFate {
  /// The server has it; it left the queue.
  delivered,

  /// It could not be sent (offline, a server error); it stays queued.
  retained,

  /// The server refused its pain answers. It stays stored, marked, until the
  /// athlete has been told and acknowledges it
  /// ([CheckInQueue.acknowledgeRefusedPain]); a red flag is never dropped
  /// silently.
  painRefused,

  /// The server refused it for good; it was dropped and reported.
  refused,
}

/// What one replay did with the queue.
class CheckInReplay {
  const CheckInReplay({
    this.delivered = const [],
    this.retained = const [],
    this.refused = const [],
    this.fates = const {},
  });

  /// Days whose check-in the server accepted; each is cleared.
  final List<String> delivered;

  /// Days whose check-in could not be sent (offline, a server error) and the
  /// ones that wait behind it; each stays queued for the next resume or launch.
  final List<String> retained;

  /// Check-ins the server refused for good; each is dropped.
  final List<CheckInRefusal> refused;

  /// What became of each envelope this replay tried, by idempotency key.
  final Map<String, CheckInFate> fates;

  bool get deliveredAny => delivered.isNotEmpty;
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

/// What the stored envelopes hold that the athlete should know about.
enum CheckInPainState {
  /// No stored envelope carries a pain check.
  none,

  /// A pain check waits to be sent. The server records one only for today or
  /// yesterday, so it must reach Tracend within a day.
  waiting,

  /// The server refused the pain check; it was not recorded.
  refused,
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
///
/// A new check-in replaces the envelope that waits for its day, with one
/// exception: an envelope that carries a pain check is never replaced and
/// lost. It moves to a list of earlier envelopes that are sent first, in the
/// order they were made (the server counts the last one sent as the day's
/// check-in), so a red flag in a check-in that never got through is not
/// overwritten by a second one. Every send, the check-in sheet's too, goes
/// through [replay], so an older envelope never lands after a newer one.
///
/// Every change of what is stored goes through one lock per athlete and
/// changes one envelope by its idempotency key, never by writing back a list
/// read before an await: a check-in saved while a replay waits on the network
/// survives whether that replay lands or is refused. Replays run one after
/// the other.
class CheckInQueue {
  CheckInQueue(this._preferences, {String? userId})
    : _key = userId == null ? queueStorageKey : queueStorageKeyFor(userId),
      _earlierKey = earlierKeyFor(userId ?? ''),
      _singleSlotKeys = [
        if (userId != null) singleSlotKeyFor(userId),
        singleSlotKey,
      ];
  final SharedPreferences _preferences;
  final String _key;
  final String _earlierKey;

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

  /// The earlier envelopes with a pain check that a newer check-in did not
  /// replace.
  static String earlierKeyFor(String userId) =>
      '$singleSlotKey.earlier.$userId';

  /// Whether the server read the check-in and said no for good, so retrying
  /// cannot change the answer: 22023 invalid parameter, 22P02 bad text, 23514
  /// check violation, or P0001 for the day's limit on pain reports. A lost
  /// connection, a server error or a sign-in that lapsed (42501) is not one.
  static bool isFinalRefusal(PostgrestException error) =>
      const {'22023', '22P02', '23514'}.contains(error.code) ||
      (error.code == 'P0001' &&
          error.message.contains('too many pain reports'));

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
    await _migrate();
    final entries = _readEntries();
    await _keepEarlier(entries[localDate]);
    final key = newIdempotencyKey();
    entries[localDate] = {
      'idempotency_key': key,
      'local_date': localDate,
      'timezone': timezone,
      'payload': payload,
    };
    await _writeEntries(entries);
    return key;
  });

  /// Moves [waiting], the envelope about to be replaced, to the earlier ones
  /// when it carries a pain check, so the one about to be written does not
  /// overwrite it.
  Future<void> _keepEarlier(Map<String, dynamic>? waiting) async {
    if (waiting == null || !_hasPainCheck(waiting['payload'] as Map)) return;
    final earlier = _readEarlier();
    if (earlier.any(
      (e) => e['idempotency_key'] == waiting['idempotency_key'],
    )) {
      return;
    }
    await _writeEarlier([...earlier, waiting]);
  }

  /// The days with a check-in waiting, oldest first.
  Future<List<String>> pendingDays() => _locked(() async {
    await _migrate();
    return {
      ..._readEntries().keys,
      for (final e in _readEarlier()) e['local_date'] as String,
    }.toList()..sort();
  });

  /// Moves any single envelope an earlier build kept into the keyed list. An
  /// envelope that cannot be read, or that predates the stored format, is
  /// discarded as stale. Call it inside the lock.
  Future<void> _migrate() async {
    final stored = <String>[];
    final entries = _readEntries();
    for (final oldKey in _singleSlotKeys) {
      final value = _preferences.getString(oldKey);
      if (value == null) continue;
      stored.add(oldKey);
      final entry = _readEnvelope(value);
      if (entry != null) {
        entries.putIfAbsent(entry['local_date'] as String, () => entry);
      }
    }
    if (stored.isEmpty) return;
    // The keyed list is written first, and the old keys go only once that
    // write succeeded: a failure or an interruption leaves them to be read
    // again, and the move is repeatable.
    if (!await _writeEntries(entries)) return;
    for (final oldKey in stored) {
      await _preferences.remove(oldKey);
    }
  }

  /// The keyed list: each day's waiting envelope.
  Map<String, Map<String, dynamic>> _readEntries() {
    final entries = <String, Map<String, dynamic>>{};
    final stored = _preferences.getString(_key);
    if (stored == null) return entries;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return entries;
      for (final item in decoded.values) {
        final envelope = _readEnvelope(item);
        if (envelope != null) {
          entries[envelope['local_date'] as String] = envelope;
        }
      }
    } on FormatException {
      return entries;
    }
    return entries;
  }

  Future<bool> _writeEntries(Map<String, Map<String, dynamic>> entries) =>
      entries.isEmpty
      ? _preferences.remove(_key)
      : _preferences.setString(_key, jsonEncode(entries));

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

  /// Changes the envelope with [idempotencyKey], wherever it is kept, with
  /// [change]; null removes it. Other envelopes are left as they are.
  Future<void> _changeByKey(
    String idempotencyKey,
    Map<String, dynamic>? Function(Map<String, dynamic> envelope) change,
  ) async {
    final entries = _readEntries();
    for (final day in entries.keys.toList()) {
      if (entries[day]!['idempotency_key'] != idempotencyKey) continue;
      final changed = change(entries[day]!);
      if (changed == null) {
        entries.remove(day);
      } else {
        entries[day] = changed;
      }
      await _writeEntries(entries);
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
    final earlier = _readEarlier();
    final delivered = _envelopes()
        .where((e) => e['idempotency_key'] == idempotencyKey)
        .firstOrNull;
    await _changeByKey(idempotencyKey, (_) => null);
    if (delivered == null) return;
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

  /// Drops the envelope with [idempotencyKey]: the server refused it for good.
  Future<void> _drop(String idempotencyKey) =>
      _locked(() => _changeByKey(idempotencyKey, (_) => null));

  /// Replay the pending envelopes, if any: the earlier ones first, in order,
  /// then each day's, oldest day first.
  ///
  /// [send] performs the actual `save_daily_check_in` RPC and returns whether
  /// the server accepted the check-in. An accepted one is cleared. A refusal
  /// for good (see [isFinalRefusal]) drops an envelope and is reported back;
  /// if the envelope carries a pain check it is kept, marked, instead, so the
  /// athlete is told. Any other throw keeps the envelope for the next resume
  /// or launch and stops the replay, since the rest would fail the same way.
  /// Replays run one after the other, so one that starts while another waits
  /// on the network sees what that one left.
  Future<CheckInReplay> replay(CheckInSend send) {
    final done = Completer<CheckInReplay>();
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

  Future<CheckInReplay> _replay(CheckInSend send) async {
    await _locked(_migrate);
    final delivered = <String>[];
    final refused = <CheckInRefusal>[];
    final fates = <String, CheckInFate>{};
    final tried = <String>{};
    var stopped = false;
    while (!stopped) {
      final next = _nextToSend(tried);
      if (next == null) break;
      final key = next['idempotency_key'] as String;
      final day = next['local_date'] as String;
      tried.add(key);
      final result = await _attempt(next, send);
      fates[key] = result.fate;
      switch (result.fate) {
        case CheckInFate.delivered:
          delivered.add(day);
          await clearDelivered(key);
        case CheckInFate.painRefused:
          await markPainRefused(key, tooOld: result.tooOld);
        case CheckInFate.refused:
          refused.add(CheckInRefusal(day, result.error!));
          await _drop(key);
        case CheckInFate.retained:
          stopped = true;
      }
    }
    return CheckInReplay(
      delivered: delivered,
      retained: stopped
          ? [for (final e in _sendable()) e['local_date'] as String]
          : const [],
      refused: refused,
      fates: fates,
    );
  }

  /// The envelopes still to be sent, in the order they go: the earlier ones,
  /// then each day's, oldest day first. Those the server refused wait for the
  /// athlete instead.
  List<Map<String, dynamic>> _sendable() {
    final entries = _readEntries();
    return [
      for (final e in [
        ..._readEarlier(),
        for (final day in entries.keys.toList()..sort()) entries[day]!,
      ])
        if (e['pain_refused'] != true) e,
    ];
  }

  /// The envelope to send next, leaving out those already tried.
  Map<String, dynamic>? _nextToSend(Set<String> tried) {
    for (final envelope in _sendable()) {
      if (!tried.contains(envelope['idempotency_key'])) return envelope;
    }
    return null;
  }

  /// One send of [envelope]: delivered, retained, refused for good, or (when
  /// the server refused its pain answers) kept for the athlete to be told.
  ///
  /// A duplicate idempotency key (23505) means the server already has the
  /// check-in.
  Future<({CheckInFate fate, bool tooOld, PostgrestException? error})> _attempt(
    Map<String, dynamic> envelope,
    CheckInSend send,
  ) async {
    final payload = envelope['payload'] as Map;
    try {
      final accepted = await send(
        envelope['local_date'] as String,
        envelope['timezone'] as String,
        envelope['idempotency_key'] as String,
        Map<String, dynamic>.from(payload),
      );
      return (
        fate: accepted ? CheckInFate.delivered : CheckInFate.retained,
        tooOld: false,
        error: null,
      );
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        return (fate: CheckInFate.delivered, tooOld: false, error: null);
      }
      if (!isFinalRefusal(error)) {
        return (fate: CheckInFate.retained, tooOld: false, error: null);
      }
      return _hasPainCheck(payload)
          ? (
              fate: CheckInFate.painRefused,
              tooOld: isPainDateRefusal(error),
              error: null,
            )
          : (fate: CheckInFate.refused, tooOld: false, error: error);
    } on Object {
      return (fate: CheckInFate.retained, tooOld: false, error: null);
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
    ..._readEntries().values,
  ];

  /// The athlete has read that the server did not record the pain check.
  /// The rest of the check-in is still theirs: it is sent without the pain
  /// answers (which the server would refuse again), or kept for the next try
  /// when that send fails. A refused check-in that a newer one for the same
  /// day has replaced on the server is let go instead: sent now, it would
  /// become the day's check-in again.
  Future<void> acknowledgeRefusedPain(CheckInSend send) async {
    await _locked(() async {
      await _migrate();
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
      final entries = _readEntries();
      var changed = false;
      for (final day in entries.keys.toList()) {
        if (entries[day]!['pain_refused'] != true) continue;
        entries[day] = withoutPain(entries[day]!);
        changed = true;
      }
      if (changed) await _writeEntries(entries);
    });
    // What was kept without its pain answers goes in order.
    await replay(send);
  }

  static const _markerKeys = {
    'pain_refused',
    'pain_refused_too_old',
    'superseded',
  };
}
