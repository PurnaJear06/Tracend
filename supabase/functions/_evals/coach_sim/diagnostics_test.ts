// Error capture and redaction: what a failed call records, with no key or token in it. No network.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { bodyExcerptChars, excerpt, redact, summariseErrors } from "./diagnostics.ts";
import { routerChat } from "./router_client.ts";
import { routerModelFetch } from "../live_model.ts";
import { nextAthleteMessage } from "./athlete.ts";
import { personaById } from "./personas.ts";
import { scenarios } from "./scenarios.ts";

// Built at run time so the repository holds no key-shaped literal.
const key = `sk-nry-${"a1B2c3D4".repeat(4)}`;
const bearer = ["abc", "def-ghi_123"].join(".");
const opaque = "9f8e7d6c".repeat(6);
const hex = "0123456789abcdef".repeat(2);
const jwt = ["eyJhbGciOiJIUzI1NiJ9", "eyJzdWIiOiIxMjM0NTY3ODkwIn0", "abcDEF123xyz"].join(".");
const google = ["AIza", "SyA1234567890abcdefghijklmnopqrstuv"].join("");
const github = ["gh", "p_", "abcdefghijklmnopqrstuvwxyz0123456789"].join("");

Deno.test("keys and tokens are redacted, whatever shape they come in", () => {
  const samples = [
    `Incorrect API key provided: ${key}.`,
    `{"error":{"message":"bad","api_key":"hunter2hunter2"}}`,
    `Authorization: Bearer ${bearer}`,
    `token=${hex}`,
    `key ${google}`,
    `gh token ${github}`,
    `jwt ${jwt}`,
    `opaque ${opaque}`,
  ];
  const secrets = ["hunter2hunter2", key, bearer, hex, google, github, jwt, opaque];
  for (const sample of samples) {
    const out = redact(sample);
    assertStringIncludes(out, "[redacted]");
    for (const secret of secrets) assert(!out.includes(secret), `${secret} leaked in ${out}`);
  }
  // Ordinary words, model ids and request ids stay.
  assertEquals(
    redact("model claude-haiku-5.5 not found (req_01HZXAMPLE)"),
    "model claude-haiku-5.5 not found (req_01HZXAMPLE)",
  );
  // The exact key the run holds goes even when it matches no pattern.
  assertEquals(redact("echo: plainsecret", ["plainsecret"]), "echo: [redacted]");
});

Deno.test("an excerpt is redacted before it is cut, so a key split by the limit cannot leak", () => {
  const body = `${"x ".repeat(140)}${key} tail`;
  const out = excerpt(body);
  assert(out.length <= bodyExcerptChars);
  assert(!out.includes("sk-nry"));
  assertEquals(excerpt("a\n\n  b"), "a b");
});

Deno.test("distinct errors are grouped with their counts", () => {
  const base = { source: "coach", model: "m", status: 400, kind: "http", body: "bad" } as const;
  const summary = summariseErrors([
    base,
    { ...base, turn: 2 },
    { ...base, status: 403, body: "no" },
    { ...base, source: "judge" },
  ]);
  assertEquals(summary.map((g) => [g.source, g.status, g.count]), [
    ["coach", 400, 2],
    ["coach", 403, 1],
    ["judge", 400, 1],
  ]);
});

Deno.test("a failed chat call records the status and the redacted start of the body, never the key", async () => {
  const seen: { headers?: HeadersInit; body?: string }[] = [];
  const chat = routerChat("https://router.example/v1", key, {
    fetcher: (_input, init) => {
      seen.push({ headers: init?.headers, body: String(init?.body) });
      return Promise.resolve(
        new Response(
          JSON.stringify({
            error: { type: "validation_error", message: `invalid key ${key}`.padEnd(900, "!") },
          }),
          { status: 400 },
        ),
      );
    },
    retryDelayMs: 0,
  });
  const result = await chat({
    model: "claude-sonnet-5.5",
    system: "s",
    user: "u",
    maxTokens: 10,
    json: true,
    source: "judge",
  });
  assert(!result.ok);
  assertEquals(result.status, 400);
  assertEquals(result.kind, "http");
  assert(result.body.length <= bodyExcerptChars);
  assertStringIncludes(result.body, "validation_error");
  assert(!JSON.stringify(result).includes("sk-nry"));
  // A client error is not asked again.
  assertEquals(seen.length, 1);
});

Deno.test("a network failure and an empty answer are recorded too", async () => {
  const down = routerChat("https://router.example/v1", "k", {
    fetcher: () => Promise.reject(new TypeError("connection reset")),
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
  assert(!failed.ok);
  assertEquals([failed.status, failed.kind], [null, "network"]);
  assertStringIncludes(failed.body, "connection reset");

  const empty = routerChat("https://router.example/v1", "k", {
    fetcher: () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            choices: [{ message: { content: "" }, finish_reason: "stop" }],
            usage: { completion_tokens: 300 },
          }),
          { status: 200 },
        ),
      ),
    retryDelayMs: 0,
  });
  const blank = await empty({
    model: "deepseek-v4-flash",
    system: "s",
    user: "u",
    maxTokens: 300,
    json: true,
    source: "athlete",
  });
  assert(!blank.ok);
  assertEquals(blank.kind, "empty");
  assertStringIncludes(blank.body, "finish_reason=stop");
  assertStringIncludes(blank.body, "completion_tokens=300");
});

Deno.test("the Coach's wire errors reach the observer with the status and a redacted body", async () => {
  const errors: unknown[] = [];
  const send = routerModelFetch(
    "claude-haiku-5.5",
    () =>
      Promise.resolve(
        new Response(`{"error":{"type":"validation_error","message":"nope ${key}"}}`, {
          status: 400,
        }),
      ),
    undefined,
    { onError: (e) => errors.push(e), secrets: [key] },
  );
  const response = await send("https://router.example/v1/chat/completions", {
    method: "POST",
    body: JSON.stringify({ model: "deepseek-v4-flash", max_tokens: 10, messages: [] }),
  });
  // The gateway still gets the answer to read.
  assertEquals(response.status, 400);
  assertEquals(errors.length, 1);
  const [error] = errors as { status: number; kind: string; body: string }[];
  assertEquals([error.status, error.kind], [400, "http"]);
  assertStringIncludes(error.body, "validation_error");
  assert(!error.body.includes("sk-nry"));

  const thrown: unknown[] = [];
  const sendDown = routerModelFetch(
    "claude-haiku-5.5",
    () => Promise.reject(new DOMException("timed out", "TimeoutError")),
    undefined,
    { onError: (e) => thrown.push(e) },
  );
  let rejected = false;
  try {
    await sendDown("https://router.example/v1/chat/completions", { method: "POST" });
  } catch {
    rejected = true;
  }
  assert(rejected);
  assertEquals((thrown[0] as { kind: string }).kind, "timeout");
});

Deno.test("an empty athlete answer is asked for once more with a bigger budget, then the conversation ends with the reason", async () => {
  const persona = personaById("primary");
  const scenario = scenarios[0];
  const budgets: number[] = [];
  const blank = {
    ok: false,
    reason: "empty answer",
    costUsd: 0.001,
    kind: "empty",
    status: 200,
    body: "empty content; finish_reason=length completion_tokens=400 max_tokens=400",
  } as const;
  const twice = await nextAthleteMessage(
    (request) => {
      budgets.push(request.maxTokens);
      return Promise.resolve(blank);
    },
    "deepseek-v4-flash",
    persona,
    scenario,
    [],
    2,
    6,
  );
  assertEquals(budgets.length, 2);
  assert(budgets[1] > budgets[0]);
  assertEquals(twice.message, null);
  assertStringIncludes(twice.failure!, "empty answer");
  assertStringIncludes(twice.failure!, "asked twice");
  assertEquals(twice.error?.kind, "empty");
  assertEquals(twice.costUsd, 0.002);

  // The second ask can succeed.
  let calls = 0;
  const recovered = await nextAthleteMessage(
    (request) => {
      calls++;
      return Promise.resolve(
        calls === 1 ? blank : {
          ok: true,
          text: JSON.stringify({ message: "Fair enough, what then?", done: false }),
          model: request.model,
          tokens: { inputTokens: 1, outputTokens: 1, cacheReadTokens: 0, cacheWriteTokens: 0 },
          costUsd: 0.001,
          finishReason: "stop",
        },
      );
    },
    "deepseek-v4-flash",
    persona,
    scenario,
    [],
    2,
    6,
  );
  assertEquals(recovered.message?.message, "Fair enough, what then?");
  assertEquals(calls, 2);

  // Any other failure ends it at once.
  let tries = 0;
  const refused = await nextAthleteMessage(
    () => {
      tries++;
      return Promise.resolve({
        ...blank,
        kind: "http",
        status: 403,
        reason: "http 403",
        body: "no",
      });
    },
    "deepseek-v4-flash",
    persona,
    scenario,
    [],
    2,
    6,
  );
  assertEquals(tries, 1);
  assertStringIncludes(refused.failure!, "http 403");
});

Deno.test("an HTML error page from a CDN is reduced to its words, with who answered", async () => {
  const page = '<!DOCTYPE html>\n<!--[if lt IE 7]> <html class="no-js ie6"> <![endif]-->\n' +
    "<html><head><title>router.example | 502: Bad gateway</title><style>body{}</style></head>" +
    "<body><h1>Bad gateway</h1><p>Error code 502</p></body></html>";
  const out = excerpt(page);
  assertStringIncludes(out, "502: Bad gateway");
  assert(!out.includes("<"), out);
  const chat = routerChat("https://router.example/v1", "k", {
    fetcher: () =>
      Promise.resolve(
        new Response(page, {
          status: 502,
          headers: { server: "cloudflare", "cf-ray": "abc123-SIN", "set-cookie": "s=1" },
        }),
      ),
    retryDelayMs: 0,
  });
  const result = await chat({
    model: "claude-haiku-5.5",
    system: "s",
    user: "u",
    maxTokens: 10,
    json: true,
    source: "judge",
  });
  assert(!result.ok);
  assertEquals(result.status, 502);
  assertStringIncludes(result.body, "server=cloudflare cf-ray=abc123-SIN");
  assertStringIncludes(result.body, "502: Bad gateway");
  assert(!result.body.includes("set-cookie"), "only the named headers are recorded");
  assert(!result.body.includes("<"), result.body);
});

Deno.test("a router that is briefly down is asked again; the error is recorded once, when it stays down", async () => {
  const unavailable = () =>
    new Response(
      '{"error":{"type":"service_unavailable","message":"The model service is temporarily unavailable."}}',
      {
        status: 503,
      },
    );
  const request = { method: "POST", body: JSON.stringify({ model: "x", messages: [] }) };
  let calls = 0;
  const errors: { status: number | null }[] = [];
  const recovering = routerModelFetch(
    "claude-haiku-5.5",
    () =>
      Promise.resolve(
        ++calls < 3 ? unavailable() : new Response(
          JSON.stringify({ choices: [{ message: { content: "{}" }, finish_reason: "stop" }] }),
          { status: 200 },
        ),
      ),
    undefined,
    { retryDelaysMs: [0, 0], onError: (e) => errors.push(e) },
  );
  assertEquals(
    (await recovering("https://router.example/v1/chat/completions", request)).status,
    200,
  );
  assertEquals([calls, errors.length], [3, 0]);

  calls = 0;
  const down = routerModelFetch(
    "claude-haiku-5.5",
    () => Promise.resolve((calls++, unavailable())),
    undefined,
    { retryDelaysMs: [0, 0], onError: (e) => errors.push(e) },
  );
  assertEquals((await down("https://router.example/v1/chat/completions", request)).status, 503);
  assertEquals([calls, errors.length, errors[0].status], [3, 1, 503]);
});
