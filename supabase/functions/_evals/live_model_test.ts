import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { claudeMessage, fakeFetch, jsonResponse, routeFor } from "../_shared/ai/fakes.ts";
import {
  gatewayGenerate,
  knownPrice,
  matchModel,
  normalizedModelId,
  productionCoachModel,
  routedFetch,
  routerCarrierModel,
  routerGatewayFromEnv,
  routerModelFetch,
} from "./live_model.ts";

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

Deno.test("model ids compare across router spellings", () => {
  assertEquals(normalizedModelId("anthropic/claude-haiku-5.5"), "claude-haiku-5-5");
  assertEquals(normalizedModelId("deepseek/deepseek-v4-flash"), "deepseek-v4-flash");
  const listed = ["gpt-5", "anthropic/claude-haiku-5.5", "deepseek-v4-flash"];
  assertEquals(matchModel(listed, "claude-haiku-5-5"), "anthropic/claude-haiku-5.5");
  assertEquals(matchModel(listed, "deepseek-v4-flash"), "deepseek-v4-flash");
  assertEquals(matchModel(listed, "claude-sonnet-5-5"), null);
  assertEquals(knownPrice("anthropic/claude-haiku-5.5")?.input, 0.1);
  assertEquals(knownPrice("some-router-model"), null);
});

Deno.test("the router request names the played model with the fields that model takes", async () => {
  const sent: Record<string, unknown>[] = [];
  const usage: number[] = [];
  const fetcher = (_input: string | URL | Request, init?: RequestInit) => {
    sent.push(JSON.parse(String(init?.body)));
    return Promise.resolve(
      new Response(JSON.stringify({ usage: { prompt_tokens: 100, completion_tokens: 20 } }), {
        status: 200,
      }),
    );
  };
  const request = {
    method: "POST",
    body: JSON.stringify({
      model: "deepseek-v4-flash",
      thinking: { type: "disabled" },
      temperature: 0.1,
      messages: [],
    }),
  };
  await routerModelFetch("anthropic/claude-haiku-5.5", fetcher, (t) => usage.push(t.inputTokens))(
    "https://router.example/v1/chat/completions",
    request,
  );
  await routerModelFetch("deepseek-v4-flash", fetcher)(
    "https://router.example/v1/chat/completions",
    request,
  );
  await routerModelFetch("qwen/qwen3.8-27b", fetcher)(
    "https://router.example/v1/chat/completions",
    request,
  );
  assertEquals(sent[0], { model: "anthropic/claude-haiku-5.5", messages: [] });
  assertEquals(sent[1], {
    model: "deepseek-v4-flash",
    thinking: { type: "disabled" },
    temperature: 0.1,
    reasoning_effort: "none",
    messages: [],
  });
  assertEquals(sent[2], { model: "qwen/qwen3.8-27b", temperature: 0.1, messages: [] });
  assertEquals(usage, [100]);
});

const routerEnv = (values: Record<string, string>) => (name: string) =>
  ({ EVAL_BASE_URL: "https://router.example/v1", EVAL_API_KEY: "synthetic-test-key", ...values })[
    name
  ];

const listing = (ids: string[] | null) => () =>
  Promise.resolve(
    ids === null
      ? new Response("no", { status: 404 })
      : new Response(JSON.stringify({ data: ids.map((id) => ({ id })) }), { status: 200 }),
  );

Deno.test("the router gateway route says which model plays the Coach and why", async () => {
  const listed = await routerGatewayFromEnv(
    routerEnv({}),
    listing(["deepseek-v4-flash", "anthropic/claude-haiku-5.5"]),
  );
  assert(!("error" in listed));
  assertEquals(listed.coachModel, "anthropic/claude-haiku-5.5");
  assertEquals(listed.coachRoute.vendor, "router");
  assertEquals(listed.coachRoute.model, routerCarrierModel);
  assertEquals(listed.coachRoute.timeoutMs, 120_000);

  const missing = await routerGatewayFromEnv(routerEnv({}), listing(["deepseek-v4-flash"]));
  assert(!("error" in missing));
  assertEquals(missing.coachModel, routerCarrierModel);
  assertEquals(missing.production, false);
  assertEquals(
    missing.choice,
    `the router does not list the production model ${productionCoachModel}; using deepseek-v4-flash`,
  );

  const unlisted = await routerGatewayFromEnv(
    routerEnv({ EVAL_MODEL: "qwen/qwen3.8-27b" }),
    listing(null),
  );
  assert(!("error" in unlisted));
  assertEquals(unlisted.coachModel, "qwen/qwen3.8-27b");
  assertEquals(unlisted.available, []);

  const chosen = await routerGatewayFromEnv(
    routerEnv({ EVAL_COACH_MODEL: "claude-haiku-5-5" }),
    listing([]),
  );
  assert(!("error" in chosen));
  assertEquals(chosen.coachModel, "claude-haiku-5-5");
  assert(chosen.production);

  const noKey = await routerGatewayFromEnv(routerEnv({ EVAL_API_KEY: "" }), listing([]));
  assert("error" in noKey);
});
