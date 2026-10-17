// The pre-model red-flag screen as Coach chat applies it (coach_safety/red_flags.ts): a hit is
// answered by the fixed referral before any provider is configured, called or charged.
import { assert, assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { parseCoachChatAnswer } from "../contracts/coach_chat_v1.ts";
import { routeFor } from "../ai/fakes.ts";
import {
  CoachChatUnavailableError,
  deterministicSafetyGeneration,
  generateCoachChat,
} from "./coach_chat_provider.ts";
import { generateCoachChatViaGateway } from "./coach_chat_provider_gateway.ts";

const neverCalled = (() => {
  throw new Error("a referral must not call a provider");
}) as unknown as typeof fetch;

const context = (extra: Record<string, unknown> = {}) => ({
  coaching_date: "2026-10-17",
  permitted_evidence: ["APPROVED_PLAN_ACTIVE"],
  ...extra,
});

Deno.test("a red flag is answered by the referral with no provider, tokens or cost", async () => {
  const generation = await generateCoachChat(
    "I have chest pain after my workout",
    context(),
    "recovery",
    neverCalled,
  );
  assertEquals(generation.provider, "mock");
  assertEquals(generation.model, "deterministic-safety-v1");
  assertEquals(
    [generation.inputUnits, generation.outputUnits, generation.estimatedCostUsd],
    [0, 0, 0],
  );
  assertEquals(generation.attempts, []);
  assertEquals(generation.safety, { category: "chest", rule: "chest_symptom", source: "message" });
  assertEquals(generation.answer.safety_state, "limited");
  assertStringIncludes(generation.answer.answer, "emergency number");
  parseCoachChatAnswer(generation.answer, []);
});

Deno.test("the gateway path answers a red flag before any request", async () => {
  const generation = await generateCoachChatViaGateway({
    question: "I fainted at the gym yesterday",
    context: context(),
    contextKind: "general",
    route: routeFor("coach_chat"),
    consentVendor: "anthropic",
  }, { fetch: neverCalled });
  assertEquals(generation.model, "deterministic-safety-v1");
  assertEquals(generation.safety?.category, "collapse");
  assertEquals(generation.estimatedCostUsd, 0);
});

Deno.test("pain of 7 or more on today's check-in answers a training question with the referral", async () => {
  const generation = await generateCoachChat(
    "Should I train legs today?",
    context({ permitted_evidence: ["APPROVED_PLAN_ACTIVE", "CHECK_IN_SAFETY_ESCALATION"] }),
    "daily_action",
    neverCalled,
  );
  assertEquals(generation.safety?.source, "check_in");
  assertEquals(generation.answer.safety_state, "limited");
  assertStringIncludes(generation.answer.answer, "pain of 7 or more");
});

Deno.test("self-harm and unsupported requests are refused, not limited", () => {
  const selfHarm = deterministicSafetyGeneration({
    category: "self_harm",
    rule: "self_harm",
    source: "message",
  });
  assertEquals(selfHarm.answer.safety_state, "refused");
  const scope = deterministicSafetyGeneration({
    category: "scope",
    rule: "diagnosis_request",
    source: "message",
  });
  assertEquals(scope.answer.safety_state, "refused");
});

Deno.test("ordinary questions are not screened: they reach the provider", async () => {
  for (
    const question of [
      "How many sets should I do today?",
      "I take medication, can I train?",
      "how do I avoid dizziness when cutting?",
      "my legs are sore",
    ]
  ) {
    // No provider is configured in the test environment, so a question that is not answered by
    // the referral fails at the provider.
    const error = await assertRejects(
      () => generateCoachChat(question, context(), "general", neverCalled),
      CoachChatUnavailableError,
    );
    assert(error instanceof CoachChatUnavailableError, question);
    assertEquals(error.model, "provider_not_configured", question);
  }
});
