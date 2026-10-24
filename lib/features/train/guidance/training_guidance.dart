import 'package:flutter/foundation.dart';

/// Where a lighter week stands today (Contract: `get_my_training_guidance_v1`,
/// rules `deload-v1`). `notDue` covers every suppression; the server says which
/// in [DeloadGuidance.suppressedBy].
enum DeloadStatus {
  notDue('not_due'),
  suggested('suggested'),
  pending('pending'),
  running('running');

  const DeloadStatus(this.wire);
  final String wire;

  static DeloadStatus? fromWire(Object? value) {
    for (final status in values) {
      if (status.wire == value) return status;
    }
    return null;
  }
}

/// Why the rules suggest a lighter week. Each is the athlete's own data, never
/// a heart signal.
enum DeloadReason {
  performanceDrop('performance_drop'),
  runDown('run_down'),
  blockDone('block_done');

  const DeloadReason(this.wire);
  final String wire;

  static DeloadReason? fromWire(Object? value) {
    for (final reason in values) {
      if (reason.wire == value) return reason;
    }
    return null;
  }
}

/// The lighter-week part of the guidance. A status or a reason this build does
/// not know never reaches here: a status it cannot read makes
/// [TrainingGuidance.deload] null, and an unknown reason is left out of
/// [reasons].
@immutable
class DeloadGuidance {
  const DeloadGuidance({
    required this.status,
    this.reasons = const [],
    this.proposalId,
    this.suppressedBy,
    this.hadUnreadReasons = false,
  });

  final DeloadStatus status;

  /// The reasons this build can say in words, in the order the server gave.
  final List<DeloadReason> reasons;

  /// The open (`pending`) or running (`running`) proposal.
  final String? proposalId;

  /// The rule that holds a suggestion back (`not_due` only). Kept as the
  /// server's word; nothing in the app branches on it.
  final String? suppressedBy;

  /// The server named a reason this build cannot say in words.
  final bool hadUnreadReasons;

  static DeloadGuidance? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final status = DeloadStatus.fromWire(raw['status']);
    if (status == null) return null;
    final rawReasons = raw['reasons'];
    final reasons = <DeloadReason>[];
    var unread = false;
    if (rawReasons is List) {
      for (final item in rawReasons) {
        final reason = DeloadReason.fromWire(item);
        if (reason == null) {
          unread = true;
        } else if (!reasons.contains(reason)) {
          reasons.add(reason);
        }
      }
    }
    final proposalId = raw['proposal_id'];
    final suppressedBy = raw['suppressed_by'];
    return DeloadGuidance(
      status: status,
      reasons: reasons,
      proposalId: proposalId is String && proposalId.isNotEmpty
          ? proposalId
          : null,
      suppressedBy: suppressedBy is String ? suppressedBy : null,
      hadUnreadReasons: unread,
    );
  }
}

/// Why the cardio dose is not given today.
enum CardioWithheld {
  safetyRoute('safety_route'),
  screening('screening');

  const CardioWithheld(this.wire);
  final String wire;

  static CardioWithheld? fromWire(Object? value) {
    for (final reason in values) {
      if (reason.wire == value) return reason;
    }
    return null;
  }
}

/// The week's cardio against the public health guideline (rules `cardio-v1`).
@immutable
class CardioWeek {
  const CardioWeek({
    required this.targetMin,
    required this.doneMin,
    required this.intensityKnown,
    required this.vigorousAllowed,
    this.stretchMax,
    this.vigorousSessionsMax = 0,
    this.vigorousCountsAs = 2,
    this.liftSeparationHours = 3,
    this.easyHrReserveMax,
    this.windowFrom,
    this.windowTo,
  });

  /// Minutes of moderate cardio a week (150).
  final int targetMin;

  /// Minutes counted from Apple Health workouts; null when fewer than five of
  /// the seven days have Apple Health data. Null is never 0.
  final int? doneMin;

  /// False: every counted minute is read as moderate, because a workout record
  /// does not say how hard it was.
  final bool intensityKnown;

  /// Hard cardio is open today.
  final bool vigorousAllowed;

  /// The upper figure for fat loss and recomposition (300); null for others.
  final int? stretchMax;
  final int vigorousSessionsMax;
  final int vigorousCountsAs;
  final int liftSeparationHours;

  /// Easy effort stays below this share of heart-rate reserve.
  final int? easyHrReserveMax;
  final DateTime? windowFrom;
  final DateTime? windowTo;

  static int? _whole(Object? value) =>
      value is num && value == value.truncate() && value >= 0
      ? value.toInt()
      : null;

  static CardioWeek? tryParse(Object? raw) {
    if (raw is! Map || !raw.containsKey('done_min')) return null;
    final target = _whole(raw['target_min']);
    final done = raw['done_min'] == null ? null : _whole(raw['done_min']);
    if (target == null ||
        target == 0 ||
        (raw['done_min'] != null && done == null) ||
        raw['intensity_known'] is! bool ||
        raw['vigorous_allowed'] is! bool) {
      return null;
    }
    final stretch = _whole(raw['stretch_max']);
    return CardioWeek(
      targetMin: target,
      doneMin: done,
      intensityKnown: raw['intensity_known'] as bool,
      vigorousAllowed: raw['vigorous_allowed'] as bool,
      stretchMax: stretch != null && stretch > target ? stretch : null,
      vigorousSessionsMax: _whole(raw['vigorous_sessions_max']) ?? 0,
      vigorousCountsAs: _whole(raw['vigorous_counts_as']) ?? 2,
      liftSeparationHours: _whole(raw['lift_separation_hours']) ?? 3,
      easyHrReserveMax: _whole(raw['easy_hr_reserve_max']),
      windowFrom: _date(raw['window_from']),
      windowTo: _date(raw['window_to']),
    );
  }

  static DateTime? _date(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}

/// What `get_my_training_guidance_v1` says about today: whether a lighter week
/// could help and how the week's cardio stands. Versions 1.0 and 1.1 read; a
/// later 1.x reads what this build knows and leaves the rest out. A part this
/// build cannot read is null (the card or row is not shown), never guessed.
@immutable
class TrainingGuidance {
  const TrainingGuidance({
    required this.localDate,
    this.safetyRoute,
    this.deload,
    this.cardioWithheld,
    this.cardioWeek,
  });

  /// `YYYY-MM-DD`, the server's own day the guidance is for.
  final String localDate;

  /// Set on a day that routes out (pain referral, red flag). Any value counts,
  /// including one this build does not know.
  final String? safetyRoute;

  /// Null when the status is one this build does not know.
  final DeloadGuidance? deload;

  /// Why no cardio dose is given today, when the reason is one this build
  /// knows. Any reason at all leaves [cardioWeek] null.
  final CardioWithheld? cardioWithheld;

  /// The week's cardio; null in 1.0, when a reason withholds it, or when the
  /// figures are not the shape this build reads.
  final CardioWeek? cardioWeek;

  static TrainingGuidance? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final version = raw['schema_version'];
    if (version is! String || !version.startsWith('1.')) return null;
    final localDate = raw['local_date'];
    if (localDate is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(localDate)) {
      return null;
    }
    final route = raw['safety_route'];
    final withheldRaw = raw['cardio_withheld'];
    final withheld = CardioWithheld.fromWire(withheldRaw);
    return TrainingGuidance(
      localDate: localDate,
      safetyRoute: route is String && route.isNotEmpty ? route : null,
      deload: DeloadGuidance.tryParse(raw['deload']),
      cardioWithheld: withheld,
      // A dose is shown only when nothing withholds it, whatever the reason.
      cardioWeek: withheldRaw == null
          ? CardioWeek.tryParse(raw['cardio_week'])
          : null,
    );
  }
}

/// What the lighter-week card shows today.
enum DeloadCardState {
  /// Nothing to say: no card.
  hidden,

  /// The rules suggest a lighter week and nothing is stored yet.
  suggested,

  /// A proposal for a lighter week is open and waits for the athlete.
  pending,

  /// A lighter week is the plan now; it can be undone for seven days.
  running,
}

/// The card state [guidance] puts the card in. A status this build cannot
/// read, a suggestion with no reason it can say, a proposal with no id, and a
/// suggestion or open proposal on a day with a safety route all hide it.
DeloadCardState deloadCardState(TrainingGuidance? guidance) {
  final deload = guidance?.deload;
  if (guidance == null || deload == null) return DeloadCardState.hidden;
  switch (deload.status) {
    case DeloadStatus.notDue:
      return DeloadCardState.hidden;
    case DeloadStatus.suggested:
      return guidance.safetyRoute == null && deload.reasons.isNotEmpty
          ? DeloadCardState.suggested
          : DeloadCardState.hidden;
    case DeloadStatus.pending:
      return guidance.safetyRoute == null && deload.proposalId != null
          ? DeloadCardState.pending
          : DeloadCardState.hidden;
    case DeloadStatus.running:
      return deload.proposalId != null
          ? DeloadCardState.running
          : DeloadCardState.hidden;
  }
}
