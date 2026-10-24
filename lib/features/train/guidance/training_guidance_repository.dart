import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/train/guidance/training_guidance.dart';

/// Why a read or a request did not go through.
enum TrainingGuidanceFailure {
  /// The server's day is not the date that was sent.
  wrongDate,

  /// The server no longer suggests a lighter week (the day moved on or the
  /// rules changed their mind): nothing was stored.
  notSuggested,

  /// Another change is waiting for the athlete's answer in Coach; storing a
  /// lighter week would have closed it, so nothing was stored.
  otherProposalPending,

  /// The rules turned the request down; [TrainingGuidanceException.code] says
  /// which rule.
  refused,

  /// Tracend sent something this version cannot read.
  unreadable,

  /// No connection, or the session ended.
  network,
}

class TrainingGuidanceException implements Exception {
  const TrainingGuidanceException(this.failure, {this.code});
  final TrainingGuidanceFailure failure;

  /// The rule that turned the request down (`screening_see_professional`,
  /// `plan_changed`, ...). The app words it; the server's own words are
  /// Coach's.
  final String? code;
  @override
  String toString() => 'TrainingGuidanceException: ${failure.name}';
}

/// Reads today's training guidance and asks for the lighter week to be
/// prepared. Preparing stores a proposal for the athlete to answer; it applies
/// nothing.
abstract interface class TrainingGuidanceRepository {
  /// [localToday] is the server's own today; the server refuses any other.
  Future<TrainingGuidance> load(DateTime localToday);

  /// Stores the lighter week the rules suggest and returns its proposal id, or
  /// the open one when there is one already.
  Future<String> prepareDeload(DateTime localToday);
}

typedef GuidanceRpc =
    Future<Object?> Function(String function, Map<String, dynamic> params);
typedef GuidanceInvoke =
    Future<Object?> Function(String function, Map<String, dynamic> body);

class SupabaseTrainingGuidanceRepository implements TrainingGuidanceRepository {
  SupabaseTrainingGuidanceRepository(SupabaseClient client)
    : _rpc = ((function, params) => client.rpc(function, params: params)),
      _invoke = ((function, body) async {
        final response = await client.functions.invoke(function, body: body);
        return response.data;
      });

  /// Talks through [rpc] and [invoke] instead of a client, for tests.
  @visibleForTesting
  SupabaseTrainingGuidanceRepository.withBackends({
    required GuidanceRpc rpc,
    required GuidanceInvoke invoke,
  }) : _rpc = rpc,
       _invoke = invoke;

  final GuidanceRpc _rpc;
  final GuidanceInvoke _invoke;

  static String _date(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  @override
  Future<TrainingGuidance> load(DateTime localToday) async {
    final Object? value;
    try {
      value = await _rpc('get_my_training_guidance_v1', {
        'local_date': _date(localToday),
      });
    } on PostgrestException catch (error) {
      debugPrint('Non-critical error: training guidance: $error');
      throw TrainingGuidanceException(
        error.code == '22023'
            ? TrainingGuidanceFailure.wrongDate
            : TrainingGuidanceFailure.network,
      );
    }
    final guidance = TrainingGuidance.tryParse(value);
    if (guidance == null) {
      throw const TrainingGuidanceException(TrainingGuidanceFailure.unreadable);
    }
    return guidance;
  }

  @override
  Future<String> prepareDeload(DateTime localToday) async {
    final Object? value;
    try {
      value = await _invoke('training-proposals', {
        'schema_version': '1.0',
        'kind': 'deload',
        'local_date': _date(localToday),
      });
    } on FunctionException catch (error) {
      debugPrint('Non-critical error: lighter week not prepared: $error');
      final details = error.details;
      final code = details is Map ? details['error'] : null;
      throw switch ((error.status, code)) {
        (422, 'wrong_date') => const TrainingGuidanceException(
          TrainingGuidanceFailure.wrongDate,
        ),
        (409, 'not_suggested') => const TrainingGuidanceException(
          TrainingGuidanceFailure.notSuggested,
        ),
        (409, 'other_proposal_pending') => const TrainingGuidanceException(
          TrainingGuidanceFailure.otherProposalPending,
        ),
        (409, final String refusal) => TrainingGuidanceException(
          TrainingGuidanceFailure.refused,
          code: refusal,
        ),
        _ => const TrainingGuidanceException(TrainingGuidanceFailure.network),
      };
    }
    final id = value is Map ? value['proposal_id'] : null;
    if (id is! String || id.isEmpty) {
      throw const TrainingGuidanceException(TrainingGuidanceFailure.unreadable);
    }
    return id;
  }
}
