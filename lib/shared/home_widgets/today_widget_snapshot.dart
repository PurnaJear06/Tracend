import 'dart:convert';

import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_session_progress.dart';
import 'package:tracend/features/train/workout_draft.dart' show formatKg;

/// What the Today and Lock Screen widgets show, as the compact, versioned
/// JSON the app writes to the app group (`ios/Shared/TodayWidgetSnapshot.swift`
/// reads it; `test/contract/fixtures/today_widget_snapshot_v1.json` pins the
/// shape for both sides).
///
/// Every number is the one Today already shows, taken from the loaded brief
/// and the plan's targets; the widgets calculate nothing. Nothing here is free
/// text (no notes, no coach words, no meal names): the session and exercise
/// names are the plan's own, and the rest are counts. The `lock` section is
/// present only while the athlete chose to show health numbers on the Lock
/// Screen; without it the Lock Screen widgets show a placeholder
/// (SECURITY_PRIVACY.md §10).
class TodayWidgetSnapshot {
  const TodayWidgetSnapshot._({
    required this.generatedAt,
    required this.localDate,
    required this.sessionState,
    required this.sessionName,
    required this.setsLogged,
    required this.setsTotal,
    required this.exercises,
    required this.recovery,
    required this.calories,
    required this.caloriesTarget,
    required this.proteinG,
    required this.proteinTargetG,
    required this.checkInDone,
    required this.lockScreenNumbers,
  });

  /// The JSON shape's version. The widgets show nothing from a version they do
  /// not know and ask the athlete to open the app.
  static const schemaVersion = 1;

  /// A snapshot older than this, or from another day, reads "Open Tracend to
  /// refresh". The widgets take the value from the snapshot itself.
  static const staleAfter = Duration(hours: 12);

  /// The medium widget lists this many exercises at most.
  static const maxExercises = 3;

  /// Builds the snapshot of [brief] as Today shows it. [targets] is the plan's
  /// calorie and protein targets (null when they did not load, and then only
  /// what was eaten shows). [checkedIn] is whether today's check-in is saved.
  /// [lockScreenNumbers] is the athlete's choice to show numbers on the Lock
  /// Screen. [now] stamps the snapshot.
  factory TodayWidgetSnapshot.build({
    required DailyBrief brief,
    required NutritionTargets? targets,
    required bool checkedIn,
    required bool lockScreenNumbers,
    required DateTime now,
  }) {
    final progress = TodaySessionProgress.of(brief);
    final workout = brief.workout;
    return TodayWidgetSnapshot._(
      generatedAt: now,
      localDate: brief.localDate,
      sessionState: progress.state,
      sessionName: workout == null
          ? null
          : _text(workout['name'], fallback: 'Workout'),
      setsLogged: progress.logged,
      setsTotal: progress.total,
      exercises: [
        for (final exercise in progress.exercises.take(maxExercises))
          (
            name: _text(exercise.name, fallback: 'Exercise'),
            target: _target(exercise.row),
          ),
      ],
      recovery: brief.computed?.scores.recovery,
      calories: _whole(brief.nutrition?['calories']),
      caloriesTarget: _positive(targets?.calories),
      proteinG: _whole(brief.nutrition?['protein_g']),
      proteinTargetG: _positive(targets?.protein),
      checkInDone: checkedIn,
      lockScreenNumbers: lockScreenNumbers,
    );
  }

  final DateTime generatedAt;

  /// The brief's local date, `YYYY-MM-DD`.
  final String localDate;

  /// `rest`, `planned`, `in_progress` or `completed`.
  final String sessionState;

  /// Null on a rest day.
  final String? sessionName;
  final int setsLogged;
  final int setsTotal;
  final List<({String name, String target})> exercises;

  /// Today's recovery score; null when it was not scored.
  final int? recovery;
  final int calories;
  final int? caloriesTarget;
  final int proteinG;
  final int? proteinTargetG;
  final bool checkInDone;
  final bool lockScreenNumbers;

  /// The snapshot as the app group stores it.
  Map<String, dynamic> toJson() => {
    ..._content(),
    'generated_at_millis': generatedAt.millisecondsSinceEpoch,
  };

  /// The JSON without its time stamp: two snapshots with the same key show
  /// the same widgets.
  String get contentKey => jsonEncode(_content());

  Map<String, dynamic> _content() => {
    'schema_version': schemaVersion,
    'stale_after_seconds': staleAfter.inSeconds,
    'local_date': localDate,
    'session': {
      'state': sessionState,
      'name': sessionName,
      'sets_logged': setsLogged,
      'sets_total': setsTotal,
      'exercises': [
        for (final exercise in exercises)
          {'name': exercise.name, 'target': exercise.target},
      ],
    },
    'recovery': recovery,
    'nutrition': {
      'calories': calories,
      'calories_target': caloriesTarget,
      'protein_g': proteinG,
      'protein_target_g': proteinTargetG,
    },
    'check_in_done': checkInDone,
    'lock': lockScreenNumbers
        ? {
            'session': sessionName ?? 'Rest day',
            'session_state': sessionState,
            'recovery': recovery,
            'protein_g': proteinG,
            'protein_target_g': proteinTargetG,
          }
        : null,
  };

  /// "4 × 6–8 · 82.5 kg", or without the load when the plan sets none.
  static String _target(Map<String, dynamic> row) {
    final sets = (row['set_count'] as num?)?.toInt() ?? 0;
    final min = (row['rep_min'] as num?)?.toInt() ?? 0;
    final max = (row['rep_max'] as num?)?.toInt() ?? min;
    final reps = min == max ? '$min' : '$min–$max';
    final load = row['target_load_kg'];
    final base = '$sets × $reps';
    return load is num && load > 0 ? '$base · ${formatKg(load)} kg' : base;
  }

  /// A plan name, trimmed and shortened so a long one cannot fill a widget.
  static String _text(Object? value, {required String fallback}) {
    final text = value is String ? value.trim() : '';
    if (text.isEmpty) return fallback;
    return text.length <= 40 ? text : '${text.substring(0, 39)}…';
  }

  static int _whole(Object? value) => value is num ? value.round() : 0;

  static int? _positive(num? value) =>
      value != null && value > 0 ? value.round() : null;
}
