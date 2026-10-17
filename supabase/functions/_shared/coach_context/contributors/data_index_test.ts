import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { coachLookupNames } from "../../coach_lookups/catalogue.ts";
import { dataIndexContributorBudgetChars, renderDataIndex } from "./data_index.ts";

const domain = (first: string, last: string, count: number) => ({ first, last, count });
const payload = {
  schema_version: "1.0",
  local_date: "2026-10-17",
  domains: {
    workouts: domain("2026-06-03", "2026-10-15", 61),
    meals: domain("2026-06-10", "2026-10-17", 90),
    body: domain("2026-06-03", "2026-10-16", 40),
    check_ins: domain("2026-07-01", "2026-10-17", 70),
    recovery: domain("2026-06-01", "2026-10-17", 120),
    plan_history: domain("2026-06-03", "2026-09-01", 3),
    goals: domain("2026-06-03", "2026-06-03", 1),
    weekly_reviews: { first: null, last: null, count: 0 },
    health_history: domain("2025-10-01", "2026-09-01", 12),
  },
};

Deno.test("the index lists each kind of record with its first and last date and count", () => {
  const text = renderDataIndex(payload, "2026-10-17")!;
  assertStringIncludes(text, "- workouts: 2026-06-03 to 2026-10-15, 61 completed workouts");
  assertStringIncludes(text, "- meals: 2026-06-10 to 2026-10-17, 90 days with confirmed meals");
  assertStringIncludes(text, "- health_history: 2025-10-01 to 2026-09-01, 12 months imported");
  assertStringIncludes(text, "No records yet for: weekly_reviews.");
  assertStringIncludes(text, "exercise_history reads one exercise out of the workouts.");
  assertEquals(text.length <= dataIndexContributorBudgetChars, true);
});

Deno.test("every index name is a lookup the catalogue knows", () => {
  for (const name of Object.keys(payload.domains)) {
    assertEquals(coachLookupNames.includes(name as never), true, name);
  }
});

Deno.test("an unreadable payload renders nothing", () => {
  assertEquals(renderDataIndex({ schema_version: "9" }, "2026-10-17"), null);
});
