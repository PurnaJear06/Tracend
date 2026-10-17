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
  "ba2e78d197dd68f76496415222a38d3b65b3bdb44c2776905fa66c86047d978d",
  "43c2af7315b8b2706e75ea51539caa5a5b5d9c904d2fa26fdcf8b4b9a420969e",
  "53f9e08c56eee644b764d4b45e28b170d75b5507a684414fad8b7268ec1b64cc",
  "5d285ca31e6f3137c1d5bd8620e1ec923826b628908273fac4af6deb16b48168",
  "e488cdcfb1f1766d9bc5c59844858b316155a526a4a241c615b5d8290a44dc82",
  "14df52044cb43370bb2113899b60a50eae51fcb0366e1d85f83744f1a6181519",
  "be8c1ac62424ac5608ae7365e81b2f1152d67dea42ef95feca1dbf61fbb348dc",
  "b6298d10ee790b4594ea84c064e7089c3244a4b12c90299904e8f52a547d1f4f",
  "596341ecac103b065a9ed966245854092895bf9274f98920ff057ba754f5e199",
  "afa1ae5088f7995401479fa9bea4b565bf1b1d97f2df99274a52e6226a536171",
  "71df207de011767f52bf2b2511d4eacbc448533e44cadfe4544663a59c7a9439",
  "bda410ba6d2cc563b7edea7451250297959004d9bc36134a4c2b53bd0b81e5d6",
  "c7622614529a2abdd4c83b9cb481ae81935821763ca012e01ada5f564dc81808",
  "6f1052c5f4c7a61bf524fac9f83f87743918d65c8b16f4872df5e5c7466eee17",
  "80a950ec0729849653548a25a9104a824a21b3f7eab4758f2752ccb56b03e0c3",
  "62efe99658f0ad4c3e03a0285336a081dad887a34c7d3cddf7c751fa7418b6c8",
  "cf09c8c58d511cea219134771a8c5b34a6f6678a889504b35f28d100815e9048",
  "9b3c6bd38c1172325e1b1de415827875f3332742f25082d142787f810ad6bac1",
];
