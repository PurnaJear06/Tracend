/// Physique goals an athlete can choose as a target, keyed as the
/// `set_goal_target_v1` function stores them.
const physiqueGoalLabels = <String, String>{
  'visible_abs': 'Visible abs',
  'more_definition': 'More definition',
  'athletic_build': 'Athletic build',
  'bigger_muscles': 'Bigger muscles',
  'stronger': 'Stronger',
  'lean_and_toned': 'Lean and toned',
  'other': 'Something else',
};

/// Longest physique note the function accepts.
const goalPhysiqueNoteMaxLength = 120;

/// The end point the athlete set for their goal. Only the athlete sets it;
/// Coach may ask for one but never writes it.
class GoalTarget {
  const GoalTarget({
    this.weightKg,
    this.bodyFatMinPct,
    this.bodyFatMaxPct,
    this.physique,
    this.physiqueNote,
    this.date,
  });

  final double? weightKg;
  final double? bodyFatMinPct;
  final double? bodyFatMaxPct;

  /// A key of [physiqueGoalLabels].
  final String? physique;
  final String? physiqueNote;
  final DateTime? date;

  bool get hasBodyFat => bodyFatMinPct != null || bodyFatMaxPct != null;

  /// Whether a weight, body-fat range or physique goal is set. A date alone
  /// is not a target.
  bool get isSet => weightKg != null || hasBodyFat || physique != null;

  /// One line for the card, for example "72 kg · by 14 Feb 2027".
  String get summary {
    final parts = <String>[
      if (weightKg != null) '${_trim(weightKg!)} kg',
      if (hasBodyFat) _bodyFat(),
      if (physique != null) _physique(),
      if (date != null) 'by ${_formatDate(date!)}',
    ];
    return parts.join(' · ');
  }

  String _bodyFat() => bodyFatMinPct != null && bodyFatMaxPct != null
      ? '${_trim(bodyFatMinPct!)} to ${_trim(bodyFatMaxPct!)}% body fat'
      : '${_trim((bodyFatMinPct ?? bodyFatMaxPct)!)}% body fat';

  String _physique() {
    final label = physiqueGoalLabels[physique] ?? 'Physique goal';
    final note = physiqueNote;
    return note == null || note.isEmpty ? label : '$label ($note)';
  }

  static String _trim(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _formatDate(DateTime date) =>
      '${date.day} ${_months[date.month - 1]} ${date.year}';

  static double? _number(Object? value) =>
      value is num ? value.toDouble() : null;

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  /// Reads the `target` object of the goal-target functions.
  static GoalTarget fromJson(Object? value) {
    if (value is! Map) return const GoalTarget();
    final physique = _text(value['physique']);
    return GoalTarget(
      weightKg: _number(value['weight_kg']),
      bodyFatMinPct: _number(value['body_fat_pct_min']),
      bodyFatMaxPct: _number(value['body_fat_pct_max']),
      physique: physiqueGoalLabels.containsKey(physique) ? physique : null,
      physiqueNote: _text(value['physique_note']),
      date: DateTime.tryParse(_text(value['date']) ?? ''),
    );
  }
}

/// The active goal and its target, from `get_goal_target_v1` and
/// `set_goal_target_v1` (schema version 1.x).
class GoalTargetState {
  const GoalTargetState({
    required this.hasGoal,
    required this.target,
    this.goalType,
    this.minTargetWeightKg,
  });

  final bool hasGoal;
  final GoalTarget target;
  final String? goalType;

  /// The lowest target weight accepted: BMI 18.5 at the athlete's height.
  /// Null when no height is known.
  final double? minTargetWeightKg;

  /// True only for an active goal with a weight, body-fat range or physique
  /// goal set.
  bool get hasTarget => hasGoal && target.isSet;

  /// Reads a function response; null when it is not a version 1 payload.
  static GoalTargetState? fromJson(Object? value) {
    if (value is! Map) return null;
    final version = value['schema_version'];
    if (version is! String || !version.startsWith('1.')) return null;
    final goalType = value['goal_type'];
    return GoalTargetState(
      hasGoal: value['has_goal'] == true,
      target: GoalTarget.fromJson(value['target']),
      goalType: goalType is String ? goalType : null,
      minTargetWeightKg: GoalTarget._number(value['min_target_weight_kg']),
    );
  }
}
