import 'package:supabase_flutter/supabase_flutter.dart';

class OnboardingDraft {
  const OnboardingDraft({
    required this.path,
    required this.currentSection,
    required this.payload,
  });

  final String? path;
  final String currentSection;
  final Map<String, dynamic> payload;
}

class OnboardingProposal {
  const OnboardingProposal({
    required this.id,
    required this.training,
    required this.nutrition,
    required this.rationale,
    required this.benefit,
    required this.downside,
    required this.confidence,
  });

  final String id;
  final Map<String, dynamic> training;
  final Map<String, dynamic> nutrition;
  final String rationale;
  final String benefit;
  final String downside;
  final String confidence;
}

abstract interface class OnboardingRepository {
  Future<bool> isOnboardingComplete();
  Future<OnboardingDraft?> loadDraft();
  Future<void> saveDraft({
    required String? path,
    required String currentSection,
    required Map<String, dynamic> payload,
  });
  Future<void> recordEligibilityAndConsent({
    required bool eligible,
    required String experience,
    required int trainingDays,
    required int sessionMinutes,
  });
  Future<void> saveGoal(String goal);
  Future<OnboardingProposal> generateProposal();
  Future<OnboardingProposal> loadProposal(String proposalId);
  Future<void> respond(String proposalId, String action);
}

class SupabaseOnboardingRepository implements OnboardingRepository {
  SupabaseOnboardingRepository(this._client);

  final SupabaseClient _client;

  String get _userId => _client.auth.currentUser!.id;

  @override
  Future<bool> isOnboardingComplete() async {
    final row = await _client
        .from('user_accounts')
        .select('onboarding_state')
        .eq('id', _userId)
        .single();
    return row['onboarding_state'] == 'completed';
  }

  @override
  Future<OnboardingDraft?> loadDraft() async {
    final rows = await _client
        .from('onboarding_drafts')
        .select('path,current_section,payload')
        .eq('user_id', _userId)
        .limit(1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return OnboardingDraft(
      path: row['path'] as String?,
      currentSection: row['current_section'] as String,
      payload: Map<String, dynamic>.from(row['payload'] as Map),
    );
  }

  @override
  Future<void> saveDraft({
    required String? path,
    required String currentSection,
    required Map<String, dynamic> payload,
  }) async {
    await _client.from('onboarding_drafts').upsert({
      'user_id': _userId,
      'path': path,
      'current_section': currentSection,
      'payload': payload,
    });
    await _client
        .from('user_accounts')
        .update({'onboarding_state': 'in_progress'})
        .eq('id', _userId);
  }

  @override
  Future<void> recordEligibilityAndConsent({
    required bool eligible,
    required String experience,
    required int trainingDays,
    required int sessionMinutes,
  }) async {
    await _client.from('user_profiles').upsert({
      'user_id': _userId,
      'adult_attested_at': DateTime.now().toUtc().toIso8601String(),
      'eligible': eligible,
      'experience_level': experience,
      'training_days': List<int>.generate(trainingDays, (index) => index + 1),
      'session_minutes': sessionMinutes,
    });
    await _client.from('consent_records').insert([
      {
        'user_id': _userId,
        'consent_type': 'terms',
        'notice_version': '2026-07-01',
        'action': 'granted',
        'source': 'owner_development',
      },
      {
        'user_id': _userId,
        'consent_type': 'privacy',
        'notice_version': '2026-07-01',
        'action': 'granted',
        'source': 'owner_development',
      },
    ]);
  }

  @override
  Future<void> saveGoal(String goal) async {
    final existing = await _client
        .from('user_goals')
        .select('id')
        .eq('user_id', _userId)
        .eq('status', 'draft')
        .limit(1);
    if (existing.isEmpty) {
      await _client.from('user_goals').insert({
        'user_id': _userId,
        'goal_type': goal,
        'priority': 1,
        'status': 'draft',
      });
    } else {
      await _client
          .from('user_goals')
          .update({'goal_type': goal})
          .eq('id', existing.first['id']);
    }
  }

  @override
  Future<OnboardingProposal> generateProposal() async {
    final result = await _client.functions.invoke('onboarding-propose-plan');
    if (result.status != 200 || result.data is! Map) {
      throw const FormatException('Proposal generation failed.');
    }
    final proposalId = (result.data as Map)['proposal_id'] as String?;
    if (proposalId == null) throw const FormatException('Proposal ID missing.');
    return loadProposal(proposalId);
  }

  @override
  Future<OnboardingProposal> loadProposal(String proposalId) async {
    final row = await _client
        .from('change_proposals')
        .select(
          'id,proposed_training,proposed_nutrition,rationale,expected_benefit,downside,confidence',
        )
        .eq('id', proposalId)
        .single();
    return OnboardingProposal(
      id: row['id'] as String,
      training: Map<String, dynamic>.from(row['proposed_training'] as Map),
      nutrition: Map<String, dynamic>.from(row['proposed_nutrition'] as Map),
      rationale: row['rationale'] as String,
      benefit: row['expected_benefit'] as String,
      downside: row['downside'] as String,
      confidence: row['confidence'] as String,
    );
  }

  @override
  Future<void> respond(String proposalId, String action) async {
    await _client.rpc(
      'respond_to_onboarding_proposal',
      params: {'proposal_id': proposalId, 'response_action': action},
    );
  }
}
