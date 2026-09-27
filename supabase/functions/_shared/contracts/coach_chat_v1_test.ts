import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.13";
import {
  coachChatAnswerLimits,
  CoachChatAnswerValidationError,
  parseCoachChatAnswer,
  parseCoachChatRequest,
} from "./coach_chat_v1.ts";

Deno.test("chat request rejects ownership and accepts bounded input", () => {
  const request = parseCoachChatRequest({
    schema_version: "1.0",
    thread_id: "11111111-1111-4111-8111-111111111111",
    question: "What should I focus on in today's workout?",
    timezone: "Asia/Kolkata",
    idempotency_key: "22222222-2222-4222-8222-222222222222",
  });
  assertEquals(request.question.startsWith("What"), true);
  assertThrows(() => parseCoachChatRequest({ ...request, user_id: "unsafe" }));
});

Deno.test("chat answer rejects unsupported evidence", () => {
  const answer = {
    answer: "Keep the approved plan.",
    evidence: [{
      code: "APPROVED_PLAN_ACTIVE",
      label: "Approved plan",
      source: "feature_snapshot",
    }],
    missing_data: [],
    safety_state: "allowed",
    suggested_follow_ups: ["Show today's workout"],
  };
  assertEquals(parseCoachChatAnswer(answer, ["APPROVED_PLAN_ACTIVE"]).safety_state, "allowed");
  assertThrows(() => parseCoachChatAnswer(answer, []));
});

Deno.test("chat answer exposes only a finite validation rule and JSON path", () => {
  const error = assertThrows(
    () =>
      parseCoachChatAnswer({
        answer: "Grounded answer",
        evidence: [{ code: "INVENTED", label: "No", source: "feature_snapshot" }],
        missing_data: [],
        safety_state: "allowed",
        suggested_follow_ups: [],
        reasoning_chain: [],
      }, ["APPROVED_PLAN_ACTIVE"]),
    CoachChatAnswerValidationError,
  );
  assertEquals(error.rule, "evidence_code_not_permitted");
  assertEquals(error.path, "evidence[0].code");
  assertEquals(error.message.includes("Grounded answer"), false);
});

Deno.test("chat answer reports reasoning limits from shared constants", () => {
  const error = assertThrows(
    () =>
      parseCoachChatAnswer({
        answer: "Grounded answer",
        evidence: [],
        missing_data: [],
        safety_state: "allowed",
        suggested_follow_ups: [],
        reasoning_chain: [{
          step: "Recovery",
          value: "x".repeat(coachChatAnswerLimits.reasoningValueMaxLength + 1),
          evidence_id: null,
        }],
      }, []),
    CoachChatAnswerValidationError,
  );
  assertEquals(error.rule, "reasoning_value_too_long");
  assertEquals(error.path, "reasoning_chain[0].value");
  assertEquals(error.limit, coachChatAnswerLimits.reasoningValueMaxLength);
});
