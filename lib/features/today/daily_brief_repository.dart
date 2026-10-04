import 'package:supabase_flutter/supabase_flutter.dart';

import 'computed_metrics.dart';

class DailyBrief {
  const DailyBrief({
    required this.localDate,
    this.workout,
    this.nextMeal,
    this.checkIn,
    this.health,
    this.nutrition,
    this.computed,
    this.decision,
    this.recoveryPrevious,
    this.plan,
    this.week = const [],
    this.todaySession,
  });
  final String localDate;
  final Map<String, dynamic>? workout;
  final Map<String, dynamic>? nextMeal;
  final Map<String, dynamic>? checkIn;
  final Map<String, dynamic>? health;
  final Map<String, dynamic>? nutrition;
  final ComputedMetrics? computed;
  final Map<String, dynamic>? decision;

  /// Yesterday's stored recovery score; null when it was not scored.
  final int? recoveryPrevious;

  /// The active plan's place in its block; null without an active plan.
  final TodayPlan? plan;

  /// Monday to Sunday of the brief's week; empty on briefs before 1.7.
  final List<TodayWeekDay> week;

  /// Today's latest kept workout session; null when none was started.
  final TodaySession? todaySession;

  /// Maps a `get_my_daily_brief` payload. Fields a brief's schema version
  /// does not carry stay null or empty.
  factory DailyBrief.fromJson(Map<String, dynamic> value) {
    Map<String, dynamic>? object(String key) =>
        value[key] is Map ? Map<String, dynamic>.from(value[key] as Map) : null;
    final computedRaw = value['computed'];
    final computed = computedRaw is Map
        ? ComputedMetrics.fromJson(Map<String, dynamic>.from(computedRaw))
        : null;
    return DailyBrief(
      localDate: value['local_date'] as String,
      workout: object('today_workout'),
      nextMeal: object('next_meal'),
      checkIn: object('check_in'),
      health: object('health'),
      nutrition: object('nutrition'),
      computed: computed,
      decision: object('latest_decision'),
      recoveryPrevious: (value['recovery_previous'] as num?)?.toInt(),
      plan: object('plan') == null ? null : TodayPlan.fromJson(object('plan')!),
      week: [
        for (final day in (value['week'] as List? ?? const []))
          TodayWeekDay.fromJson(Map<String, dynamic>.from(day as Map)),
      ],
      todaySession: object('today_session') == null
          ? null
          : TodaySession.fromJson(object('today_session')!),
    );
  }
}

/// The active plan's place in its block (brief 1.7 `plan`).
class TodayPlan {
  const TodayPlan({
    required this.title,
    required this.weekNumber,
    required this.blockWeeks,
  });

  factory TodayPlan.fromJson(Map<String, dynamic> json) => TodayPlan(
    title: json['title'] as String? ?? 'Your plan',
    weekNumber: (json['week_number'] as num).toInt(),
    blockWeeks: (json['block_weeks'] as num).toInt(),
  );

  final String title;

  /// Weeks since the plan took effect, from 1. Can pass [blockWeeks].
  final int weekNumber;
  final int blockWeeks;
}

/// One day of the brief's week (brief 1.7 `week`).
class TodayWeekDay {
  const TodayWeekDay({
    required this.date,
    required this.trained,
    required this.planned,
    this.recovery,
    this.strain,
  });

  factory TodayWeekDay.fromJson(Map<String, dynamic> json) => TodayWeekDay(
    date: DateTime.parse(json['local_date'] as String),
    recovery: (json['recovery'] as num?)?.toInt(),
    strain: (json['strain'] as num?)?.toDouble(),
    trained: json['trained'] as bool? ?? false,
    planned: json['planned'] as bool? ?? false,
  );

  final DateTime date;

  /// The day's recovery score; null when it was not scored.
  final int? recovery;

  /// The day's training strain; null when none was computed.
  final double? strain;

  /// A session was completed that day.
  final bool trained;

  /// The active plan has a workout on that weekday.
  final bool planned;
}

/// Today's latest kept session (brief 1.7 `today_session`).
class TodaySession {
  const TodaySession({required this.state, required this.completedSets});

  factory TodaySession.fromJson(Map<String, dynamic> json) => TodaySession(
    state: json['state'] as String,
    completedSets: {
      for (final row in (json['exercises'] as List? ?? const []))
        ((row as Map)['order'] as num).toInt(): (row['completed_sets'] as num)
            .toInt(),
    },
  );

  /// `in_progress` or `completed`.
  final String state;

  /// Completed sets by exercise order.
  final Map<int, int> completedSets;

  bool get completed => state == 'completed';
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
    return DailyBrief.fromJson(value);
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
