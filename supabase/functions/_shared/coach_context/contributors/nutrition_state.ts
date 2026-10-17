// Contract 7 contributor (A10): the athlete's nutrition this week, with partial days kept apart.
// It reads get_coach_nutrition_state_v1 (service role). A logging day is complete with at least 3
// confirmed meals or 70% of the calorie target (docs/ALGORITHMS.md section 6); only complete days
// are averaged and compared with the target, and a partial day is named as partial: the rest of
// it was probably not logged, so it says nothing about intake. Also today's plan: the schedule's
// slots not yet logged with their foods, next to what has been eaten, and where the last two
// weeks of meals came from (a photo estimate is an estimate). Replaces the athlete file's
// per-logged-day nutrition lines.
import type { CoachContextContributor } from "../host.ts";
import { coachServiceRpc, type StateSource, stateSourceFromRpc } from "../service_source.ts";

export const nutritionStateContributorId = "nutrition_state";
export const nutritionStateContributorBudgetChars = 3_200;

type Json = Record<string, unknown>;
const rec = (value: unknown): Json =>
  value && typeof value === "object" && !Array.isArray(value) ? value as Json : {};
const list = (value: unknown): Json[] => Array.isArray(value) ? value.map(rec) : [];
const num = (value: unknown): number | null =>
  typeof value === "number" && Number.isFinite(value) ? value : null;
const str = (value: unknown): string => typeof value === "string" ? value : "";

export type NutritionDay = Readonly<{
  localDate: string;
  meals: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  complete: boolean;
}>;

export type NutritionState = Readonly<{
  localDate: string;
  target: Readonly<{ calories: number; protein: number; carbs: number; fat: number }> | null;
  minMeals: number;
  minShare: number;
  days: readonly NutritionDay[];
  schedule: readonly Readonly<{ label: string; time: string; foods: string; logged: boolean }>[];
  eaten: readonly Readonly<{ type: string; how: string; foods: string }>[];
  sources: Readonly<{ meals: number; photo: number; schedule: number; typed: number }>;
}>;

function foodText(food: unknown): string {
  if (typeof food === "string") return food;
  const item = rec(food);
  const name = str(item.name) || str(item.food);
  const quantity = str(item.quantity) || str(item.serving);
  return quantity ? `${name} ${quantity}` : name;
}

export function parseNutritionState(payload: unknown): NutritionState | null {
  const body = rec(payload);
  if (!str(body.schema_version).startsWith("1.") || typeof body.local_date !== "string") {
    return null;
  }
  const target = rec(body.target);
  const rules = rec(body.rules);
  const sources = rec(body.sources);
  return {
    localDate: body.local_date,
    target: num(target.calories) === null ? null : {
      calories: num(target.calories)!,
      protein: num(target.protein_g) ?? 0,
      carbs: num(target.carbohydrate_g) ?? 0,
      fat: num(target.fat_g) ?? 0,
    },
    minMeals: num(rules.min_meals) ?? 3,
    minShare: num(rules.min_target_share) ?? 0.7,
    days: list(body.days).map((day) => ({
      localDate: str(day.local_date),
      meals: num(day.meals) ?? 0,
      calories: num(day.calories) ?? 0,
      protein: num(day.protein_g) ?? 0,
      carbs: num(day.carbohydrate_g) ?? 0,
      fat: num(day.fat_g) ?? 0,
      complete: day.complete === true,
    })),
    schedule: list(body.schedule).map((slot) => ({
      label: str(slot.label),
      time: str(slot.local_time),
      foods: (Array.isArray(slot.foods) ? slot.foods : []).map(foodText).filter(Boolean).join(", "),
      logged: slot.logged === true,
    })),
    eaten: list(body.eaten_today).map((meal) => ({
      type: str(meal.meal_type),
      how: str(meal.source) === "photo_analysis"
        ? "photo estimate"
        : meal.from_schedule === true
        ? "from the schedule"
        : "typed in",
      foods: list(meal.foods).map((food) => `${str(food.name)} ${num(food.calories) ?? "—"} kcal`)
        .join(", "),
    })),
    sources: {
      meals: num(sources.meals) ?? 0,
      photo: num(sources.photo_estimate) ?? 0,
      schedule: num(sources.from_schedule) ?? 0,
      typed: num(sources.typed_in) ?? 0,
    },
  };
}

const signed = (value: number) => value > 0 ? `+${value}` : String(value);
const mean = (values: readonly number[]) =>
  Math.round(values.reduce((sum, value) => sum + value, 0) / values.length);

/** The text for one nutrition state, or null when there is nothing to say. Exposed for tests. */
export function renderNutritionState(state: NutritionState | null): string | null {
  if (state === null) return null;
  const lines: string[] = [];
  const complete = state.days.filter((day) => day.complete);
  const partial = state.days.filter((day) => !day.complete);
  if (state.days.length === 0) {
    lines.push("Last 7 days (to " + state.localDate + "): no confirmed meals logged.");
  } else {
    lines.push(
      `Last 7 days (to ${state.localDate}): ${complete.length} of ${state.days.length} logged ` +
        `days are complete (a complete day has at least ${state.minMeals} confirmed meals or ` +
        `${Math.round(state.minShare * 100)}% of the calorie target). Days with no meals are ` +
        "unknown, not zero.",
    );
  }
  if (complete.length > 0) {
    const part = (
      name: string,
      unit: string,
      values: number[],
      target: number | undefined,
    ) => {
      const average = mean(values);
      return target === undefined
        ? `${average} ${unit} ${name}`
        : `${average} ${unit} ${name} (target ${target}, ${signed(average - target)})`;
    };
    const t = state.target;
    lines.push(
      `Average of the ${complete.length} complete ${complete.length === 1 ? "day" : "days"}: ${
        part("energy", "kcal", complete.map((day) => day.calories), t?.calories)
      }, ${part("protein", "g", complete.map((day) => day.protein), t?.protein)}, ${
        part("carbohydrate", "g", complete.map((day) => day.carbs), t?.carbs)
      }, ${part("fat", "g", complete.map((day) => day.fat), t?.fat)}.`,
    );
  } else if (state.days.length > 0) {
    lines.push("No complete day yet this week, so no intake average is given.");
  }
  if (partial.length > 0) {
    lines.push(
      "Partial days (probably not fully logged; do not read them as low intake): " +
        partial.map((day) =>
          `${day.localDate} ${day.meals} ${
            day.meals === 1 ? "meal" : "meals"
          }, ${day.calories} kcal, ${day.protein} g protein`
        ).join("; ") + ".",
    );
  }
  const open = state.schedule.filter((slot) => !slot.logged);
  const logged = state.schedule.filter((slot) => slot.logged);
  if (state.schedule.length > 0) {
    lines.push(
      open.length
        ? "Planned meals not logged yet today: " +
          open.map((slot) => `${slot.label} ${slot.time} (${slot.foods || "no foods listed"})`)
            .join("; ") +
          "."
        : "Every planned meal today is logged.",
    );
    if (logged.length) {
      lines.push(
        `Planned meals already logged today: ${logged.map((slot) => slot.label).join(", ")}.`,
      );
    }
  }
  lines.push(
    state.eaten.length
      ? "Eaten today (confirmed): " +
        state.eaten.map((meal) => `${meal.type} (${meal.how}): ${meal.foods}`).join("; ") + "."
      : "Eaten today (confirmed): nothing logged yet.",
  );
  if (state.sources.meals > 0) {
    lines.push(
      `Where the last 14 days of meals came from (${state.sources.meals} meals): ${state.sources.photo} ` +
        `photo estimates (calories are estimates), ${state.sources.schedule} from the schedule, ` +
        `${state.sources.typed} typed in.`,
    );
  }
  return lines.join("\n");
}

export function createNutritionStateContributor(source: StateSource): CoachContextContributor {
  return {
    id: nutritionStateContributorId,
    slot: "volatile",
    budgetChars: nutritionStateContributorBudgetChars,
    async render(input) {
      return renderNutritionState(parseNutritionState(await source(input.userId, input.localDate)));
    },
  };
}

export const nutritionStateContributor: CoachContextContributor = createNutritionStateContributor(
  stateSourceFromRpc(coachServiceRpc, "get_coach_nutrition_state_v1"),
);
