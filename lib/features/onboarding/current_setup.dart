import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/onboarding/onboarding_repository.dart';
import 'package:tracend/features/onboarding/onboarding_screening.dart';

/// The answers behind the athlete's approved plan, for "Change my setup".
abstract interface class CurrentSetupSource {
  /// The approved answers as an onboarding draft opened at Review. Nothing is
  /// written; the flow saves answers only when the athlete builds a plan.
  Future<OnboardingDraft> load();
}

/// Reads the approved answers from where approval keeps them: the profile,
/// the active goal and the newest weight, with the last saved draft for what
/// approval does not keep (the current plan, top sets, the Apple Health
/// answer). A draft the athlete edited and walked away from never wins over
/// what was approved.
class SupabaseCurrentSetup implements CurrentSetupSource {
  SupabaseCurrentSetup(
    this._client, {
    this.callTimeout = const Duration(seconds: 20),
  });

  final SupabaseClient _client;
  final Duration callTimeout;

  String get _userId => _client.auth.currentUser!.id;

  @override
  Future<OnboardingDraft> load() async {
    final reads = await Future.wait<Object?>([
      _client
          .from('onboarding_drafts')
          .select('path,payload')
          .eq('user_id', _userId)
          .maybeSingle(),
      _client
          .from('user_profiles')
          .select(
            'experience_level,height_cm,training_days,session_minutes,sex,'
            'birth_year,daily_activity,equipment,equipment_note,'
            'avoid_patterns,limitations_note,nutrition_note,training_years,'
            'priority_muscles,strong_muscles',
          )
          .eq('user_id', _userId)
          .maybeSingle(),
      _client
          .from('user_goals')
          .select('goal_type,details')
          .eq('user_id', _userId)
          .eq('status', 'active')
          .order('priority', ascending: true)
          .limit(1)
          .maybeSingle(),
      _client
          .from('body_measurements')
          .select('weight_kg')
          .eq('user_id', _userId)
          .isFilter('superseded_at', null)
          .not('weight_kg', 'is', null)
          .order('measured_on', ascending: false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle(),
      _client.rpc('get_my_screening_v1'),
    ]).timeout(callTimeout);
    final draft = reads[0] as Map<String, dynamic>?;
    final weight = reads[3] as Map<String, dynamic>?;
    return currentSetupDraft(
      draftPath: draft?['path'] as String?,
      draftPayload: draft?['payload'] is Map
          ? Map<String, dynamic>.from(draft!['payload'] as Map)
          : const {},
      profile: reads[1] as Map<String, dynamic>?,
      goal: reads[2] as Map<String, dynamic>?,
      weightKg: weight?['weight_kg'] as num?,
      screening: StoredScreening.fromJson(reads[4]).answers,
    );
  }
}

/// The approved answers laid over the saved draft, in the keys the flow
/// restores. Whatever approval kept wins; the follow-up answers and the
/// revision note belong to an earlier build of the plan and start empty.
OnboardingDraft currentSetupDraft({
  required String? draftPath,
  required Map<String, dynamic> draftPayload,
  required Map<String, dynamic>? profile,
  required Map<String, dynamic>? goal,
  required num? weightKg,
  required ScreeningAnswers? screening,
}) {
  final payload = {...draftPayload}
    ..remove('follow_ups')
    ..remove('follow_ups_hash')
    ..remove('revision_note');

  void put(String key, Object? value) {
    if (value != null) payload[key] = value;
  }

  List<Object?>? list(Object? value) =>
      value is List && value.isNotEmpty ? List<Object?>.of(value) : null;
  String? text(Object? value) {
    final trimmed = value is String ? value.trim() : '';
    return trimmed.isEmpty ? null : trimmed;
  }

  if (goal != null) {
    put('goal', goal['goal_type']);
    final details = goal['details'];
    // The approved goal has the target it has: a draft target is not kept.
    payload['target_weight_kg'] = details is Map
        ? details['target_weight_kg']
        : null;
  }
  if (profile != null) {
    put('experience', profile['experience_level']);
    put('sex', profile['sex']);
    put('birth_year', profile['birth_year']);
    put('height_cm', profile['height_cm']);
    put('daily_activity', profile['daily_activity']);
    final days = list(profile['training_days']);
    if (days != null) {
      put('training_weekdays', days);
      payload['training_days'] = days.length;
    }
    put('session_minutes', profile['session_minutes']);
    if (profile['equipment'] is List) {
      payload['equipment_items'] = profile['equipment'];
      payload['equipment'] = text(profile['equipment_note']) ?? '';
    }
    put('nutrition_context', text(profile['nutrition_note']));
    payload['constraints'] = text(profile['limitations_note']) ?? '';
    if (profile['avoid_patterns'] is List) {
      payload['avoid_patterns'] = profile['avoid_patterns'];
    }
    put('training_years', profile['training_years']);
    put('priority_muscles', profile['priority_muscles']);
    put('strong_muscles', profile['strong_muscles']);
  }
  put('weight_kg', weightKg);
  if (screening != null) payload['screening'] = screening.toJson();

  final path =
      draftPath ??
      (text(payload['training_years']) == null ? 'beginner' : 'experienced');
  return OnboardingDraft(
    path: path,
    currentSection: 'review',
    payload: payload,
  );
}
