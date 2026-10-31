import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/consent/photo_ai_notice.dart';
import 'package:tracend/features/nutrition/meal_portions.dart';
import 'package:tracend/shared/shared_reads.dart';
import 'package:uuid/uuid.dart';
import 'package:tracend/shared/diagnostics.dart';

export 'package:tracend/features/consent/photo_ai_notice.dart';
export 'package:tracend/features/nutrition/meal_portions.dart';

class NutritionSummary {
  const NutritionSummary({
    required this.calories,
    required this.protein,
    required this.carbohydrate,
    required this.fat,
    required this.confirmedMeals,
  });
  final double calories;
  final double protein;
  final double carbohydrate;
  final double fat;
  final int confirmedMeals;

  /// Reads `get_my_daily_nutrition` (schema version 1.x; an answer from
  /// before the field existed reads as 1.0).
  factory NutritionSummary.fromJson(Object? value) {
    if (value is! Map || !_isVersionOne(value['schema_version'])) {
      throw const FormatException('The daily nutrition answer is unreadable.');
    }
    return NutritionSummary(
      calories: (value['calories'] as num).toDouble(),
      protein: (value['protein_g'] as num).toDouble(),
      carbohydrate: (value['carbohydrate_g'] as num).toDouble(),
      fat: (value['fat_g'] as num).toDouble(),
      confirmedMeals: (value['confirmed_meals'] as num).toInt(),
    );
  }
}

bool _isVersionOne(Object? version) =>
    version == null || (version is String && version.startsWith('1.'));

/// The meal a photo draft was made for, from `create_meal_photo_draft`
/// (schema version 1.x).
String mealIdFromDraft(Object? value) {
  if (value is! Map ||
      !_isVersionOne(value['schema_version']) ||
      value['meal_id'] is! String) {
    throw const FormatException('The meal photo draft is unreadable.');
  }
  return value['meal_id'] as String;
}

class NutritionTargets {
  const NutritionTargets({
    required this.calories,
    required this.protein,
    required this.carbohydrate,
    required this.fat,
  });
  final double calories;
  final double protein;
  final double carbohydrate;
  final double fat;
}

/// One confirmed food inside a meal (`meal_items`).
class MealItem {
  const MealItem({
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbohydrate,
    required this.fat,
  });
  final String name;
  final double calories;
  final double protein;
  final double carbohydrate;
  final double fat;
}

class MealEntry {
  const MealEntry({
    required this.id,
    required this.type,
    required this.status,
    required this.source,
    this.items = const [],
    this.loggedAt,
    this.scheduleItemId,
  });

  /// Maps a `meals` row with its embedded `meal_items`.
  factory MealEntry.fromRow(Map<String, dynamic> row) {
    final logged = row['confirmed_at'] ?? row['created_at'];
    return MealEntry(
      id: row['id'] as String,
      type: row['meal_type'] as String,
      status: row['status'] as String,
      source: row['source'] as String,
      loggedAt: logged is String ? DateTime.parse(logged).toLocal() : null,
      scheduleItemId: row['nutrition_schedule_item_id'] as String?,
      items: [
        for (final item in (row['meal_items'] as List? ?? const []))
          MealItem(
            name: (item as Map)['name_snapshot'] as String,
            calories: (item['calories'] as num).toDouble(),
            protein: (item['protein_g'] as num).toDouble(),
            carbohydrate: (item['carbohydrate_g'] as num).toDouble(),
            fat: (item['fat_g'] as num).toDouble(),
          ),
      ],
    );
  }

  final String id;
  final String type;
  final String status;
  final String source;

  /// Confirmed foods; empty for a draft, whose foods are still candidates.
  final List<MealItem> items;

  /// When the meal was confirmed, or created for a draft.
  final DateTime? loggedAt;

  /// The schedule slot this meal fills, when it was logged from one.
  final String? scheduleItemId;

  double get calories => items.fold(0, (sum, item) => sum + item.calories);
  double get protein => items.fold(0, (sum, item) => sum + item.protein);
  double get carbohydrate =>
      items.fold(0, (sum, item) => sum + item.carbohydrate);
  double get fat => items.fold(0, (sum, item) => sum + item.fat);
}

class ScheduledMeal {
  const ScheduledMeal({
    required this.id,
    required this.slotKey,
    required this.label,
    required this.time,
    required this.foods,
    required this.status,
    required this.optional,
    required this.reminderEnabled,
  });
  final String id;
  final String slotKey;
  final String label;
  final String time;
  final List<Map<String, dynamic>> foods;
  final String status;
  final bool optional;
  final bool reminderEnabled;
}

class NutritionSchedule {
  const NutritionSchedule({required this.title, required this.items});
  final String title;
  final List<ScheduledMeal> items;
  ScheduledMeal? get nextMeal {
    for (final item in items) {
      if (item.status == 'due' ||
          item.status == 'upcoming' ||
          item.status == 'optional') {
        return item;
      }
    }
    return null;
  }
}

abstract interface class NutritionScheduleRepository {
  Future<NutritionSchedule> loadSchedule(DateTime date);
}

abstract interface class ScheduledMealLogger {
  /// [idempotencyKey] makes a repeat of the same save return the meal the
  /// first one wrote.
  Future<void> saveScheduledMeal({
    required DateTime date,
    required String scheduleItemId,
    required String mealType,
    required ManualFoodInput food,
    required String idempotencyKey,
  });
}

abstract interface class MealPhotoRepository {
  /// The notice shown before the first analysis, and whether its current
  /// version is granted. The server refuses analysis until it is.
  Future<PhotoAiNotice> loadMealPhotoNotice();

  /// Appends a `meal_photo_ai` grant, or a `withdrawn` row.
  Future<void> recordMealPhotoConsent({
    required String noticeVersion,
    required bool granted,
  });

  /// Uploads the photo, creates its draft meal, and runs the analysis.
  /// Throws a [MealPhotoFailure] naming the step that failed.
  Future<String> analyzeMealPhoto({
    required DateTime date,
    required String mealType,
    required Uint8List bytes,
  });
}

/// The step at which a meal photo failed, and the error's code. The error's
/// message is left out because it can contain the photo's storage path; the
/// code alone is shown on screen and reported to Sentry.
class MealPhotoFailure implements Exception {
  const MealPhotoFailure(this.step, this.code);

  /// `notice`, `picker`, `upload`, `draft`, `analysis`, or `app`.
  final String step;
  final String code;

  @override
  String toString() => 'MealPhotoFailure($step: $code)';
}

/// How long a draft meal's photo analysis can take at most; an older draft
/// without estimates is a failed analysis.
const mealAnalysisWindow = Duration(minutes: 10);

/// A manual meal save failed and the app could not find out whether the
/// server wrote it: the meal may or may not exist.
class MealSaveOutcomeUnknown implements Exception {
  const MealSaveOutcomeUnknown();

  @override
  String toString() => 'MealSaveOutcomeUnknown';
}

/// Where a candidate's values came from (`meal_analysis_candidates.source`).
enum MealSource {
  /// Printed nutrition values that passed the server's arithmetic checks.
  label,

  /// Printed values that did not pass them; [MealCandidate.labelIssues] says
  /// which.
  labelUnverified,

  /// The model's estimate (a plate, or the front of a pack).
  estimate,
}

MealSource? _mealSource(Object? value) => switch (value) {
  'label' => MealSource.label,
  'label_unverified' => MealSource.labelUnverified,
  'estimate' => MealSource.estimate,
  _ => null,
};

double? _number(Object? value) => value is num ? value.toDouble() : null;

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

class MealCandidate {
  const MealCandidate({
    required this.id,
    required this.name,
    required this.servingLabel,
    required this.calories,
    required this.protein,
    required this.carbohydrate,
    required this.fat,
    required this.confidence,
    this.source,
    this.brand = '',
    this.perGram,
    this.servingGrams,
    this.servingsPerPack,
    this.packGrams,
    this.portionGrams,
    this.assumptions = const [],
    this.question = '',
    this.labelIssues = const [],
  });

  /// Maps a `meal_analysis_candidates` row. Rows stored before the packaged
  /// food columns existed have no source and no notes.
  factory MealCandidate.fromRow(Map<String, dynamic> row) {
    final kcal = _number(row['kcal_per_g']);
    final protein = _number(row['protein_per_g']);
    final carbohydrate = _number(row['carbohydrate_per_g']);
    final fat = _number(row['fat_per_g']);
    return MealCandidate(
      id: row['id'] as String,
      name: row['food_label'] as String,
      servingLabel: row['serving_label'] as String,
      calories: (row['calories'] as num).toDouble(),
      protein: (row['protein_g'] as num).toDouble(),
      carbohydrate: (row['carbohydrate_g'] as num).toDouble(),
      fat: (row['fat_g'] as num).toDouble(),
      confidence: row['confidence'] as String,
      source: _mealSource(row['source']),
      brand: row['brand'] as String? ?? '',
      perGram:
          kcal == null || protein == null || carbohydrate == null || fat == null
          ? null
          : PerGramNutrients(
              kcal: kcal,
              protein: protein,
              carbohydrate: carbohydrate,
              fat: fat,
            ),
      servingGrams: _number(row['serving_g']),
      servingsPerPack: _number(row['servings_per_pack']),
      packGrams: _number(row['pack_g']),
      portionGrams: _number(row['portion_g']),
      assumptions: _strings(row['assumptions']),
      question: row['question'] as String? ?? '',
      labelIssues: _strings(row['label_issues']),
    );
  }

  /// The columns [MealCandidate.fromRow] reads.
  static const columns =
      'id,food_label,serving_label,calories,protein_g,carbohydrate_g,fat_g,'
      'confidence,source,brand,kcal_per_g,protein_per_g,carbohydrate_per_g,'
      'fat_per_g,serving_g,servings_per_pack,pack_g,portion_g,assumptions,'
      'question,label_issues';

  final String id;
  final String name;
  final String servingLabel;
  final double calories;
  final double protein;
  final double carbohydrate;
  final double fat;
  final String confidence;

  /// Null for a row stored before sources were recorded.
  final MealSource? source;
  final String brand;

  /// Present when any portion can be recalculated (a label, or a pack whose
  /// weight is printed).
  final PerGramNutrients? perGram;
  final double? servingGrams;
  final double? servingsPerPack;
  final double? packGrams;

  /// The grams the stored values are for.
  final double? portionGrams;

  /// What the model assumed, and its question for the athlete.
  final List<String> assumptions;
  final String question;

  /// The label checks that failed (`energy_mismatch`, …).
  final List<String> labelIssues;

  MealCandidate copyWith({
    String? name,
    String? servingLabel,
    double? calories,
    double? protein,
    double? carbohydrate,
    double? fat,
  }) => MealCandidate(
    id: id,
    name: name ?? this.name,
    servingLabel: servingLabel ?? this.servingLabel,
    calories: calories ?? this.calories,
    protein: protein ?? this.protein,
    carbohydrate: carbohydrate ?? this.carbohydrate,
    fat: fat ?? this.fat,
    confidence: confidence,
    source: source,
    brand: brand,
    perGram: perGram,
    servingGrams: servingGrams,
    servingsPerPack: servingsPerPack,
    packGrams: packGrams,
    portionGrams: portionGrams,
    assumptions: assumptions,
    question: question,
    labelIssues: labelIssues,
  );

  Map<String, dynamic> toConfirmationJson() => {
    'id': id,
    'name': name,
    'serving_label': servingLabel,
    'calories': calories,
    'protein_g': protein,
    'carbohydrate_g': carbohydrate,
    'fat_g': fat,
  };
}

class ManualFoodInput {
  const ManualFoodInput({
    required this.name,
    required this.servingLabel,
    required this.calories,
    required this.protein,
    required this.carbohydrate,
    required this.fat,
  });
  final String name;
  final String servingLabel;
  final double calories;
  final double protein;
  final double carbohydrate;
  final double fat;

  Map<String, dynamic> toJson() => {
    'name': name,
    'serving_label': servingLabel,
    'calories': calories,
    'protein_g': protein,
    'carbohydrate_g': carbohydrate,
    'fat_g': fat,
  };
}

abstract interface class NutritionRepository {
  Future<NutritionTargets?> loadTargets();
  Future<NutritionSummary> loadSummary(DateTime date);
  Future<List<MealEntry>> loadMeals(DateTime date);

  /// [idempotencyKey] makes a repeat of the same save return the meal the
  /// first one wrote, so a retry after a lost reply adds nothing.
  Future<void> saveManualMeal({
    required DateTime date,
    required String mealType,
    required ManualFoodInput food,
    required String idempotencyKey,
  });

  /// Whether a meal saved with [idempotencyKey] exists: how the app learns
  /// the outcome of a save whose reply was lost. Throws when it cannot ask.
  Future<bool> isMealSaved(String idempotencyKey);
  Future<List<MealCandidate>> loadCandidates(String mealId);
  Future<void> confirmCandidates(String mealId, List<MealCandidate> candidates);
  Future<void> deleteMeal(String mealId);
}

class SupabaseNutritionRepository
    implements
        NutritionRepository,
        NutritionScheduleRepository,
        ScheduledMealLogger,
        MealPhotoRepository {
  SupabaseNutritionRepository(this._client);
  static const _uuid = Uuid();
  final SupabaseClient _client;
  final _reads = SharedReads();

  @override
  Future<PhotoAiNotice> loadMealPhotoNotice() async {
    final notice = PhotoAiNotice.fromJson(
      await _client.rpc('get_my_meal_photo_ai_notice'),
    );
    if (notice == null) {
      throw const FormatException('The meal photo AI notice is unavailable.');
    }
    return notice;
  }

  @override
  Future<void> recordMealPhotoConsent({
    required String noticeVersion,
    required bool granted,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Authentication required.');
    await _client.from('consent_records').insert({
      'user_id': user.id,
      'consent_type': 'meal_photo_ai',
      'notice_version': noticeVersion,
      'action': granted ? 'granted' : 'withdrawn',
      'source': 'ios_app',
    });
  }

  @override
  Future<String> analyzeMealPhoto({
    required DateTime date,
    required String mealType,
    required Uint8List bytes,
  }) => _reads.afterWrite(() async {
    if (bytes.isEmpty) throw const MealPhotoFailure('upload', 'photo_empty');
    if (bytes.length > 4194304) {
      throw const MealPhotoFailure('upload', 'photo_too_large');
    }
    final userId = _client.auth.currentUser!.id;
    final requestId = _uuid.v4();
    final path = '$userId/meal/$requestId.jpg';
    try {
      await _client.storage
          .from('meal-images')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
    } catch (error) {
      throw MealPhotoFailure(
        'upload',
        error is StorageException
            ? error.statusCode ?? 'storage_error'
            : error.runtimeType.toString(),
      );
    }
    var step = 'draft';
    String? mealId;
    try {
      final account = await _client
          .from('user_accounts')
          .select('timezone')
          .single();
      final created = mealIdFromDraft(
        await _client.rpc(
          'create_meal_photo_draft',
          params: {
            'meal_date': _dateKey(date),
            'meal_timezone': account['timezone'] as String? ?? 'UTC',
            'meal_kind': mealType,
            'request_idempotency_key': requestId,
            'object_path': path,
            'object_content_type': 'image/jpeg',
            'object_byte_size': bytes.length,
            'object_checksum': sha256.convert(bytes).toString(),
          },
        ),
      );
      mealId = created;
      step = 'analysis';
      final response = await _client.functions.invoke(
        'meal-analyze',
        body: {'schema_version': '1.0', 'meal_id': created},
      );
      if (response.status != 200) {
        throw MealPhotoFailure(step, '${response.status}');
      }
      return created;
    } catch (error) {
      try {
        await _client.storage.from('meal-images').remove([path]);
      } catch (_) {
        // Best effort: a failed removal must not hide why the photo failed.
      }
      await _discardDraft(requestId, mealId);
      throw switch (error) {
        MealPhotoFailure() => error,
        FunctionException() => MealPhotoFailure(step, _functionFailure(error)),
        PostgrestException(:final code) => MealPhotoFailure(
          step,
          code ?? 'database_error',
        ),
        _ => MealPhotoFailure(step, error.runtimeType.toString()),
      };
    }
  });

  /// A photo that failed leaves no draft behind: without its photo and
  /// estimates the draft would be a "Needs review" row with nothing to
  /// review. A draft whose creation reply was lost is found by the key the
  /// request carried. Best effort: a failure here must not hide why the
  /// photo failed, and an empty draft that stays can be deleted from its
  /// sheet.
  Future<void> _discardDraft(String requestId, String? mealId) async {
    try {
      var id = mealId;
      if (id == null) {
        final rows = await _client
            .from('meals')
            .select('id')
            .eq('idempotency_key', requestId)
            .eq('status', 'draft')
            .limit(1);
        id = rows.isEmpty ? null : rows.first['id'] as String;
      }
      if (id != null) {
        await _client.rpc('delete_my_meal', params: {'target_meal_id': id});
      }
    } catch (error) {
      logNonCritical(error);
    }
  }

  /// `503 meal_analysis_unavailable` from the function's JSON error body.
  static String _functionFailure(FunctionException error) {
    final details = error.details;
    final code = details is Map ? details['error'] : null;
    return code is String ? '${error.status} $code' : '${error.status}';
  }

  @override
  Future<NutritionSchedule> loadSchedule(DateTime date) =>
      _reads.join(('schedule', _dateKey(date)), () => _loadSchedule(date));

  Future<NutritionSchedule> _loadSchedule(DateTime date) async {
    final value = Map<String, dynamic>.from(
      await _client.rpc(
            'get_my_nutrition_schedule',
            params: {'target_date': _dateKey(date)},
          )
          as Map,
    );
    final version = value['version'] is Map
        ? Map<String, dynamic>.from(value['version'] as Map)
        : const <String, dynamic>{};
    return NutritionSchedule(
      title: version['title'] as String? ?? 'Meal schedule',
      items: (value['items'] as List? ?? const []).map((item) {
        final row = Map<String, dynamic>.from(item as Map);
        return ScheduledMeal(
          id: row['id'] as String,
          slotKey: row['slot_key'] as String,
          label: row['label'] as String,
          time: row['local_time'] as String,
          foods: (row['foods'] as List)
              .map((food) => Map<String, dynamic>.from(food as Map))
              .toList(),
          status: row['status'] as String,
          optional: row['optional'] as bool? ?? false,
          reminderEnabled: row['reminder_enabled'] as bool? ?? false,
        );
      }).toList(),
    );
  }

  @override
  Future<void> saveScheduledMeal({
    required DateTime date,
    required String scheduleItemId,
    required String mealType,
    required ManualFoodInput food,
    required String idempotencyKey,
  }) => _reads.afterWrite(() async {
    final account = await _client
        .from('user_accounts')
        .select('timezone')
        .single();
    await _client.rpc(
      'save_scheduled_manual_meal',
      params: {
        'meal_date': _dateKey(date),
        'meal_timezone': account['timezone'] as String? ?? 'UTC',
        'meal_kind': mealType,
        'request_idempotency_key': idempotencyKey,
        'item_payload': [food.toJson()],
        'schedule_item_id': scheduleItemId,
        'meal_note': '',
      },
    );
  });

  @override
  Future<NutritionTargets?> loadTargets() =>
      _reads.join('targets', _loadTargets);

  Future<NutritionTargets?> _loadTargets() async {
    final rows = await _client
        .from('nutrition_target_sets')
        .select('calories,protein_g,carbohydrate_g,fat_g')
        .eq('status', 'active')
        .limit(1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return NutritionTargets(
      calories: (row['calories'] as num).toDouble(),
      protein: (row['protein_g'] as num).toDouble(),
      carbohydrate: (row['carbohydrate_g'] as num).toDouble(),
      fat: (row['fat_g'] as num).toDouble(),
    );
  }

  @override
  Future<NutritionSummary> loadSummary(DateTime date) async {
    return NutritionSummary.fromJson(
      await _client.rpc(
        'get_my_daily_nutrition',
        params: {'target_date': _dateKey(date)},
      ),
    );
  }

  @override
  Future<List<MealEntry>> loadMeals(DateTime date) =>
      _reads.join(('meals', _dateKey(date)), () => _loadMeals(date));

  Future<List<MealEntry>> _loadMeals(DateTime date) async {
    final rows = await _client
        .from('meals')
        .select(
          'id,meal_type,status,source,confirmed_at,created_at,'
          'nutrition_schedule_item_id,'
          'meal_items(name_snapshot,calories,protein_g,carbohydrate_g,fat_g)',
        )
        .eq('local_date', _dateKey(date))
        .order('created_at', ascending: true);
    return rows.map(MealEntry.fromRow).toList();
  }

  @override
  Future<void> saveManualMeal({
    required DateTime date,
    required String mealType,
    required ManualFoodInput food,
    required String idempotencyKey,
  }) => _reads.afterWrite(() async {
    final account = await _client
        .from('user_accounts')
        .select('timezone')
        .single();
    await _client.rpc(
      'save_manual_meal',
      params: {
        'meal_date': _dateKey(date),
        'meal_timezone': account['timezone'] as String? ?? 'UTC',
        'meal_kind': mealType,
        'request_idempotency_key': idempotencyKey,
        'item_payload': [food.toJson()],
        'meal_note': '',
      },
    );
  });

  @override
  Future<bool> isMealSaved(String idempotencyKey) async {
    final rows = await _client
        .from('meals')
        .select('id')
        .eq('idempotency_key', idempotencyKey)
        .limit(1);
    return rows.isNotEmpty;
  }

  @override
  Future<List<MealCandidate>> loadCandidates(String mealId) async {
    final rows = await _client
        .from('meal_analysis_candidates')
        .select(MealCandidate.columns)
        .eq('meal_id', mealId)
        .order('candidate_order', ascending: true);
    return rows.map(MealCandidate.fromRow).toList();
  }

  @override
  Future<void> confirmCandidates(
    String mealId,
    List<MealCandidate> candidates,
  ) => _reads.afterWrite(() async {
    await _client.rpc(
      'confirm_analyzed_meal',
      params: {
        'target_meal_id': mealId,
        'candidate_payload': candidates
            .map((candidate) => candidate.toConfirmationJson())
            .toList(),
      },
    );
  });

  @override
  Future<void> deleteMeal(String mealId) => _reads.afterWrite(() async {
    await _client.rpc('delete_my_meal', params: {'target_meal_id': mealId});
  });

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class FixtureNutritionRepository
    implements
        NutritionRepository,
        NutritionScheduleRepository,
        ScheduledMealLogger {
  const FixtureNutritionRepository();
  @override
  Future<NutritionSchedule> loadSchedule(DateTime date) async =>
      const NutritionSchedule(
        title: 'Confirmed meal schedule',
        items: [
          ScheduledMeal(
            id: 'fixture-pre',
            slotKey: 'pre_workout',
            label: 'Pre-workout',
            time: '07:45',
            foods: [
              {'name': 'Water', 'quantity': 'as needed'},
              {'name': 'Labrada Super Charge', 'quantity': '1 scoop'},
              {'name': 'Salt', 'quantity': 'pinch optional'},
            ],
            status: 'due',
            optional: false,
            reminderEnabled: true,
          ),
          ScheduledMeal(
            id: 'fixture-post',
            slotKey: 'post_workout',
            label: 'Post-workout',
            time: '10:00',
            foods: [
              {'name': 'Whole eggs', 'quantity': '2'},
              {'name': 'Egg whites', 'quantity': '4'},
              {'name': 'Banana', 'quantity': '1'},
            ],
            status: 'upcoming',
            optional: false,
            reminderEnabled: true,
          ),
        ],
      );
  @override
  Future<void> saveScheduledMeal({
    required DateTime date,
    required String scheduleItemId,
    required String mealType,
    required ManualFoodInput food,
    required String idempotencyKey,
  }) async {}
  @override
  Future<List<MealEntry>> loadMeals(DateTime date) async => const [];
  @override
  Future<NutritionSummary> loadSummary(DateTime date) async =>
      const NutritionSummary(
        calories: 0,
        protein: 0,
        carbohydrate: 0,
        fat: 0,
        confirmedMeals: 0,
      );
  @override
  Future<NutritionTargets?> loadTargets() async => const NutritionTargets(
    calories: 2200,
    protein: 150,
    carbohydrate: 240,
    fat: 70,
  );
  @override
  Future<void> saveManualMeal({
    required DateTime date,
    required String mealType,
    required ManualFoodInput food,
    required String idempotencyKey,
  }) => throw StateError('Configure Supabase to save meals.');
  @override
  Future<bool> isMealSaved(String idempotencyKey) async => false;
  @override
  Future<List<MealCandidate>> loadCandidates(String mealId) async => const [];
  @override
  Future<void> confirmCandidates(
    String mealId,
    List<MealCandidate> candidates,
  ) => throw StateError('Configure Supabase to confirm meals.');
  @override
  Future<void> deleteMeal(String mealId) =>
      throw StateError('Configure Supabase to delete meals.');
}
