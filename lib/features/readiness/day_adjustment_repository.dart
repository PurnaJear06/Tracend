import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';

/// Why a read or an answer did not go through.
enum DayAdjustmentFailure {
  /// The server's day is not the date that was sent (22023 on a read).
  wrongDate,

  /// The server refused the answer: nothing to answer, a day with a safety
  /// route, or a change that would alter nothing (22023 on an answer).
  refused,

  /// Today can no longer be adjusted: the session started or is done (55000).
  unavailable,

  /// Too many answers today (P0001).
  tooMany,

  /// Tracend sent something this version cannot read.
  unreadable,

  /// No connection, or the session ended.
  network,
}

class DayAdjustmentException implements Exception {
  const DayAdjustmentException(this.failure);
  final DayAdjustmentFailure failure;
  @override
  String toString() => 'DayAdjustmentException: ${failure.name}';
}

/// Reads and answers today's same-day adjustment. The answer is the athlete's
/// act alone; the rules only propose.
abstract interface class DayAdjustmentRepository {
  /// Today's adjustment. [localToday] is the server's own today (the training
  /// hub's `local_today`); the server refuses any other date.
  Future<DayAdjustment> load(DateTime localToday);

  /// Applies the proposal (or [chosen], a kind the athlete picked), or with
  /// `accept: false` trains as planned, which also undoes an accepted answer.
  Future<DayAdjustment> respond(
    DateTime localToday, {
    required bool accept,
    DayAdjustmentKind? chosen,
  });
}

typedef DayAdjustmentRpc =
    Future<Object?> Function(String function, Map<String, dynamic> params);

class SupabaseDayAdjustmentRepository implements DayAdjustmentRepository {
  SupabaseDayAdjustmentRepository(SupabaseClient client)
    : _rpc = ((function, params) => client.rpc(function, params: params));

  /// Talks through [rpc] instead of a client, for tests.
  @visibleForTesting
  SupabaseDayAdjustmentRepository.withRpc(DayAdjustmentRpc rpc) : _rpc = rpc;

  final DayAdjustmentRpc _rpc;

  static String _date(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// This build shows and applies joint changes (a swap, a pain-free range,
  /// an exercise left out). It says so on every read and on every answer: a
  /// client that said it on one and not the other would preview one session
  /// and store another.
  static const _jointChanges = {'supports_joint_changes': true};

  @override
  Future<DayAdjustment> load(DateTime localToday) => _call(
    'get_my_day_adjustment_v1',
    {'local_date': _date(localToday), ..._jointChanges},
    refused: DayAdjustmentFailure.wrongDate,
  );

  @override
  Future<DayAdjustment> respond(
    DateTime localToday, {
    required bool accept,
    DayAdjustmentKind? chosen,
  }) => _call('respond_to_day_adjustment_v1', {
    'local_date': _date(localToday),
    'accept': accept,
    if (chosen != null) 'chosen_kind': chosen.wire,
    ..._jointChanges,
  }, refused: DayAdjustmentFailure.refused);

  Future<DayAdjustment> _call(
    String function,
    Map<String, dynamic> params, {
    required DayAdjustmentFailure refused,
  }) async {
    final Object? value;
    try {
      value = await _rpc(function, params);
    } on PostgrestException catch (error) {
      debugPrint('Non-critical error: day adjustment: $error');
      throw DayAdjustmentException(switch (error.code) {
        '22023' => refused,
        '55000' => DayAdjustmentFailure.unavailable,
        'P0001' => DayAdjustmentFailure.tooMany,
        _ => DayAdjustmentFailure.network,
      });
    }
    final adjustment = DayAdjustment.tryParse(value);
    if (adjustment == null) {
      throw const DayAdjustmentException(DayAdjustmentFailure.unreadable);
    }
    return adjustment;
  }
}
