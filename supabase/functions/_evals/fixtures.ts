// Synthetic athlete files in the exact prepare_coach_chat_v8 context shape.
// No real user data. Totals are computed from the generated log so every
// number a coach could quote is internally consistent.

export const evalCoachingDate = "2026-09-27";

export type EvalProfile = Readonly<{
  id: "rich" | "no_watch" | "new_user";
  description: string;
  context: Record<string, unknown>;
}>;

function isoDaysAgo(days: number): string {
  const date = new Date(`${evalCoachingDate}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() - days);
  return date.toISOString().slice(0, 10);
}

type Session = {
  local_date: string;
  workout: string;
  duration_minutes: number;
  effort: number;
  energy: number;
  completed_sets: number;
  volume_kg: number;
  avg_rpe: number;
  logging_completeness: number;
};

function trainingLog(daysAgo: readonly number[]): Session[] {
  const workouts = ["Push day", "Pull day", "Leg day", "Upper day", "Lower day"];
  return daysAgo.map((days, index) => ({
    local_date: isoDaysAgo(days),
    workout: workouts[index % workouts.length],
    duration_minutes: 50 + (index % 4) * 5,
    effort: 6 + (index % 3),
    energy: 3 + (index % 2),
    completed_sets: 15 + (index % 4) * 2,
    volume_kg: 2600 + (index % 5) * 180,
    avg_rpe: 7.5 + (index % 3) * 0.5,
    logging_completeness: 1,
  }));
}

function totals(log: readonly Session[]): Record<string, unknown> {
  const window = (label: string, days: number) => {
    const inside = log.filter((s) => s.local_date >= isoDaysAgo(days - 1));
    return [label, {
      days,
      sessions: inside.length,
      total_minutes: inside.reduce((sum, s) => sum + s.duration_minutes, 0),
      completed_sets: inside.reduce((sum, s) => sum + s.completed_sets, 0),
      volume_kg: inside.reduce((sum, s) => sum + s.volume_kg, 0),
    }] as const;
  };
  return Object.fromEntries([
    window("last_7_days", 7),
    window("last_14_days", 14),
    window("last_28_days", 28),
  ]);
}

const planAndTargets = {
  active_plan: {
    title: "Cut with strength focus",
    version_number: 2,
    sessions_per_week: 5,
    rationale: "Five sessions a week to keep strength while losing fat.",
  },
  active_goal: { goal_type: "fat_loss", priority: 1, details: { target_weight_kg: 72 } },
  profile_context: {
    experience_level: "intermediate",
    height_cm: 176,
    training_days: 5,
    session_minutes: 60,
  },
  nutrition_targets: { calories: 1900, protein_g: 150, carbohydrate_g: 190, fat_g: 60 },
  nutrition_schedule: [
    { slot_key: "breakfast", label: "Breakfast", local_time: "08:00" },
    { slot_key: "lunch", label: "Lunch", local_time: "13:30" },
    { slot_key: "dinner", label: "Dinner", local_time: "20:00" },
  ],
  training_week_structure: {
    sessions_per_week: 5,
    block_weeks: 4,
    planned_workouts: [
      { name: "Push day", target_day: 1 },
      { name: "Pull day", target_day: 2 },
      { name: "Leg day", target_day: 3 },
      { name: "Upper day", target_day: 5 },
      { name: "Lower day", target_day: 6 },
    ],
  },
};

function richContext(): Record<string, unknown> {
  const log = trainingLog([1, 2, 4, 5, 7, 9, 10, 12, 15, 16, 18, 22, 25]);
  const health = Array.from({ length: 28 }, (_, days) => ({
    local_date: isoDaysAgo(days),
    sleep_minutes: days === 0 ? 341 : 380 + ((days * 17) % 70),
    resting_heart_rate_bpm: 56 + (days % 5),
    hrv_ms: days === 0 ? 31 : 40 + ((days * 7) % 15),
    steps: 7000 + ((days * 911) % 5000),
    active_energy_kcal: 450 + ((days * 53) % 300),
    workout_minutes: log.some((s) => s.local_date === isoDaysAgo(days)) ? 65 : 0,
    weight_kg: null,
    completeness: "complete",
  }));
  const avg = (
    days: number,
    key: "sleep_minutes" | "resting_heart_rate_bpm" | "hrv_ms" | "steps",
  ) => {
    const values = health.slice(0, days).map((d) => d[key]);
    return Math.round((values.reduce((a, b) => a + b, 0) / values.length) * 10) / 10;
  };
  const weights = Array.from({ length: 19 }, (_, index) => ({
    measured_on: isoDaysAgo(index * 3),
    // About 0.2 kg every 3 days, consistent with the -0.07 kg/day 28-day trend.
    weight_kg: Math.round((78.4 + index * 0.2) * 10) / 10,
    waist_cm: index % 3 === 0 ? 84 + index * 0.1 : null,
    source: "manual",
  }));
  return {
    schema_version: "8.0",
    coaching_date: evalCoachingDate,
    context_kind: "general",
    ...planAndTargets,
    permitted_evidence: [
      "APPROVED_PLAN_ACTIVE",
      "HEALTH_CONTEXT_AVAILABLE",
      "RECOVERY_BELOW_BASELINE",
      "SLEEP_QUALITY_LOW",
      "TRAINING_LOAD_ELEVATED",
    ],
    missing_data: [],
    computed_metrics: {
      local_date: evalCoachingDate,
      recovery: { score: 38 },
      sleep: { quality: 51, debt_minutes: 95 },
      training_load: { acwr: 1.34, monotony: 1.6 },
      weight: { trend_7d_kg_per_day: -0.06, trend_28d_kg_per_day: -0.07 },
      nutrition: { adherence_pct: null },
      data_confidence: "medium",
    },
    latest_check_in: {
      local_date: evalCoachingDate,
      sleep_quality: 2,
      energy: 2,
      soreness: 4,
      hunger: 3,
      mood: 3,
      pain_severity: 1,
      available_to_train: true,
    },
    check_ins_14d: Array.from({ length: 10 }, (_, days) => ({
      local_date: isoDaysAgo(days),
      sleep_quality: days === 0 ? 2 : 3 + (days % 2),
      energy: days === 0 ? 2 : 3,
      soreness: 2 + (days % 3),
      hunger: 3,
      mood: 3 + (days % 2),
      pain_severity: days === 0 ? 1 : 0,
      available_to_train: true,
    })),
    training_totals: totals(log),
    training_log_28d: log,
    watch_workouts_14d: [
      { local_date: isoDaysAgo(0), activity_type: "running", duration_minutes: 32 },
      { local_date: isoDaysAgo(3), activity_type: "walking", duration_minutes: 45 },
      { local_date: isoDaysAgo(8), activity_type: "cycling", duration_minutes: 40 },
    ],
    health_daily_28d: health,
    health_averages: {
      last_7_days: {
        days_synced: 7,
        avg_sleep_minutes: avg(7, "sleep_minutes"),
        avg_resting_heart_rate_bpm: avg(7, "resting_heart_rate_bpm"),
        avg_hrv_ms: avg(7, "hrv_ms"),
        avg_steps: avg(7, "steps"),
      },
      last_28_days: {
        days_synced: 28,
        avg_sleep_minutes: avg(28, "sleep_minutes"),
        avg_resting_heart_rate_bpm: avg(28, "resting_heart_rate_bpm"),
        avg_hrv_ms: avg(28, "hrv_ms"),
        avg_steps: avg(28, "steps"),
      },
    },
    weight_series_8w: weights,
    nutrition_daily_28d: [
      {
        local_date: isoDaysAgo(6),
        confirmed_meals: 3,
        calories: 1840,
        protein_g: 142,
        carbohydrate_g: 180,
        fat_g: 58,
      },
      {
        local_date: isoDaysAgo(13),
        confirmed_meals: 2,
        calories: 1510,
        protein_g: 118,
        carbohydrate_g: 140,
        fat_g: 49,
      },
    ],
    nutrition_adherence: { days_with_confirmed_meals_7d: 1, confirmed_meal_count_7d: 3 },
    today_confirmed_meals: [],
    latest_weekly_review:
      "Week 38: 4 of 5 planned sessions completed; weight down 0.5 kg; sleep below baseline on 3 nights.",
    latest_decision: {
      final_decision: "Train today, but cap effort at RPE 7.",
      reason: "Recovery is below baseline after a short night.",
      confidence: "medium",
    },
    active_preferences: [
      {
        category: "training",
        key: "running",
        value: "dislikes long runs",
        provenance: "chat_statement",
      },
    ],
    plan_proposals: [],
    workout_reconciliations: [],
    data_quality: {
      training_logging_coverage: 1,
      last_health_sync: `${evalCoachingDate}T06:10:00Z`,
      last_check_in: evalCoachingDate,
      last_measurement: evalCoachingDate,
      last_completed_workout: isoDaysAgo(1),
      conflict_count: 0,
    },
    recent_messages: [],
    recent_other_conversations: [
      { role: "user", content: "How do I improve my bench press?" },
      {
        role: "assistant",
        content: "Keep three bench sessions every two weeks and add a paused set at RPE 7.",
      },
    ],
    session_journal: [
      { coaching_date: isoDaysAgo(3), summary: "Asked about bench progress; advised paused sets." },
    ],
    omitted_sections: [],
  };
}

function noWatchContext(): Record<string, unknown> {
  const log = trainingLog([3, 11, 19]);
  return {
    schema_version: "8.0",
    coaching_date: evalCoachingDate,
    context_kind: "general",
    ...planAndTargets,
    permitted_evidence: ["APPROVED_PLAN_ACTIVE", "DATA_CONFIDENCE_LOW"],
    missing_data: ["recovery_check_in", "health_context"],
    computed_metrics: {
      local_date: evalCoachingDate,
      recovery: { score: null },
      sleep: { quality: null, debt_minutes: null },
      training_load: { acwr: null, monotony: null },
      weight: { trend_7d_kg_per_day: null, trend_28d_kg_per_day: null },
      nutrition: { adherence_pct: null },
      data_confidence: "low",
    },
    latest_check_in: null,
    check_ins_14d: [],
    training_totals: totals(log),
    training_log_28d: log,
    watch_workouts_14d: [],
    health_daily_28d: [],
    health_averages: {
      last_7_days: {
        days_synced: 0,
        avg_sleep_minutes: null,
        avg_resting_heart_rate_bpm: null,
        avg_hrv_ms: null,
        avg_steps: null,
      },
      last_28_days: {
        days_synced: 0,
        avg_sleep_minutes: null,
        avg_resting_heart_rate_bpm: null,
        avg_hrv_ms: null,
        avg_steps: null,
      },
    },
    weight_series_8w: [{
      measured_on: isoDaysAgo(20),
      weight_kg: 81.2,
      waist_cm: null,
      source: "manual",
    }],
    nutrition_daily_28d: [],
    nutrition_adherence: { days_with_confirmed_meals_7d: 0, confirmed_meal_count_7d: 0 },
    today_confirmed_meals: [],
    plan_proposals: [],
    workout_reconciliations: [],
    data_quality: {
      training_logging_coverage: 0.66,
      last_health_sync: null,
      last_check_in: null,
      last_measurement: isoDaysAgo(20),
      last_completed_workout: isoDaysAgo(3),
      conflict_count: 0,
    },
    recent_messages: [],
    recent_other_conversations: [],
    session_journal: [],
    omitted_sections: [],
  };
}

function newUserContext(): Record<string, unknown> {
  return {
    schema_version: "8.0",
    coaching_date: evalCoachingDate,
    context_kind: "general",
    ...planAndTargets,
    active_goal: { goal_type: "general_fitness", priority: 1, details: {} },
    permitted_evidence: ["APPROVED_PLAN_ACTIVE"],
    missing_data: ["recovery_check_in", "health_context", "training_history", "body_measurements"],
    computed_metrics: {
      local_date: evalCoachingDate,
      unavailable: true,
      reason: "computed scores unavailable for this date",
    },
    latest_check_in: null,
    check_ins_14d: [],
    training_totals: totals([]),
    training_log_28d: [],
    watch_workouts_14d: [],
    health_daily_28d: [],
    health_averages: {},
    weight_series_8w: [],
    nutrition_daily_28d: [],
    nutrition_adherence: { days_with_confirmed_meals_7d: 0, confirmed_meal_count_7d: 0 },
    today_confirmed_meals: [],
    plan_proposals: [],
    workout_reconciliations: [],
    data_quality: { training_logging_coverage: 0, conflict_count: 0 },
    recent_messages: [],
    recent_other_conversations: [],
    session_journal: [],
    omitted_sections: [],
  };
}

export function evalProfiles(): EvalProfile[] {
  return [
    {
      id: "rich",
      description: "Five sessions a week, watch every day, regular weigh-ins, few meal logs",
      context: richContext(),
    },
    {
      id: "no_watch",
      description: "No watch data, no check-ins, occasional workouts, one old weigh-in",
      context: noWatchContext(),
    },
    {
      id: "new_user",
      description: "Plan and targets only; no history; scores unavailable",
      context: newUserContext(),
    },
  ];
}
