import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { CoachChatUnavailableError } from "../_shared/providers/coach_chat_provider.ts";
import {
  buildSessionSummary,
  coachChatFailureResponse,
  coachChatResponseSchemaVersion,
  detectPreferenceStatement,
} from "./index.ts";

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
