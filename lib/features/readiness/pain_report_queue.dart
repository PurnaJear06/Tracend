import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/features/readiness/pain_check.dart';

/// A pain report from a workout that waits on this phone until it can be sent.
@immutable
class QueuedPainReport {
  const QueuedPainReport({
    required this.report,
    this.refused = false,
    this.tooOld = false,
  });

  final PainReport report;

  /// The server refused it: it can never be recorded as it is, and the
  /// athlete is told.
  final bool refused;

  /// For a refused report: it is older than yesterday, which the server
  /// records no pain for. Any other refusal is a value it does not take.
  final bool tooOld;

  Map<String, dynamic> toJson() => {
    ...report.toJson(),
    'refused': refused,
    if (refused) 'too_old': tooOld,
  };
}

/// What a drain of the queue left behind.
@immutable
class PainQueueState {
  const PainQueueState({
    this.waiting = const [],
    this.refused = const [],
    this.refusedTooOld = true,
    this.sent = 0,
  });

  /// Reports that have not reached Tracend yet (no connection, or a limit
  /// that lifts).
  final List<PainReport> waiting;

  /// Reports Tracend refused. They stay until the athlete has been told and
  /// acknowledges it.
  final List<PainReport> refused;

  /// Every refused report was refused only for its age. False when one was
  /// refused for a value the server does not take, which the words say
  /// differently.
  final bool refusedTooOld;

  /// How many reports the drain that made this state sent.
  final int sent;

  bool get isEmpty => waiting.isEmpty && refused.isEmpty;
}

/// Pain reports made during a workout, kept per athlete until Tracend has
/// them.
///
/// The server records a pain report only for the athlete's today or
/// yesterday, so a report that waits longer than a day is refused for good.
/// A report is therefore sent again every time the app comes forward, and a
/// refused one is never dropped silently: it stays here, [state] names it, and
/// it goes only when the athlete acknowledges it with [dismissRefused].
///
/// Every change of what is stored goes through one lock per athlete, and
/// changes the report by its idempotency key rather than writing back a list
/// read earlier: a report added while a drain waits on the network is kept, a
/// refusal the athlete dismissed stays dismissed, and a queue cleared for a
/// deleted account stays empty.
class PainReportQueue {
  PainReportQueue(
    this._preferences, {
    String? userId,
    String? Function()? signedInUser,
  }) : _userId = userId,
       _signedInUser = signedInUser,
       _key = userId == null ? _anonymousKey : storageKeyFor(userId);

  final SharedPreferences _preferences;
  final String? _userId;

  /// The athlete signed in now, when the queue is to check it before each
  /// send; null checks nothing.
  final String? Function()? _signedInUser;
  final String _key;

  static const _anonymousKey = 'pain_reports_pending';

  static String storageKeyFor(String userId) => '$_anonymousKey.$userId';

  /// The end of the changes waiting for each stored list, so changes to one
  /// list run one after the other.
  static final _tails = <String, Future<void>>{};

  /// The drains in flight, so a second one joins the first instead of
  /// sending the same reports again.
  static final _draining = <String, Future<PainQueueState>>{};

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

  /// Forgets everything kept for [userId] (a deleted account). A drain that
  /// is waiting on the network finds nothing left to change when it comes
  /// back.
  static Future<void> clearFor(SharedPreferences preferences, String userId) =>
      PainReportQueue(
        preferences,
        userId: userId,
      )._locked(() => preferences.remove(storageKeyFor(userId)));

  List<QueuedPainReport> _read() {
    final stored = _preferences.getString(_key);
    if (stored == null) return const [];
    try {
      final list = jsonDecode(stored);
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (PainReport.tryParse(item) case final report?)
            QueuedPainReport(
              report: report,
              refused: item is Map && item['refused'] == true,
              // A report refused before the reason was kept was refused for
              // its age.
              tooOld: item is Map && item['too_old'] != false,
            ),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> _write(List<QueuedPainReport> reports) async {
    if (reports.isEmpty) {
      await _preferences.remove(_key);
      return;
    }
    await _preferences.setString(
      _key,
      jsonEncode([for (final item in reports) item.toJson()]),
    );
  }

  /// Keeps [report] until it is sent. The same idempotency key is used for
  /// every attempt, so the server records it once. With [refused] it is kept
  /// as one the server will not take, so the athlete is told.
  Future<void> add(
    PainReport report, {
    bool refused = false,
    bool tooOld = false,
  }) => _locked(() async {
    final reports = _read();
    if (reports.any((r) => r.report.idempotencyKey == report.idempotencyKey)) {
      return;
    }
    await _write([
      ...reports,
      QueuedPainReport(report: report, refused: refused, tooOld: tooOld),
    ]);
  });

  /// Forgets [report] once the server has it.
  Future<void> remove(String idempotencyKey) => _locked(
    () async => _write([
      for (final item in _read())
        if (item.report.idempotencyKey != idempotencyKey) item,
    ]),
  );

  /// Marks the report with [idempotencyKey] as one the server will not take.
  /// A report that is no longer kept (sent, dismissed or cleared meanwhile)
  /// is not brought back.
  Future<void> _markRefused(String idempotencyKey, {required bool tooOld}) =>
      _locked(() async {
        final reports = _read();
        if (!reports.any((r) => r.report.idempotencyKey == idempotencyKey)) {
          return;
        }
        await _write([
          for (final item in reports)
            if (item.report.idempotencyKey == idempotencyKey)
              QueuedPainReport(
                report: item.report,
                refused: true,
                tooOld: tooOld,
              )
            else
              item,
        ]);
      });

  PainQueueState get state {
    final reports = _read();
    return PainQueueState(
      waiting: [
        for (final item in reports)
          if (!item.refused) item.report,
      ],
      refused: [
        for (final item in reports)
          if (item.refused) item.report,
      ],
      refusedTooOld: reports.every((item) => !item.refused || item.tooOld),
    );
  }

  /// Sends every waiting report, oldest first, and returns what is left. A
  /// report the server took goes; one it refused as too old is marked refused
  /// and kept; any other failure leaves it for the next try. Each outcome
  /// changes that one report, so what was added, dismissed or cleared while
  /// the network was awaited is not undone. It stops at once if the signed-in
  /// athlete is no longer the queue's. A drain already running is joined.
  Future<PainQueueState> drain(PainCheckRepository repository) {
    final running = _draining[_key];
    if (running != null) return running;
    final drain = _drain(repository);
    _draining[_key] = drain;
    return drain.whenComplete(() => _draining.remove(_key));
  }

  Future<PainQueueState> _drain(PainCheckRepository repository) async {
    var sent = 0;
    final tried = <String>{};
    while (true) {
      // Read again each round: a report added while one was being sent is
      // sent too.
      final next = [
        for (final item in _read())
          if (!item.refused && !tried.contains(item.report.idempotencyKey))
            item,
      ];
      if (next.isEmpty) break;
      for (final item in next) {
        final owner = _userId;
        final signedIn = _signedInUser;
        if (owner != null && signedIn != null && signedIn() != owner) {
          return _stateAfter(sent);
        }
        tried.add(item.report.idempotencyKey);
        try {
          await repository.record(item.report);
          sent++;
          await remove(item.report.idempotencyKey);
        } on PainCheckException catch (error) {
          if (error.failure == PainCheckFailure.refused) {
            await _markRefused(
              item.report.idempotencyKey,
              tooOld: error.tooOld,
            );
          }
        } on Exception catch (error) {
          debugPrint('Non-critical error: pain report waits: $error');
        }
      }
    }
    return _stateAfter(sent);
  }

  PainQueueState _stateAfter(int sent) {
    final now = state;
    return PainQueueState(
      waiting: now.waiting,
      refused: now.refused,
      refusedTooOld: now.refusedTooOld,
      sent: sent,
    );
  }

  /// The athlete has read that a refused report was not recorded.
  Future<void> dismissRefused() => _locked(
    () async => _write([
      for (final item in _read())
        if (!item.refused) item,
    ]),
  );
}
