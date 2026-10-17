// Coach chat rollback parity (A6). With no AI_COACH_CHAT_* settings Coach chat must send exactly
// the request it sent before the gateway existed. Each case records the bytes the legacy DeepSeek
// path sends (an invalid first answer forces the repair request too) and compares their SHA-256
// with the digest recorded from the pre-A6 code (commit 477da79). A digest changes only when the
// legacy request changes, which A6 forbids; a later chunk that changes it on purpose records the
// new digests and says so in its pull request. B7 (goal phase review) did: it adds the goal-phase
// rules, the no-tools and brevity persona rules and the goal-details rendering, and (for the rich athlete, whose goal weight is set) the
// calculators' kilogram rows that stop at the goal weight, and records the digests again.

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
  "6276178fa7cebe814a1483872d9171df3039b751a9c5f9c1daeaffdf51f79e8e",
  "da2448771bdd747d3b69b2604cf18838e8b92b21867ebd67065ef6edd82d5a9d",
  "4f1880184d50b1a379894ba01f8d7085c2df1141f493478b671dab21ded79064",
  "38dfc1d7312893fa6fcf0f53dec3ebfbcd3a55028c137ca9f04129cab3abdb55",
  "55e6f43074c24a2751294f396fd7a2f25e8eeea6bb0e924f075c64e0282ff2c2",
  "d80dc5c24395d3e18e85adcd12779f5e27fc63dec85f256b67c9983da5360f68",
  "63839f30a02f16b672b7010646fec7f88cf86a87eaba9280bb00812c0c52e732",
  "770123bb7501f5a69b91187de857c7e5d39f4ba4fe0e4204a5221e36fdaf529d",
  "bfe88f4978d64eaa37d62da051248ff2e5d5ae0300a8ec6031157f4771f616fa",
  "53f6c8b2b00b3509502104ae2ba3bf5ceb8907e4496ec24a1af782d8e3b88a82",
  "f23da3a0b80dff08e5fe0c3037cc48c447b4fab64d3ee90bbdbeccdb28e0a6ad",
  "9856bd7feab46ca1a3f04657eee1564b803c02b59cbdbf76a7ce3a084abf91be",
  "3021003a993a9b6bfbf40bfd2ccf61b1667f96c3d79fa9399028ea56021bf99a",
  "b80f82691a03ed2cd245a22a4096795abba1c9c1f0959b3ae850725b5f6be434",
  "70d45cc3c6dbc00b9c3ed54f6932355ddff29417497e9152b2c396dbd1398773",
  "668f55d0b4453fe4f46b25be54c1319efbb13dd70af59697cb33a6c3bcb4202c",
  "ed1a35b24d79c66bfd5099876b7ebed96ac7d5d740c2641e9b123bf727f668e0",
  "23a9663615cc56d8a49f0fefaf392cc8e169a2e06e6532bff654bd1eeba5205a",
];
