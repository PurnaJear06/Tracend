// Coach chat rollback parity (A6). With no AI_COACH_CHAT_* settings Coach chat must send exactly
// the request it sent before the gateway existed. Each case records the bytes the legacy DeepSeek
// path sends (an invalid first answer forces the repair request too) and compares their SHA-256
// with the digest recorded from the pre-A6 code (commit 477da79). A digest changes only when the
// legacy request changes, which A6 forbids; a later chunk that changes it on purpose records the
// new digests and says so in its pull request. B7 (goal phase review) did: it adds the goal-phase
// rules, the no-tools and brevity persona rules and the goal-details rendering, and (for the rich athlete, whose goal weight is set) the
// calculators' kilogram rows that stop at the goal weight, and records the digests again. A9 (Coach
// guardrails) did too: it adds the red-flag, Safe Ranges, screening and numbers rules to the persona
// and answer contract and the Safe Ranges section to the athlete file, and records them again.

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
  "989e44ffc9594adfbc14a97d8f00f1ccb19f7ebc9930cd1c97919bf910887935",
  "970a7718eaa0f0e7e9a0ad77226c3c86294d6d7b094a098bf50fb0890815dfd0",
  "d4483ba11405fd613878217fd21721958c80eaa00a2261d6e417cd6e32f6368c",
  "b25b017ab2d95faf5a303a042642a6bd23644ae32e0495953e1c1edd7498ffe2",
  "fa9842b0d678d2a372ab3ddbf6dd846bf7e41b83a1c086c953e85b23b19d3564",
  "077438c340a5e8726f1b08f78df4aed72fc18ec69484c9ac1f85bdc0412c0c2a",
  "7e92a2a08d48c8ef280b443eae76a2c019d955c1b67c3348dc2a85f463f830b5",
  "644b2d24d7d4633aac8c57c9d7b7cf6791ca073bc0e85483f4e421d68c68aef2",
  "2190e5d09eddce84241c44ee0e36998a767dbdfe5bbc57915e5263ade56d338c",
  "320a71d3799276d3686302114444e68455f1b0e39ec66d34a42964b99cc21a42",
  "f94512697748444a454fd32d2e34c3fd1365a34e4b7bb3aa33d4a63dff8fa270",
  "04a7949a30b0bd4e3806d518cc480f7bf7d25ab4c2aef9c9f53adfd0b9658345",
  "70367fb97a75c55b992805d8e42eb534bea5cccdebc7f0f4e87aeff866912066",
  "580de77c8105a4f0be5153b013e7ae0b15a722267a9c45b3d6ab8c3e22e267de",
  "bf317d9ef486576f9338a383b42306433261f9765d9960d925987affb1e31db2",
  "2d75677e1b5c6a08ab4d6fa619043ebea5dc2daf88e7be37ba32e727210fd356",
  "5834f07fefb78c93b286d1c18aec11ae35cd3897e7bee1299ec39d7f1236d5b4",
  "c527c2a1e4afe3f89efa02fa86fb3bf38cca921ab7d774f0116989089efc2625",
];
