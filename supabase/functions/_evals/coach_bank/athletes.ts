// Synthetic athletes for the Coach eval bank, built from the three base files in ../fixtures.ts
// and the goal-phase fixtures. Every builder returns a fresh clone, so a case never sees another
// case's changes. Names, ids and numbers are invented.
import { evalCoachingDate, evalProfiles } from "../fixtures.ts";
import { longCutReadings } from "../../_shared/training/goal_phase/fixtures.ts";
import type { CoachFact } from "../../_shared/coach_memory/facts.ts";
import type { FactKind } from "../../_shared/coach_memory/vocabulary.ts";
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

/**
 * An athlete whose newest nutrition day is partly logged (a `get_coach_nutrition_state_v1`
 * payload with that one incomplete day), as the nutrition_state contributor reads it.
 */
export function partialNutritionDay(context: Context, day: Context): Athlete {
  const target = obj(context.nutrition_targets);
  return athlete(context, {
    nutritionState: {
      schema_version: "1.0",
      local_date: context.coaching_date,
      target: Object.keys(target).length ? target : null,
      rules: { min_meals: 3, min_target_share: 0.7 },
      days: [{ ...day, meals: day.confirmed_meals, complete: false }],
      schedule: [],
      eaten_today: [],
      sources: { window_days: 14, meals: 0, photo_estimate: 0, from_schedule: 0, typed_in: 0 },
    },
  });
}

/**
 * A fact the athlete confirmed, as the memory holds it (A10 part 2). The case gives it to
 * `athlete(context, { memory: { facts: [...] } })`; the real confirmed-facts contributor renders it.
 */
export function confirmedFact(
  kind: FactKind,
  subject: string,
  statement: string,
  confirmedOn = "2026-09-01",
  reconfirmOn: string | null = null,
): CoachFact {
  const id = `00000000-0000-4000-8000-${
    String(1 + Array.from(subject).reduce((sum, ch) => sum + ch.charCodeAt(0), 0)).padStart(12, "0")
  }`;
  return {
    id,
    lineageId: id,
    version: 1,
    kind,
    subject,
    statement,
    source: "athlete_typed",
    confirmedOn,
    reconfirmOn,
  };
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
