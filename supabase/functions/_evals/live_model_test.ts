import { assertEquals } from "jsr:@std/assert@1.0.14";
import { claudeMessage, fakeFetch, jsonResponse, routeFor } from "../_shared/ai/fakes.ts";
import { type CoachContributions, noCoachContributions } from "../_shared/coach_context/host.ts";
import { gatewayGenerate, routedFetch } from "./live_model.ts";

Deno.test("a router run changes only the URL and says thinking is off", async () => {
  let sent: { url: string; init?: RequestInit } | undefined;
  const fetcher = routedFetch("https://router.example/v1/", (input, init) => {
    sent = { url: String(input), init };
    return Promise.resolve(new Response("{}"));
  });
  await fetcher("https://api.deepseek.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: "Bearer synthetic-key" },
    body: JSON.stringify({ model: "deepseek-v4-flash", thinking: { type: "disabled" } }),
  });
  assertEquals(sent?.url, "https://router.example/v1/chat/completions");
  assertEquals(
    (sent?.init?.headers as Record<string, string>).Authorization,
    "Bearer synthetic-key",
  );
  assertEquals(JSON.parse(String(sent?.init?.body)), {
    model: "deepseek-v4-flash",
    thinking: { type: "disabled" },
    reasoning_effort: "none",
  });
});

const answerJson = JSON.stringify({
  data_requests: [],
  proposal_intent: [],
  fact_suggestions: [],
  answer: "Keep it easy today.",
  evidence: [],
  missing_data: [],
  safety_state: "allowed",
  suggested_follow_ups: [],
  reasoning_chain: [],
});

/** A turn whose contributors reported pain on record, which asks for the stronger route. */
const withPain: CoachContributions = {
  ...noCoachContributions,
  traces: { watch_outs: { lines: 1, decisions: 1, pain: true } },
};

async function modelsUsed(
  turns: (CoachContributions | null)[],
  strong: ReturnType<typeof routeFor> | null,
  defaults = routeFor("coach_chat", { MODEL: "claude-haiku-5-5" }),
): Promise<string[]> {
  const fake = fakeFetch(() =>
    jsonResponse(claudeMessage({ content: [{ type: "text", text: answerJson }] }))
  );
  const generate = gatewayGenerate(defaults, () => strong, { fetch: fake.fetch });
  for (const contributions of turns) {
    await generate({
      question: "How is my progress on the cut?",
      context: { coaching_date: "2026-10-14", permitted_evidence: [] },
      contextKind: "general",
      contributions,
    });
  }
  return fake.sent.map((sent) => String(sent.body.model));
}

Deno.test("the gateway path picks the route per turn from the athlete's records, like coach-chat does", async () => {
  const strong = routeFor("coach_chat_strong", { MODEL: "claude-sonnet-5-5" });
  assertEquals(
    await modelsUsed([withPain, null], strong),
    ["claude-sonnet-5-5", "claude-haiku-5-5"],
  );
  assertEquals(await modelsUsed([withPain], null), ["claude-haiku-5-5"]);
});

Deno.test("a strong route at another vendor than the notice is skipped", async () => {
  const other = routeFor("coach_chat_strong", {
    PROVIDER: "openai_compatible",
    MODEL: "deepseek-flash",
    BASE_URL: "https://api.deepseek.com/v1",
    OPENAI_COMPATIBLE_API_KEY_COACH_CHAT_STRONG: "synthetic-test-key",
  });
  assertEquals(await modelsUsed([withPain], other), ["claude-haiku-5-5"]);
});
