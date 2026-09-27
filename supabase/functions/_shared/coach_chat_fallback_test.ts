import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { buildCoachChatDataSummary } from "./coach_chat_fallback.ts";
import { parseCoachChatAnswer } from "./contracts/coach_chat_v1.ts";

const context = {
  coaching_date: "2026-09-27",
  active_plan: { title: "Cut plan", sessions_per_week: 5 },
  permitted_evidence: ["APPROVED_PLAN_ACTIVE", "RECOVERY_BELOW_BASELINE"],
  missing_data: ["recovery_check_in"],
  computed_metrics: {
    recovery: { score: 38 },
    sleep: { quality: 51 },
    weight: { trend_28d_kg_per_day: -0.05 },
  },
  training_totals: {
    last_14_days: { sessions: 7, total_minutes: 400, completed_sets: 120, volume_kg: 20450 },
  },
  watch_workouts_14d: [{ activity_type: "running" }, { activity_type: "cycling" }],
  health_averages: { last_7_days: { days_synced: 6, avg_sleep_minutes: 395 } },
  weight_series_8w: [{ measured_on: "2026-09-25", weight_kg: 78.4 }],
  nutrition_targets: { calories: 1900, protein_g: 150 },
  nutrition_adherence: { days_with_confirmed_meals_7d: 0 },
};

Deno.test("data summary copies every number from the prepared context", () => {
  const summary = buildCoachChatDataSummary(context);
  for (
    const fact of [
      "7 completed sessions, 400 minutes, 120 completed sets (20450 kg volume)",
      "Your plan calls for 5 sessions a week",
      "Your watch also recorded 2 workouts",
      "Recovery today: 38/100",
      "Sleep quality: 51/100",
      "Average sleep over the last 7 days: 395 minutes (6 days synced)",
      "Latest weight: 78.4 kg on 2026-09-25",
      "28-day trend: -0.05 kg/day",
      "Nutrition target: 1900 kcal and 150 g protein a day",
      "0 of the last 7 days have confirmed meals",
    ]
  ) {
    assert(summary.answer.includes(fact), `missing: ${fact}`);
  }
});

Deno.test("data summary is labeled and passes the chat answer contract", () => {
  const summary = buildCoachChatDataSummary(context);
  assert(summary.answer.startsWith("I couldn't put together a full coaching answer"));
  assertEquals(summary.safety_state, "unavailable");
  assertEquals(summary.missing_data, ["recovery_check_in"]);
  const parsed = parseCoachChatAnswer(summary, context.permitted_evidence);
  assertEquals(parsed.evidence.map((e) => e.code), context.permitted_evidence);
});

Deno.test("data summary says what was not measured and invents nothing", () => {
  const summary = buildCoachChatDataSummary({
    permitted_evidence: [],
    computed_metrics: { recovery: { score: null } },
  });
  assert(summary.answer.includes("Recovery wasn't measured today."));
  assert(!/\d/.test(summary.answer), "no number may appear without data");
  assertEquals(summary.evidence, []);
});

Deno.test("data summary omits scores when the scoring engine failed", () => {
  const summary = buildCoachChatDataSummary({
    ...context,
    computed_metrics: { unavailable: true, reason: "computed scores unavailable for this date" },
  });
  assert(!summary.answer.includes("Recovery today"));
  assert(!summary.answer.includes("28-day trend"));
  assert(summary.answer.includes("Latest weight: 78.4 kg"));
});
