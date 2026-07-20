import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { deterministicBoundary } from "./coach_chat_provider.ts";

Deno.test("deterministicBoundary — chest pain triggers emergency redirect", () => {
  const result = deterministicBoundary("I have chest pain after my workout");
  assert(result !== null);
  assertEquals(result.safety_state, "refused");
  assertEquals(result.evidence.length, 0);
  assertEquals(result.missing_data.length, 0);
  assert(result.answer.includes("emergency services"));
});

Deno.test("deterministicBoundary — fainting triggers emergency redirect", () => {
  const result = deterministicBoundary("I felt fainting during squats");
  assert(result !== null);
  assertEquals(result.safety_state, "refused");
  assert(result.answer.includes("emergency services"));
});

Deno.test("deterministicBoundary — can't breathe triggers emergency redirect", () => {
  const result = deterministicBoundary("I can't breathe properly");
  assert(result !== null);
  assertEquals(result.safety_state, "refused");
  assertEquals(result.suggested_follow_ups.length, 0);
});

Deno.test("deterministicBoundary — severe shortness of breath triggers emergency", () => {
  const result = deterministicBoundary("Experiencing severe shortness of breath");
  assert(result !== null);
  assertEquals(result.safety_state, "refused");
});

Deno.test("deterministicBoundary — diagnose triggers clinical disclosure", () => {
  const result = deterministicBoundary("Please diagnose my knee pain");
  assert(result !== null);
  assertEquals(result.safety_state, "refused");
  assert(result.answer.includes("diagnosis"));
  assert(result.answer.includes("qualified clinician"));
});

Deno.test("deterministicBoundary — medication triggers clinical disclosure", () => {
  const result = deterministicBoundary("Should I take any medication for this?");
  assert(result !== null);
  assertEquals(result.safety_state, "refused");
  assert(result.suggested_follow_ups.length > 0);
});

Deno.test("deterministicBoundary — medical report triggers clinical disclosure", () => {
  const result = deterministicBoundary("Can you read my medical report?");
  assert(result !== null);
  assertEquals(result.safety_state, "refused");
});

Deno.test("deterministicBoundary — rehab triggers clinical disclosure", () => {
  const result = deterministicBoundary("I need rehab for my shoulder");
  assert(result !== null);
  assertEquals(result.safety_state, "refused");
});

Deno.test("deterministicBoundary — pregnant triggers clinical disclosure", () => {
  const result = deterministicBoundary("I am pregnant, can I still train?");
  assert(result !== null);
  assertEquals(result.safety_state, "refused");
  assert(result.answer.includes("pregnancy"));
});

Deno.test("deterministicBoundary — eating disorder triggers clinical disclosure", () => {
  const result = deterministicBoundary("I think I have an eating disorder");
  assert(result !== null);
  assertEquals(result.safety_state, "refused");
  assert(result.answer.includes("eating-disorder"));
});

Deno.test("deterministicBoundary — normal question passes through", () => {
  assertEquals(deterministicBoundary("How many sets should I do today?"), null);
  assertEquals(deterministicBoundary("What should I eat for dinner?"), null);
  assertEquals(deterministicBoundary("Show me my progress"), null);
});

Deno.test("deterministicBoundary — emergency takes priority over clinical", () => {
  const result = deterministicBoundary("I have chest pain and need medication diagnosed");
  assert(result !== null);
  assert(result.answer.includes("emergency services"));
});

Deno.test("deterministicBoundary — case insensitive matching", () => {
  const result = deterministicBoundary("CHEST PAIN right now");
  assert(result !== null);
  assertEquals(result.safety_state, "refused");
});

Deno.test("deterministicBoundary — partial word match does NOT trigger", () => {
  const result = deterministicBoundary("My chest muscles are sore from training");
  assertEquals(result, null);
});
