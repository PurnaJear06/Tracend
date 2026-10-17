// Synthetic athlete for the Coach safety tests: the owner's case (180 cm, 74.4 kg after a cut
// that began on 2026-07-04 at 86.2 kg, fat loss with no target), with invented data. It matches
// the production replies quoted in the A9 brief: a loss of 11.8 kg (13.7%) over 14.6 weeks, a
// 4-week pace of -0.62 kg/week, BMI 23.
import type { WeightReading } from "../training/goal_phase/types.ts";

const rows: readonly (readonly [string, number])[] = [
  ["2026-07-04", 86.2],
  ["2026-07-11", 85.3],
  ["2026-07-18", 84.4],
  ["2026-07-25", 83.4],
  ["2026-08-01", 82.5],
  ["2026-08-08", 81.6],
  ["2026-08-15", 80.7],
  ["2026-08-22", 79.8],
  ["2026-08-29", 78.8],
  ["2026-09-05", 77.9],
  ["2026-09-12", 77.0],
  ["2026-09-19", 76.3],
  ["2026-09-26", 76.2],
  ["2026-10-03", 74.9],
  ["2026-10-10", 74.4],
  ["2026-10-14", 74.4],
];

export const ownerReadings: readonly WeightReading[] = rows.map(([date, kg]) => ({ date, kg }));

/** The get_goal_phase_inputs_v1 payload for the owner's case. */
export const ownerGoalPhasePayload = {
  schema_version: "1.0",
  height_cm: 180,
  goal: {
    goal_type: "fat_loss",
    activated_on: "2026-07-04",
    target: {
      weight_kg: null,
      body_fat_pct_min: null,
      body_fat_pct_max: null,
      physique: null,
      physique_note: null,
      date: null,
    },
  },
  readings: ownerReadings.map(({ date, kg }) => ({ date, kg })),
};

/** The prepared Coach context for the owner's case (the file holds eight weeks of weight). */
export function ownerContext(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    coaching_date: "2026-10-14",
    permitted_evidence: ["APPROVED_PLAN_ACTIVE", "HEALTH_CONTEXT_AVAILABLE"],
    profile_context: {
      height_cm: 180,
      sex: "male",
      age: 31,
      experience_level: "intermediate",
    },
    active_goal: {
      goal_type: "fat_loss",
      priority: 1,
      details: { description: "Fat loss with muscle retention", current_weight_kg: 86.2 },
    },
    nutrition_targets: { calories: 2000, protein_g: 160, carbohydrate_g: 200, fat_g: 60 },
    training_totals: {
      last_7_days: {
        sessions: 3,
        total_minutes: 180,
        completed_sets: 54,
        volume_kg: 9800,
      },
    },
    active_plan: { title: "Upper lower", version_number: 2, sessions_per_week: 6 },
    nutrition_adherence: { days_with_confirmed_meals_7d: 1, confirmed_meal_count_7d: 3 },
    weight_series_8w: [...ownerReadings].reverse().filter((r) => r.date >= "2026-08-22").map((
      r,
    ) => ({ measured_on: r.date, weight_kg: r.kg, waist_cm: null, source: "manual" })),
    ...extra,
  };
}
