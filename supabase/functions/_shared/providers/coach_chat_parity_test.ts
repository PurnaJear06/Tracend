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
  "182b4a9d8726317ab2c65622e2e816ba3c2c9ee8f209c3be8e688d8e12ad8ee6",
  "65504a5e52ee76e6db69435c717d1b175fe36fb0b35ec438c540959bd62a9a8b",
  "937483169ea0e1ec094bba872f988a20b586bf9d52c4dd36f6e8480730d611a9",
  "973d4201f163f3bb2ad5580f96db0f6a892f3cfa5fbac5e9e8029da2f796c702",
  "c4c3fe1da70b4449624a8259fec7f1f169a0cfb6c7724351653540b5f126e31e",
  "1b0bb5366ed7f7857a46b438ff85a260334bfdf14285201b757200688a0dee1b",
  "e03e642c7d4255150c5f4b7ef7a4db63d8cc100c07b02aeda7d56d5011f2a2d6",
  "09b02acb6767248863e0540b059b781a2b07459e7589b1a0ce5d4987eb0ffb94",
  "220e1f9dc6986bc21f66e96baa72653c83fd9196f7fd780f290e55ce5869bde5",
  "d72078e7ebfb6ab39ff359a29f9881c9d3477fb2baa83b34729dc85adc418111",
  "66995fd7560d9f2bab17ddc59dfa17d3501fe2476925bc83cf26ca228b3505fd",
  "f312ce5548b45031a8152dfa82626a1554f6cfa8dc23f313a107f286de0efff4",
  "50ee7b6cec83cbc3fdb03f967642d7c0220a69503428ffe592ae49aeed4c0658",
  "448484d5510d112ad027e11c312f64e3df6b70a05bd95ea9a3de922d00f52e01",
  "99bbb7a72db805ed519f46e3bc571095b6a953ce576a2cdf0d6bf9aae2d29192",
  "26c104df8da9fca436e9fcf68abb1d065390d2af0f55c52045a7c352921744a6",
  "7db39f101c77e10730b8c29f79c04abcd89019636c1d60e2af907859ebfbf092",
  "68b3ce2eac3f4e565b9a25b912d287d1ffd1843556467aaa3e87f58819734931",
];
