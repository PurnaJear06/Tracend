import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

class MealEntry {
  const MealEntry({
    required this.id,
    required this.type,
    required this.status,
    required this.source,
  });
  final String id;
  final String type;
  final String status;
  final String source;
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
  Future<void> saveScheduledMeal({
    required DateTime date,
    required String scheduleItemId,
    required String mealType,
    required ManualFoodInput food,
  });
}

abstract interface class MealPhotoRepository {
  Future<String> analyzeMealPhoto({
    required DateTime date,
    required String mealType,
    required Uint8List bytes,
  });
}

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
  });
  final String id;
  final String name;
  final String servingLabel;
  final double calories;
  final double protein;
  final double carbohydrate;
  final double fat;
  final String confidence;

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
  Future<void> saveManualMeal({
    required DateTime date,
    required String mealType,
    required ManualFoodInput food,
  });
  Future<String> createFixtureMeal({
    required DateTime date,
    required String mealType,
  });
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

  @override
  Future<String> analyzeMealPhoto({
    required DateTime date,
    required String mealType,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty || bytes.length > 4194304) {
      throw const FormatException('Meal photo must be 4 MB or smaller.');
    }
    final userId = _client.auth.currentUser!.id;
    final requestId = _uuid.v4();
    final path = '$userId/meal/$requestId.jpg';
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
    try {
      final account = await _client
          .from('user_accounts')
          .select('timezone')
          .single();
      final draft = Map<String, dynamic>.from(
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
            )
            as Map,
      );
      final mealId = draft['meal_id'] as String;
      final response = await _client.functions.invoke(
        'meal-analyze',
        body: {'schema_version': '1.0', 'meal_id': mealId},
      );
      if (response.status != 200) {
        throw StateError('Meal analysis unavailable.');
      }
      return mealId;
    } catch (e) {
      debugPrint('Non-critical error: $e');
      await _client.storage.from('meal-images').remove([path]);
      rethrow;
    }
  }

  @override
  Future<NutritionSchedule> loadSchedule(DateTime date) async {
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
  }) async {
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
        'request_idempotency_key': _uuid.v4(),
        'item_payload': [food.toJson()],
        'schedule_item_id': scheduleItemId,
        'meal_note': '',
      },
    );
  }

  @override
  Future<NutritionTargets?> loadTargets() async {
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
    final value = Map<String, dynamic>.from(
      await _client.rpc(
            'get_my_daily_nutrition',
            params: {'target_date': _dateKey(date)},
          )
          as Map,
    );
    return NutritionSummary(
      calories: (value['calories'] as num).toDouble(),
      protein: (value['protein_g'] as num).toDouble(),
      carbohydrate: (value['carbohydrate_g'] as num).toDouble(),
      fat: (value['fat_g'] as num).toDouble(),
      confirmedMeals: (value['confirmed_meals'] as num).toInt(),
    );
  }

  @override
  Future<List<MealEntry>> loadMeals(DateTime date) async {
    final rows = await _client
        .from('meals')
        .select('id,meal_type,status,source')
        .eq('local_date', _dateKey(date))
        .order('created_at');
    return rows
        .map(
          (row) => MealEntry(
            id: row['id'] as String,
            type: row['meal_type'] as String,
            status: row['status'] as String,
            source: row['source'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<void> saveManualMeal({
    required DateTime date,
    required String mealType,
    required ManualFoodInput food,
  }) async {
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
        'request_idempotency_key': _uuid.v4(),
        'item_payload': [food.toJson()],
        'meal_note': '',
      },
    );
  }

  @override
  Future<String> createFixtureMeal({
    required DateTime date,
    required String mealType,
  }) async {
    final account = await _client
        .from('user_accounts')
        .select('timezone')
        .single();
    return await _client.rpc(
          'create_fixture_meal',
          params: {
            'meal_date': _dateKey(date),
            'meal_timezone': account['timezone'] as String? ?? 'UTC',
            'meal_kind': mealType,
            'request_idempotency_key': _uuid.v4(),
          },
        )
        as String;
  }

  @override
  Future<List<MealCandidate>> loadCandidates(String mealId) async {
    final rows = await _client
        .from('meal_analysis_candidates')
        .select(
          'id,food_label,serving_label,calories,protein_g,carbohydrate_g,fat_g,confidence',
        )
        .eq('meal_id', mealId)
        .order('candidate_order');
    return rows
        .map(
          (row) => MealCandidate(
            id: row['id'] as String,
            name: row['food_label'] as String,
            servingLabel: row['serving_label'] as String,
            calories: (row['calories'] as num).toDouble(),
            protein: (row['protein_g'] as num).toDouble(),
            carbohydrate: (row['carbohydrate_g'] as num).toDouble(),
            fat: (row['fat_g'] as num).toDouble(),
            confidence: row['confidence'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<void> confirmCandidates(
    String mealId,
    List<MealCandidate> candidates,
  ) async {
    await _client.rpc(
      'confirm_analyzed_meal',
      params: {
        'target_meal_id': mealId,
        'candidate_payload': candidates
            .map((candidate) => candidate.toConfirmationJson())
            .toList(),
      },
    );
  }

  @override
  Future<void> deleteMeal(String mealId) async {
    await _client.rpc('delete_my_meal', params: {'target_meal_id': mealId});
  }

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
  }) => throw StateError('Configure Supabase to save meals.');
  @override
  Future<String> createFixtureMeal({
    required DateTime date,
    required String mealType,
  }) => throw StateError('Configure Supabase to analyze meals.');
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
