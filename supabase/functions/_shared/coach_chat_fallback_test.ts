import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { buildCoachChatDataSummary, mayConcernHealthRisk } from "./coach_chat_fallback.ts";
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
  health_averages: { last_7_days: { days_synced: 7, days_with_sleep: 1, avg_sleep_minutes: 395 } },
  weight_series_8w: [{ measured_on: "2026-09-25", weight_kg: 78.4 }],
  nutrition_targets: { calories: 1900, protein_g: 150 },
  nutrition_adherence: { days_with_confirmed_meals_7d: 0 },
};

const question = "Give me a quick review of my week.";

Deno.test("data summary copies every number from the prepared context", () => {
  const summary = buildCoachChatDataSummary(context, question);
  for (
    const fact of [
      "7 completed sessions, 400 minutes, 120 completed sets (20450 kg volume)",
      "Your plan calls for 5 sessions a week",
      "Your watch also recorded 2 workouts",
      "Recovery today: 38/100",
      "Sleep quality: 51/100",
      "Latest weight: 78.4 kg on 2026-09-25",
      "28-day trend: -0.05 kg/day",
      "Nutrition target: 1900 kcal and 150 g protein a day",
      "0 of the last 7 days have confirmed meals",
    ]
  ) {
    assert(summary.answer.includes(fact), `missing: ${fact}`);
  }
});

Deno.test("a sleep average names the nights it was measured on, not the days synced", () => {
  const summary = buildCoachChatDataSummary(context, question);
  assert(
    summary.answer.includes(
      "Average sleep over the last 7 days: 395 minutes, from 1 night measured.",
    ),
  );
  assert(!summary.answer.includes("days synced"));
  const oneDay = buildCoachChatDataSummary({
    ...context,
    nutrition_adherence: { days_with_confirmed_meals_7d: 1 },
  }, question);
  assert(oneDay.answer.includes("1 of the last 7 days has confirmed meals"));
});

Deno.test("data summary is labeled and passes the chat answer contract", () => {
  const summary = buildCoachChatDataSummary(context, question);
  assert(summary.answer.startsWith("I couldn't put together a full coaching answer"));
  assert(summary.answer.endsWith("talk to a doctor or another qualified professional."));
  assertEquals(summary.safety_state, "unavailable");
  assertEquals(summary.missing_data, ["recovery_check_in"]);
  const parsed = parseCoachChatAnswer(summary, context.permitted_evidence);
  assertEquals(parsed.evidence.map((e) => e.code), context.permitted_evidence);
});

Deno.test("data summary says what was not measured and invents nothing", () => {
  const summary = buildCoachChatDataSummary({
    permitted_evidence: [],
    computed_metrics: { recovery: { score: null } },
  }, question);
  assert(summary.answer.includes("Recovery wasn't measured today."));
  assert(!/\d/.test(summary.answer), "no number may appear without data");
  assertEquals(summary.evidence, []);
});

Deno.test("data summary omits scores when the scoring engine failed", () => {
  const summary = buildCoachChatDataSummary({
    ...context,
    computed_metrics: { unavailable: true, reason: "computed scores unavailable for this date" },
  }, question);
  assert(!summary.answer.includes("Recovery today"));
  assert(!summary.answer.includes("28-day trend"));
  assert(summary.answer.includes("Latest weight: 78.4 kg"));
});

Deno.test("a message that may be about a health risk gets a referral, never numbers", () => {
  for (
    const risky of [
      "I've been making myself throw up after big meals to stay in my calories.",
      "I fainted after my workout yesterday, is that normal?",
      "I think I tore something in my shoulder, it's swollen and I can't lift my arm.",
      "Can I take a fat burner with my blood pressure medication?",
      "I just found out I'm pregnant, can I keep lifting heavy?",
      "I get chest pain and dizziness when I run, should I keep going?",
      "puking after every cardio session lol",
      "bhai kal se chakkar aa raha hai, gym jaun?",
      "knee hurts when i squat, push through?",
      "been taking laxatives to drop water weight before the weigh in",
      "honestly some days i want to die",
    ]
  ) {
    const reply = buildCoachChatDataSummary(context, risky);
    assertEquals(reply.safety_state, "limited", risky);
    assertEquals(reply.evidence, [], risky);
    assert(!/\d/.test(reply.answer), `no numbers for: ${risky}`);
    assert(reply.answer.includes("doctor"), risky);
    parseCoachChatAnswer(reply, context.permitted_evidence);
  }
});

Deno.test("ordinary training and food questions still get the data summary", () => {
  for (
    const ordinary of [
      "I slept badly and my legs are sore — should I still do legs today, and what should I eat after?",
      "hey couch my recovery is very poor idk why and now eveing ill have cardio !",
      "Chest day done, what should I eat tonight?",
      "I broke my bench PR today! What next?",
      "What's my heart rate trend this month?",
      "Did I hit my numbers this week?",
      "I'm starving after leg day, is a big dinner ok?",
      "I'm not eating enough protein, am I?",
      "The prescribed weight felt heavy today.",
    ]
  ) {
    assertEquals(mayConcernHealthRisk(ordinary), false, ordinary);
    assertEquals(buildCoachChatDataSummary(context, ordinary).safety_state, "unavailable");
  }
});
