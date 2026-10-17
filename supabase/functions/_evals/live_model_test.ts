import { assertEquals } from "jsr:@std/assert@1.0.14";
import { claudeMessage, fakeFetch, jsonResponse, routeFor } from "../_shared/ai/fakes.ts";
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
  answer: "Keep it easy today.",
  evidence: [],
  missing_data: [],
  safety_state: "allowed",
  suggested_follow_ups: [],
});

async function modelsUsed(
  questions: string[],
  strong: ReturnType<typeof routeFor> | null,
  defaults = routeFor("coach_chat", { MODEL: "claude-haiku-5-5" }),
): Promise<string[]> {
  const fake = fakeFetch(() =>
    jsonResponse(claudeMessage({ content: [{ type: "text", text: answerJson }] }))
  );
  const generate = gatewayGenerate(defaults, () => strong, { fetch: fake.fetch });
  for (const question of questions) {
    await generate({
      question,
      context: { coaching_date: "2026-10-14", permitted_evidence: [] },
      contextKind: "general",
      contributions: null,
    });
  }
  return fake.sent.map((sent) => String(sent.body.model));
}

Deno.test("the gateway path picks the route per question like coach-chat does", async () => {
  const strong = routeFor("coach_chat_strong", { MODEL: "claude-sonnet-5-5" });
  assertEquals(
    await modelsUsed(
      ["How is my progress on the cut?", "What should I eat for breakfast?"],
      strong,
    ),
    ["claude-sonnet-5-5", "claude-haiku-5-5"],
  );
  assertEquals(
    await modelsUsed(["How is my progress on the cut?"], null),
    ["claude-haiku-5-5"],
  );
});

Deno.test("a strong route at another vendor than the notice is skipped", async () => {
  const other = routeFor("coach_chat_strong", {
    PROVIDER: "openai_compatible",
    MODEL: "deepseek-flash",
    BASE_URL: "https://api.deepseek.com/v1",
    OPENAI_COMPATIBLE_API_KEY_COACH_CHAT_STRONG: "synthetic-test-key",
  });
  assertEquals(await modelsUsed(["How is my progress on the cut?"], other), ["claude-haiku-5-5"]);
});
