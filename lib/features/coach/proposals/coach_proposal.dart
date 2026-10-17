import 'package:tracend/shared/formatting.dart';

/// Where a Coach proposal stands. `changed` means the athlete asked for
/// something different; `undone` means it was approved and then reversed.
enum CoachProposalStatus {
  pending,
  accepted,
  declined,
  changed,
  expired,
  undone;

  static CoachProposalStatus? parse(Object? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

/// What the athlete can answer. `change` closes the card; the follow-up
/// message in chat starts a fresh proposal.
enum CoachProposalAction {
  approve,
  decline,
  change;

  String get wire => name;
}

/// One line of a card column, for example "Calories" and "2,100 kcal".
class ProposalRow {
  const ProposalRow({required this.label, required this.value});

  final String label;
  final String value;
}

/// A training day as the card lists it.
class ProposalSession {
  const ProposalSession({
    required this.weekday,
    required this.name,
    required this.exercises,
    required this.minutes,
  });

  /// ISO weekday, 1 = Monday; null for a plan without fixed days.
  final int? weekday;
  final String name;
  final int exercises;
  final int minutes;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// "Mon · Full body A · 6 exercises · 60 min".
  String get line {
    final day = weekday != null && weekday! >= 1 && weekday! <= 7
        ? '${_days[weekday! - 1]} · '
        : '';
    return '$day$name · $exercises ${exercises == 1 ? 'exercise' : 'exercises'}'
        ' · $minutes min';
  }
}

/// The before or after column of a card: values the rules computed.
class ProposalSnapshot {
  const ProposalSnapshot({this.rows = const [], this.sessions = const []});

  final List<ProposalRow> rows;
  final List<ProposalSession> sessions;

  static ProposalSnapshot? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final rawRows = json['rows'];
    final rawSessions = json['sessions'];
    if (rawRows is! List || (rawSessions != null && rawSessions is! List)) {
      return null;
    }
    final rows = <ProposalRow>[];
    for (final item in rawRows) {
      if (item is! Map<String, dynamic>) return null;
      final label = item['label'];
      final value = item['value'];
      if (label is! String || value is! String) return null;
      rows.add(ProposalRow(label: label, value: value));
    }
    final sessions = <ProposalSession>[];
    for (final item in (rawSessions as List? ?? const [])) {
      if (item is! Map<String, dynamic>) return null;
      final name = item['name'];
      final exercises = item['exercises'];
      final minutes = item['minutes'];
      final weekday = item['weekday'];
      if (name is! String ||
          exercises is! int ||
          minutes is! int ||
          (weekday != null && weekday is! int)) {
        return null;
      }
      sessions.add(
        ProposalSession(
          weekday: weekday as int?,
          name: name,
          exercises: exercises,
          minutes: minutes,
        ),
      );
    }
    return ProposalSnapshot(rows: rows, sessions: sessions);
  }
}

/// What a proposal is based on, in the athlete's words.
class ProposalEvidence {
  const ProposalEvidence({required this.code, required this.label});

  final String code;
  final String label;
}

/// A change Coach proposed: rules computed every number in it, and nothing
/// is applied until the athlete approves. Reads `get_my_coach_proposals_v1`.
class CoachProposal {
  const CoachProposal({
    required this.id,
    required this.kind,
    required this.status,
    required this.title,
    required this.rationale,
    required this.benefit,
    required this.downside,
    required this.confidence,
    required this.evidence,
    required this.before,
    required this.after,
    required this.createdAt,
    required this.expiresAt,
    required this.canUndo,
    this.endsOn,
    this.appliedAt,
    this.undoUntil,
    this.undoneAt,
    this.sourceMessageId,
  });

  final String id;
  final String kind;
  final CoachProposalStatus status;
  final String title;
  final String rationale;
  final String benefit;
  final String downside;
  final String confidence;
  final List<ProposalEvidence> evidence;
  final ProposalSnapshot before;
  final ProposalSnapshot after;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// The last day a temporary change applies; the plan returns after it.
  final DateTime? endsOn;
  final DateTime? appliedAt;
  final DateTime? undoUntil;
  final DateTime? undoneAt;
  final bool canUndo;
  final String? sourceMessageId;

  /// Null when the payload is not the expected shape, so a half-read card is
  /// never shown.
  static CoachProposal? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final status = CoachProposalStatus.parse(json['status']);
    final before = ProposalSnapshot.fromJson(json['before']);
    final after = ProposalSnapshot.fromJson(json['after']);
    final evidence = json['evidence'];
    final id = json['id'];
    final kind = json['kind'];
    final title = json['title'];
    final rationale = json['rationale'];
    final benefit = json['benefit'];
    final downside = json['downside'];
    final confidence = json['confidence'];
    final createdAt = _time(json['created_at']);
    final expiresAt = _time(json['expires_at']);
    if (status == null ||
        before == null ||
        after == null ||
        evidence is! List ||
        id is! String ||
        kind is! String ||
        title is! String ||
        rationale is! String ||
        benefit is! String ||
        downside is! String ||
        confidence is! String ||
        createdAt == null ||
        expiresAt == null ||
        json['can_undo'] is! bool) {
      return null;
    }
    return CoachProposal(
      id: id,
      kind: kind,
      status: status,
      title: title,
      rationale: rationale,
      benefit: benefit,
      downside: downside,
      confidence: confidence,
      evidence: [
        for (final item in evidence)
          if (item is Map<String, dynamic> &&
              item['code'] is String &&
              item['label'] is String)
            ProposalEvidence(
              code: item['code'] as String,
              label: item['label'] as String,
            ),
      ],
      before: before,
      after: after,
      createdAt: createdAt,
      expiresAt: expiresAt,
      canUndo: json['can_undo'] as bool,
      endsOn: _time(json['ends_on']),
      appliedAt: _time(json['applied_at']),
      undoUntil: _time(json['undo_until']),
      undoneAt: _time(json['undone_at']),
      sourceMessageId: json['source_message_id'] as String?,
    );
  }

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  /// The proposals in a `get_my_coach_proposals_v1` payload, newest first.
  /// Anything that is not the expected shape yields none.
  static List<CoachProposal> listFromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        json['schema_version'] is! String ||
        json['proposals'] is! List) {
      return const [];
    }
    final parsed = (json['proposals'] as List).map(fromJson).toList();
    return parsed.contains(null) ? const [] : parsed.cast<CoachProposal>();
  }

  /// The proposal with the status the server just answered and its undo
  /// window, for a card whose re-read failed. Undo stays possible only for an
  /// approval, and only until the window ends.
  CoachProposal withStatus(CoachProposalStatus next, DateTime? window) =>
      CoachProposal(
        id: id,
        kind: kind,
        status: next,
        title: title,
        rationale: rationale,
        benefit: benefit,
        downside: downside,
        confidence: confidence,
        evidence: evidence,
        before: before,
        after: after,
        createdAt: createdAt,
        expiresAt: expiresAt,
        canUndo: next == CoachProposalStatus.accepted,
        endsOn: endsOn,
        appliedAt: appliedAt,
        undoUntil: window ?? undoUntil,
        undoneAt: undoneAt,
        sourceMessageId: sourceMessageId,
      );

  /// "Open until Tue 21 Oct" while pending; null otherwise.
  String? get expiryLine => status == CoachProposalStatus.pending
      ? 'Open until ${_dayLabel(expiresAt)}'
      : null;

  /// "Your regular plan returns after 30 Oct", for a change that ends.
  String? get endsLine => endsOn == null ? null : 'Ends ${_dayLabel(endsOn!)}';

  /// "Undo until Tue 25 Oct", while it can be undone.
  String? get undoLine => canUndo && undoUntil != null
      ? 'You can undo this until ${_dayLabel(undoUntil!)}'
      : null;

  static String _dayLabel(DateTime date, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final day = DateTime(date.year, date.month, date.day);
    return switch (day.difference(today).inDays) {
      0 => 'today',
      1 => 'tomorrow',
      _ => friendlyDate(day, now: reference),
    };
  }

  /// The message the app sends when the athlete taps "Change it".
  String get changeRequestMessage =>
      'I want to change this: $title. Can we adjust it?';
}

/// What the server answered to approve, decline, change or undo.
class CoachProposalAnswer {
  const CoachProposalAnswer({
    required this.proposalId,
    required this.status,
    this.reason,
    this.undoUntil,
    this.changedPlan = false,
  });

  final String proposalId;

  /// accepted, declined, changed, expired, undone, undo_window_ended or
  /// superseded.
  final String status;

  /// Why an approval was refused as expired (the plan, targets or goal
  /// changed in the meantime).
  final String? reason;
  final DateTime? undoUntil;

  /// True when a plan, targets or goal version was written or restored.
  final bool changedPlan;

  static CoachProposalAnswer? fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        json['schema_version'] is! String ||
        json['proposal_id'] is! String ||
        json['status'] is! String) {
      return null;
    }
    final status = json['status'] as String;
    return CoachProposalAnswer(
      proposalId: json['proposal_id'] as String,
      status: status,
      reason: json['reason'] as String?,
      undoUntil: json['undo_until'] is String
          ? DateTime.tryParse(json['undo_until'] as String)?.toLocal()
          : null,
      changedPlan: status == 'accepted' || status == 'undone',
    );
  }
}
