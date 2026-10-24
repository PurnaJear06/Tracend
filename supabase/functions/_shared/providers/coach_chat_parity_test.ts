// Coach chat rollback parity (A6). With no AI_COACH_CHAT_* settings Coach chat must send exactly
// the request it sent before the gateway existed. Each case records the bytes the legacy DeepSeek
// path sends (an invalid first answer forces the repair request too) and compares their SHA-256
// with the digest recorded from the pre-A6 code (commit 477da79). A digest changes only when the
// legacy request changes, which A6 forbids; a later chunk that changes it on purpose records the
// new digests and says so in its pull request. B7 (goal phase review) did: it adds the goal-phase
// rules, the no-tools and brevity persona rules and the goal-details rendering, and (for the rich athlete, whose goal weight is set) the
// calculators' kilogram rows that stop at the goal weight, and records the digests again. A9 (Coach
// guardrails) did too: it adds the red-flag, Safe Ranges, screening and numbers rules to the persona
// and answer contract and the Safe Ranges section to the athlete file, and records them again. The later A9 fixes did
// once more: a persona line for the coaching principles digest and the stricter screening rule.
// A10 (Coach sees the plan) did on purpose as well: the persona now says to answer first with
// named exercises, bring data in only when it changes the advice, never repeat a caution and build
// home routines from the plan's home options; and the athlete file no longer carries the sections
// the training_plan and nutrition_state contributors replace (today's check-in, the weekly
// review string, the meal schedule and today's meals, per-logged-day nutrition, the week
// structure). Today's DeepSeek request has no lookups: those are gateway-only.
// A8 (Coach proposals) did on purpose too: the persona's "You have no tools" line now reads "You
// cannot change anything yourself" (the proposal rules themselves are gateway-only), and the
// claimed-action repair hint says the same.
// The E3 production pass did on purpose: the digest is shown without its source ids, so the persona
// line for it no longer mentions them and says it names no citable source.

import { assertEquals } from "jsr:@std/assert@1.0.14";
import { route } from "../ai/routes.ts";
import { evalProfiles } from "../../_evals/fixtures.ts";
import { classifyQuestion, generateCoachChat } from "./coach_chat_provider.ts";

const legacyEnvironment: Record<string, string> = {
  COACH_AI_ENABLED: "true",
  COACH_MODEL_PROVIDER: "deepseek",
  DEEPSEEK_API_KEY: "synthetic-key",
  DEEPSEEK_MODEL: "deepseek-flash",
};

async function withLegacyEnvironment<T>(run: () => Promise<T>): Promise<T> {
  const previous = new Map(
    Object.keys(legacyEnvironment).map((name) => [name, Deno.env.get(name)]),
  );
  for (const [name, value] of Object.entries(legacyEnvironment)) Deno.env.set(name, value);
  try {
    return await run();
  } finally {
    for (const [name, value] of previous) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

const validAnswer = JSON.stringify({
  answer: "Keep today's session as planned.",
  evidence: [],
  missing_data: [],
  safety_state: "allowed",
  suggested_follow_ups: [],
});

/** The body digest of every request one legacy turn sends. */
async function legacyRequests(question: string, context: Record<string, unknown>) {
  const sent: string[] = [];
  const fetcher = (async (input: string | URL | Request, init?: RequestInit) => {
    const body = String(init?.body);
    assertEquals(String(input), "https://api.deepseek.com/v1/chat/completions");
    assertEquals(init?.method, "POST");
    assertEquals(init?.headers, {
      "Content-Type": "application/json",
      Authorization: "Bearer synthetic-key",
    });
    sent.push(await sha256(body));
    const content = sent.length === 1 ? "{not json" : validAnswer;
    return new Response(
      JSON.stringify({
        choices: [{ message: { content }, finish_reason: "stop" }],
        usage: { prompt_tokens: 1000, completion_tokens: 100 },
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  }) as typeof fetch;
  await withLegacyEnvironment(() =>
    generateCoachChat(question, structuredClone(context), classifyQuestion(question), fetcher)
  );
  return sent;
}

const questions = [
  "How did my training go this week?",
  "Can you build me a new training plan for the next block?",
];

const history = [
  { role: "user", content: "Should I train today?" },
  { role: "assistant", content: "Yes, keep the planned session. How did you sleep?" },
];

Deno.test("no route settings: Coach chat has no gateway route", () => {
  assertEquals(route("coach_chat", (name) => legacyEnvironment[name]), null);
});

Deno.test("no route settings: the DeepSeek request is byte-identical to the pre-A6 request", async () => {
  const recorded: string[] = [];
  for (const profile of evalProfiles()) {
    for (const question of questions) {
      recorded.push(...await legacyRequests(question, profile.context));
    }
    recorded.push(
      ...await legacyRequests(questions[0], { ...profile.context, recent_messages: history }),
    );
  }
  assertEquals(recorded, preA6Requests);
});

// Per athlete (rich, no_watch, new_user): weekly question, plan-change question, weekly question
// with history; each the first request and its repair.
const preA6Requests: readonly string[] = [
  "556654531efb642e909a85cbfcc1077aa6277b868ec158908e733a340b6db8f8",
  "3cd795e48534cf9c7c9744131f8e1efe6f442eac16593ab797bbfec1596c70c7",
  "86aab7b2919b599dae63b666bd97d9d323a9a58b61dcca6845aa60220cc1906c",
  "bd815947b2c311e15ca27794a5fc9849c9567a991c546fa0caa3f43cfee46c08",
  "38236a5923ff4c8f8758ab4f39f175905fad47833e65e0db6ee7e6830ed7accb",
  "a56b9638c3f3bde3be352aa417b916b21eea68662e2878e43d8b6f8c7fc7ef5c",
  "8f279b042a856d1e615f4041b54c996e26ff16b01f4f79cd610b38318e08a3d2",
  "48a674f369d589748fee9997c6f864a3d2c8f6c7f48894947d2b96097dc1c3fd",
  "20aafdc7cf947d9441e46230036b1ed6dd2f668442fdd43df73cd39438266b84",
  "afe78e7b7267c564036d0cee1df994d237928631c1db091a3948d3acbcf7bb78",
  "1071aac99899bea7e40c0b0958a32ba32776ef27f273f464e28f247d08813f19",
  "c3ff35e2a09373c717f0585617183e0c9edc44e45155c8a6350cc10c7d9a7583",
  "e7accad2b5b6771edf08557efee7741c87687102a4ad5526e327406b6906cd62",
  "3da61fdc49d1eb10e443cdc438a42fdd4235a221bac6c7497f2ba9ea7ddc6f29",
  "fead9fdb9440acf8669cedae9f55cbfd624fcbf72671da4a0ab468ac18e2c162",
  "d409266eafd7b64cb4c9aa9b02bdc871e73fc78145cf3292539dcc61d2e5d51e",
  "c0b89896947b8bd747aaa6038b22e5edac9b40e2e048551b81b3ebe3931666b9",
  "e13855d55fd3bb6b7f6dea4a54fee782a96623fe5caebad45b4d23f0196e9655",
];
