// Synthetic athletes for the goal phase tests and the Coach eval. They reproduce the shape of a
// real failure (a long cut, a short Coach window, a stale goal detail, one impossible reading)
// with invented data and ids.
import type { GoalPhaseInputs, WeightReading } from "./types.ts";

const rows: readonly (readonly [string, number])[] = [
  ["2026-06-03", 90.0],
  ["2026-06-10", 89.0],
  ["2026-06-17", 88.0],
  ["2026-06-24", 87.0],
  ["2026-07-02", 60.0], // impossible: 27 kg between two readings a week apart
  ["2026-07-09", 83.0],
  ["2026-07-16", 82.0],
  ["2026-07-23", 81.0],
  ["2026-07-30", 80.2],
  ["2026-08-06", 79.4],
  ["2026-08-13", 78.6],
  ["2026-08-20", 77.9],
  ["2026-08-27", 77.2],
  ["2026-09-03", 76.6],
  ["2026-09-10", 76.1],
  ["2026-09-17", 75.7],
  ["2026-09-24", 75.4],
  ["2026-10-01", 75.2],
  ["2026-10-07", 74.7],
  ["2026-10-10", 74.9],
  ["2026-10-13", 74.8],
];

export const longCutReadings: readonly WeightReading[] = rows.map(([date, kg]) => ({ date, kg }));

/** A 180 cm athlete on a fat-loss goal since 1 June: 90.0 to 74.8 kg, no target, one bad reading. */
export const longCutInputs: GoalPhaseInputs = {
  today: "2026-10-14",
  goalType: "fat_loss",
  activatedOn: "2026-06-01",
  heightCm: 180,
  target: {
    weightKg: null,
    bodyFatMinPct: null,
    bodyFatMaxPct: null,
    physique: null,
    physiqueNote: null,
    date: null,
  },
  readings: longCutReadings,
};

/** The RPC payload (get_goal_phase_inputs_v1) for the same athlete. */
export const longCutPayload = {
  schema_version: "1.0",
  height_cm: 180,
  goal: {
    goal_type: "fat_loss",
    activated_on: "2026-06-01",
    target: {
      weight_kg: null,
      body_fat_pct_min: null,
      body_fat_pct_max: null,
      physique: null,
      physique_note: null,
      date: null,
    },
  },
  readings: longCutReadings.map(({ date, kg }) => ({ date, kg })),
};

/**
 * The prepared Coach context (the shape of prepare_coach_chat_v8) for the same athlete: the file
 * holds only the last 8 weeks of weight, and the goal details still carry the weight from July.
 */
export const longCutContext: Record<string, unknown> = {
  coaching_date: "2026-10-14",
  profile_context: { height_cm: 180, experience_level: "intermediate" },
  active_goal: {
    goal_type: "fat_loss",
    priority: 1,
    details: {
      description: "Aggressive fat loss with muscle retention",
      current_weight_kg: 86.2,
    },
  },
  weight_series_8w: [...longCutReadings].reverse()
    .filter((r) => r.date >= "2026-08-20")
    .map((r) => ({ measured_on: r.date, weight_kg: r.kg, waist_cm: null, source: "manual" })),
};
