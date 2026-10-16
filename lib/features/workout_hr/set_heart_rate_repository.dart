import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_summary.dart';

/// A workout's per-set heart-rate summaries, as `get_my_set_heart_rate_v1`
/// returns them.
class SetHeartRateReport {
  const SetHeartRateReport(this.sets);

  factory SetHeartRateReport.fromJson(Map<String, dynamic> json) {
    final rows = json['sets'];
    return SetHeartRateReport([
      for (final row in rows is List ? rows : const [])
        if (row is Map)
          SetHeartRateSummary.fromJson(Map<String, dynamic>.from(row)),
    ]);
  }

  final List<SetHeartRateSummary> sets;

  /// The summaries of one exercise, by set number.
  List<SetHeartRateSummary> forExercise(int exerciseOrder) => [
    for (final set in sets)
      if (set.exerciseOrder == exerciseOrder) set,
  ]..sort((a, b) => a.setNumber.compareTo(b.setNumber));
}

/// Saves and reads the summaries of the signed-in athlete's workouts.
abstract interface class SetHeartRateRepository {
  /// Saves [summaries] for [sessionId], replacing earlier ones for the same
  /// sets; completes with how many sets the server stored. Throws a
  /// [PostgrestException] when the server refuses them.
  Future<int> persist(String sessionId, List<SetHeartRateSummary> summaries);

  Future<SetHeartRateReport> load(String sessionId);
}

class SupabaseSetHeartRateRepository implements SetHeartRateRepository {
  SupabaseSetHeartRateRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<int> persist(
    String sessionId,
    List<SetHeartRateSummary> summaries,
  ) async {
    final value = await _client.rpc(
      'persist_set_heart_rate_v1',
      params: {
        'session_id': sessionId,
        'summaries': [for (final summary in summaries) summary.toJson()],
      },
    );
    return value is Map ? (value['saved'] as num?)?.toInt() ?? 0 : 0;
  }

  @override
  Future<SetHeartRateReport> load(String sessionId) async {
    final value = await _client.rpc(
      'get_my_set_heart_rate_v1',
      params: {'session_id': sessionId},
    );
    return SetHeartRateReport.fromJson(
      value is Map ? Map<String, dynamic>.from(value) : const {},
    );
  }
}
