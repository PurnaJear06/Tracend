import 'package:tracend/features/coach/proposals/coach_proposal.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_repository.dart';

/// What a proposal card says when an answer did not apply. The words depend on
/// who made the proposal: Coach's card may send the athlete back to Coach, a
/// card the rules made (a lighter week on Train) speaks as Tracend and never
/// names Coach as its author.

/// Said when an approval came back as expired: [reason] is the server's.
String proposalStaleNotice(
  String? reason,
  CoachProposalOrigin origin,
) => switch (origin) {
  CoachProposalOrigin.coach => switch (reason) {
    'expired' =>
      'This proposal expired before it was approved, so nothing changed.',
    'block_over' || 'block_running' =>
      'Your plan moved on while this was open, so nothing changed. Ask Coach again.',
    _ =>
      'Your plan changed since Coach proposed this, so nothing was applied. Ask Coach again.',
  },
  CoachProposalOrigin.tracend => switch (reason) {
    'expired' =>
      'This lighter week expired before it was approved, so nothing '
          'changed.',
    'block_over' || 'block_running' =>
      'Your plan moved on while this was open, so nothing changed. Pull '
          'down on Train to look again.',
    _ =>
      'Your plan changed since this was prepared, so nothing was applied. '
          'Pull down on Train to look again.',
  },
};

/// Said when the server refused an answer.
String proposalErrorNotice(
  CoachProposalException error,
  CoachProposalOrigin origin,
) {
  if (origin == CoachProposalOrigin.coach ||
      error.safetyRouteDay ||
      !error.stale) {
    return error.message;
  }
  return 'This lighter week can no longer be applied. Pull down on Train to '
      'look again.';
}
