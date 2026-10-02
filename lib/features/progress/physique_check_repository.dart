import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Muscles a physique check may suggest, with their display names.
const physiqueMuscleLabels = <String, String>{
  'quads': 'Quads',
  'glutes': 'Glutes',
  'hamstrings': 'Hamstrings',
  'chest': 'Chest',
  'back': 'Back',
  'shoulders': 'Shoulders',
  'biceps': 'Biceps',
  'triceps': 'Triceps',
  'core': 'Core',
  'calves': 'Calves',
};

/// Plain-language tips for the photo problems a check can report.
const physiquePhotoIssueTips = <String, String>{
  'lighting': 'Lighting was uneven',
  'pose': 'Poses differed from the guide',
  'clothing': 'Clothing hid the muscles',
  'framing': 'Part of the body was out of frame',
  'blur': 'A photo was blurry',
  'mismatch': 'The photos were taken in different conditions',
};

/// The most focus muscles an athlete may confirm from one check.
const maxFocusMuscles = 2;

const _confidences = {'low', 'medium', 'high'};

/// One muscle to develop, relative to the athlete's own build.
class PhysiquePriority {
  const PhysiquePriority({
    required this.muscle,
    required this.confidence,
    required this.reason,
  });

  /// A key of [physiqueMuscleLabels].
  final String muscle;

  /// `low`, `medium` or `high`.
  final String confidence;
  final String reason;
}

/// The model's visual estimate for one photo set. Interpretation only: it
/// changes nothing until the athlete confirms focus muscles.
class PhysiqueCheckResult {
  const PhysiqueCheckResult({
    required this.priorities,
    required this.observations,
    required this.photoIssues,
    required this.limitations,
  });

  /// One to three muscles, strongest suggestion first.
  final List<PhysiquePriority> priorities;
  final List<String> observations;

  /// Keys of [physiquePhotoIssueTips].
  final List<String> photoIssues;
  final String limitations;

  /// Reads a `physique-check` result, dropping unknown muscles, confidences
  /// and issues. Null when no usable priority remains.
  static PhysiqueCheckResult? fromJson(Object? value) {
    if (value is! Map) return null;
    final priorities = <PhysiquePriority>[];
    for (final item in value['development_priorities'] as List? ?? const []) {
      if (item is! Map) continue;
      final muscle = item['muscle'];
      final confidence = item['confidence'];
      final reason = item['reason'];
      if (muscle is! String || !physiqueMuscleLabels.containsKey(muscle)) {
        continue;
      }
      if (confidence is! String || !_confidences.contains(confidence)) {
        continue;
      }
      if (priorities.any((p) => p.muscle == muscle)) continue;
      priorities.add(
        PhysiquePriority(
          muscle: muscle,
          confidence: confidence,
          reason: reason is String ? reason.trim() : '',
        ),
      );
    }
    if (priorities.isEmpty) return null;
    final observations = (value['observations'] as List? ?? const [])
        .whereType<String>()
        .map((text) => text.trim())
        .where((text) => text.isNotEmpty)
        .take(3)
        .toList();
    final photoIssues = (value['photo_issues'] as List? ?? const [])
        .whereType<String>()
        .where(physiquePhotoIssueTips.containsKey)
        .toSet()
        .take(3)
        .toList();
    final limitations = value['limitations'];
    return PhysiqueCheckResult(
      priorities: priorities.take(3).toList(),
      observations: observations,
      photoIssues: photoIssues,
      limitations: limitations is String ? limitations.trim() : '',
    );
  }
}

/// The progress-photo AI notice (`get_my_photo_ai_notice`) and whether the
/// athlete's newest answer grants this exact version.
class PhotoAiNotice {
  const PhotoAiNotice({
    required this.version,
    required this.providerLabel,
    required this.model,
    required this.body,
    required this.granted,
  });

  final String version;
  final String providerLabel;
  final String model;

  /// Paragraphs separated by blank lines, shown verbatim.
  final String body;
  final bool granted;

  /// Null when the response is not a notice.
  static PhotoAiNotice? fromJson(Object? value) {
    if (value is! Map) return null;
    final version = value['version'];
    final body = value['body'];
    if (version is! String || version.isEmpty) return null;
    if (body is! String || body.trim().isEmpty) return null;
    final provider = value['provider_label'];
    final model = value['model'];
    return PhotoAiNotice(
      version: version,
      providerLabel: provider is String ? provider : '',
      model: model is String ? model : '',
      body: body,
      granted: value['granted'] == true,
    );
  }

  PhotoAiNotice withGranted(bool granted) => PhotoAiNotice(
    version: version,
    providerLabel: providerLabel,
    model: model,
    body: body,
    granted: granted,
  );

  List<String> get paragraphs => body
      .split(RegExp(r'\n\s*\n'))
      .map((paragraph) => paragraph.trim())
      .where((paragraph) => paragraph.isNotEmpty)
      .toList();
}

/// One stored check and the focus muscles the athlete confirmed from it.
class PhysiqueAnalysis {
  const PhysiqueAnalysis({
    required this.id,
    required this.photoSetId,
    required this.result,
    required this.confirmedMuscles,
    required this.createdAt,
  });

  final String id;
  final String photoSetId;
  final PhysiqueCheckResult result;
  final List<String> confirmedMuscles;
  final DateTime createdAt;

  /// Reads a `physique_analyses` row; null when its result is unusable.
  static PhysiqueAnalysis? fromRow(Map<String, dynamic> row) {
    final result = PhysiqueCheckResult.fromJson(row['result']);
    if (result == null) return null;
    return PhysiqueAnalysis(
      id: row['id'] as String,
      photoSetId: row['current_photo_set_id'] as String,
      result: result,
      confirmedMuscles: (row['confirmed_muscles'] as List? ?? const [])
          .whereType<String>()
          .where(physiqueMuscleLabels.containsKey)
          .toList(),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

/// Why a check produced no result, from the function's `error` code.
enum PhysiqueCheckError {
  unavailable(
    'physique_check_unavailable',
    'Physique checks are not available for this account.',
    retryable: false,
  ),
  consentRequired(
    'photo_ai_consent_required',
    'Agree to the photo check notice to continue.',
    retryable: false,
  ),
  usageLimit(
    'ai_usage_limit',
    "You've reached today's AI limit. Try again tomorrow.",
    retryable: false,
  ),
  busy(
    'physique_check_busy',
    'The photo check is busy. Try again in a minute.',
  ),
  photoSetNotFound(
    'photo_set_not_found',
    'Take a complete photo set first.',
    retryable: false,
  ),
  photoSetUnsupported(
    'photo_set_unsupported',
    "These photos can't be checked. Take a new set with the camera.",
    retryable: false,
  ),
  unassessable(
    'photo_set_unassessable',
    "These photos don't show enough of your body to suggest muscles. Retake "
        'the set with your full body in frame, fitted clothing and even light.',
    retryable: false,
  ),
  invalid(
    'physique_check_invalid',
    "The check didn't return a usable answer. Nothing was saved. Try again.",
  ),
  failed(
    'physique_check_failed',
    "The check didn't finish. Check your connection and try again.",
  );

  const PhysiqueCheckError(this.code, this.message, {this.retryable = true});

  final String code;
  final String message;

  /// Whether trying the same set again can succeed.
  final bool retryable;

  /// The error for a function `error` code; unknown codes are [failed].
  static PhysiqueCheckError fromCode(Object? code) =>
      values.firstWhere((error) => error.code == code, orElse: () => failed);
}

class PhysiqueCheckException implements Exception {
  const PhysiqueCheckException(this.error);
  final PhysiqueCheckError error;

  @override
  String toString() => 'PhysiqueCheckException(${error.code})';
}

/// The owner-only physique check on a complete progress photo set. Nothing
/// here changes a plan: only [setPriorityMuscles], on the athlete's explicit
/// choice, writes focus muscles.
abstract interface class PhysiqueCheckRepository {
  /// Who a check would send photos to, named by the server; null when this
  /// account may not run checks, or on any error.
  Future<String?> loadProvider();
  Future<PhotoAiNotice> loadNotice();

  /// Appends a `progress_photo_ai` grant, or a `withdrawn` row.
  Future<void> recordConsent({
    required String noticeVersion,
    required bool granted,
  });

  /// The newest check with a usable result, or null.
  Future<PhysiqueAnalysis?> loadLatestAnalysis();

  /// Sends the set's front, side and back photos to the provider. Throws
  /// [PhysiqueCheckException] when no usable result comes back.
  Future<PhysiqueAnalysis> check(String photoSetId);

  /// Saves up to [maxFocusMuscles] muscles from [analysisId]'s priorities as
  /// the athlete's focus; returns the stored focus muscles.
  Future<List<String>> setPriorityMuscles(
    List<String> muscles, {
    required String analysisId,
  });
}

class SupabasePhysiqueCheckRepository implements PhysiqueCheckRepository {
  SupabasePhysiqueCheckRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<String?> loadProvider() async {
    try {
      final response = await _client.functions.invoke(
        'physique-check',
        body: {'schema_version': '1.0', 'mode': 'status'},
      );
      final data = response.data;
      final label = data is Map ? data['provider_label'] : null;
      return data is Map &&
              data['enabled'] == true &&
              label is String &&
              label.isNotEmpty
          ? label
          : null;
    } catch (e) {
      debugPrint('Non-critical error: $e');
      return null;
    }
  }

  @override
  Future<PhotoAiNotice> loadNotice() async {
    final notice = PhotoAiNotice.fromJson(
      await _client.rpc('get_my_photo_ai_notice'),
    );
    if (notice == null) {
      throw const FormatException('The photo AI notice is unavailable.');
    }
    return notice;
  }

  @override
  Future<void> recordConsent({
    required String noticeVersion,
    required bool granted,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Authentication required.');
    await _client.from('consent_records').insert({
      'user_id': user.id,
      'consent_type': 'progress_photo_ai',
      'notice_version': noticeVersion,
      'action': granted ? 'granted' : 'withdrawn',
      'source': 'ios_app',
    });
  }

  @override
  Future<PhysiqueAnalysis?> loadLatestAnalysis() async {
    final row = await _client
        .from('physique_analyses')
        .select('id,current_photo_set_id,result,confirmed_muscles,created_at')
        .not('result', 'is', null)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : PhysiqueAnalysis.fromRow(row);
  }

  @override
  Future<PhysiqueAnalysis> check(String photoSetId) async {
    final FunctionResponse response;
    try {
      response = await _client.functions
          .invoke(
            'physique-check',
            body: {
              'schema_version': '1.0',
              'mode': 'check',
              'photo_set_id': photoSetId,
            },
          )
          .timeout(const Duration(seconds: 60));
    } on FunctionException catch (error) {
      final details = error.details;
      throw PhysiqueCheckException(
        PhysiqueCheckError.fromCode(details is Map ? details['error'] : null),
      );
    } on TimeoutException {
      throw const PhysiqueCheckException(PhysiqueCheckError.failed);
    } catch (e) {
      debugPrint('Non-critical error: $e');
      throw const PhysiqueCheckException(PhysiqueCheckError.failed);
    }
    final data = response.data;
    final analysisId = data is Map ? data['analysis_id'] : null;
    final result = data is Map
        ? PhysiqueCheckResult.fromJson(data['result'])
        : null;
    if (analysisId is! String || result == null) {
      throw const PhysiqueCheckException(PhysiqueCheckError.invalid);
    }
    return PhysiqueAnalysis(
      id: analysisId,
      photoSetId: photoSetId,
      result: result,
      confirmedMuscles: const [],
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<List<String>> setPriorityMuscles(
    List<String> muscles, {
    required String analysisId,
  }) async {
    final value = await _client.rpc(
      'set_my_priority_muscles',
      params: {'muscles': muscles, 'source_analysis_id': analysisId},
    );
    if (value is! Map || value['priority_muscles'] is! List) {
      throw const FormatException('Focus muscles were not confirmed.');
    }
    return (value['priority_muscles'] as List).whereType<String>().toList();
  }
}

/// Builds without a backend: checks are never offered.
class FixturePhysiqueCheckRepository implements PhysiqueCheckRepository {
  const FixturePhysiqueCheckRepository();
  @override
  Future<String?> loadProvider() async => null;
  @override
  Future<PhotoAiNotice> loadNotice() => throw StateError('Configure Supabase.');
  @override
  Future<void> recordConsent({
    required String noticeVersion,
    required bool granted,
  }) => throw StateError('Configure Supabase.');
  @override
  Future<PhysiqueAnalysis?> loadLatestAnalysis() async => null;
  @override
  Future<PhysiqueAnalysis> check(String photoSetId) =>
      throw StateError('Configure Supabase.');
  @override
  Future<List<String>> setPriorityMuscles(
    List<String> muscles, {
    required String analysisId,
  }) => throw StateError('Configure Supabase.');
}
