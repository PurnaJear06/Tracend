import 'package:tracend/features/readiness/pain_check.dart';

/// The server's `record_pain_check_v1`, as far as the app can tell: it takes
/// every report it is given (and says the outcome the rules give), unless it
/// is told to refuse or to be out of reach. Every report is recorded.
class FakePainCheckRepository implements PainCheckRepository {
  final reports = <PainReport>[];

  /// When set, every report is refused with this failure.
  PainCheckFailure? failure;

  /// For a refusal: the report is older than the server records (else it is a
  /// value the server does not take).
  bool tooOld = true;

  /// When set, the server does not answer until this completes.
  Future<void>? hold;

  /// When set, the server takes the report and answers with this (a payload
  /// this build cannot read).
  Object? unreadable;

  /// When set, the server says the area is in this state, whatever the report.
  String? areaState;

  @override
  Future<PainCheckResult> record(PainReport report) async {
    reports.add(report);
    final hold = this.hold;
    if (hold != null) await hold;
    final failure = this.failure;
    if (failure != null) {
      throw PainCheckException(failure, tooOld: tooOld);
    }
    final outcome = report.outcome;
    if (unreadable != null) {
      return PainCheckResult(
        id: '',
        outcome: outcome,
        areaState: 'none',
        understood: false,
      );
    }
    return PainCheckResult(
      id: 'report-${reports.length}',
      outcome: outcome,
      areaState:
          areaState ??
          switch (outcome) {
            PainOutcome.urgent ||
            PainOutcome.clinicianToday ||
            PainOutcome.clinician => 'held',
            PainOutcome.modify => 'limited',
            PainOutcome.watch => 'watch',
            PainOutcome.clear => 'none',
          },
    );
  }
}
