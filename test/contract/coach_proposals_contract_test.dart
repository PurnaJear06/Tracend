import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/coach/proposals/coach_proposal.dart';

Map<String, dynamic> _loadFixtureJson(String name) {
  final file = File('test/contract/fixtures/$name');
  if (!file.existsSync()) {
    throw FileSystemException('Contract fixture not found: $name');
  }
  final parsed = json.decode(file.readAsStringSync());
  if (parsed is! Map<String, dynamic>) {
    throw FormatException('Contract fixture "$name" must be a JSON object');
  }
  return parsed;
}

void main() {
  group('Coach proposals contract — get_my_coach_proposals_v1 1.0', () {
    // The key lists are the contract: add keys, never remove or rename them.
    // The same lists are asserted against the database in
    // supabase/tests/database/coach_proposals_test.sql.
    const proposalKeys = [
      'after',
      'applied_at',
      'before',
      'benefit',
      'can_undo',
      'confidence',
      'created_at',
      'downside',
      'ends_on',
      'evidence',
      'expires_at',
      'id',
      'kind',
      'rationale',
      'source_message_id',
      'status',
      'title',
      'undo_until',
      'undone_at',
    ];
    const answerKeys = [
      'goal_id',
      'nutrition_target_set_id',
      'proposal_id',
      'schema_version',
      'status',
      'training_plan_version_id',
      'undo_until',
    ];
    const undoKeys = [
      'goal_id',
      'nutrition_target_set_id',
      'proposal_id',
      'schema_version',
      'status',
      'training_plan_version_id',
    ];

    test('the list carries its schema version and every proposal its keys', () {
      final fixture = _loadFixtureJson('coach_proposals_v1_0.json');
      expect(fixture['schema_version'], '1.0');
      expect(fixture.keys.toList()..sort(), ['proposals', 'schema_version']);
      for (final proposal in fixture['proposals'] as List) {
        expect(
          (proposal as Map<String, dynamic>).keys.toList()..sort(),
          proposalKeys,
        );
      }
    });

    test('approve and undo answer exactly their keys', () {
      expect(
        _loadFixtureJson('respond_to_coach_proposal_v1_0.json').keys.toList()
          ..sort(),
        answerKeys,
      );
      expect(
        _loadFixtureJson('undo_coach_proposal_v1_0.json').keys.toList()..sort(),
        undoKeys,
      );
    });

    test('the proposals parse into their parts', () {
      final proposals = CoachProposal.listFromJson(
        _loadFixtureJson('coach_proposals_v1_0.json'),
      );
      expect(proposals.map((p) => p.status), [
        CoachProposalStatus.pending,
        CoachProposalStatus.accepted,
        CoachProposalStatus.expired,
      ]);
      final pending = proposals.first;
      expect(pending.kind, 'goal_or_phase');
      expect(pending.title, 'Take a diet break');
      expect(pending.before.rows.first.label, 'Phase');
      expect(pending.after.rows[1].value, '2,240 kcal');
      expect(pending.endsOn, DateTime(2026, 10, 31));
      expect(pending.canUndo, isFalse);
      expect(pending.evidence.map((e) => e.code), [
        'NUTRITION_POLICY_V2',
        'GOAL_PHASE_REVIEW',
      ]);
      final block = proposals[1];
      expect(block.canUndo, isTrue);
      expect(block.after.sessions.length, 3);
      expect(
        block.after.sessions.first.line,
        'Mon · Full body A · 5 exercises · 51 min',
      );
      expect(block.undoUntil, isNotNull);
    });

    test('approve and undo answers parse', () {
      final approved = CoachProposalAnswer.fromJson(
        _loadFixtureJson('respond_to_coach_proposal_v1_0.json'),
      )!;
      expect(approved.status, 'accepted');
      expect(approved.changedPlan, isTrue);
      expect(approved.undoUntil, isNotNull);
      final undone = CoachProposalAnswer.fromJson(
        _loadFixtureJson('undo_coach_proposal_v1_0.json'),
      )!;
      expect(undone.status, 'undone');
      expect(undone.changedPlan, isTrue);
    });

    test('a payload that is not the expected shape yields nothing', () {
      expect(CoachProposal.listFromJson(null), isEmpty);
      expect(CoachProposal.listFromJson({'proposals': []}), isEmpty);
      final fixture = _loadFixtureJson('coach_proposals_v1_0.json');
      final broken = json.decode(json.encode(fixture)) as Map<String, dynamic>;
      ((broken['proposals'] as List).first as Map<String, dynamic>)['status'] =
          'sideways';
      expect(CoachProposal.listFromJson(broken), isEmpty);
      expect(CoachProposalAnswer.fromJson({'status': 'accepted'}), isNull);
    });
  });
}
