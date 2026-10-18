import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { claudeMessage, fakeFetch, jsonResponse, routeFor } from "../_shared/ai/fakes.ts";
import { anthropicSchema } from "../_shared/ai/adapters/anthropic.ts";
import { coachChatGatewaySchema } from "../_shared/providers/coach_chat_provider_gateway.ts";
import type { WireError } from "./coach_sim/diagnostics.ts";
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

const goodAnswer = {
  data_requests: [],
  proposal_intent: [],
  fact_suggestions: [],
  answer: "ok",
  evidence: [],
  missing_data: [],
  safety_state: "allowed",
  suggested_follow_ups: [],
  reasoning_chain: [],
};

async function throughRouter(choice: Record<string, unknown>, onError: (e: WireError) => void) {
  const send = routerModelFetch(
    "claude-haiku-5.5",
    () =>
      Promise.resolve(
        new Response(
          JSON.stringify({ choices: [choice], usage: { prompt_tokens: 10, completion_tokens: 5 } }),
          { status: 200 },
        ),
      ),
    undefined,
    { onError, schema: coachChatGatewaySchema() },
  );
  const response = await send("https://router.example/v1/chat/completions", {
    method: "POST",
    body: JSON.stringify({ model: "x", messages: [], response_format: { type: "json_object" } }),
  });
  return (await response.json()).choices[0] as {
    finish_reason: string;
    message: { content: string };
  };
}

Deno.test("a JSON answer handed over as a tool call reaches the gateway as the content", async () => {
  const errors: WireError[] = [];
  const choice = await throughRouter({
    finish_reason: "tool_calls",
    message: {
      content: null,
      tool_calls: [{ function: { name: "json", arguments: JSON.stringify(goodAnswer) } }],
    },
  }, (e) => errors.push(e));
  assertEquals(choice.finish_reason, "stop");
  assertEquals(JSON.parse(choice.message.content), goodAnswer);
  // The cause stays on record: the finish reason and the shape of the message.
  assertEquals(errors.map((e) => e.kind), ["finish"]);
  assert(errors[0].body.includes("finish_reason=tool_calls; content empty"), errors[0].body);
});

Deno.test("a tool call with nothing to read is left as the gateway rejects it, and reported", async () => {
  const errors: WireError[] = [];
  const choice = await throughRouter(
    { finish_reason: "tool_calls", message: { content: "", tool_calls: [] } },
    (e) => errors.push(e),
  );
  assertEquals(choice.finish_reason, "tool_calls");
  assertEquals(errors.map((e) => e.kind), ["finish", "finish"]);
});

Deno.test("JSON wrapped in a fence is cleaned and reported; a reply off the schema names the path", async () => {
  const errors: WireError[] = [];
  const cleaned = await throughRouter({
    finish_reason: "stop",
    message: { content: "Here you go:\n```json\n" + JSON.stringify(goodAnswer) + "\n```" },
  }, (e) => errors.push(e));
  assertEquals(JSON.parse(cleaned.message.content), goodAnswer);
  assertEquals(errors.map((e) => e.kind), ["wrapped"]);

  errors.length = 0;
  const { evidence: _evidence, ...missing } = goodAnswer;
  const untouched = await throughRouter(
    { finish_reason: "stop", message: { content: JSON.stringify(missing) } },
    (e) => errors.push(e),
  );
  assertEquals(JSON.parse(untouched.message.content), missing, "the reply is not repaired");
  assertEquals(errors, [{ kind: "schema", status: 200, body: "$.evidence is missing" }]);

  errors.length = 0;
  const shape = await throughRouter({
    finish_reason: "stop",
    message: { content: JSON.stringify({ ...goodAnswer, proposal_intent: { kind: "x" } }) },
  }, (e) => errors.push(e));
  assertEquals(JSON.parse(shape.message.content).proposal_intent, { kind: "x" });
  assertEquals(errors.map((e) => e.body), ["$.proposal_intent does not match (object)"]);
});

Deno.test("structured mode sends the answer schema as production gives it to Claude", async () => {
  const sent: Record<string, unknown>[] = [];
  const send = routerModelFetch(
    "claude-sonnet-5.5",
    (_input, init) => {
      sent.push(JSON.parse(String(init?.body)));
      return Promise.resolve(
        new Response(
          JSON.stringify({
            choices: [{ finish_reason: "stop", message: { content: JSON.stringify(goodAnswer) } }],
          }),
          { status: 200 },
        ),
      );
    },
    undefined,
    {
      mode: { responseFormat: true, maxTokensField: "max_tokens", structured: true },
      schema: coachChatGatewaySchema(),
    },
  );
  await send("https://router.example/v1/chat/completions", {
    method: "POST",
    body: JSON.stringify({ model: "x", messages: [], response_format: { type: "json_object" } }),
  });
  const format = sent[0].response_format as {
    type: string;
    json_schema: { name: string; strict: boolean; schema: Record<string, unknown> };
  };
  assertEquals(format.type, "json_schema");
  assertEquals(format.json_schema.strict, true);
  assertEquals(format.json_schema.schema, anthropicSchema(coachChatGatewaySchema()));
  assertEquals(format.json_schema.schema.additionalProperties, false);
});
