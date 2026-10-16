// Coach chat rollback parity (A6). With no AI_COACH_CHAT_* settings Coach chat must send exactly
// the request it sent before the gateway existed. Each case records the bytes the legacy DeepSeek
// path sends (an invalid first answer forces the repair request too) and compares their SHA-256
// with the digest recorded from the pre-A6 code (commit 477da79). A digest changes only when the
// legacy request changes, which A6 forbids; a later chunk that changes it on purpose records the
// new digests and says so in its pull request.

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
  "aa5b43c56d3ec98afce39c3f2115a71fefcd397ea39f75833372041ca9cc0a36",
  "ee40b91bfb8349149ebf48bd93c7a620fb9f7991db9786c15bcd7c4bf5533169",
  "827d8bbdef854d069167cbcc8d047dcc02174ee98402f3131957390e9b162d4f",
  "431c317b5912c8eaaa7aed7705e3bf8b7299094da744b8aec73944ef2cdd22e8",
  "14a6bc16d86f28595b33abd30edc95d822468a9ae67cbb9e8c28df0e9878327e",
  "153fec699d1782680ae350d8c5e0e70d173afca720ecf7a71a6975063137db7e",
  "517886c5af6d9f378b7defab0e99b81a7a1d7f2d39c4695ab7949c9518b4c51a",
  "c18691d618506a5b3fb16ebec50609473868f8e0508b374aec1bf907a8dc8430",
  "a2fd78ed640edb5e46b1f02fce3df903ad177e9c7229aa03f39784a2427c3f83",
  "909816d03b6eb6f55105d2f73f7f8bfa4c1179b089460228af4abe0a0afcc44e",
  "2a5e4134a7bda5d03538447b3944acc04d646dba44e63fc76dcf53bef3c689eb",
  "1725be6c7aec997f4b82cba6a7911d93f9149d208f677403f149efc46e346bd0",
  "0d9494d8aad621e12b7506320ff3a2bdd8edfbb6b30172be7cf5d3936b505075",
  "e3fe397d9efe92758abfef28e820e2ee2e5e1b082c7187a1db11f9051a3eb567",
  "1f4847d41eecc2d866f46b57fc259e178b2317dc4625038132b3682bc4072217",
  "d93fe078008f43b1cde48b3c60aaa4714463b1fed8462c9a998d7782bdd910e1",
  "3ad02747a5c904795ccfaf1b41767cb1465b18fefef92f7a9eace4a9b736b8f1",
  "fd655a49c60690a98a5440d4f72747367c81dcbb371800ac8a79588d2c1866b0",
];
