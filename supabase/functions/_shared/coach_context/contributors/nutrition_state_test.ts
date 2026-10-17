import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  createNutritionStateContributor,
  nutritionStateContributorBudgetChars,
  parseNutritionState,
  renderNutritionState,
} from "./nutrition_state.ts";

const day = (
  local_date: string,
  meals: number,
  calories: number,
  complete: boolean,
  protein_g = 120,
) => ({ local_date, meals, calories, protein_g, carbohydrate_g: 200, fat_g: 60, complete });

function payload(overrides: Record<string, unknown> = {}) {
  return {
    schema_version: "1.0",
    local_date: "2026-10-17",
    target: { calories: 2000, protein_g: 150, carbohydrate_g: 220, fat_g: 65 },
    rules: { min_meals: 3, min_target_share: 0.7 },
    days: [
      day("2026-10-17", 1, 380, false, 30),
      day("2026-10-16", 4, 1900, true, 140),
      day("2026-10-15", 3, 2100, true, 160),
      day("2026-10-13", 2, 1500, true, 100),
    ],
    schedule: [
      {
        label: "Pre-workout",
        local_time: "07:45",
        optional: false,
        logged: true,
        foods: [{ name: "Banana", quantity: "1" }],
      },
      {
        label: "Lunch",
        local_time: "13:00",
        optional: false,
        logged: false,
        foods: [{ name: "Rice", quantity: "200 g" }, { name: "Chicken", quantity: "150 g" }],
      },
    ],
    eaten_today: [{
      meal_type: "breakfast",
      source: "photo_analysis",
      from_schedule: false,
      foods: [{ name: "Eggs", serving: "3", calories: 230, protein_g: 18 }],
    }],
    sources: { window_days: 14, meals: 20, photo_estimate: 5, from_schedule: 9, typed_in: 6 },
    ...overrides,
  };
}

Deno.test("k of n days complete; only complete days are averaged; partial days are named as partial", () => {
  const text = renderNutritionState(parseNutritionState(payload()))!;
  assertStringIncludes(text, "3 of 4 logged days are complete");
  assertStringIncludes(text, "at least 3 confirmed meals or 70% of the calorie target");
  // (1900 + 2100 + 1500) / 3 = 1833; protein (140 + 160 + 100) / 3 = 133.
  assertStringIncludes(
    text,
    "Average of the 3 complete days: 1833 kcal energy (target 2000, -167)",
  );
  assertStringIncludes(text, "133 g protein (target 150, -17)");
  assertStringIncludes(
    text,
    "Partial days (probably not fully logged; do not read them as low intake): 2026-10-17 1 meal, 380 kcal.",
  );
});

Deno.test("a breakfast-only day is partial, never a deficit, and a week without a complete day gets no average", () => {
  const text = renderNutritionState(parseNutritionState(payload({
    days: [day("2026-10-17", 1, 380, false)],
  })))!;
  assertStringIncludes(text, "0 of 1 logged days are complete");
  assertStringIncludes(text, "No complete day yet this week, so no intake average is given.");
  assertEquals(text.includes("Average of the"), false);
});

Deno.test("today: planned meals not logged yet with their foods, next to what was eaten", () => {
  const text = renderNutritionState(parseNutritionState(payload()))!;
  assertStringIncludes(
    text,
    "Planned meals not logged yet today: Lunch 13:00 (Rice 200 g, Chicken 150 g).",
  );
  assertStringIncludes(text, "Planned meals already logged today: Pre-workout.");
  assertStringIncludes(text, "Eaten today (confirmed): breakfast (photo estimate): Eggs 230 kcal.");
});

Deno.test("meal sources: a photo estimate is labelled an estimate", () => {
  const text = renderNutritionState(parseNutritionState(payload()))!;
  assertStringIncludes(
    text,
    "Where the last 14 days of meals came from (20 meals): 5 photo estimates (calories are estimates), 9 from the schedule, 6 typed in.",
  );
});

Deno.test("nothing logged: days are unknown, not zero; an unreadable payload renders nothing", () => {
  const text = renderNutritionState(parseNutritionState(payload({
    days: [],
    eaten_today: [],
    schedule: [],
    sources: { window_days: 14, meals: 0, photo_estimate: 0, from_schedule: 0, typed_in: 0 },
  })))!;
  assertStringIncludes(text, "no confirmed meals logged");
  assertStringIncludes(text, "nothing logged yet");
  assertEquals(renderNutritionState(parseNutritionState({ schema_version: "2.0" })), null);
});

Deno.test("the contributor reads the state for the coaching date and fits its budget", async () => {
  const seen: string[] = [];
  const contributor = createNutritionStateContributor((userId, localDate) => {
    seen.push(`${userId}|${localDate}`);
    return Promise.resolve(payload());
  });
  const text = await contributor.render({ userId: "u1", question: "q", localDate: "2026-10-17" });
  assertEquals(seen, ["u1|2026-10-17"]);
  assertEquals(text!.length <= nutritionStateContributorBudgetChars, true);
});
