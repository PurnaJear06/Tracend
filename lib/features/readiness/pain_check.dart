import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';

/// The pain check (B5): where it hurts, how strong, and the red-flag
/// questions. The outcome of a report is worked out by deterministic rules,
/// never a model; the database holds the same table (`private.pain_rules`,
/// `private.pain_outcome`) and a test keeps the two equal. The phone works
/// the outcome out as well so that a red flag is answered at once, with a
/// referral, even when nothing can be sent yet.

/// What a pain report leads to, strictest first.
enum PainOutcome {
  /// Get medical help now.
  urgent('urgent'),

  /// See a doctor or physio today.
  clinicianToday('clinician_today'),

  /// Book a doctor or physio.
  clinician('clinician'),

  /// Pain of 4 to 6: ease the area for a week.
  modify('modify'),

  /// Pain of 1 to 3: watch the area for a week.
  watch('watch'),

  /// No pain.
  clear('clear');

  const PainOutcome(this.wire);
  final String wire;

  static PainOutcome? fromWire(Object? value) {
    for (final outcome in values) {
      if (outcome.wire == value) return outcome;
    }
    return null;
  }

  /// The report sends the athlete to a professional and holds the area.
  bool get routesOut =>
      this == urgent || this == clinicianToday || this == clinician;

  /// The safety route this outcome gives the day.
  String? get route => routesOut ? wire : null;
}

/// The closed list of red-flag codes with the outcome each leads to and the
/// areas the app asks about it. The server accepts any code for any area (a
/// flag that is stored is never wrong to act on); the app asks the area's own
/// and the general ones, in the list's order (sorted by code).
const redFlagRules = <String, ({PainOutcome outcome, Set<PainArea> areas})>{
  'bladder_bowel_saddle': (outcome: PainOutcome.urgent, areas: {PainArea.back}),
  'cannot_bear_or_move': (
    outcome: PainOutcome.clinicianToday,
    areas: _everyArea,
  ),
  'chest_or_breath': (
    outcome: PainOutcome.urgent,
    areas: {PainArea.shoulder, PainArea.other},
  ),
  'dislocated_or_cannot_lift': (
    outcome: PainOutcome.clinicianToday,
    areas: {PainArea.shoulder},
  ),
  'fever_unwell': (outcome: PainOutcome.clinician, areas: _everyArea),
  'locks_gives_way': (outcome: PainOutcome.clinician, areas: {PainArea.knee}),
  'night_pain': (outcome: PainOutcome.clinician, areas: _everyArea),
  'numb_weak_limb': (outcome: PainOutcome.clinicianToday, areas: _everyArea),
  'pop_or_sudden': (outcome: PainOutcome.clinicianToday, areas: _everyArea),
  'rapid_swelling': (
    outcome: PainOutcome.clinicianToday,
    areas: {PainArea.knee, PainArea.other},
  ),
};

const _everyArea = {
  PainArea.knee,
  PainArea.back,
  PainArea.shoulder,
  PainArea.other,
};

/// The red-flag questions the app asks about [area], by code.
List<String> redFlagCodesFor(PainArea area) => [
  for (final entry in redFlagRules.entries)
    if (entry.value.areas.contains(area)) entry.key,
];

/// The outcome of one report: the same answers always give the same outcome
/// (`private.pain_outcome`). A report that did not ask about red flags
/// ([redFlags] null) is judged by [severity] alone. A code the app does not
/// know counts as the strictest the athlete could mean: it routes out today.
PainOutcome painOutcome(int severity, List<String>? redFlags) {
  final outcomes = [
    for (final code in redFlags ?? const <String>[])
      redFlagRules[code]?.outcome ?? PainOutcome.clinicianToday,
  ];
  if (outcomes.contains(PainOutcome.urgent)) return PainOutcome.urgent;
  if (severity >= 7 || outcomes.contains(PainOutcome.clinicianToday)) {
    return PainOutcome.clinicianToday;
  }
  if (outcomes.contains(PainOutcome.clinician)) return PainOutcome.clinician;
  if (severity >= 4) return PainOutcome.modify;
  if (severity >= 1) return PainOutcome.watch;
  return PainOutcome.clear;
}

/// One pain report from a workout, as `record_pain_check_v1` takes it.
@immutable
class PainReport {
  const PainReport({
    required this.localDate,
    required this.area,
    required this.severity,
    required this.redFlags,
    required this.idempotencyKey,
    this.pattern,
    this.exercisePerformanceId,
    this.source = 'workout',
    this.clearedByClinician = false,
  });

  /// `YYYY-MM-DD`: the server's today when it is known.
  final String localDate;
  final PainArea area;
  final int severity;

  /// The red flags that apply, or null when the red-flag questions were not
  /// asked (a workout check that asks two of the ten: the server then judges
  /// by the strength alone, and an empty list would claim "none of these").
  final List<String>? redFlags;
  final String idempotencyKey;
  final String? pattern;
  final String? exercisePerformanceId;
  final String source;
  final bool clearedByClinician;

  PainOutcome get outcome => painOutcome(severity, redFlags);

  Map<String, dynamic> toJson() => {
    'local_date': localDate,
    'area': area.name,
    'severity': severity,
    'red_flags': redFlags,
    'idempotency_key': idempotencyKey,
    'pattern': pattern,
    'exercise_performance_id': exercisePerformanceId,
    'source': source,
    'cleared_by_clinician': clearedByClinician,
  };

  /// Null when [raw] is not a report this build wrote.
  static PainReport? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final area = PainArea.fromWire(raw['area']);
    final severity = raw['severity'];
    final flags = raw['red_flags'];
    final key = raw['idempotency_key'];
    final date = raw['local_date'];
    if (area == null ||
        severity is! int ||
        (flags != null && flags is! List) ||
        key is! String ||
        date is! String) {
      return null;
    }
    return PainReport(
      localDate: date,
      area: area,
      severity: severity,
      redFlags: flags == null
          ? null
          : [
              for (final flag in flags as List)
                if (flag is String) flag,
            ],
      idempotencyKey: key,
      pattern: raw['pattern'] as String?,
      exercisePerformanceId: raw['exercise_performance_id'] as String?,
      source: raw['source'] as String? ?? 'workout',
      clearedByClinician: raw['cleared_by_clinician'] == true,
    );
  }
}

/// What the server said of a report it took.
@immutable
class PainCheckResult {
  const PainCheckResult({
    required this.id,
    required this.outcome,
    required this.areaState,
    this.understood = true,
  });

  /// False when the server took the report but this build could not read its
  /// answer: [outcome] is then the phone's own and [areaState] says nothing.
  final bool understood;

  final String id;
  final PainOutcome outcome;

  /// `held`, `limited`, `watch` or `none`.
  final String areaState;

  static PainCheckResult? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final version = raw['schema_version'];
    final id = raw['id'];
    final outcome = PainOutcome.fromWire(raw['outcome']);
    if (version is! String ||
        !version.startsWith('1.') ||
        id is! String ||
        outcome == null) {
      return null;
    }
    return PainCheckResult(
      id: id,
      outcome: outcome,
      areaState: raw['area_state'] as String? ?? 'none',
    );
  }
}

/// Why a report was not taken.
enum PainCheckFailure {
  /// The server refused it (22023): the date is older than yesterday, or an
  /// answer is not one it knows. It will never be accepted as it is
  /// ([PainCheckException.tooOld] says which).
  refused,

  /// No connection, the session ended, or a limit that lifts: try again.
  retry,
}

/// Whether [error] is the refusal for a date more than a day from the
/// server's own (`a pain check is for today or yesterday`): the one 22023 that
/// means the report is too old. Any other 22023 is a value the server does
/// not take.
bool isPainDateRefusal(PostgrestException error) =>
    error.code == '22023' && error.message.contains('today or yesterday');

class PainCheckException implements Exception {
  const PainCheckException(this.failure, {this.tooOld = false});
  final PainCheckFailure failure;

  /// For a refusal: the report is older than the server records.
  final bool tooOld;
  @override
  String toString() => 'PainCheckException: ${failure.name}';
}

/// Sends a pain report from a workout to Tracend.
abstract interface class PainCheckRepository {
  Future<PainCheckResult> record(PainReport report);
}

typedef PainCheckRpc =
    Future<Object?> Function(String function, Map<String, dynamic> params);

class SupabasePainCheckRepository implements PainCheckRepository {
  SupabasePainCheckRepository(SupabaseClient client)
    : _rpc = ((function, params) => client.rpc(function, params: params));

  /// Talks through [rpc] instead of a client, for tests.
  @visibleForTesting
  SupabasePainCheckRepository.withRpc(PainCheckRpc rpc) : _rpc = rpc;

  final PainCheckRpc _rpc;

  @override
  Future<PainCheckResult> record(PainReport report) async {
    final Object? value;
    try {
      value = await _rpc('record_pain_check_v1', {
        'local_date': report.localDate,
        'source': report.source,
        'area': report.area.name,
        'severity': report.severity,
        'pattern': report.pattern,
        'red_flags': report.redFlags,
        'cleared_by_clinician': report.clearedByClinician,
        'exercise_performance_id': report.exercisePerformanceId,
        'idempotency_key': report.idempotencyKey,
      });
    } on PostgrestException catch (error) {
      debugPrint('Non-critical error: pain check: ${error.code}');
      throw PainCheckException(
        error.code == '22023'
            ? PainCheckFailure.refused
            : PainCheckFailure.retry,
        tooOld: isPainDateRefusal(error),
      );
    }
    // The call went through: the report is recorded even when this build
    // cannot read the answer, so it is never kept to be sent again; the
    // phone's own outcome stands.
    return PainCheckResult.tryParse(value) ??
        PainCheckResult(
          id: '',
          outcome: report.outcome,
          areaState: 'none',
          understood: false,
        );
  }
}

/// Without a backend nothing can be sent: every report waits on the phone.
class OfflinePainCheckRepository implements PainCheckRepository {
  const OfflinePainCheckRepository();

  @override
  Future<PainCheckResult> record(PainReport report) =>
      Future.error(const PainCheckException(PainCheckFailure.retry));
}
