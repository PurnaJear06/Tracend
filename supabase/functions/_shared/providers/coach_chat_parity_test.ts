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
  "4641178c83f4a986b9c2ba159de5d4609dcad81b5b2560e3ed4544b1fe4ca59a",
  "77a9c734e58d63727ec31852940c2bb90d8b7e52fa86d557b354588ae8ede49a",
  "9dd75fb1ebd16e8eac455be3214e35ac4e3be1a90cfe38d6cc6a56ea8c544f17",
  "f2b333f3474d60f45519933920caa3a3924efa3647f209aa5eca9981a89bc214",
  "2969fd56d73c3b9236520010895163de4b831f1bd0404f18f4ef6d1580cf28c9",
  "a22ca8c1a24b3b299b7465841841762a5660620f2dfe78504ee9b2082c88bc60",
  "5221449ada84a6b2ed6df9fe09d2a2a1b03374f1b8fc6926070dd74d3e03e540",
  "ea4b6942ba8b836f82a511d134ad9bf4f303f38226dc2163ed373aae162ed431",
  "dd45fd3705fba51d5a957bf5807a306e52026f1f7a004221ab703b4f151125a5",
  "8788d49f8abc82abaf90acc7d2d27894aa671e5e942a1e8be9ff89fcda50fd85",
  "25e1884a4c065f3ae6102052ae328c4410a7d0cc6c8eed2f15208916e3d1d9f6",
  "866804b9791281e5653f1284b46bd830687b1349a87353022592fb4d3de1a60d",
  "e79b32ed30b1c849e96424250b443b8b595b392e729f01ccabe8444d3d99a452",
  "c8da9334a3011a74a83e6fa02fc1f0b7c5dcaca26ab1d2d827c3e418b4785805",
  "235d63feb1fa39c1996cf37dd597c42afdc750bc36287f111f09221511fcd400",
  "781559d2e193a476ebcb3658b254607199fce229c13eda79241c5be760d5eccf",
  "e33b757ed4a38c670b9b22792a6860487b75d9bb7964a01ec5bd08c50d7a7266",
  "542f2fe7b34d241922e71afef5b4b5ba1a27890fdeb32d90ce93974f858537eb",
];
