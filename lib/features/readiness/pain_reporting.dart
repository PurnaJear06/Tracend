import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/readiness/pain_check.dart';
import 'package:tracend/features/readiness/pain_report_queue.dart';
import 'package:tracend/features/readiness/safety_acknowledgements.dart';

/// What happened to a report the athlete just made.
@immutable
class PainSubmission {
  const PainSubmission({
    required this.report,
    required this.outcome,
    required this.sent,
    this.refused = false,
  });

  final PainReport report;

  /// The server's outcome when it took the report, else the one the phone
  /// worked out from the same rules.
  final PainOutcome outcome;

  /// Tracend has the report.
  final bool sent;

  /// The server will not take it as it is (22023); it waits as a refused
  /// report and the athlete is told.
  final bool refused;
}

/// Sends pain reports from a workout and keeps the ones that cannot go yet.
///
/// A report that cannot be sent is kept on the phone and sent again whenever
/// the app comes forward or a workout syncs: the server records a pain report
/// only for today or yesterday, so it has to get there within a day, and the
/// athlete is told so. The outcome shown at once is worked out on the phone
/// by the same rules as the server's, so a red flag is answered with a
/// referral even when nothing can be sent.
class PainReporting {
  PainReporting({required this.repository, this.readiness, this.userId});

  final PainCheckRepository repository;

  /// Today's readiness, read again after a report is sent so the card says
  /// what the report changed. Also names the server's today.
  final DayAdjustmentController? readiness;
  final String? userId;

  Future<PainReportQueue> _queue() async =>
      PainReportQueue(await SharedPreferences.getInstance(), userId: userId);

  /// Records [report]: sent at once when it can be, else kept for later.
  Future<PainSubmission> submit(PainReport report) async {
    final local = report.outcome;
    try {
      final result = await repository.record(report);
      unawaited(readiness?.load());
      unawaited(drain());
      return PainSubmission(
        report: report,
        outcome: result.outcome,
        sent: true,
      );
    } on PainCheckException catch (error) {
      final refused = error.failure == PainCheckFailure.refused;
      await _keep(report, refused: refused);
      return PainSubmission(
        report: report,
        outcome: local,
        sent: false,
        refused: refused,
      );
    } on Exception catch (error) {
      debugPrint('Non-critical error: pain report waits: $error');
      await _keep(report);
      return PainSubmission(report: report, outcome: local, sent: false);
    }
  }

  Future<void> _keep(PainReport report, {bool refused = false}) async {
    try {
      await (await _queue()).add(report, refused: refused);
    } on Exception catch (error) {
      debugPrint('Non-critical error: pain report not kept: $error');
    }
  }

  /// Sends the reports that wait, and returns what is left.
  Future<PainQueueState> drain() async {
    try {
      final state = await (await _queue()).drain(repository);
      if (state.waiting.isEmpty) unawaited(readiness?.load());
      return state;
    } on Exception catch (error) {
      debugPrint('Non-critical error: pain reports not drained: $error');
      return const PainQueueState();
    }
  }

  /// Reports waiting or refused, without sending anything.
  Future<PainQueueState> state() async {
    try {
      return (await _queue()).state;
    } on Exception {
      return const PainQueueState();
    }
  }

  /// The athlete has read that refused reports were not recorded.
  Future<void> dismissRefused() async => (await _queue()).dismissRefused();

  /// The athlete has answered the referral for [route] on [localDate]
  /// (`YYYY-MM-DD`), so Today does not show it again for that day.
  Future<void> acknowledge(String localDate, String route) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await SafetyAcknowledgements(
        preferences,
        userId: userId,
      ).acknowledge(SafetyAcknowledgements.keyOf(localDate, route));
    } on Exception catch (error) {
      debugPrint('Non-critical error: referral not remembered: $error');
    }
  }
}
