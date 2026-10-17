import { assert, assertEquals, assertStringIncludes, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  CoachChatAnswerValidationError,
  parseCoachChatAnswer,
} from "../contracts/coach_chat_v1.ts";
import {
  buildCoachChatUserMessage,
  coachChatInstructions,
  formatGoalDetails,
  generateCoachChat,
  repairContractText,
} from "./coach_chat_provider.ts";
import { weightClaimCheckFor } from "../training/goal_phase/guard.ts";
import { longCutContext } from "../training/goal_phase/fixtures.ts";

const answer = (text: string) => ({
  answer: text,
  evidence: [],
  missing_data: [],
  safety_state: "allowed",
  suggested_follow_ups: [],
});

Deno.test("an answer that projects a weight without a target fails with its own rule", () => {
  const check = weightClaimCheckFor(longCutContext, "What now?");
  const error = assertThrows(
    () => parseCoachChatAnswer(answer("You would be at 66.5 kg in 12 weeks."), [], check),
    CoachChatAnswerValidationError,
  );
  assertEquals(error.rule, "projection_without_target");
  assertEquals(error.path, "answer");
  parseCoachChatAnswer(answer("You are at 74.8 kg, BMI 23. What is your target?"), [], check);
  parseCoachChatAnswer(answer("You would be at 66.5 kg in 12 weeks."), []);
});

Deno.test("the repair names what to remove for each weight rule", () => {
  const floor = repairContractText({ rule: "weight_below_healthy_floor", path: "answer" }, []);
  assertStringIncludes(floor, "healthy range");
  const none = repairContractText({ rule: "projection_without_target", path: "answer" }, []);
  assertStringIncludes(none, "ask the athlete for a target");
  assert(!repairContractText({ rule: "answer_too_long", path: "answer" }, []).includes("target"));
});

Deno.test("goal details keep the target and notes, and drop measurements", () => {
  const text = formatGoalDetails({
    description: "Aggressive fat loss",
    current_weight_kg: 86.2,
    start_weight: "86 kg",
    waist_cm: 90,
    target_weight_kg: 72,
    target_physique: "visible_abs",
    target_set_at: "2026-10-17T05:00:00Z",
    nested: { weight: 1 },
    unlisted_key: "an unreviewed note",
  });
  assertStringIncludes(
    text,
    "Target set by the athlete on 2026-10-17: weight 72 kg, physique visible abs",
  );
  assertStringIncludes(text, "Entered when the goal was written, not updated since");
  assertStringIncludes(text, "description: Aggressive fat loss");
  assert(!text.includes("86"), text);
  assert(!text.includes("waist"), text);
  assert(!text.includes("unreviewed"), "only whitelisted note keys are rendered");
  assertEquals(formatGoalDetails(null), "");
  assertEquals(formatGoalDetails({ current_weight_kg: 86.2 }), "");
});

Deno.test("today's path carries contributor blocks between the athlete file and the question", () => {
  const message = buildCoachChatUserMessage("Hello?", longCutContext, "general", {
    stable: "",
    volatile: '<reference_data source="goal_phase">\nX\n</reference_data>',
    outcomes: [],
  });
  assert(message.indexOf("</coaching_context>") < message.indexOf("goal_phase"));
  assert(message.indexOf("goal_phase") < message.indexOf("User's message:"));
  assert(message.endsWith("Hello?"));
});

Deno.test("the goal phase rules are in every prompt", () => {
  const rules = coachChatInstructions([]);
  assertStringIncludes(rules, "A weight trend is history, not a goal");
  assertStringIncludes(rules, "current_weight_kg");
  assertStringIncludes(rules, "consider_maintenance_or_diet_break");
});

const goalPhaseBlock = {
  stable: "",
  volatile: '<reference_data source="goal_phase">\nGOAL-PHASE-MARKER\n</reference_data>',
  outcomes: [],
};

const okBody = (shape: "groq" | "gemini") => {
  const content = JSON.stringify(answer("You are at 74.8 kg. What is your target?"));
  return JSON.stringify(
    shape === "groq"
      ? {
        choices: [{ message: { content } }],
        usage: { prompt_tokens: 500, completion_tokens: 50 },
      }
      : {
        candidates: [{ content: { parts: [{ text: content }] } }],
        usageMetadata: { promptTokenCount: 500, candidatesTokenCount: 50 },
      },
  );
};

async function sentBody(env: Record<string, string>, shape: "groq" | "gemini"): Promise<string> {
  for (const [key, value] of Object.entries(env)) Deno.env.set(key, value);
  try {
    let body = "";
    const fetcher = (_url: unknown, init?: RequestInit) => {
      body = String(init?.body ?? "");
      return Promise.resolve(new Response(okBody(shape), { status: 200 }));
    };
    await generateCoachChat(
      "Hello",
      longCutContext,
      "general",
      fetcher as unknown as typeof fetch,
      undefined,
      goalPhaseBlock,
    );
    return body;
  } finally {
    for (const key of Object.keys(env)) Deno.env.delete(key);
  }
}

Deno.test("the Groq request carries the goal-phase block and its rules", async () => {
  const body = await sentBody({
    COACH_AI_ENABLED: "true",
    COACH_MODEL_PROVIDER: "groq",
    GROQ_API_KEY: "synthetic-key",
    GROQ_MODEL: "qwen/qwen3.6-27b",
  }, "groq");
  assertStringIncludes(body, "GOAL-PHASE-MARKER");
  assertStringIncludes(body, "A weight trend is history, not a goal");
});

Deno.test("the Gemini request carries the goal-phase block and its rules", async () => {
  const body = await sentBody({
    COACH_AI_ENABLED: "true",
    COACH_MODEL_PROVIDER: "gemini",
    GEMINI_PAID_DATA_TERMS_ACCEPTED: "true",
    GEMINI_API_KEY: "synthetic-key",
    GEMINI_MODEL: "gemini-3.5-flash",
  }, "gemini");
  assertStringIncludes(body, "GOAL-PHASE-MARKER");
  assertStringIncludes(body, "A weight trend is history, not a goal");
});
