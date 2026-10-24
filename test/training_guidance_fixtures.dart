import 'dart:convert';
import 'dart:io';

import 'package:tracend/features/coach/proposals/coach_proposal.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_repository.dart';
import 'package:tracend/features/train/guidance/training_guidance.dart';
import 'package:tracend/features/train/guidance/training_guidance_repository.dart';

/// A contract fixture of `get_my_training_guidance_v1`, moved to [date] (the
/// training hub fixtures name 2 October as the server's today).
Map<String, dynamic> guidanceJson(
  String name, {
  String date = '2026-10-02',
  void Function(Map<String, dynamic> json)? change,
}) {
  final json = Map<String, dynamic>.from(
    jsonDecode(File('test/contract/fixtures/$name.json').readAsStringSync())
        as Map,
  )..['local_date'] = date;
  if (json['cardio_week'] is Map) {
    json['cardio_week'] = Map<String, dynamic>.from(json['cardio_week'] as Map);
  }
  json['deload'] = Map<String, dynamic>.from(json['deload'] as Map);
  change?.call(json);
  return json;
}

/// The suggestion on 2 October: two reasons, cardio at 85 of 150 minutes.
Map<String, dynamic> suggestedJson({
  void Function(Map<String, dynamic> json)? change,
}) => guidanceJson('training_guidance_v1_1', change: change);

Map<String, dynamic> deloadOf(Map<String, dynamic> json) =>
    json['deload'] as Map<String, dynamic>;

Map<String, dynamic> cardioOf(Map<String, dynamic> json) =>
    json['cardio_week'] as Map<String, dynamic>;

const deloadProposalId = '00000000-0000-4000-8000-0000000000b1';

/// The lighter-week proposal as `get_my_coach_proposals_v1` carries it.
///
/// [byRules] false is a lighter week the athlete asked Coach for: it lacks the
/// `DELOAD_SIGNALS` evidence the rules' own suggestion carries.
CoachProposal deloadProposal({
  String status = 'pending',
  bool canUndo = false,
  bool byRules = true,
}) => CoachProposal.fromJson({
  'id': deloadProposalId,
  'kind': 'intensity_or_phase',
  'status': status,
  'title': 'Deload until 8 Oct',
  'rationale':
      'Two or more of your lifts have stalled or slipped. For 1 week your sets '
      'are halved, loads stay at your current working weights, and effort '
      'stays at 7 or below. Your regular plan returns after 8 Oct.',
  'benefit': 'Recovery while you keep the habit and the movement patterns.',
  'downside': 'Less training stress for a short while, so progress pauses.',
  'confidence': 'medium',
  'evidence': [
    {
      'code': 'TRAINING_STANDARD',
      'label': "Tracend's weekly volume, effort and rest limits for you",
      'source': 'policy_evaluation',
    },
    if (byRules)
      {
        'code': 'DELOAD_SIGNALS',
        'label': 'Your logged lifts, check-ins and training weeks',
        'source': 'training_guidance',
      },
  ],
  'before': {
    'rows': [
      {'label': 'Effort', 'value': 'Your regular effort'},
      {'label': 'Weekly sets', 'value': '16'},
    ],
  },
  'after': {
    'rows': [
      {'label': 'Effort', 'value': 'RPE 7 or lower'},
      {'label': 'Weekly sets', 'value': '8'},
      {'label': 'Until', 'value': '8 Oct'},
    ],
  },
  'created_at': '2026-10-02T09:00:00+00:00',
  'expires_at': '2026-10-05T09:00:00+00:00',
  'ends_on': '2026-10-08',
  'applied_at': status == 'accepted' ? '2026-10-02T09:05:00+00:00' : null,
  'undo_until': status == 'accepted' ? '2026-10-09T09:05:00+00:00' : null,
  'undone_at': null,
  'can_undo': canUndo,
  'source_message_id': null,
})!;

/// Answers like the server's guidance reader and the training-proposals
/// function, and records what it was asked.
class FakeGuidanceRepository implements TrainingGuidanceRepository {
  FakeGuidanceRepository(this.json);

  Map<String, dynamic> json;
  final loads = <DateTime>[];
  final prepares = <DateTime>[];
  String prepareId = deloadProposalId;
  TrainingGuidanceException? loadError;

  /// Thrown by a read in place of an answer: not a [TrainingGuidanceException].
  Object? loadThrows;
  TrainingGuidanceException? prepareError;

  /// Runs when a lighter week is prepared, before it answers: the server
  /// changes its mind, or stores the proposal.
  void Function()? onPrepare;

  /// Holds the answer to a prepare until it completes, for a request still on
  /// its way.
  Future<void>? prepareGate;

  @override
  Future<TrainingGuidance> load(DateTime localToday) async {
    loads.add(localToday);
    if (loadError != null) throw loadError!;
    if (loadThrows != null) throw loadThrows!;
    return TrainingGuidance.tryParse(json)!;
  }

  @override
  Future<String> prepareDeload(DateTime localToday) async {
    prepares.add(localToday);
    onPrepare?.call();
    await prepareGate;
    if (prepareError != null) throw prepareError!;
    return prepareId;
  }
}

/// Answers a proposal like the server: approving makes it accepted with an
/// undo window, declining closes it, undo restores.
class FakeProposals implements CoachProposalRepository {
  FakeProposals(this.proposal);

  CoachProposal proposal;

  /// Runs after each answer the server takes ('approve', 'decline', 'undo'):
  /// the guidance the server would give next changes with it.
  void Function(String answer)? onAnswer;
  final calls = <String>[];
  final loadedIds = <String?>[];

  @override
  Future<List<CoachProposal>> load({String? id}) async {
    loadedIds.add(id);
    return [proposal];
  }

  @override
  Future<CoachProposalAnswer> respond(
    String id,
    CoachProposalAction action, {
    String? note,
  }) async {
    calls.add(action.wire);
    switch (action) {
      case CoachProposalAction.approve:
        proposal = deloadProposal(
          status: 'accepted',
          canUndo: true,
          byRules: proposal.suggestedByRules,
        );
      case CoachProposalAction.decline:
        proposal = proposal.withStatus(CoachProposalStatus.declined, null);
      case CoachProposalAction.change:
        proposal = proposal.withStatus(CoachProposalStatus.changed, null);
    }
    onAnswer?.call(action.wire);
    return CoachProposalAnswer(
      proposalId: id,
      status: switch (action) {
        CoachProposalAction.approve => 'accepted',
        CoachProposalAction.decline => 'declined',
        CoachProposalAction.change => 'changed',
      },
      changedPlan: action == CoachProposalAction.approve,
    );
  }

  @override
  Future<CoachProposalAnswer> undo(String id) async {
    calls.add('undo');
    proposal = proposal.withStatus(CoachProposalStatus.undone, null);
    onAnswer?.call('undo');
    return CoachProposalAnswer(
      proposalId: id,
      status: 'undone',
      changedPlan: true,
    );
  }
}
