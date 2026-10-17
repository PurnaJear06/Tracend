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
  "b2ca992837854827b82037a233679d00281b29a1bf359e6656cfd0615c738911",
  "b0e0f2c6807918b9f3b345f1fee4653dbe7f60bc52996f0f00a58efb5bf3a158",
  "d4965af55f5811e27e1cf5bb8d5a35d821ce0e092061c73a03374d05b49c17ac",
  "adcc88ded82b5c891c382034df13baa6c38ffb9ad9933206c891397750988e7b",
  "57fbb2b5168f349cd4da7ba8a8500e49111f2f31f86b27aad88d69b751dd5399",
  "3bb6a7bee1e1a4f98fdc96e1f250ba13d5cd5900b0e77cfcd29ab8d53e6f48b8",
  "b478dfe4d5c990f46ac2f209b33d8343120dfc8df8d9fcfe405390c066886e73",
  "0ea7f9c62a8499c5cb9504942236be48621644a43127db6e023b01ed9a28e801",
  "b9c7d80270cc629f9b2608584f0219345cb3033bc9d922e5d1f80529919cb5dd",
  "dbb786d6ffcb4e6f94df23cd61f259f696c33597688a32d840cd09bf8199d2b3",
  "718cb4d3091ba66a714f64ed89d47f8624a7561a1b22a77b41f519033afcebcd",
  "5983ef761a314256e50083af0247bee292b0db61882644fa80fb5b394e0a3399",
  "d5786b0a3e4574d91d6de289184d280429b3ac88e2ad2b71e399cc512a2aa506",
  "fea382dc6e4e2aff9eda76fe603182de7ee42cfd7679596d80be710efb93408c",
  "c821ce84bca13306f2fb220a551956eb8dc7d4969cf51ed50d935cea9dbb674c",
  "8916fefb7bf74c9ce8b696b93ff898e023998021de4f301c2c5bd83e358efc46",
  "020bf80906cb6da9e9161b6eef66ef340f0cfeaf080d7f5428e7356056557f12",
  "11b5b28423bf73d4bef3e9d10c5130742ec35fe46154531597d4489387bd27b5",
];
