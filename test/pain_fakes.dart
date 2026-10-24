import 'package:tracend/features/readiness/pain_check.dart';

/// The server's `record_pain_check_v1`, as far as the app can tell: it takes
/// every report it is given (and says the outcome the rules give), unless it
/// is told to refuse or to be out of reach. Every report is recorded.
class FakePainCheckRepository implements PainCheckRepository {
  final reports = <PainReport>[];

  /// When set, every report is refused with this failure.
  PainCheckFailure? failure;

  @override
  Future<PainCheckResult> record(PainReport report) async {
    reports.add(report);
    final failure = this.failure;
    if (failure != null) throw PainCheckException(failure);
    final outcome = report.outcome;
    return PainCheckResult(
      id: 'report-${reports.length}',
      outcome: outcome,
      areaState: switch (outcome) {
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
