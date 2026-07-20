import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BodyMeasurement {
  const BodyMeasurement({
    required this.date,
    required this.weightKg,
    this.waistCm,
    this.chestCm,
    this.hipCm,
    this.armCm,
    this.thighCm,
    this.source = 'manual',
  });
  final DateTime date;
  final double weightKg;
  final double? waistCm;
  final double? chestCm;
  final double? hipCm;
  final double? armCm;
  final double? thighCm;
  final String source;
}

class ProgressSummary {
  const ProgressSummary({
    required this.observationCount,
    required this.currentWeightKg,
    required this.weightChangeKg,
    required this.currentWaistCm,
    required this.waistChangeCm,
  });
  final int observationCount;
  final double? currentWeightKg;
  final double? weightChangeKg;
  final double? currentWaistCm;
  final double? waistChangeCm;
  bool get hasTrend => observationCount >= 2;
}

class ProgressPhotoSet {
  const ProgressPhotoSet({
    required this.id,
    required this.date,
    required this.status,
    required this.objectKeys,
  });
  final String id;
  final DateTime date;
  final String status;
  final List<String> objectKeys;
}

class WeeklyProgressReview {
  const WeeklyProgressReview({
    required this.id,
    required this.week,
    required this.outcomeCode,
    required this.plannedSessions,
    required this.completedWorkouts,
    required this.completedSets,
    required this.adherencePercent,
    required this.checkInDays,
    required this.averageEnergy,
    required this.averageSoreness,
    required this.healthDays,
    required this.confirmedNutritionDays,
    required this.measurementDays,
    required this.missingData,
    required this.nextFocusCode,
    required this.acknowledged,
  });
  final String id;
  final DateTime week;
  final String outcomeCode;
  final int plannedSessions;
  final int completedWorkouts;
  final int completedSets;
  final int adherencePercent;
  final int checkInDays;
  final double? averageEnergy;
  final double? averageSoreness;
  final int healthDays;
  final int confirmedNutritionDays;
  final int measurementDays;
  final List<String> missingData;
  final String nextFocusCode;
  final bool acknowledged;
}

class WeeklyReviewJob {
  const WeeklyReviewJob({required this.status, required this.week});
  final String status;
  final DateTime week;
  bool get isPending =>
      const {'queued', 'processing', 'retryable'}.contains(status);
}

class ProgressSessionException implements Exception {
  const ProgressSessionException();
}

abstract interface class ProgressRepository {
  Future<List<BodyMeasurement>> loadMeasurements();
  Future<ProgressSummary> loadSummary();
  Future<void> saveMeasurement(BodyMeasurement measurement);
  Future<List<ProgressPhotoSet>> loadPhotoSets();
  Future<void> grantPhotoStorageConsent();
  Future<String> beginPhotoSet();
  Future<void> uploadPhoto({
    required String setId,
    required String pose,
    required Uint8List bytes,
    required String contentType,
  });
  Future<List<String>> createPhotoReadUrls(ProgressPhotoSet set);
  Future<void> deletePhotoSet(ProgressPhotoSet set);
  Future<WeeklyProgressReview?> loadLatestWeeklyReview();
  Future<WeeklyReviewJob?> loadLatestWeeklyReviewJob();
  Future<void> requestWeeklyReview();
  Future<void> acknowledgeWeeklyReview(String reviewId);
}

class SupabaseProgressRepository implements ProgressRepository {
  SupabaseProgressRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<BodyMeasurement>> loadMeasurements() async {
    final rows = await _client
        .from('body_measurements')
        .select(
          'measured_on,weight_kg,waist_cm,chest_cm,hip_cm,arm_cm,thigh_cm,source,created_at',
        )
        .isFilter('superseded_at', null)
        .order('measured_on')
        .order('created_at');
    final byDate = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final date = row['measured_on'] as String;
      final existing = byDate[date];
      if (existing == null || row['source'] == 'manual') byDate[date] = row;
    }
    final values = byDate.values
        .map(
          (row) => BodyMeasurement(
            date: DateTime.parse(row['measured_on'] as String),
            weightKg: (row['weight_kg'] as num).toDouble(),
            waistCm: (row['waist_cm'] as num?)?.toDouble(),
            chestCm: (row['chest_cm'] as num?)?.toDouble(),
            hipCm: (row['hip_cm'] as num?)?.toDouble(),
            armCm: (row['arm_cm'] as num?)?.toDouble(),
            thighCm: (row['thigh_cm'] as num?)?.toDouble(),
            source: row['source'] as String,
          ),
        )
        .toList();
    values.sort((a, b) => a.date.compareTo(b.date));
    return values;
  }

  @override
  Future<ProgressSummary> loadSummary() async {
    final value = Map<String, dynamic>.from(
      await _client.rpc('get_my_progress_summary') as Map,
    );
    return ProgressSummary(
      observationCount: (value['observation_count'] as num).toInt(),
      currentWeightKg: (value['current_weight_kg'] as num?)?.toDouble(),
      weightChangeKg: (value['weight_change_kg'] as num?)?.toDouble(),
      currentWaistCm: (value['current_waist_cm'] as num?)?.toDouble(),
      waistChangeCm: (value['waist_change_cm'] as num?)?.toDouble(),
    );
  }

  @override
  Future<void> saveMeasurement(BodyMeasurement measurement) async {
    await _client.rpc(
      'save_body_measurement',
      params: {
        'measurement_date': _dateKey(measurement.date),
        'weight_kg': measurement.weightKg,
        'waist_cm': measurement.waistCm,
        'chest_cm': measurement.chestCm,
        'hip_cm': measurement.hipCm,
        'arm_cm': measurement.armCm,
        'thigh_cm': measurement.thighCm,
      },
    );
  }

  @override
  Future<List<ProgressPhotoSet>> loadPhotoSets() async {
    final sets = await _client
        .from('progress_photo_sets')
        .select('id,captured_on,status')
        .order('captured_on', ascending: false);
    final photos = await _client
        .from('progress_photos')
        .select('photo_set_id,media_objects(object_key)');
    return sets.map((set) {
      final id = set['id'] as String;
      return ProgressPhotoSet(
        id: id,
        date: DateTime.parse(set['captured_on'] as String),
        status: set['status'] as String,
        objectKeys: photos
            .where((p) => p['photo_set_id'] == id)
            .map((p) => (p['media_objects'] as Map)['object_key'] as String)
            .toList(),
      );
    }).toList();
  }

  @override
  Future<void> grantPhotoStorageConsent() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Authentication required.');
    await _client.from('consent_records').insert({
      'user_id': user.id,
      'consent_type': 'progress_photo_storage',
      'notice_version': 'progress-storage-v1',
      'action': 'granted',
      'source': 'ios_app',
    });
  }

  @override
  Future<String> beginPhotoSet() async =>
      await _client.rpc(
            'begin_progress_photo_set',
            params: {
              'capture_date': _dateKey(DateTime.now()),
              'timing': 'user-confirmed standardized capture',
            },
          )
          as String;

  @override
  Future<void> uploadPhoto({
    required String setId,
    required String pose,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Authentication required.');
    final extension = contentType == 'image/png'
        ? 'png'
        : contentType == 'image/heic'
        ? 'heic'
        : 'jpg';
    final key = '${user.id}/progress/$setId/$pose.$extension';
    await _client.storage
        .from('progress-photos')
        .uploadBinary(
          key,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    try {
      await _client.rpc(
        'register_progress_photo',
        params: {
          'target_set_id': setId,
          'photo_pose': pose,
          'storage_key': key,
          'media_type': contentType,
          'media_bytes': bytes.length,
          'media_checksum': sha256.convert(bytes).toString(),
        },
      );
    } catch (e) {
      debugPrint('Non-critical error: $e');
      await _client.storage.from('progress-photos').remove([key]);
      rethrow;
    }
  }

  @override
  Future<List<String>> createPhotoReadUrls(ProgressPhotoSet set) => Future.wait(
    set.objectKeys.map(
      (key) => _client.storage.from('progress-photos').createSignedUrl(key, 60),
    ),
  );
  @override
  Future<void> deletePhotoSet(ProgressPhotoSet set) async {
    if (set.objectKeys.isNotEmpty) {
      await _client.storage.from('progress-photos').remove(set.objectKeys);
    }
    await _client.rpc(
      'delete_my_progress_photo_set',
      params: {'target_set_id': set.id},
    );
  }

  @override
  Future<WeeklyProgressReview?> loadLatestWeeklyReview() async {
    final row = await _client
        .from('progress_reviews')
        .select('id,review_week,summary,acknowledged_at')
        .order('review_week', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    final summary = Map<String, dynamic>.from(row['summary'] as Map);
    final training = Map<String, dynamic>.from(summary['training'] as Map);
    final recovery = Map<String, dynamic>.from(summary['recovery'] as Map);
    final nutrition = Map<String, dynamic>.from(summary['nutrition'] as Map);
    final progress = Map<String, dynamic>.from(summary['progress'] as Map);
    return WeeklyProgressReview(
      id: row['id'] as String,
      week: DateTime.parse(row['review_week'] as String),
      outcomeCode: summary['outcome_code'] as String,
      plannedSessions: (training['planned_sessions'] as num).toInt(),
      completedWorkouts: (training['completed_workouts'] as num).toInt(),
      completedSets: (training['completed_sets'] as num).toInt(),
      adherencePercent: (training['adherence_percent'] as num).toInt(),
      checkInDays: (recovery['check_in_days'] as num).toInt(),
      averageEnergy: (recovery['average_energy'] as num?)?.toDouble(),
      averageSoreness: (recovery['average_soreness'] as num?)?.toDouble(),
      healthDays: (recovery['health_days'] as num).toInt(),
      confirmedNutritionDays: (nutrition['confirmed_days'] as num).toInt(),
      measurementDays: (progress['measurement_days'] as num).toInt(),
      missingData: (summary['missing_data'] as List).cast<String>(),
      nextFocusCode: summary['next_focus_code'] as String,
      acknowledged: row['acknowledged_at'] != null,
    );
  }

  @override
  Future<WeeklyReviewJob?> loadLatestWeeklyReviewJob() async {
    final row = await _client
        .from('weekly_review_jobs')
        .select('review_week,status')
        .order('review_week', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return WeeklyReviewJob(
      status: row['status'] as String,
      week: DateTime.parse(row['review_week'] as String),
    );
  }

  @override
  Future<void> requestWeeklyReview() async {
    await _refreshExpiredSession();
    final today = DateTime.now();
    final monday = today.subtract(Duration(days: today.weekday - 1 + 7));
    await _client.rpc(
      'request_my_weekly_review',
      params: {'target_review_week': _dateKey(monday)},
    );
  }

  Future<void> _refreshExpiredSession() async {
    final session = _client.auth.currentSession;
    if (session == null) throw const ProgressSessionException();
    if (!session.isExpired) return;
    try {
      final refreshed = await _client.auth.refreshSession();
      if (refreshed.session == null) throw const ProgressSessionException();
    } on AuthException {
      throw const ProgressSessionException();
    }
  }

  @override
  Future<void> acknowledgeWeeklyReview(String reviewId) async {
    await _client.rpc(
      'acknowledge_my_progress_review',
      params: {'target_review_id': reviewId},
    );
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class FixtureProgressRepository implements ProgressRepository {
  const FixtureProgressRepository();
  @override
  Future<List<BodyMeasurement>> loadMeasurements() async => const [];
  @override
  Future<ProgressSummary> loadSummary() async => const ProgressSummary(
    observationCount: 0,
    currentWeightKg: null,
    weightChangeKg: null,
    currentWaistCm: null,
    waistChangeCm: null,
  );
  @override
  Future<void> saveMeasurement(BodyMeasurement measurement) =>
      throw StateError('Configure Supabase to save measurements.');
  @override
  Future<List<ProgressPhotoSet>> loadPhotoSets() async => const [];
  @override
  Future<void> grantPhotoStorageConsent() =>
      throw StateError('Configure Supabase.');
  @override
  Future<String> beginPhotoSet() => throw StateError('Configure Supabase.');
  @override
  Future<void> uploadPhoto({
    required String setId,
    required String pose,
    required Uint8List bytes,
    required String contentType,
  }) => throw StateError('Configure Supabase.');
  @override
  Future<List<String>> createPhotoReadUrls(ProgressPhotoSet set) async =>
      const [];
  @override
  Future<void> deletePhotoSet(ProgressPhotoSet set) =>
      throw StateError('Configure Supabase.');
  @override
  Future<WeeklyProgressReview?> loadLatestWeeklyReview() async => null;
  @override
  Future<WeeklyReviewJob?> loadLatestWeeklyReviewJob() async => null;
  @override
  Future<void> requestWeeklyReview() => throw StateError('Configure Supabase.');
  @override
  Future<void> acknowledgeWeeklyReview(String reviewId) =>
      throw StateError('Configure Supabase.');
}
