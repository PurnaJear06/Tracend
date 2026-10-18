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
  "0935c4aa55e0cc421b3dd5f882e451e9cf810e250c8f06e3f53676b3ec0f9016",
  "5d7f8b93b7b3c3d67a0961539b1b622956255e58228dd893cbe59a3d193f0238",
  "e5c51e7b8f98d937f80677efaef61c00964c714e398c91bb994c65f94e3de4a5",
  "d06e98596e7dda96feeff6076d40e30800fa08dca2871b80c11cc7f5a9d485ae",
  "616a7be37593f05420470a325814e3f4313bf46fb63344699f4cd7a2c1b13e2f",
  "d1039ab9764b0d332fbe5a09c3be5c35bad8480463f03f3c2aad4443729971ad",
  "ba99c3e523b39047c01889dce999a7bed31c818c64b48e4efde9ed69553e04f9",
  "3a576951e6605ef81aa4c2a0640baa28d8da188a54cd7871db60688b4179861b",
  "1c9b0a276545e8cd855ac2d14c2989c86e12cbf4b9b3a9c5fa8e201de33a6821",
  "3aad918b6d351b98708d09094a7282c7682b0d6f19017cab3ac38b64f0da64c3",
  "4fccd1e8ec2263795a3ed044abe3a3fdd117508264827302dd41b65b1f7f48f6",
  "6e5e11c99e901288c6bd2086a5ca64d8b2585c8003ed6b3c94a2ac4de35fbb22",
  "d5b0a8f96a6eccf769c330300264eb764e5dd3aa82d89d7d03c63ba34e7287b2",
  "1f944595a2a52777a7fe0b769b74689be8a605eec005f21e7475a21a56cc9231",
  "be46bcd0e7aea63eaf4bce15316f79d1969b6d09e0de80057373fc631a78cad1",
  "797ef87fd806b17dabb497182a81fa48c931375001054489b892bfc24d6fbffa",
  "b3969425c728a0116f20c3e144bec5f34c6784486e9f2ea47eff761225596018",
  "ec38bccc930c8d57214e3b9ef155cb9f2f7c6bcbcf30443f045d522471bd387c",
];
