/// What Coach remembers about the athlete (A10 part 2): the facts the athlete
/// confirmed, and the notes Coach wrote after past conversations. The facts
/// are the athlete's to add, edit and delete; the notes can only be read and
/// deleted. Nothing here is written by the Coach model.
library;

/// The closed list of things a confirmed fact can be about. The wire values
/// are the database's `coach_facts.kind` check.
enum CoachFactKind {
  injuryLimitation('injury_limitation', 'Injuries and limitations'),
  scheduleConstraint('schedule_constraint', 'Schedule and life'),
  equipment('equipment', 'Equipment'),
  foodLike('food_like', 'Foods you like'),
  foodDislike('food_dislike', 'Foods you dislike'),
  allergy('allergy', 'Allergies and intolerances'),
  exerciseLike('exercise_like', 'Exercises you like'),
  exerciseDislike('exercise_dislike', 'Exercises you dislike'),
  coachingStyle('coaching_style', 'Coaching style'),
  otherPreference('other_preference', 'Other preferences');

  const CoachFactKind(this.wire, this.label);

  final String wire;
  final String label;

  static CoachFactKind? fromWire(Object? wire) {
    for (final kind in values) {
      if (kind.wire == wire) return kind;
    }
    return null;
  }
}

/// Who put a fact there. `onboarding` is written only by the server.
enum CoachFactSource {
  athleteTyped('athlete_typed', 'You typed it'),
  coachSuggestionConfirmed(
    'coach_suggestion_confirmed',
    'Coach suggested it, you confirmed',
  ),
  onboarding('onboarding', 'From onboarding');

  const CoachFactSource(this.wire, this.label);

  final String wire;
  final String label;

  static CoachFactSource fromWire(Object? wire) {
    for (final source in values) {
      if (source.wire == wire) return source;
    }
    return athleteTyped;
  }
}

/// The most facts one athlete can keep, and the limits of the notes. They come
/// from the server with the memory and are shown to the athlete.
class CoachMemoryLimits {
  const CoachMemoryLimits({
    this.maxFacts = 60,
    this.maxNotes = 20,
    this.noteDays = 60,
  });

  factory CoachMemoryLimits.fromJson(Object? json) {
    if (json is! Map) return const CoachMemoryLimits();
    return CoachMemoryLimits(
      maxFacts: (json['max_facts'] as num?)?.toInt() ?? 60,
      maxNotes: (json['max_notes'] as num?)?.toInt() ?? 20,
      noteDays: (json['note_days'] as num?)?.toInt() ?? 60,
    );
  }

  final int maxFacts;
  final int maxNotes;
  final int noteDays;
}

/// One confirmed fact, the current version of it.
class CoachFact {
  const CoachFact({
    required this.id,
    required this.lineageId,
    required this.version,
    required this.kind,
    required this.subject,
    required this.statement,
    required this.source,
    required this.confirmedAt,
    this.reconfirmAt,
    this.reconfirmDue = false,
  });

  factory CoachFact.fromJson(Map<String, dynamic> json) => CoachFact(
    id: json['id'] as String,
    lineageId: json['lineage_id'] as String,
    version: (json['version'] as num).toInt(),
    kind: CoachFactKind.fromWire(json['kind']) ?? CoachFactKind.otherPreference,
    subject: json['subject'] as String,
    statement: json['statement'] as String,
    source: CoachFactSource.fromWire(json['source']),
    confirmedAt: DateTime.parse(json['confirmed_at'] as String),
    reconfirmAt: json['reconfirm_at'] == null
        ? null
        : DateTime.parse(json['reconfirm_at'] as String),
    reconfirmDue: json['reconfirm_due'] == true,
  );

  final String id;
  final String lineageId;
  final int version;
  final CoachFactKind kind;
  final String subject;
  final String statement;
  final CoachFactSource source;
  final DateTime confirmedAt;

  /// When Coach should ask again (injuries and schedule limits); null for
  /// kinds that do not lapse.
  final DateTime? reconfirmAt;

  /// That date has come: the memory screen asks whether the fact still holds.
  final bool reconfirmDue;
}

/// How a note's advice turned out, once a week has passed.
class CoachNoteFollowThrough {
  const CoachNoteFollowThrough({required this.status, required this.detail});

  factory CoachNoteFollowThrough.fromJson(Map<String, dynamic> json) =>
      CoachNoteFollowThrough(
        status: json['status'] as String,
        detail: json['detail'] as String? ?? '',
      );

  /// `followed`, `partly` or `not_followed`.
  final String status;
  final String detail;

  String get label => switch (status) {
    'followed' => 'You followed it',
    'partly' => 'You followed it in part',
    _ => 'Not followed',
  };
}

/// One of Coach's own notes about a past conversation or a piece of advice.
class CoachNote {
  const CoachNote({
    required this.id,
    required this.entryKind,
    required this.noteDate,
    required this.summary,
    this.followThrough,
  });

  factory CoachNote.fromJson(Map<String, dynamic> json) => CoachNote(
    id: json['id'] as String,
    entryKind: json['entry_kind'] as String,
    noteDate: DateTime.parse(json['note_date'] as String),
    summary: json['summary'] as String,
    followThrough: json['follow_through'] is Map
        ? CoachNoteFollowThrough.fromJson(
            Map<String, dynamic>.from(json['follow_through'] as Map),
          )
        : null,
  );

  final String id;

  /// `conversation` or `advice`.
  final String entryKind;
  final DateTime noteDate;
  final String summary;
  final CoachNoteFollowThrough? followThrough;

  bool get isAdvice => entryKind == 'advice';
}

class CoachMemory {
  const CoachMemory({
    this.facts = const [],
    this.notes = const [],
    this.limits = const CoachMemoryLimits(),
  });

  /// Reads `get_my_coach_memory_v1`. A fact or note this build cannot read is
  /// left out rather than failing the whole screen.
  factory CoachMemory.fromJson(Map<String, dynamic> json) {
    List<T> read<T>(Object? rows, T Function(Map<String, dynamic>) parse) => [
      for (final row in rows as List? ?? const []) ?_tryParse(row, parse),
    ];
    return CoachMemory(
      facts: read(json['facts'], CoachFact.fromJson),
      notes: read(json['notes'], CoachNote.fromJson),
      limits: CoachMemoryLimits.fromJson(json['limits']),
    );
  }

  final List<CoachFact> facts;
  final List<CoachNote> notes;
  final CoachMemoryLimits limits;

  bool get isEmpty => facts.isEmpty && notes.isEmpty;
  bool get factsFull => facts.length >= limits.maxFacts;
}

T? _tryParse<T>(Object? row, T Function(Map<String, dynamic>) parse) {
  if (row is! Map) return null;
  try {
    return parse(Map<String, dynamic>.from(row));
  } on Object {
    return null;
  }
}

/// The short label saved with a fact typed on the memory screen: the
/// statement in lower case, one line, at most 60 characters, cut at a word.
String coachFactSubjectFor(String statement) {
  final flat = statement
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[.!?,;:]+$'), '')
      .trim();
  if (flat.length <= 60) return flat;
  final cut = flat.substring(0, 60);
  final space = cut.lastIndexOf(' ');
  return (space > 30 ? cut.substring(0, space) : cut).trim();
}
