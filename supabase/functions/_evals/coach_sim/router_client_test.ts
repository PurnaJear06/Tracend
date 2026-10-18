// The router chat client and model choice, with a fake fetch. No network.
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import {
  athletePreferences,
  jsonObjectIn,
  judgePreferences,
  pickModel,
  pickModels,
  routerChat,
} from "./router_client.ts";

const answer = (content: string, model = "m") =>
  new Response(
    JSON.stringify({
      model,
      choices: [{ message: { content } }],
      usage: { prompt_tokens: 2_000, completion_tokens: 500 },
    }),
    { status: 200 },
  );

Deno.test("a chat call sends the router's request and prices the answer at list price", async () => {
  const bodies: Record<string, unknown>[] = [];
  const chat = routerChat("https://router.example/v1/", "synthetic-test-key", {
    fetcher: (input, init) => {
      assertEquals(String(input), "https://router.example/v1/chat/completions");
      bodies.push(JSON.parse(String(init?.body)));
      return Promise.resolve(answer('{"message":"hi"}', "anthropic/claude-sonnet-5.5"));
    },
    retryDelayMs: 0,
  });
  const result = await chat({
    model: "anthropic/claude-sonnet-5.5",
    system: "s",
    user: "u",
    maxTokens: 100,
    json: true,
    source: "judge",
  });
  assert(result.ok);
  // Sonnet 5.5 list price: 2,000 x 2 + 500 x 10 per million.
  assertEquals(result.costUsd, 0.009);
  assertEquals(bodies[0].response_format, { type: "json_object" });
  assertEquals(bodies[0].temperature, undefined, "Claude takes default sampling only");
  await chat({
    model: "deepseek-v4-flash",
    system: "s",
    user: "u",
    maxTokens: 100,
    json: false,
    source: "athlete",
  });
  assertEquals(bodies[1].temperature, 0.3);
  assertEquals(bodies[1].response_format, undefined);
});

Deno.test("a failed call is retried once; a second failure is reported with both costs", async () => {
  let calls = 0;
  const flaky = routerChat("https://router.example/v1", "k", {
    fetcher: () => {
      calls++;
      return Promise.resolve(calls === 1 ? new Response("busy", { status: 503 }) : answer("ok"));
    },
    retryDelayMs: 0,
  });
  const recovered = await flaky({
    model: "m",
    system: "s",
    user: "u",
    maxTokens: 10,
    json: false,
    source: "athlete",
  });
  assert(recovered.ok);
  assertEquals(calls, 2);
  const down = routerChat("https://router.example/v1", "k", {
    fetcher: () => Promise.resolve(new Response("down", { status: 500 })),
    retryDelayMs: 0,
  });
  const failed = await down({
    model: "m",
    system: "s",
    user: "u",
    maxTokens: 10,
    json: false,
    source: "athlete",
  });
  assertEquals(failed, {
    ok: false,
    reason: "http 500",
    costUsd: 0,
    kind: "http",
    status: 500,
    body: "[content-type=text/plain;charset=UTF-8] down",
  });
});

Deno.test("JSON is found whole, fenced or inside prose", () => {
  assertEquals(jsonObjectIn('{"a":1}'), { a: 1 });
  assertEquals(jsonObjectIn('Sure!\n```json\n{"a":2}\n```'), { a: 2 });
  assertEquals(jsonObjectIn('The verdict is {"a":3} as asked.'), { a: 3 });
  assertEquals(jsonObjectIn("[1,2]"), null);
  assertEquals(jsonObjectIn("no json"), null);
});

Deno.test("models are picked by preference from what the router lists, never an excluded one", () => {
  const listed = ["gpt-5-nano", "gpt-5", "anthropic/claude-haiku-5.5", "deepseek-v4-flash"];
  assertEquals(pickModel(listed, judgePreferences, ["claude-haiku-5-5"]), "gpt-5");
  assertEquals(
    pickModel([...listed, "anthropic/claude-sonnet-5.5"], judgePreferences, ["claude-haiku-5-5"]),
    "anthropic/claude-sonnet-5.5",
  );
  assertEquals(
    pickModel(listed, athletePreferences, ["deepseek-v4-flash"]),
    "anthropic/claude-haiku-5.5",
  );
  assertEquals(
    pickModel(["anthropic/claude-haiku-5.5"], judgePreferences, ["claude-haiku-5-5"]),
    null,
  );
  // When the router cannot list its models, the first preference that is not excluded.
  assertEquals(pickModel([], judgePreferences, ["claude-sonnet-5-5"]), "claude-opus-5-5");
});

const withChoice = (choice: Record<string, unknown>) =>
  new Response(
    JSON.stringify({
      model: "m",
      choices: [choice],
      usage: { prompt_tokens: 100, completion_tokens: 700 },
    }),
    { status: 200 },
  );

Deno.test("an answer that ran into max_tokens is a truncation, not an empty or half verdict", async () => {
  for (const content of ["", '{"scores": {"spec']) {
    let calls = 0;
    const chat = routerChat("https://router.example/v1", "k", {
      fetcher: () => {
        calls++;
        return Promise.resolve(
          withChoice({ message: { content }, finish_reason: "length" }),
        );
      },
      retryDelayMs: 0,
    });
    const result = await chat({
      model: "claude-opus-5.5",
      system: "s",
      user: "u",
      maxTokens: 700,
      json: true,
      source: "judge",
    });
    assert(!result.ok);
    assertEquals(result.kind, "truncated");
    assertEquals(calls, 1, "a truncated call is not asked again at the same limit");
    assert(result.costUsd > 0, "the billed tokens are counted");
    assert(result.body.includes("completion_tokens=700 max_tokens=700"), result.body);
  }
});

Deno.test("a JSON answer handed over as a tool call is read from its arguments", async () => {
  const chat = routerChat("https://router.example/v1", "k", {
    fetcher: () =>
      Promise.resolve(
        withChoice({
          message: {
            content: null,
            tool_calls: [{ function: { name: "json", arguments: '{"message":"hi"}' } }],
          },
          finish_reason: "tool_calls",
        }),
      ),
    retryDelayMs: 0,
  });
  const result = await chat({
    model: "m",
    system: "s",
    user: "u",
    maxTokens: 100,
    json: true,
    source: "athlete",
  });
  assert(result.ok);
  assertEquals(result.text, '{"message":"hi"}');
});

Deno.test("pickModels lists every listed preference in order, without the excluded model", () => {
  const listed = ["claude-opus-5.5", "claude-sonnet-5.5", "deepseek-v4-flash", "gemini-3.5-flash"];
  assertEquals(pickModels(listed, judgePreferences, ["claude-sonnet-5-5"]), [
    "claude-opus-5.5",
    "gemini-3.5-flash",
    "deepseek-v4-flash",
  ]);
  assertEquals(pickModels(listed, judgePreferences, ["claude-opus-5-5"])[0], "claude-sonnet-5.5");
  assertEquals(pickModels([], ["a", "b"], ["a"]), ["b"]);
});
