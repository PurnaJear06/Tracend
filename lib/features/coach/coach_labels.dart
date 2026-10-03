/// Words for the stored codes a Coach reply carries. A code is shown as a
/// word the athlete would use, never as the raw id (DESIGN_SYSTEM.md §9).
library;

import 'package:tracend/shared/formatting.dart';

/// The name a person knows an AI provider by, keyed by the server's
/// `model_provider` id. The owner switches providers by budget, so the label
/// always comes from this map and is never written into a widget. An id that
/// is not listed has no display name; the reply then reads "AI answer" alone
/// rather than showing the raw id.
const aiProviderDisplayNames = <String, String>{
  'deepseek': 'DeepSeek',
  'groq': 'Qwen',
  'gemini': 'Gemini',
  'mock': 'Test model',
};

/// "DeepSeek" for `deepseek`; null for a missing or unlisted id.
String? aiProviderDisplayName(String? id) =>
    id == null ? null : aiProviderDisplayNames[id.trim().toLowerCase()];

/// The small label under an AI reply: "AI answer · DeepSeek", or "AI answer"
/// when the provider has no display name.
String aiAnswerLabel(String? providerId) {
  final name = aiProviderDisplayName(providerId);
  return name == null ? 'AI answer' : 'AI answer · $name';
}

/// Data the Coach could not use, keyed by the `missing_data` codes the
/// coaching context, the daily decision and the feature engine produce.
const _gapLabels = <String, String>{
  'recovery_check_in': 'Morning check-in',
  'recovery_check_ins': 'Morning check-ins',
  'check_in': 'Morning check-in',
  'health_context': 'Recent Apple Health data',
  'resting_hr': 'Resting heart rate',
  'hrv_sdnn': 'Heart rate variability',
  'sleep_minutes': 'Sleep duration',
  'resp_rate': 'Respiratory rate',
  'prev_strain': 'Previous day’s training load',
  'restorative': 'Restorative sleep',
  'efficiency': 'Sleep efficiency',
  'consistency': 'Sleep consistency',
  'confirmed_nutrition': 'Confirmed meals',
  'nutrition_data': 'Confirmed meals',
  'active_training_plan': 'Active training plan',
  'current_plan': 'Current training plan',
  'training_history': 'Training history',
  'workout_execution': 'Logged workouts',
  'body_measurements': 'Body measurements',
};

/// "Morning check-in" for `recovery_check_in`. A model may write a gap as a
/// sentence, which is shown as written; an unlisted code reads as words.
String coachGapLabel(String gap) => _gapLabels[gap] ?? _readable(gap);

/// Where a piece of cited evidence came from (`coach_chat_v1` sources).
const _evidenceSourceLabels = <String, String>{
  'feature_snapshot': 'Calculated from your health data',
  'policy_evaluation': 'Tracend safety rules',
  'coach_context': 'Your coaching context',
};

/// "Calculated from your health data" for `feature_snapshot`.
String coachEvidenceSourceLabel(String source) =>
    _evidenceSourceLabels[source] ?? _readable(source);

/// The names the Coach prompt gives its reasoning steps.
const _reasoningStepLabels = <String, String>{
  'goal': 'Goal',
  'training_age': 'Training experience',
  'current_nutrition': 'Current nutrition',
  'recovery_status': 'Recovery',
  'adherence': 'Adherence',
  'conclusion': 'Conclusion',
};

/// "Training experience" for `training_age`.
String coachReasoningStepLabel(String step) =>
    _reasoningStepLabels[step] ?? _readable(step);

/// "latest today", "latest yesterday" or "latest Fri 10 Jul" for a context
/// source's ISO `latest_date`; the stored text when it is not a date.
String coachLatestLabel(String isoDate, {DateTime? now}) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) return 'latest $isoDate';
  final day = friendlyDate(date, now: now);
  return 'latest ${day == 'Today' || day == 'Yesterday' ? day.toLowerCase() : day}';
}

/// A snake_case code as words ("training_history" → "Training history").
/// Text that is already words (it has a space or a capital) stays as is.
String _readable(String code) {
  final trimmed = code.trim();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed.contains(' ') || trimmed != trimmed.toLowerCase()) {
    return trimmed;
  }
  final words = trimmed.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  if (words.isEmpty) return trimmed;
  return '${words[0].toUpperCase()}${words.substring(1)}';
}
