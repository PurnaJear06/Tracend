import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/readiness/pain_check.dart';
import 'package:tracend/features/readiness/pain_report_queue.dart';
import 'package:tracend/features/readiness/safety_acknowledgements.dart';

/// How a report the athlete just made fared on its way to Tracend.
@immutable
class PainDelivery {
  const PainDelivery({
    required this.outcome,
    required this.sent,
    this.refused = false,
    this.tooOld = false,
    this.areaState,
  });

  /// The server's outcome when it took the report, else the one the phone
  /// worked out from the same rules.
  final PainOutcome outcome;

  /// Tracend has the report.
  final bool sent;

  /// The server will not take it as it is (22023, the date); it waits as a
  /// refused report and the athlete is told.
  final bool refused;

  /// For a refusal: the report is older than the server records.
  final bool tooOld;

  /// `held`, `limited`, `watch` or `none`, when the server said.
  final String? areaState;
}

/// A report the athlete just made. [outcome] is worked out on the phone at
/// once, by the same rules as the server's, so the answer to it (a referral
/// for a red flag) never waits on the network; [delivery] settles when the
/// report reached Tracend or was kept on the phone.
@immutable
class PainSubmission {
  const PainSubmission({
    required this.report,
    required this.outcome,
    required this.delivery,
  });

  final PainReport report;
  final PainOutcome outcome;
  final Future<PainDelivery> delivery;
}

/// Sends pain reports from a workout and keeps the ones that cannot go yet.
///
/// A report that cannot be sent is kept on the phone and sent again whenever
/// the app comes forward or a workout syncs: the server records a pain report
/// only for today or yesterday, so it has to get there within a day, and the
/// athlete is told so. The outcome shown at once is worked out on the phone
/// by the same rules as the server's, so a red flag is answered with a
/// referral even when nothing can be sent, and a connection that hangs
/// delays nothing: after [sendTimeout] the report is kept and the attempt
/// goes on in the background.
class PainReporting {
  PainReporting({
    required this.repository,
    this.readiness,
    this.userId,
    this.signedInUser,
    this.sendTimeout = const Duration(seconds: 8),
  });

  final PainCheckRepository repository;

  /// Today's readiness, read again after a report is sent so the card says
  /// what the report changed. Also names the server's today.
  final DayAdjustmentController? readiness;
  final String? userId;

  /// The athlete signed in now: queued reports are sent only while it is
  /// [userId].
  final String? Function()? signedInUser;

  /// How long a send is waited for before the report is kept for later.
  final Duration sendTimeout;

  Future<PainReportQueue> _queue() async => PainReportQueue(
    await SharedPreferences.getInstance(),
    userId: userId,
    signedInUser: signedInUser,
  );

  /// Records [report]: sent at once when it can be, else kept for later. Returns
  /// at once with the outcome the phone works out; the sending is
  /// [PainSubmission.delivery].
  PainSubmission submit(PainReport report) => PainSubmission(
    report: report,
    outcome: report.outcome,
    delivery: _deliver(report),
  );

  Future<PainDelivery> _deliver(PainReport report) async {
    final local = report.outcome;
    final attempt = Future.sync(() => repository.record(report));
    try {
      final result = await attempt.timeout(sendTimeout);
      unawaited(readiness?.load());
      unawaited(drain());
      return PainDelivery(
        outcome: result.outcome,
        sent: true,
        areaState: result.understood ? result.areaState : null,
      );
    } on TimeoutException {
      // The attempt goes on; the report is kept meanwhile, and forgotten
      // again if the attempt lands.
      await _keep(report);
      unawaited(_forgetWhenSent(report, attempt));
      return PainDelivery(outcome: local, sent: false);
    } on PainCheckException catch (error) {
      final refused = error.failure == PainCheckFailure.refused;
      await _keep(report, refused: refused, tooOld: error.tooOld);
      return PainDelivery(
        outcome: local,
        sent: false,
        refused: refused,
        tooOld: error.tooOld,
      );
    } on Object catch (error) {
      // Whatever went wrong, the report is kept and the answer stands.
      debugPrint('Non-critical error: pain report waits: $error');
      await _keep(report);
      return PainDelivery(outcome: local, sent: false);
    }
  }

  Future<void> _forgetWhenSent(
    PainReport report,
    Future<PainCheckResult> attempt,
  ) async {
    try {
      await attempt;
    } on Object {
      return;
    }
    try {
      await (await _queue()).remove(report.idempotencyKey);
      unawaited(readiness?.load());
    } on Exception catch (error) {
      debugPrint('Non-critical error: sent pain report kept: $error');
    }
  }

  Future<void> _keep(
    PainReport report, {
    bool refused = false,
    bool tooOld = false,
  }) async {
    try {
      await (await _queue()).add(report, refused: refused, tooOld: tooOld);
    } on Exception catch (error) {
      debugPrint('Non-critical error: pain report not kept: $error');
    }
  }

  /// Sends the reports that wait, and returns what is left. Today's
  /// readiness is read again only when something was sent.
  Future<PainQueueState> drain() async {
    try {
      final state = await (await _queue()).drain(repository);
      if (state.sent > 0) unawaited(readiness?.load());
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
