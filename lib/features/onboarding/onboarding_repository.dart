import 'dart:async';

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

/// The server's onboarding plan generation (`get_my_onboarding_generation`).
class OnboardingGeneration {
  const OnboardingGeneration({
    required this.id,
    required this.status,
    this.proposalId,
    this.proposalStatus,
    this.proposalExpiresAt,
    this.errorCode,
  });

  final String id;

  /// `running`, `succeeded`, `failed` or `superseded`.
  final String status;
  final String? proposalId;
  final String? proposalStatus;

  /// When the proposal stops being answerable (seven days after it was made).
  final DateTime? proposalExpiresAt;
  final String? errorCode;

  bool get running => status == 'running';

  /// Finished, but its proposal expired before the athlete answered it.
  /// The server reports this; the expiry time also catches an older server.
  bool get proposalExpired =>
      status == 'succeeded' &&
      (proposalStatus == 'expired' ||
          (proposalStatus == 'pending' &&
              proposalExpiresAt != null &&
              !proposalExpiresAt!.isAfter(DateTime.now())));

  /// Finished with a proposal the athlete has not answered yet.
  bool get readyForReview =>
      status == 'succeeded' &&
      proposalId != null &&
      !proposalExpired &&
      (proposalStatus == null || proposalStatus == 'pending');

  static OnboardingGeneration? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['generation_id'];
    final status = value['status'];
    if (id is! String || status is! String) return null;
    return OnboardingGeneration(
      id: id,
      status: status,
      proposalId: value['proposal_id'] as String?,
      proposalStatus: value['proposal_status'] as String?,
      proposalExpiresAt: DateTime.tryParse(
        value['proposal_expires_at'] as String? ?? '',
      ),
      errorCode: value['error_code'] as String?,
    );
  }
}

/// The server could not start a plan because answers are missing.
class OnboardingAnswersIncomplete implements Exception {
  const OnboardingAnswersIncomplete(this.missing);

  final List<String> missing;
}

/// No safe plan fits these answers (for example, the equipment and the
/// movements to avoid leave a training day empty). [change] names the answers
/// that decide it; retrying unchanged answers gives the same result.
class OnboardingPlanInfeasible implements Exception {
  const OnboardingPlanInfeasible(this.change);

  final List<String> change;
}

/// The proposal can no longer be answered: it expired, or a newer build
/// replaced it. The athlete builds a fresh one from the same answers.
class OnboardingProposalStale implements Exception {
  const OnboardingProposalStale();
}

class ProposalExercise {
  const ProposalExercise({
    required this.name,
    required this.sets,
    required this.repMin,
    required this.repMax,
    required this.targetRpe,
    required this.restSeconds,
    required this.notes,
  });

  final String name;
  final int sets;
  final int repMin;
  final int repMax;
  final num targetRpe;
  final int restSeconds;
  final String notes;
}

class ProposalWorkout {
  const ProposalWorkout({
    required this.weekday,
    required this.name,
    required this.objective,
    required this.estimatedMinutes,
    required this.exercises,
  });

  final int weekday;
  final String name;
  final String objective;
  final int estimatedMinutes;
  final List<ProposalExercise> exercises;
}

/// How Tracend calculated the calorie range (onboarding-policy-v1).
class ProposalCalculation {
  const ProposalCalculation({
    required this.bmrKcal,
    required this.activityFactor,
    required this.tdeeKcal,
    required this.calorieRangeKcal,
    required this.floorApplied,
    required this.ceilingKcal,
    required this.ceilingApplied,
  });

  final List<int> bmrKcal;
  final num activityFactor;
  final List<int> tdeeKcal;
  final List<int> calorieRangeKcal;
  final bool floorApplied;
  final int? ceilingKcal;
  final bool ceilingApplied;
}

/// A 2.0 onboarding proposal: the exact plan that approval activates.
class OnboardingProposal {
  const OnboardingProposal({
    required this.id,
    required this.title,
    required this.blockWeeks,
    required this.origin,
    required this.model,
    required this.workouts,
    required this.calories,
    required this.proteinG,
    required this.carbohydrateG,
    required this.fatG,
    required this.nutritionRationale,
    required this.assessment,
    required this.assumptions,
    required this.missingInformation,
    required this.keptFromCurrentPlan,
    required this.changedFromCurrentPlan,
    required this.progression,
    required this.calculation,
    required this.rationale,
    required this.benefit,
    required this.downside,
    required this.confidence,
  });

  final String id;
  final String title;
  final int blockWeeks;

  /// `ai` or `rules`.
  final String origin;
  final String? model;
  final List<ProposalWorkout> workouts;
  final int calories;
  final int proteinG;
  final int carbohydrateG;
  final int fatG;
  final String nutritionRationale;
  final String assessment;
  final List<String> assumptions;
  final List<String> missingInformation;
  final List<String> keptFromCurrentPlan;
  final List<String> changedFromCurrentPlan;
  final String progression;
  final ProposalCalculation? calculation;
  final String rationale;
  final String benefit;
  final String downside;
  final String confidence;

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];

  static List<int> _ints(Object? value) => value is List
      ? value.whereType<num>().map((item) => item.round()).toList()
      : const [];

  factory OnboardingProposal.fromRow(Map<String, dynamic> row) {
    final training = Map<String, dynamic>.from(row['proposed_training'] as Map);
    final nutrition = Map<String, dynamic>.from(
      row['proposed_nutrition'] as Map,
    );
    final calculation = training['calculation'];
    return OnboardingProposal(
      id: row['id'] as String,
      title: training['title'] as String,
      blockWeeks: (training['block_weeks'] as num).toInt(),
      origin: training['origin'] as String? ?? 'rules',
      model: training['model'] as String?,
      workouts: (training['weekly_structure'] as List).map((item) {
        final workout = Map<String, dynamic>.from(item as Map);
        return ProposalWorkout(
          weekday: (workout['preferred_weekday'] as num).toInt(),
          name: workout['name'] as String,
          objective: workout['objective'] as String? ?? '',
          estimatedMinutes: (workout['estimated_minutes'] as num).toInt(),
          exercises: (workout['exercises'] as List).map((entry) {
            final exercise = Map<String, dynamic>.from(entry as Map);
            return ProposalExercise(
              name: exercise['name'] as String,
              sets: (exercise['sets'] as num).toInt(),
              repMin: (exercise['rep_min'] as num).toInt(),
              repMax: (exercise['rep_max'] as num).toInt(),
              targetRpe: exercise['target_rpe'] as num,
              restSeconds: (exercise['rest_seconds'] as num).toInt(),
              notes: exercise['notes'] as String? ?? '',
            );
          }).toList(),
        );
      }).toList(),
      calories: (nutrition['calories'] as num).toInt(),
      proteinG: (nutrition['protein_g'] as num).toInt(),
      carbohydrateG: (nutrition['carbohydrate_g'] as num).toInt(),
      fatG: (nutrition['fat_g'] as num).toInt(),
      nutritionRationale: nutrition['rationale'] as String? ?? '',
      assessment: training['assessment'] as String? ?? '',
      assumptions: _strings(training['assumptions']),
      missingInformation: _strings(training['missing_information']),
      keptFromCurrentPlan: _strings(training['kept_from_current_plan']),
      changedFromCurrentPlan: _strings(training['changed_from_current_plan']),
      progression:
          (training['prescription'] as Map?)?['progression'] as String? ?? '',
      calculation: calculation is Map
          ? ProposalCalculation(
              bmrKcal: _ints(calculation['bmr_kcal']),
              activityFactor: calculation['activity_factor'] as num? ?? 0,
              tdeeKcal: _ints(calculation['tdee_kcal']),
              calorieRangeKcal: _ints(calculation['calorie_range_kcal']),
              floorApplied: calculation['floor_applied'] == true,
              ceilingKcal: (calculation['ceiling_kcal'] as num?)?.toInt(),
              ceilingApplied: calculation['ceiling_applied'] == true,
            )
          : null,
      rationale: row['rationale'] as String,
      benefit: row['expected_benefit'] as String,
      downside: row['downside'] as String,
      confidence: row['confidence'] as String,
    );
  }
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

  /// Starts (or returns) the plan generation for the saved draft.
  /// Throws [OnboardingAnswersIncomplete] when answers are missing and
  /// [OnboardingPlanInfeasible] when no safe plan fits them.
  Future<OnboardingGeneration> startGeneration();

  /// The newest generation, or null when there is none.
  Future<OnboardingGeneration?> loadGeneration();
  Future<OnboardingProposal> loadProposal(String proposalId);

  /// Throws [OnboardingProposalStale] when the proposal can no longer be
  /// answered; nothing was activated.
  Future<void> respond(String proposalId, String action, {String? note});
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
  Future<OnboardingGeneration> startGeneration() async {
    try {
      final result = await _client.functions
          .invoke('onboarding-plan')
          .timeout(const Duration(seconds: 20));
      final generation = OnboardingGeneration.fromJson(result.data);
      if (generation == null) {
        throw const FormatException('Plan generation did not start.');
      }
      return generation;
    } on FunctionException catch (error) {
      final details = error.details;
      if (error.status == 422 && details is Map) {
        List<String> strings(Object? value) =>
            (value as List? ?? const []).whereType<String>().toList();
        if (details['error'] == 'onboarding_answers_incomplete') {
          throw OnboardingAnswersIncomplete(strings(details['missing']));
        }
        if (details['error'] == 'onboarding_plan_infeasible') {
          throw OnboardingPlanInfeasible(strings(details['change']));
        }
      }
      rethrow;
    } on TimeoutException {
      // The request may still have started a generation; the caller polls.
      final generation = await loadGeneration();
      if (generation != null) return generation;
      rethrow;
    }
  }

  @override
  Future<OnboardingGeneration?> loadGeneration() async =>
      OnboardingGeneration.fromJson(
        await _client.rpc('get_my_onboarding_generation'),
      );

  @override
  Future<OnboardingProposal> loadProposal(String proposalId) async {
    final row = await _client
        .from('change_proposals')
        .select(
          'id,proposed_training,proposed_nutrition,rationale,expected_benefit,downside,confidence',
        )
        .eq('id', proposalId)
        .single();
    return OnboardingProposal.fromRow(row);
  }

  @override
  Future<void> respond(String proposalId, String action, {String? note}) async {
    final Object? result;
    try {
      result = await _client.rpc(
        'respond_to_onboarding_proposal_v2',
        params: {
          'proposal_id': proposalId,
          'response_action': action,
          'revision_note': note,
        },
      );
    } on PostgrestException catch (error) {
      // 55000: no longer pending (expired, or replaced by a newer build).
      if (error.code == '55000') throw const OnboardingProposalStale();
      rethrow;
    }
    if (result is Map && result['status'] == 'expired') {
      throw const OnboardingProposalStale();
    }
  }
}
