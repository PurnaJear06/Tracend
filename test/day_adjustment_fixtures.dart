import 'dart:async';

import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/day_adjustment_repository.dart';

/// One exercise of a change in `get_my_day_adjustment_v1`'s shape.
Map<String, dynamic> change(
  int order,
  String name, {
  required int from,
  required int to,
  num? loadFrom,
  num? loadTo,
  int? repsFrom,
  int? repsTo,
  num? rpeTo,
  String? note,
}) => {
  'exercise_order': order,
  'planned_exercise_id': 'e$order',
  'name': name,
  'sets_from': from,
  'sets_to': to,
  'load_note': note,
  'load_kg_from': loadFrom,
  'load_kg_to': loadTo,
  'reps_from': repsFrom,
  'reps_to': repsTo,
  'rpe_to': rpeTo,
};

const _cardio = {
  'minutes_min': 20,
  'minutes_max': 30,
  'effort': 'easy',
  'talk_test': true,
  'vigorous_allowed': false,
};

/// The three kinds the server offers on a day with a session, for the workout
/// of [orders] (order, name, sets).
List<Map<String, dynamic>> optionsFor(List<(int, String, int)> exercises) {
  List<Map<String, dynamic>> held() => [
    for (final (order, name, sets) in exercises)
      change(
        order,
        name,
        from: sets,
        to: sets,
        loadFrom: 60,
        loadTo: 57.5,
        repsFrom: 8,
        repsTo: 6,
        note: "Keep last time's 57.5 kg",
      ),
  ];
  List<Map<String, dynamic>> lighter() => [
    for (final (order, name, sets) in exercises)
      change(
        order,
        name,
        from: sets,
        to: sets >= 3 ? sets - 1 : sets,
        loadFrom: 60,
        loadTo: 57.5,
        repsFrom: 8,
        repsTo: 6,
        rpeTo: 7,
        note: "Keep last time's 57.5 kg",
      ),
  ];
  int total(List<Map<String, dynamic>> changes) =>
      changes.fold(0, (sum, c) => sum + (c['sets_to'] as int));
  return [
    {
      'kind': 'hold_load',
      'explanation': "Keep last time's weights instead of adding more.",
      'sets_total_to': total(held()),
      'changes': held(),
      'cardio': null,
    },
    {
      'kind': 'reduce_sets',
      'explanation': "One set fewer on 2 exercises and last time's weights.",
      'sets_total_to': total(lighter()),
      'changes': lighter(),
      'cardio': null,
    },
    {
      'kind': 'swap_to_easy_cardio',
      'explanation':
          'Try 20 to 30 minutes of easy walking, cycling or swimming at a '
          'pace you can talk through. It keeps you moving without adding '
          'strain.',
      'sets_total_to': 0,
      'changes': [
        for (final (order, name, sets) in exercises)
          change(order, name, from: sets, to: 0),
      ],
      'cardio': _cardio,
    },
  ];
}

const bench = (1, 'Bench press', 3);
const row = (2, 'Barbell row', 3);
const press = (3, 'Overhead press', 3);

/// A `get_my_day_adjustment_v1` payload. [kind] is the proposal or the answer
/// in force; [status] is `none`, `proposed`, `accepted` or `declined`.
Map<String, dynamic> adjustmentJson({
  String day = '2026-10-02',
  String workoutId = 'w-upper-a',
  String kind = 'reduce_sets',
  String status = 'proposed',
  String band = 'amber',
  List<String> triggers = const ['sleep_poor', 'sore'],
  List<(int, String, int)> exercises = const [bench, row, press],
  bool available = true,
  String? unavailable,
  String? safetyRoute,
  String? confidence = 'medium',
  List<String> missing = const ['sleep'],
  Map<String, dynamic>? previous,
  String? origin,
  Map<String, dynamic>? signals,
  String? explanation,
}) {
  final options = optionsFor(exercises);
  final option = kind == 'none'
      ? null
      : options.firstWhere((o) => o['kind'] == kind);
  final from = exercises.fold(0, (sum, e) => sum + e.$3);
  return {
    'schema_version': '1.0',
    'local_date': day,
    'band': band,
    'triggers': triggers,
    'kind': kind,
    'changes': option?['changes'] ?? <Object>[],
    'explanation':
        explanation ??
        (kind == 'reduce_sets'
            ? "You slept poorly and you're sore. One set fewer on 3 exercises "
                  "and last time's weights."
            : kind == 'hold_load'
            ? "You slept poorly. Keep last time's weights instead of adding "
                  'more.'
            : kind == 'swap_to_easy_cardio'
            ? 'You slept very poorly. Try 20 to 30 minutes of easy walking.'
            : 'Nothing in today\'s session needs to change.'),
    'status': status,
    'available': available,
    'unavailable_reason': unavailable,
    'safety_route': safetyRoute,
    'confidence': confidence,
    'missing': missing,
    'cardio': kind == 'swap_to_easy_cardio' ? _cardio : null,
    'planned_workout_id': workoutId,
    'workout_name': 'Upper body A',
    'sets_total_from': from,
    'sets_total_to': option?['sets_total_to'] ?? from,
    'previous_answer': previous,
    'answered_at': status == 'accepted' || status == 'declined'
        ? '2026-10-02T06:41:12.345678+00:00'
        : null,
    'rules_version': 'readiness-v1',
    'origin': origin,
    'options': available && safetyRoute == null ? options : <Object>[],
    'signals':
        signals ??
        {
          'recovery_score': 60,
          'recovery_confidence': 'high',
          'recovery_mode': 'night',
          'recovery_low': false,
          'sleep_minutes': null,
        },
  };
}

/// What the server answers to a respond call, for [json]: an accepted kind
/// (the proposal or [chosen]) or a decline.
Map<String, dynamic> answered(
  Map<String, dynamic> json, {
  required bool accept,
  String? chosen,
}) {
  final next = Map<String, dynamic>.from(json);
  final kind = chosen ?? json['kind'] as String;
  if (accept) {
    final option = (json['options'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((o) => o['kind'] == kind);
    next
      ..['status'] = 'accepted'
      ..['kind'] = kind
      ..['changes'] = option['changes']
      ..['sets_total_to'] = option['sets_total_to']
      ..['cardio'] = option['cardio']
      ..['origin'] = chosen == null || chosen == json['kind']
          ? 'proposed'
          : 'chosen'
      ..['explanation'] = option['explanation']
      ..['previous_answer'] = null;
  } else {
    next
      ..['status'] = 'declined'
      ..['previous_answer'] = null;
  }
  next['answered_at'] = '2026-10-02T07:00:00.000000+00:00';
  return next;
}

/// The server, as far as the app can tell: reads return [json], answers change
/// it, and every call is recorded.
class FakeDayAdjustmentRepository implements DayAdjustmentRepository {
  FakeDayAdjustmentRepository(this.json);

  Map<String, dynamic> json;
  final loads = <DateTime>[];
  final responses =
      <({DateTime day, bool accept, DayAdjustmentKind? chosen})>[];
  DayAdjustmentException? loadError;
  DayAdjustmentException? respondError;

  /// When set, a read waits for it.
  Completer<void>? loadGate;

  /// When set, an answer waits for it: the answer is on its way.
  Completer<void>? respondGate;

  @override
  Future<DayAdjustment> load(DateTime localToday) async {
    loads.add(localToday);
    await loadGate?.future;
    if (loadError != null) throw loadError!;
    return _parse();
  }

  DayAdjustment _parse() =>
      DayAdjustment.tryParse(json) ??
      (throw const DayAdjustmentException(DayAdjustmentFailure.unreadable));

  @override
  Future<DayAdjustment> respond(
    DateTime localToday, {
    required bool accept,
    DayAdjustmentKind? chosen,
  }) async {
    responses.add((day: localToday, accept: accept, chosen: chosen));
    await respondGate?.future;
    if (respondError != null) throw respondError!;
    json = answered(json, accept: accept, chosen: chosen?.wire);
    return _parse();
  }
}
