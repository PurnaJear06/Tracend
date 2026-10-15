import { assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import {
  captureLogs,
  claudeMessage,
  fakeFetch,
  jsonResponse,
  routeFor,
  type Sent,
  syntheticKey,
} from "./fakes.ts";
import { call } from "./gateway.ts";
import type { AiRequest, AiResult } from "./types.ts";

const secretPrompt = "PROMPT-MARKER athlete slept 4h";
const secretReply = "REPLY-MARKER train lighter";
const secretImage = "SU1BR0UtTUFSS0VS";

const decisionSchema = {
  type: "object",
  additionalProperties: false,
  properties: { action: { type: "string", enum: ["PROCEED", "ADJUST"] } },
  required: ["action"],
};

function request(extra: Partial<AiRequest> = {}, values: Record<string, string> = {}): AiRequest {
  return {
    route: routeFor("coach_chat", values),
    system: [{ type: "text", text: "Tracend rules.", cache: true }],
    messages: [{ role: "user", content: [{ type: "text", text: secretPrompt }] }],
    output: { kind: "text" },
    consentProvider: "anthropic",
    ...extra,
  };
}

const claude = (overrides: Record<string, unknown> = {}, usage: Record<string, unknown> = {}) =>
  fakeFetch(() => jsonResponse(claudeMessage(overrides, usage)));

const quiet = async (run: () => Promise<AiResult>) => (await captureLogs(run)).result;

Deno.test("a Claude call returns the text, stop, model and priced usage", async () => {
  const fake = claude(
    { content: [{ type: "text", text: secretReply }] },
    {
      input_tokens: 3000,
      output_tokens: 800,
      cache_read_input_tokens: 12_000,
      cache_creation_input_tokens: 1000,
    },
  );
  const result = await quiet(() => call(request(), { fetch: fake.fetch }));
  assertEquals(fake.sent.length, 1);
  assertEquals(fake.sent[0].headers["x-api-key"], syntheticKey);
  if (!result.ok) throw new Error(`expected ok, got ${result.reason}`);
  assertEquals(result.text, secretReply);
  assertEquals(result.stop, "end");
  assertEquals(result.model, "claude-sonnet-5-5");
  assertEquals(result.json, undefined);
  // Sonnet 5.5: 3,000 × 2 + 800 × 10 + 12,000 × 0.10 + 1,000 × 2.50 = 17,700 µUSD.
  assertEquals(result.usage.inputTokens, 3000);
  assertEquals(result.usage.cacheReadTokens, 12_000);
  assertEquals(result.usage.cacheWriteTokens, 1000);
  assertAlmostEquals(result.usage.costUsd, 0.0177, 1e-12);
});

Deno.test("a text answer cut off at the token limit is returned with stop max_tokens", async () => {
  const result = await quiet(() =>
    call(request(), { fetch: claude({ stop_reason: "max_tokens" }).fetch })
  );
  assertEquals(result.ok && result.stop, "max_tokens");
});

Deno.test("JSON output is parsed and checked against the schema", async () => {
  const output = { kind: "json" as const, schema: decisionSchema };
  const answer = (text: string) => claude({ content: [{ type: "text", text }] });

  const good = await quiet(() =>
    call(request({ output }), { fetch: answer('{"action":"ADJUST"}').fetch })
  );
  assertEquals(good.ok && good.json, { action: "ADJUST" });

  for (const text of ['{"action":"ADJ', '{"action":"SKIP"}', '{"action":"PROCEED","x":1}', ""]) {
    const result = await quiet(() => call(request({ output }), { fetch: answer(text).fetch }));
    assertEquals(result.ok, false, text);
    if (!result.ok) {
      assertEquals(result.reason, "invalid_output", text);
      // The answer was billed, so its usage comes back for the budget.
      assertEquals(result.usage?.outputTokens, 200, text);
    }
  }
});

Deno.test("a refusal is reported with its usage", async () => {
  const result = await quiet(() =>
    call(request(), {
      fetch: claude({
        stop_reason: "refusal",
        stop_details: { type: "refusal", category: "bio" },
        content: [],
      }).fetch,
    })
  );
  assertEquals(result.ok, false);
  if (!result.ok) {
    assertEquals(result.reason, "refused");
    assertEquals(result.usage?.inputTokens, 1000);
  }
});

Deno.test("429 is rate_limited with retry-after; 529 and 503 are overloaded; others provider_error", async () => {
  const status = async (code: number, headers: Record<string, string> = {}) =>
    await quiet(() =>
      call(request(), {
        fetch: fakeFetch(() => jsonResponse({ type: "error" }, code, headers)).fetch,
      })
    );
  assertEquals(await status(429, { "retry-after": "30" }), {
    ok: false,
    reason: "rate_limited",
    usage: null,
    retryAfterSeconds: 30,
  });
  const dated = await status(429, { "retry-after": new Date(Date.now() + 90_000).toUTCString() });
  if (dated.ok || dated.retryAfterSeconds === undefined) throw new Error("no retry-after");
  assertEquals(dated.retryAfterSeconds > 80 && dated.retryAfterSeconds <= 90, true);
  assertEquals(await status(429), { ok: false, reason: "rate_limited", usage: null });
  assertEquals(await status(529), { ok: false, reason: "overloaded", usage: null });
  assertEquals(await status(503, { "retry-after": "5" }), {
    ok: false,
    reason: "overloaded",
    usage: null,
    retryAfterSeconds: 5,
  });
  for (const code of [400, 401, 404, 500]) {
    assertEquals(await status(code), { ok: false, reason: "provider_error", usage: null });
  }
});

const hangingFetch = () =>
  fakeFetch((sent: Sent) =>
    new Promise<Response>((_, reject) => {
      sent.signal?.addEventListener("abort", () => {
        reject(new DOMException("The signal has been aborted", "AbortError"));
      });
    })
  );

Deno.test("the route timeout aborts the request", async () => {
  const fake = hangingFetch();
  const result = await quiet(() =>
    call(request({}, { TIMEOUT_MS: "1000" }), { fetch: fake.fetch })
  );
  assertEquals(result, { ok: false, reason: "timeout", usage: null });
  assertEquals(fake.sent[0].signal?.aborted, true);
});

Deno.test("the caller's AbortSignal aborts the request as a timeout", async () => {
  const fake = hangingFetch();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5);
  try {
    const result = await quiet(() =>
      call(request({ signal: controller.signal }), { fetch: fake.fetch })
    );
    assertEquals(result, { ok: false, reason: "timeout", usage: null });
  } finally {
    clearTimeout(timer);
  }

  const already = hangingFetch();
  const aborted = new AbortController();
  aborted.abort();
  const result = await quiet(() =>
    call(request({ signal: aborted.signal }), { fetch: already.fetch })
  );
  assertEquals(result, { ok: false, reason: "timeout", usage: null });
  assertEquals(already.sent.length, 0);
});

Deno.test("a network failure is network; an unreadable 200 is provider_error", async () => {
  const network = await quiet(() =>
    call(request(), {
      fetch: (() => Promise.reject(new TypeError("error sending request"))) as typeof fetch,
    })
  );
  assertEquals(network, { ok: false, reason: "network", usage: null });

  const unreadable = await quiet(() =>
    call(request(), { fetch: fakeFetch(() => new Response("<html>", { status: 200 })).fetch })
  );
  assertEquals(unreadable, { ok: false, reason: "provider_error", usage: null });
});

Deno.test("a consent for another provider, or none, sends nothing", async () => {
  for (const consentProvider of [null, "openai_compatible", "gemini"] as const) {
    const fake = claude();
    const result = await quiet(() => call(request({ consentProvider }), { fetch: fake.fetch }));
    assertEquals(result, { ok: false, reason: "consent_provider_mismatch", usage: null });
    assertEquals(fake.sent.length, 0, String(consentProvider));
  }
});

Deno.test("requests no provider can take are refused before sending", async () => {
  const deepseek = routeFor("coach_chat", {
    PROVIDER: "openai_compatible",
    MODEL: "deepseek-flash",
    BASE_URL: "https://api.deepseek.com/v1",
    OPENAI_COMPATIBLE_API_KEY_COACH_CHAT: syntheticKey,
  });
  const image = { type: "image" as const, mediaType: "image/jpeg" as const, base64: secretImage };
  const refused: Partial<AiRequest>[] = [
    // A route that did not come from route() has no key.
    { route: { ...routeFor("coach_chat") } },
    // Claude 5 models reject an assistant prefill.
    {
      messages: [
        { role: "user", content: [{ type: "text", text: "Hi" }] },
        { role: "assistant", content: [{ type: "text", text: "{" }] },
      ],
    },
    { messages: [] },
    { messages: [{ role: "user", content: [] }] },
    { system: [image] },
    { messages: [{ role: "assistant", content: [image] }, { role: "user", content: [image] }] },
    {
      route: deepseek,
      consentProvider: "openai_compatible",
      messages: [{ role: "user", content: [image] }],
    },
    { output: { kind: "json", schema: { $ref: "#/x" } } },
  ];
  for (const extra of refused) {
    const fake = claude();
    const result = await quiet(() => call(request(extra), { fetch: fake.fetch }));
    assertEquals(result, { ok: false, reason: "provider_error", usage: null });
    assertEquals(fake.sent.length, 0, JSON.stringify(Object.keys(extra)));
  }
});

Deno.test("an empty text answer is a provider_error that keeps its usage", async () => {
  const result = await quiet(() => call(request(), { fetch: claude({ content: [] }).fetch }));
  assertEquals(!result.ok && result.reason, "provider_error");
  assertEquals(!result.ok && result.usage?.outputTokens, 200);
});

Deno.test("DeepSeek through the gateway prices cache hits at the cache rate", async () => {
  const route = routeFor("daily_decision", {
    PROVIDER: "openai_compatible",
    MODEL: "deepseek-flash",
    BASE_URL: "https://api.deepseek.com/v1",
    OPENAI_COMPATIBLE_API_KEY_DAILY_DECISION: syntheticKey,
  });
  const fake = fakeFetch(() =>
    jsonResponse({
      model: "deepseek-flash",
      choices: [{ message: { content: '{"action":"PROCEED"}' }, finish_reason: "stop" }],
      usage: { prompt_tokens: 10_000, completion_tokens: 500, prompt_cache_hit_tokens: 8000 },
    })
  );
  const result = await quiet(() =>
    call({
      route,
      system: [{ type: "text", text: "Return JSON." }],
      messages: [{ role: "user", content: [{ type: "text", text: secretPrompt }] }],
      output: { kind: "json", schema: decisionSchema },
      consentProvider: "openai_compatible",
    }, { fetch: fake.fetch })
  );
  assertEquals(fake.sent[0].url, "https://api.deepseek.com/v1/chat/completions");
  if (!result.ok) throw new Error(result.reason);
  assertEquals(result.json, { action: "PROCEED" });
  // 2,000 × 0.30 + 500 × 1.20 + 8,000 × 0.006 = 1,248 µUSD.
  assertAlmostEquals(result.usage.costUsd, 0.001248, 1e-12);
});

Deno.test("Gemini through the gateway", async () => {
  const route = routeFor("meal_vision", {
    PROVIDER: "gemini",
    MODEL: "gemini-3.5-flash",
    GEMINI_API_KEY: syntheticKey,
    GEMINI_PAID_DATA_TERMS_ACCEPTED: "true",
  });
  const fake = fakeFetch(() =>
    jsonResponse({
      candidates: [{ content: { parts: [{ text: "Dal and rice" }] }, finishReason: "STOP" }],
      usageMetadata: { promptTokenCount: 1300, candidatesTokenCount: 100, thoughtsTokenCount: 50 },
    })
  );
  const result = await quiet(() =>
    call({
      route,
      system: [],
      messages: [{
        role: "user",
        content: [{ type: "text", text: "Meal?" }, {
          type: "image",
          mediaType: "image/jpeg",
          base64: secretImage,
        }],
      }],
      output: { kind: "text" },
      consentProvider: "gemini",
    }, { fetch: fake.fetch })
  );
  assertEquals(fake.sent[0].headers["x-goog-api-key"], syntheticKey);
  if (!result.ok) throw new Error(result.reason);
  assertEquals(result.text, "Dal and rice");
  assertEquals(result.model, "gemini-3.5-flash");
  // 1,300 × 1.50 + 150 × 9 = 3,300 µUSD.
  assertAlmostEquals(result.usage.costUsd, 0.0033, 1e-12);
});

Deno.test("every call logs one ai_call line without prompt, image, reply or key", async () => {
  const ticks = [100, 1342];
  const now = () => ticks.shift() ?? 0;
  const image = { type: "image" as const, mediaType: "image/jpeg" as const, base64: secretImage };
  const okRun = await captureLogs(() =>
    call(
      request({
        messages: [{ role: "user", content: [{ type: "text", text: secretPrompt }, image] }],
      }),
      { fetch: claude({ content: [{ type: "text", text: secretReply }] }).fetch, now },
    )
  );
  assertEquals(okRun.lines.length, 1);
  const line = JSON.parse(okRun.lines[0]);
  assertEquals(line.level, "info");
  assertEquals(line.msg, "ai_call");
  assertEquals(line.feature, "coach_chat");
  assertEquals(line.provider, "anthropic");
  assertEquals(line.model, "claude-sonnet-5-5");
  assertEquals(line.outcome, "ok");
  assertEquals(line.input_tokens, 1000);
  assertEquals(line.output_tokens, 200);
  assertEquals(line.cache_read_tokens, 0);
  assertEquals(line.cache_write_tokens, 0);
  assertAlmostEquals(line.cost_usd, 0.004, 1e-12);
  assertEquals(line.latency_ms, 1242);
  assertEquals(line.http_status, 200);
  assertEquals(line.stop, "end");

  const failures = [
    await captureLogs(() =>
      call(request({ output: { kind: "json", schema: decisionSchema } }), {
        fetch: claude({ content: [{ type: "text", text: secretReply }] }).fetch,
      })
    ),
    await captureLogs(() =>
      call(request(), {
        fetch: fakeFetch(() => jsonResponse({ error: { message: secretPrompt } }, 400)).fetch,
      })
    ),
    await captureLogs(() => call(request({ consentProvider: null }), { fetch: claude().fetch })),
  ];
  assertEquals(failures.map((run) => JSON.parse(run.lines[0]).outcome), [
    "invalid_output",
    "provider_error",
    "consent_provider_mismatch",
  ]);
  for (const run of [okRun, ...failures]) {
    assertEquals(run.lines.length, 1);
    for (const secret of [secretPrompt, secretReply, secretImage, syntheticKey, "Tracend rules"]) {
      assertEquals(run.lines[0].includes(secret), false, secret);
    }
  }
  assertEquals(JSON.parse(failures[0].lines[0]).level, "warn");
});
