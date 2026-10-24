import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/features/readiness/pain_check.dart';

/// A pain report from a workout that waits on this phone until it can be sent.
@immutable
class QueuedPainReport {
  const QueuedPainReport({required this.report, this.refused = false});

  final PainReport report;

  /// The server refused it (it is older than yesterday): it can never be
  /// recorded as it is, and the athlete is told.
  final bool refused;

  Map<String, dynamic> toJson() => {...report.toJson(), 'refused': refused};
}

/// What a drain of the queue left behind.
@immutable
class PainQueueState {
  const PainQueueState({this.waiting = const [], this.refused = const []});

  /// Reports that have not reached Tracend yet (no connection, or a limit
  /// that lifts).
  final List<PainReport> waiting;

  /// Reports Tracend refused as too old. They stay until the athlete has
  /// been told and acknowledges it.
  final List<PainReport> refused;

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
class PainReportQueue {
  PainReportQueue(this._preferences, {String? userId})
    : _key = userId == null ? _anonymousKey : storageKeyFor(userId);

  final SharedPreferences _preferences;
  final String _key;

  static const _anonymousKey = 'pain_reports_pending';

  static String storageKeyFor(String userId) => '$_anonymousKey.$userId';

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
  Future<void> add(PainReport report, {bool refused = false}) async {
    final reports = _read();
    if (reports.any((r) => r.report.idempotencyKey == report.idempotencyKey)) {
      return;
    }
    await _write([
      ...reports,
      QueuedPainReport(report: report, refused: refused),
    ]);
  }

  /// Forgets [report] once the server has it.
  Future<void> remove(String idempotencyKey) async {
    await _write([
      for (final item in _read())
        if (item.report.idempotencyKey != idempotencyKey) item,
    ]);
  }

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
    );
  }

  /// Sends every waiting report, oldest first. A report the server took
  /// goes; one it refused as too old is marked refused and kept; any other
  /// failure leaves it for the next try. Returns what is left.
  Future<PainQueueState> drain(PainCheckRepository repository) async {
    final reports = _read();
    final kept = <QueuedPainReport>[];
    for (final item in reports) {
      if (item.refused) {
        kept.add(item);
        continue;
      }
      try {
        await repository.record(item.report);
      } on PainCheckException catch (error) {
        kept.add(
          error.failure == PainCheckFailure.refused
              ? QueuedPainReport(report: item.report, refused: true)
              : item,
        );
      } on Exception catch (error) {
        debugPrint('Non-critical error: pain report waits: $error');
        kept.add(item);
      }
    }
    await _write(kept);
    return state;
  }

  /// The athlete has read that a refused report was not recorded.
  Future<void> dismissRefused() async {
    await _write([
      for (final item in _read())
        if (!item.refused) item,
    ]);
  }
}
