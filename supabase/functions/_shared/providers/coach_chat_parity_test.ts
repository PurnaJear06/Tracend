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
  "128f07870fdbb073a6e6e8be79e0231942f0e187c1428010801aca2aae7bcf88",
  "3c02788aa56b2d9294275f1382ab14e3d77164c903abc6c06d61c69a0317cb17",
  "0e7abcfc55e968febb455eda2a42850bee0401225b4d47ce5455a0d438f5d42e",
  "bca11c1529a813ed0ee39d420b02a68e59a271b27164dc429e5a5e52c7ddcb71",
  "06fa8f33cd034a5b1c553f19f1f24d5df84d9241a449fccef5ddda1681f53fa8",
  "d4815330c633b7b502e7fbef3b5f62f0a13163fd505c0546a153dd1ff0519aba",
  "047cc2892f63f9977b48e008d2d681f9ba3c21c2e12e9c2f187f7af911701b37",
  "ddc8e5b74dcad8002425ae47fab760621c795c5e341d27a16a85d46a2d33030b",
  "ceb3574891a03f80265ae3794a8dacb5ac7023c1f837af15d3d8b11c7410503b",
  "96a46484862b45ad656227a25d752c4804c0c3f52e2998a2a619ff8c7cf66fb8",
  "a179fe2bc0e5a2ac67a318d592ea68e03006427d24cd5fa8e6b097c10c8de152",
  "0108848ed690f150ad721a298618a8e6c416809dee1d9c8068eb2a68b705df70",
  "29e4d00a0c5a6451c3dccc98f6efe1a9f50275dc628d3d5e17725809e574313a",
  "90a7f5e87e27740f3a8d4c4367915b322ddb127149f201fa3b2b252eea791ab3",
  "22bc370bf60ee9be5d9dc15ccf7c2939d25e3942b3dbc147abe78e223040b381",
  "771a5ae8cb4d79857f10ba642dc6330a70c71b14e24f569e000536538365fe65",
  "3df3e1b478c0c28c19e514510e6301aa1de0b0fa7220299bc1e681c3513d7f91",
  "757cddbc18cdbe77e52194bbb4415633afc40c176e27ba91e1701a908b4aefa3",
];
