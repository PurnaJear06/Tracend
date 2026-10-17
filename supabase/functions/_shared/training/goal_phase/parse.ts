// Reads the get_goal_phase_inputs_v1 payload (service role, version 1.x) into review inputs.
// Anything unreadable becomes "missing", never a guess.
import { dayIndex } from "./math.ts";
import { type GoalPhaseInputs, noGoalTarget, type WeightReading } from "./types.ts";

function obj(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function num(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : null;
}

function date(value: unknown): string | null {
  return typeof value === "string" && dayIndex(value.slice(0, 10)) !== null
    ? value.slice(0, 10)
    : null;
}

export function parseGoalPhaseInputs(payload: unknown, today: string): GoalPhaseInputs {
  const root = obj(payload);
  const goal = obj(root.goal);
  const target = obj(goal.target);
  const readings: WeightReading[] = (Array.isArray(root.readings) ? root.readings : [])
    .flatMap((item) => {
      const row = obj(item);
      const day = date(row.date);
      const kg = num(row.kg);
      return day === null || kg === null || kg <= 0 ? [] : [{ date: day, kg }];
    });
  return {
    today,
    goalType: text(goal.goal_type),
    activatedOn: date(goal.activated_on),
    heightCm: num(root.height_cm),
    target: root.goal === null || root.goal === undefined ? noGoalTarget : {
      weightKg: num(target.weight_kg),
      bodyFatMinPct: num(target.body_fat_pct_min),
      bodyFatMaxPct: num(target.body_fat_pct_max),
      physique: text(target.physique),
      physiqueNote: text(target.physique_note),
      date: date(target.date),
    },
    readings,
  };
}
