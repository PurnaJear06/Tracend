import 'package:supabase_flutter/supabase_flutter.dart';

class DailyBrief {
  const DailyBrief({
    required this.localDate,
    this.workout,
    this.nextMeal,
    this.checkIn,
    this.health,
    this.nutrition,
    this.decision,
  });
  final String localDate;
  final Map<String, dynamic>? workout;
  final Map<String, dynamic>? nextMeal;
  final Map<String, dynamic>? checkIn;
  final Map<String, dynamic>? health;
  final Map<String, dynamic>? nutrition;
  final Map<String, dynamic>? decision;

  String get nextAction {
    if (checkIn == null) return 'Add today’s check-in.';
    if (workout != null) return 'Complete ${workout!['name']}.';
    if (nextMeal != null) {
      return 'Prepare ${nextMeal!['label']} at ${nextMeal!['local_time']}.';
    }
    if (decision != null) return decision!['final_decision'] as String;
    return 'Keep the approved plan.';
  }

  String get reason {
    if (checkIn == null) {
      return 'Recovery input is missing. Add it before Tracend interprets today’s evidence.';
    }
    if (workout != null) {
      return workout!['objective'] as String? ??
          'This is the next approved training action.';
    }
    if (nextMeal != null) {
      return 'This is the next item in your active confirmed meal schedule.';
    }
    return decision?['reason'] as String? ??
        'No plan change is supported by current evidence.';
  }
}

abstract interface class DailyBriefRepository {
  Future<DailyBrief> load(DateTime date);
}

class SupabaseDailyBriefRepository implements DailyBriefRepository {
  const SupabaseDailyBriefRepository(this._client);
  final SupabaseClient _client;
  @override
  Future<DailyBrief> load(DateTime date) async {
    final value = Map<String, dynamic>.from(
      await _client.rpc(
            'get_my_daily_brief',
            params: {
              'target_date':
                  '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
            },
          )
          as Map,
    );
    Map<String, dynamic>? object(String key) =>
        value[key] is Map ? Map<String, dynamic>.from(value[key] as Map) : null;
    return DailyBrief(
      localDate: value['local_date'] as String,
      workout: object('today_workout'),
      nextMeal: object('next_meal'),
      checkIn: object('check_in'),
      health: object('health'),
      nutrition: object('nutrition'),
      decision: object('latest_decision'),
    );
  }
}

class FixtureDailyBriefRepository implements DailyBriefRepository {
  const FixtureDailyBriefRepository();
  @override
  Future<DailyBrief> load(DateTime date) async => DailyBrief(
    localDate: date.toIso8601String().substring(0, 10),
    workout: const {
      'name': 'Push day',
      'objective':
          'Complete the approved working sets at the prescribed effort.',
    },
    nextMeal: const {'label': 'Post-workout meal', 'local_time': '10:00'},
    checkIn: const {'energy': 3},
  );
}
