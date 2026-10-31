import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/goals/goal_target.dart';
import 'package:tracend/shared/diagnostics.dart';

/// A target the server refused, with a message that can be shown as is.
class GoalTargetException implements Exception {
  const GoalTargetException(this.message);
  final String message;
  @override
  String toString() => 'GoalTargetException: $message';
}

/// What to tell the athlete when the server refuses a target. 22023 carries a
/// plain-language reason (for example a weight below the healthy range), 55000
/// means there is no active goal, and anything else is a connection or session
/// problem.
String goalTargetErrorMessage(PostgrestException error) {
  if (error.code == '22023' && error.message.isNotEmpty) {
    return '${error.message[0].toUpperCase()}${error.message.substring(1)}.';
  }
  if (error.code == '55000') {
    return 'You have no active goal to set a target for. Finish setting up '
        'your plan first.';
  }
  return 'Could not save your target. Check your connection and try again.';
}

/// Reads and sets the target of the athlete's active goal. Setting is the
/// athlete's act alone: nothing here is reachable from a model answer.
abstract interface class GoalTargetRepository {
  Future<GoalTargetState> load();

  /// Replaces the whole target (a part left null is unset).
  Future<GoalTargetState> save(GoalTarget target);
}

class SupabaseGoalTargetRepository implements GoalTargetRepository {
  SupabaseGoalTargetRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<GoalTargetState> load() async {
    final state = GoalTargetState.fromJson(
      await _client.rpc('get_goal_target_v1'),
    );
    if (state == null) {
      throw const FormatException('The goal target is unavailable.');
    }
    return state;
  }

  @override
  Future<GoalTargetState> save(GoalTarget target) async {
    final date = target.date;
    final Object? value;
    try {
      value = await _client.rpc(
        'set_goal_target_v1',
        params: {
          if (target.weightKg != null) 'p_target_weight_kg': target.weightKg,
          if (target.bodyFatMinPct != null)
            'p_body_fat_pct_min': target.bodyFatMinPct,
          if (target.bodyFatMaxPct != null)
            'p_body_fat_pct_max': target.bodyFatMaxPct,
          if (target.physique != null) 'p_physique': target.physique,
          if (target.physiqueNote != null)
            'p_physique_note': target.physiqueNote,
          if (date != null)
            'p_target_date':
                '${date.year.toString().padLeft(4, '0')}-'
                '${date.month.toString().padLeft(2, '0')}-'
                '${date.day.toString().padLeft(2, '0')}',
        },
      );
    } on PostgrestException catch (error) {
      logNonCritical(error);
      // 22023 carries a plain-language reason (for example a weight below the
      // healthy range); anything else is a connection or session problem.
      throw GoalTargetException(goalTargetErrorMessage(error));
    }
    final state = GoalTargetState.fromJson(value);
    if (state == null) {
      throw const GoalTargetException(
        'Could not save your target. Check your connection and try again.',
      );
    }
    return state;
  }
}

/// Builds without a backend: there is no goal, so no target card shows.
class FixtureGoalTargetRepository implements GoalTargetRepository {
  const FixtureGoalTargetRepository();

  @override
  Future<GoalTargetState> load() async =>
      const GoalTargetState(hasGoal: false, target: GoalTarget());

  @override
  Future<GoalTargetState> save(GoalTarget target) =>
      throw StateError('Configure Supabase.');
}
