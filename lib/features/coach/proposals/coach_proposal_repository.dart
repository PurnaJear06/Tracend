import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/coach/proposals/coach_proposal.dart';

/// A proposal answer the server refused, with a message that can be shown as
/// is.
class CoachProposalException implements Exception {
  const CoachProposalException(this.message);
  final String message;
  @override
  String toString() => 'CoachProposalException: $message';
}

const _connectionMessage =
    'Could not reach Tracend. Check your connection and try again.';

/// What to tell the athlete when the server refuses an answer. 55000 means
/// the proposal can no longer be answered (it was answered already, or the
/// health check changed), anything else is a connection or session problem.
String coachProposalErrorMessage(PostgrestException error) {
  if (error.code == '55000') {
    return 'This change can no longer be applied. Ask Coach again and it '
        'will start from your latest plan.';
  }
  return _connectionMessage;
}

/// Reads and answers Coach proposals. Approving is the athlete's act alone:
/// no model answer reaches these calls.
abstract interface class CoachProposalRepository {
  /// The athlete's proposals, newest first; one proposal when [id] is given.
  Future<List<CoachProposal>> load({String? id});

  Future<CoachProposalAnswer> respond(
    String id,
    CoachProposalAction action, {
    String? note,
  });

  /// Restores what an approved proposal replaced, within the undo window.
  Future<CoachProposalAnswer> undo(String id);
}

class SupabaseCoachProposalRepository implements CoachProposalRepository {
  SupabaseCoachProposalRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<CoachProposal>> load({String? id}) async {
    final Object? value;
    try {
      value = await _client.rpc(
        'get_my_coach_proposals_v1',
        params: {'p_proposal_id': ?id},
      );
    } on PostgrestException catch (error) {
      debugPrint('Non-critical error: $error');
      throw CoachProposalException(coachProposalErrorMessage(error));
    } on Exception catch (error) {
      // A lost connection or a timeout is a connection message too.
      debugPrint('Non-critical error: $error');
      throw const CoachProposalException(_connectionMessage);
    }
    return CoachProposal.listFromJson(value);
  }

  @override
  Future<CoachProposalAnswer> respond(
    String id,
    CoachProposalAction action, {
    String? note,
  }) => _answer('respond_to_coach_proposal_v1', {
    'proposal_id': id,
    'action': action.wire,
    if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
  });

  @override
  Future<CoachProposalAnswer> undo(String id) =>
      _answer('undo_coach_proposal_v1', {'proposal_id': id});

  Future<CoachProposalAnswer> _answer(
    String function,
    Map<String, dynamic> params,
  ) async {
    final Object? value;
    try {
      value = await _client.rpc(function, params: params);
    } on PostgrestException catch (error) {
      debugPrint('Non-critical error: $error');
      throw CoachProposalException(coachProposalErrorMessage(error));
    } on Exception catch (error) {
      // The answer may still have been written: the card reads the proposal
      // again after any error.
      debugPrint('Non-critical error: $error');
      throw const CoachProposalException(_connectionMessage);
    }
    final answer = CoachProposalAnswer.fromJson(value);
    if (answer == null) {
      throw const CoachProposalException(
        'Tracend sent an answer this version cannot read. Update the app and try again.',
      );
    }
    return answer;
  }
}
