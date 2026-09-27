import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { CoachChatUnavailableError } from "../_shared/providers/coach_chat_provider.ts";
import { buildCoachChatDataSummary } from "../_shared/coach_chat_fallback.ts";
import {
  buildSessionSummary,
  coachChatDataSummaryResponse,
  coachChatFailureResponse,
  coachChatFailureRules,
  coachChatPreparationFailureCode,
  coachChatResponseSchemaVersion,
  detectPreferenceStatement,
  supportsDataSummary,
} from "./index.ts";

Deno.test("a blocked context preparation names its cause with a finite code", () => {
  assertEquals(
    coachChatPreparationFailureCode({ code: "P0001", message: "daily rate limit reached" }),
    "daily_rate_limit",
  );
  assertEquals(
    coachChatPreparationFailureCode({ code: "22023", message: "chat context too large" }),
    "chat_context_too_large",
  );
  assertEquals(
    coachChatPreparationFailureCode({ code: "P0002", message: "approved plan required" }),
    "approved_plan_required",
  );
  // Unknown database errors keep only the SQLSTATE, never the message text.
  assertEquals(
    coachChatPreparationFailureCode({ code: "42703", message: 'column "x" does not exist' }),
    "sqlstate_42703",
  );
  assertEquals(coachChatPreparationFailureCode({ message: "fetch failed" }), "unknown");
  assertEquals(coachChatPreparationFailureCode(null), "missing_prepared_context");
});

Deno.test("only the current app schema receives the data-summary reply", () => {
  assertEquals(supportsDataSummary({ schema_version: "1.1" }), true);
  assertEquals(supportsDataSummary({ schema_version: "1.0" }), false);
});

Deno.test("data-summary response is labeled and exposes only finite diagnostics", () => {
  const error = new CoachChatUnavailableError(
    "deepseek",
    "deepseek-v4-flash",
    "provider_response_invalid",
    null,
    { initialRule: "evidence_code_not_permitted", repairRule: "reasoning_step_too_long" },
  );
  const summary = buildCoachChatDataSummary({
    permitted_evidence: ["APPROVED_PLAN_ACTIVE"],
    weight_series_8w: [{ measured_on: "2026-09-25", weight_kg: 78.4 }],
  });
  const response = coachChatDataSummaryResponse(
    summary,
    error,
    { assistant_message_id: "33333333-3333-4333-8333-333333333333", created_at: "2026-09-27" },
    null,
  );
  assertEquals(response.schema_version, "1.2");
  const message = response.message as Record<string, unknown>;
  assertEquals(message.id, "33333333-3333-4333-8333-333333333333");
  assertEquals(message.answer_source, "data_summary");
  assertEquals(message.model_provider, "deterministic");
  assertEquals(message.safety_state, "unavailable");
  assertEquals(message.diagnostic, {
    failure_code: "provider_response_invalid",
    initial_rule: "evidence_code_not_permitted",
    repair_rule: "reasoning_step_too_long",
  });
  assertEquals(coachChatFailureRules(error), [
    "evidence_code_not_permitted",
    "reasoning_step_too_long",
  ]);
});

Deno.test("an unstored data summary still reaches the athlete", () => {
  const error = new CoachChatUnavailableError(
    "deepseek",
    "deepseek-v4-flash",
    "provider_timeout",
    null,
  );
  const response = coachChatDataSummaryResponse(
    buildCoachChatDataSummary({}),
    error,
    null,
    null,
  );
  const message = response.message as Record<string, unknown>;
  assert(typeof message.id === "string" && message.id.length === 36);
  assertEquals(coachChatFailureRules(error), []);
});

Deno.test("buildSessionSummary reads the v8 athlete file", () => {
  const summary = buildSessionSummary(
    {
      active_goal: { goal_type: "fat_loss" },
      active_plan: { title: "Cut plan" },
      weight_series_8w: [{ measured_on: "2026-09-25", weight_kg: 78.4 }],
      training_log_28d: [{ local_date: "2026-09-26" }, { local_date: "2026-09-24" }],
      health_daily_28d: [{ sleep_minutes: 402, resting_heart_rate_bpm: 58 }],
    },
    "2026-09-27",
  );
  assertStringIncludes(summary, "fat_loss phase: Cut plan.");
  assertStringIncludes(summary, "Weight 78.4kg.");
  assertStringIncludes(summary, "2 workouts in 28 days.");
  assertStringIncludes(summary, "Sleep 402min.");
});

Deno.test("detectPreferenceStatement — negative food statement", () => {
  const result = detectPreferenceStatement("I don't eat mushrooms");
  assert(result !== null);
  const parsed = JSON.parse(result);
  assertEquals(parsed.category, "food");
  assertEquals(parsed.key, "mushrooms");
  assertEquals(parsed.provenance, "chat_statement");
});

Deno.test("detectPreferenceStatement — hate eating food", () => {
  const result = detectPreferenceStatement("I hate eat sushi");
  assert(result !== null);
  const parsed = JSON.parse(result);
  assertEquals(parsed.category, "food");
  assertEquals(parsed.key, "sushi");
});

Deno.test("detectPreferenceStatement — cannot stand food with punctuation", () => {
  const result = detectPreferenceStatement("I cannot stand drink spicy food in my dinner!");
  assert(result !== null);
  const parsed = JSON.parse(result);
  assertEquals(parsed.category, "food");
  assert(parsed.key.includes("spicy food"));
});

Deno.test("detectPreferenceStatement — prefer X over Y", () => {
  const result = detectPreferenceStatement("I prefer chicken over beef");
  assert(result !== null);
  const parsed = JSON.parse(result);
  assertEquals(parsed.category, "food");
  assert(parsed.key.includes("chicken"));
});

Deno.test("detectPreferenceStatement — dislike training", () => {
  const result = detectPreferenceStatement("I dislike doing burpees");
  assert(result !== null);
  const parsed = JSON.parse(result);
  assertEquals(parsed.category, "training");
  assertEquals(parsed.key, "burpees");
});

Deno.test("detectPreferenceStatement — prefer training type", () => {
  const result = detectPreferenceStatement("I prefer training running outdoors");
  assert(result !== null);
  const parsed = JSON.parse(result);
  assertEquals(parsed.category, "training");
  assertEquals(parsed.key, "running outdoors");
});

Deno.test("detectPreferenceStatement — no match returns null", () => {
  assertEquals(detectPreferenceStatement("How many sets should I do?"), null);
  assertEquals(detectPreferenceStatement("What should I eat for dinner"), null);
});

Deno.test("detectPreferenceStatement — matches all 6 patterns", () => {
  const positiveMatches = [
    "I don't eat mushrooms",
    "I prefer chicken over beef",
    "I prefer chicken as my main protein",
    "I only eat vegetarian meals",
    "I hate doing planks",
    "I prefer training swimming",
  ];
  for (const q of positiveMatches) {
    const result = detectPreferenceStatement(q);
    assert(result !== null, `Expected match for: "${q}"`);
  }
});

Deno.test("buildSessionSummary — includes active plan and goal", () => {
  const summary = buildSessionSummary({
    active_plan: { title: "Foundation Block" },
    active_goal: { type: "Lose 5 kg" },
    latest_weight: { weight_kg: 82 },
    recent_execution: [],
    brief_health: [{ sleep_minutes: 420, resting_heart_rate_bpm: 58 }],
    confirmed_nutrition_history: [],
  }, "2026-07-01");
  assertStringIncludes(summary, "Foundation Block");
  assertStringIncludes(summary, "82kg");
});

Deno.test("buildSessionSummary — caps at 400 chars", () => {
  const longName = "X".repeat(500);
  const summary = buildSessionSummary({
    active_plan: { title: longName },
    active_goal: { type: longName },
    latest_weight: { weight_kg: 100 },
    recent_execution: [],
    brief_health: [],
    confirmed_nutrition_history: [],
  }, "2026-07-01");
  assert(summary.length <= 400);
});

Deno.test("buildSessionSummary — handles missing context gracefully", () => {
  const summary = buildSessionSummary({}, "2026-07-01");
  assert(typeof summary === "string");
  assert(summary.length > 0);
});

Deno.test("buildSessionSummary — handles empty arrays", () => {
  const summary = buildSessionSummary({
    active_plan: undefined,
    active_goal: null,
    recent_execution: [],
    brief_health: [],
    confirmed_nutrition_history: [],
  }, "2026-07-01");
  assertEquals(typeof summary, "string");
});

Deno.test("coachChatFailureResponse exposes only the versioned safe error contract", () => {
  const error = new CoachChatUnavailableError(
    "deepseek",
    "deepseek-v4-flash",
    "provider_response_invalid",
    null,
    { attempt: "repair", finishReason: "stop" },
    { cause: new SyntaxError("Unexpected end of JSON input") },
  );
  const response = coachChatFailureResponse(error);
  assertEquals(response, {
    schema_version: "1.1",
    error: "chat_unavailable",
    code: "provider_response_invalid",
    retry_after_seconds: null,
  });
  assertEquals(coachChatResponseSchemaVersion, "1.1");
  const serialized = JSON.stringify(response);
  assert(!serialized.includes("Unexpected end of JSON input"));
  assert(!serialized.includes("deepseek-v4-flash"));
});
