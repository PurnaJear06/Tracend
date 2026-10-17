// Synthetic athletes for the Coach eval bank, built from the three base files in ../fixtures.ts
// and the goal-phase fixtures. Every builder returns a fresh clone, so a case never sees another
// case's changes. Names, ids and numbers are invented.
import { evalCoachingDate, evalProfiles } from "../fixtures.ts";
import { longCutReadings } from "../../_shared/training/goal_phase/fixtures.ts";
import type { Athlete, Contributors, Turn } from "./types.ts";

type Context = Record<string, unknown>;

export type BaseProfile = "rich" | "no_watch" | "new_user";

export const ownerToday = "2026-10-14";

/** A base athlete as of a coaching date. */
export function baseContext(profile: BaseProfile, today: string = evalCoachingDate): Context {
  return structuredClone(evalProfiles(today).find((p) => p.id === profile)!.context);
}

const obj = (value: unknown): Context => (value ?? {}) as Context;

export function withProfile(context: Context, patch: Context): Context {
  return { ...context, profile_context: { ...obj(context.profile_context), ...patch } };
}

export function withHistory(context: Context, turns: readonly Turn[]): Context {
  return { ...context, recent_messages: turns.map((turn) => ({ ...turn })) };
}

export function withGoal(context: Context, goalType: string, details: Context = {}): Context {
  return { ...context, active_goal: { goal_type: goalType, priority: 1, details } };
}

/** Weights as [date, kg], any order; the file lists them newest first. */
export function withWeights(
  context: Context,
  readings: readonly (readonly [string, number])[],
): Context {
  const sorted = [...readings].sort((a, b) => b[0].localeCompare(a[0]));
  return {
    ...context,
    weight_series_8w: sorted.map(([measured_on, weight_kg]) => ({
      measured_on,
      weight_kg,
      waist_cm: null,
      source: "manual",
    })),
  };
}

/** Today's check-in (and the newest row of the 14-day list). */
export function withCheckIn(context: Context, patch: Context): Context {
  const latest = { ...obj(context.latest_check_in), ...patch, local_date: context.coaching_date };
  const rest = Array.isArray(context.check_ins_14d) ? context.check_ins_14d.slice(1) : [];
  return { ...context, latest_check_in: latest, check_ins_14d: [latest, ...rest] };
}

export function withNutritionDay(context: Context, day: Context): Context {
  const days = Array.isArray(context.nutrition_daily_28d) ? context.nutrition_daily_28d : [];
  return { ...context, nutrition_daily_28d: [day, ...days] };
}

export function withPreference(
  context: Context,
  category: string,
  key: string,
  value: string,
  provenance = "chat_statement",
): Context {
  const preferences = Array.isArray(context.active_preferences) ? context.active_preferences : [];
  return {
    ...context,
    active_preferences: [...preferences, { category, key, value, provenance }],
  };
}

/**
 * A fact the athlete confirmed (goal, injury, equipment, schedule, diet). In the v8 file the only
 * store for it is `active_preferences`, with provenance "confirmed_fact"; when the confirmed-facts
 * section of the v9 file ships (A10), this is the one place to change.
 */
export function withConfirmedFact(
  context: Context,
  category: string,
  key: string,
  value: string,
): Context {
  return withPreference(context, category, key, value, "confirmed_fact");
}

/** An athlete with no plan, targets or schedule yet. */
export function withoutPlan(context: Context): Context {
  return {
    ...context,
    active_plan: null,
    nutrition_targets: null,
    nutrition_schedule: [],
    training_week_structure: null,
    permitted_evidence: ((context.permitted_evidence as string[]) ?? []).filter((code) =>
      code !== "APPROVED_PLAN_ACTIVE"
    ),
  };
}

export function athlete(context: Context, contributors: Contributors = {}): Athlete {
  return { context, contributors };
}

// ---- the owner's athlete --------------------------------------------------------------------

/** The goal-phase payload for the owner's weight case: the late-activated goal, no bad reading. */
export function ownerGoalPayload(
  overrides: Partial<{ target: Context; readings: readonly (readonly [string, number])[] }> = {},
): Context {
  const readings = overrides.readings ??
    longCutReadings.filter((r) => r.kg !== 60).map((r) => [r.date, r.kg] as const);
  return {
    schema_version: "1.0",
    height_cm: 180,
    goal: {
      goal_type: "fat_loss",
      activated_on: "2026-07-03",
      target: {
        weight_kg: null,
        body_fat_pct_min: null,
        body_fat_pct_max: null,
        physique: null,
        physique_note: null,
        date: null,
        ...overrides.target,
      },
    },
    readings: readings.map(([date, kg]) => ({ date, kg })),
  };
}

/**
 * 180 cm, 90 kg on 2026-06-03 down to 74.8 kg on 2026-10-13, fat loss since 2026-07-03 with no
 * target. The file holds eight weeks of weight and a goal detail from July (86.2 kg); the whole
 * change is only in the goal-phase reference data. With `outlier`, one 60 kg reading sits inside
 * the eight weeks.
 */
export function ownerAthlete(options: { outlier?: boolean } = {}): Athlete {
  const readings = longCutReadings.filter((r) => r.kg !== 60).map((r) => [r.date, r.kg] as const);
  if (options.outlier) readings.push(["2026-10-04", 60]);
  let context = baseContext("rich", ownerToday);
  context = withProfile(context, { height_cm: 180, sex: "male", age: 31 });
  context = withGoal(context, "fat_loss", {
    description: "Aggressive fat loss with muscle retention",
    current_weight_kg: 86.2,
  });
  context = withWeights(context, readings.filter(([date]) => date >= "2026-08-19"));
  return athlete(context, { goalPhase: ownerGoalPayload({ readings }) });
}

// ---- other athletes -------------------------------------------------------------------------
