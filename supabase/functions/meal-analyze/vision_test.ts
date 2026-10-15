import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import {
  claudeMessage,
  envOf,
  fakeFetch,
  jsonResponse,
  type Sent,
  settings,
} from "../_shared/ai/fakes.ts";
import { AiBudget } from "../_shared/ai_budget.ts";
import { MealVisionBilledError } from "../_shared/providers/gemini_meal_vision_provider.ts";
import { handleMealAnalyze, type MealAnalyzeStore } from "./handler.ts";
import golden from "./legacy_requests_golden.json" with { type: "json" };
import {
  mealVisionCeilingUsd,
  mealVisionInstructions,
  mealVisionPath,
  mealVisionRouteUnusable,
  readMealConsent,
  reserveMealBudget,
} from "./vision.ts";

// Today's settings in production: Groq, switched on and evaluated.
const today: Record<string, string> = {
  MEAL_VISION_ENABLED: "true",
  MEAL_VISION_MODEL_EVALUATED: "true",
  MEAL_VISION_PROVIDER: "groq",
  GROQ_API_KEY: "k",
};
// The gateway route A7's cutover sets: Haiku 5.5 without thinking.
const haiku = settings("meal_vision", {
  MODEL: "claude-haiku-5-5",
  MAX_OUTPUT_TOKENS: "1500",
  EVALUATED: "true",
});
const environment = (values: Record<string, string>) => {
  const env = envOf(values);
  return { get: (name: string) => env(name) };
};

// A JPEG with an EXIF segment ("GPS!!!") that must never leave the server.
const exif = [0xff, 0xe1, 0x00, 0x08, 0x47, 0x50, 0x53, 0x21, 0x21, 0x21];
const photo = new Uint8Array([0xff, 0xd8, ...exif, 0xff, 0xda, 0x00, 0x02, 0x01, 0xff, 0xd9]);
const cleanBase64 = btoa(String.fromCharCode(0xff, 0xd8, 0xff, 0xda, 0x00, 0x02, 0x01, 0xff, 0xd9));
// The bytes the legacy goldens were recorded with.
const goldenJpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xda, 0, 2, 0xff, 0xd9]);

const dal = {
  name: "Dal tadka",
  serving_label: "1 bowl",
  calories: 220,
  protein_g: 11,
  carbohydrate_g: 28,
  fat_g: 8,
  confidence: "medium" as const,
  assumptions: ["Ghee on top is about 1 tsp"],
  question: "Was ghee added after cooking?",
};
const answer = (candidates: unknown[], overrides: Record<string, unknown> = {}) =>
  jsonResponse(claudeMessage({
    model: "claude-haiku-5-5",
    content: [{ type: "text", text: JSON.stringify({ candidates }) }],
    ...overrides,
  }, { input_tokens: 1800, output_tokens: 240 }));
const failing = (status: number) => () =>
  Promise.resolve(new Response("{}", { status, headers: { "retry-after": "5" } }));

Deno.test("parity: without a route, Groq gets today's request byte for byte", async () => {
  const sent: string[] = [];
  const recording = (url: unknown, init?: RequestInit) => {
    sent.push(`${url}\n${init?.body}`);
    return Promise.resolve(new Response("{}", { status: 500 }));
  };
  // Incomplete gateway settings (no key) are no route either.
  for (const extra of [{}, { AI_MEAL_VISION_PROVIDER: "anthropic" }] as Record<string, string>[]) {
    const path = mealVisionPath({
      environment: environment({ ...today, ...extra }),
      fetch: recording as typeof fetch,
    });
    assertEquals([path.provider, path.route], ["groq", null]);
    await assertRejects(() => path.analyze(goldenJpeg, "image/jpeg", "groq"));
  }
  assertEquals(sent, [0, 1].map(() => `${golden.groq.url}\n${golden.groq.body}`));
});

Deno.test("parity: without a route, Gemini gets today's request byte for byte", async () => {
  let sent = "";
  const path = mealVisionPath({
    environment: environment({
      ...today,
      MEAL_VISION_PROVIDER: "",
      GEMINI_API_KEY: "k",
      GEMINI_PAID_DATA_TERMS_ACCEPTED: "true",
      MEAL_VISION_INPUT_COST_PER_MILLION_USD: "1",
      MEAL_VISION_OUTPUT_COST_PER_MILLION_USD: "1",
    }),
    fetch: ((url: unknown, init?: RequestInit) => {
      sent = `${url}\n${init?.body}`;
      return Promise.resolve(new Response("{}", { status: 500 }));
    }) as typeof fetch,
  });
  assertEquals([path.provider, path.route], ["gemini", null]);
  await assertRejects(() => path.analyze(goldenJpeg, "image/jpeg", "gemini"));
  assertEquals(sent, `${golden.gemini.url}\n${golden.gemini.body}`);
});

Deno.test("parity: without a route, consent and budget use today's RPCs", async () => {
  const rpcs: [string, Record<string, unknown>][] = [];
  const rpc = (name: string, params: Record<string, unknown>) => {
    rpcs.push([name, params]);
    return Promise.resolve({
      data: name === "get_meal_photo_ai_consent"
        ? { granted: true, provider: "groq" }
        : "reservation-1",
      error: null,
    });
  };
  const path = mealVisionPath({ environment: environment(today) });
  assertEquals(await readMealConsent(rpc, "user-1", path), { granted: true, provider: "groq" });
  assert(await reserveMealBudget(new AiBudget(rpc, "user-1"), path));
  assertEquals(rpcs, [
    ["get_meal_photo_ai_consent", { target_user_id: "user-1" }],
    ["reserve_ai_budget", { target_user_id: "user-1", run_purpose: "meal_vision" }],
  ]);
});

Deno.test("a route reads consent v2 and reserves the route's ceiling", async () => {
  const rpcs: [string, Record<string, unknown>][] = [];
  const rpc = (name: string, params: Record<string, unknown>) => {
    rpcs.push([name, params]);
    return Promise.resolve({
      data: name === "get_ai_consent_v2"
        ? { granted: true, provider: "anthropic", notice_version: "meal-photo-ai-v2" }
        : "reservation-1",
      error: null,
    });
  };
  const path = mealVisionPath({ environment: environment({ ...today, ...haiku }) });
  assertEquals(path.provider, "anthropic");
  assertEquals(await readMealConsent(rpc, "user-1", path), {
    granted: true,
    provider: "anthropic",
  });
  assert(await reserveMealBudget(new AiBudget(rpc, "user-1"), path));
  // 8,000 prompt tokens at Haiku's cache-write rate and 1,500 output tokens.
  assertEquals(mealVisionCeilingUsd(path.route!), 0.00175);
  assertEquals(rpcs, [
    ["get_ai_consent_v2", { target_user_id: "user-1", consent_purpose: "meal_vision" }],
    ["reserve_ai_budget_v2", {
      target_user_id: "user-1",
      run_purpose: "meal_vision",
      ceiling_usd: 0.00175,
    }],
  ]);
  // A failed consent read is unknown, never a grant.
  const broken = () => Promise.resolve({ data: null, error: { code: "XX000" } });
  assertEquals(await readMealConsent(broken, "user-1", path), null);
});

Deno.test("a route sends one Claude request: cached instructions, a clean photo, a schema", async () => {
  const { fetch, sent } = fakeFetch(() => answer([dal]));
  const path = mealVisionPath({ environment: environment({ ...today, ...haiku }), fetch });
  const result = await path.analyze(photo, "image/jpeg", "anthropic");
  assertEquals(sent.length, 1);
  const body = sent[0].body;
  assertEquals(sent[0].url, "https://api.anthropic.com/v1/messages");
  assertEquals(body.model, "claude-haiku-5-5");
  assertEquals(body.max_tokens, 1500);
  assertEquals(body.thinking, { type: "disabled" });
  for (const field of ["temperature", "top_p", "top_k", "tools", "tool_choice"]) {
    assert(!(field in body), field);
  }
  assertEquals(body.system, [{
    type: "text",
    text: mealVisionInstructions,
    cache_control: { type: "ephemeral" },
  }]);
  const content = (body.messages as { content: Record<string, unknown>[] }[])[0].content;
  assertEquals(content[0], {
    type: "image",
    source: { type: "base64", media_type: "image/jpeg", data: cleanBase64 },
  });
  assertEquals(content[1].type, "text");
  const format = (body.output_config as Record<string, Record<string, unknown>>).format;
  assertEquals(format.type, "json_schema");
  assertEquals(result.candidates, [dal]);
  assertEquals(result.model, "claude-haiku-5-5");
  assertEquals([result.inputUnits, result.outputUnits], [1800, 240]);
  // 1,800 input tokens at USD 0.10/M and 240 output tokens at USD 0.50/M.
  assertEquals(result.estimatedCostUsd, 0.0003);
});

Deno.test("a route sends nothing without the switch, the eval, a consenting vendor or a JPEG", async () => {
  const cases: [Record<string, string>, string, string | null, string][] = [
    [{ MEAL_VISION_ENABLED: "false" }, "image/jpeg", "anthropic", "meal_vision_disabled"],
    [{ AI_MEAL_VISION_EVALUATED: "false" }, "image/jpeg", "anthropic", "meal_vision_disabled"],
    [{}, "image/png", "anthropic", "meal_image_invalid"],
    [{}, "image/jpeg", "groq", "meal_vision_request_failed:consent_provider_mismatch"],
    [{}, "image/jpeg", null, "meal_vision_request_failed:consent_provider_mismatch"],
  ];
  for (const [extra, contentType, consented, code] of cases) {
    const { fetch, sent } = fakeFetch(() => answer([dal]));
    const path = mealVisionPath({
      environment: environment({ ...today, ...haiku, ...extra }),
      fetch,
    });
    await assertRejects(() => path.analyze(photo, contentType, consented), Error, code);
    assertEquals(sent.length, 0, code);
  }
});

Deno.test("gateway failures map to the handler's codes and keep billed usage", async () => {
  const run = async (respond: (sent: Sent) => Response | Promise<Response>) => {
    const { fetch } = fakeFetch(respond);
    const path = mealVisionPath({ environment: environment({ ...today, ...haiku }), fetch });
    try {
      await path.analyze(photo, "image/jpeg", "anthropic");
      return null;
    } catch (error) {
      return error as Error;
    }
  };
  assertEquals((await run(failing(429)))?.message, "meal_vision_busy");
  assertEquals((await run(failing(529)))?.message, "meal_vision_busy");
  const refused = await run(() =>
    answer([], { stop_reason: "refusal", content: [{ type: "text", text: "" }] })
  );
  assert(refused instanceof MealVisionBilledError);
  assertEquals([refused.message, refused.usage.outputUnits], ["meal_vision_refused", 240]);
  const broken = await run(() =>
    jsonResponse(claudeMessage({ content: [{ type: "text", text: '{"candidates": [' }] }))
  );
  assert(broken instanceof MealVisionBilledError);
  assertEquals(broken.message, "meal_vision_invalid_output");
  // A candidate the tables could never store is billed and refused.
  const huge = await run(() => answer([{ ...dal, calories: 9000 }]));
  assert(huge instanceof MealVisionBilledError);
  assertEquals(huge.message, "meal_vision_response_invalid");
  const cut = await run(() => Promise.reject(new TypeError("connection reset")));
  assert(cut !== null && !(cut instanceof MealVisionBilledError));
  assertEquals(cut.message, "meal_vision_network");
});

function harness(consentProvider: string) {
  const events: string[] = [];
  const store: MealAnalyzeStore = {
    consent: () => Promise.resolve({ granted: true, provider: consentProvider }),
    reserveBudget: () => {
      events.push("reserve");
      return Promise.resolve(true);
    },
    keepBudget: () => {
      events.push("keep");
    },
    loadDraft: () =>
      Promise.resolve({
        objectKey: "11111111-1111-4111-8111-111111111111/meal/x.jpg",
        contentType: "image/jpeg",
      }),
    download: () => Promise.resolve(photo),
    recordUsage: (usage) => {
      events.push(`usage:${usage.model}:${usage.estimatedCostUsd}`);
      return Promise.resolve();
    },
    persistCandidates: (_meal, candidates, model) => {
      events.push(`persist:${candidates.length}:${model}`);
      return Promise.resolve(true);
    },
    discardDraft: () => Promise.resolve(true),
  };
  return { events, store };
}

const request = { schema_version: "1.0", meal_id: "22222222-2222-4222-8222-222222222222" };

async function analyzeThrough(
  consentProvider: string,
  respond: (sent: Sent) => Response | Promise<Response>,
) {
  const { events, store } = harness(consentProvider);
  const { fetch, sent } = fakeFetch(respond);
  const path = mealVisionPath({ environment: environment({ ...today, ...haiku }), fetch });
  const response = await handleMealAnalyze(request, {
    userId: "11111111-1111-4111-8111-111111111111",
    provider: path.provider,
    analyze: path.analyze,
    store,
    log: { info: () => {}, warn: () => {}, error: () => {} },
    report: () => events.push("report"),
    now: () => 0,
  });
  return { response, events, sent };
}

Deno.test("through the handler: Claude's answer is stored with its vendor's model", async () => {
  const { response, events } = await analyzeThrough("anthropic", () => answer([dal]));
  assertEquals(response.status, 200);
  assertEquals(events, ["reserve", "usage:claude-haiku-5-5:0.0003", "persist:1:claude-haiku-5-5"]);
});

Deno.test("through the handler: an old notice sends nothing and reserves nothing", async () => {
  const { response, events, sent } = await analyzeThrough("groq", () => answer([dal]));
  assertEquals([response.status, await response.json()], [503, {
    error: "meal_photo_notice_outdated",
  }]);
  assertEquals([events, sent.length], [[], 0]);
});

Deno.test("through the handler: busy is 429 and releases; a timeout keeps the place", async () => {
  const busy = await analyzeThrough("anthropic", failing(529));
  assertEquals([busy.response.status, busy.events], [429, ["reserve"]]);
  const lost = await analyzeThrough("anthropic", () => Promise.reject(new TypeError("reset")));
  assertEquals([lost.response.status, lost.events], [503, ["reserve", "keep", "report"]]);
  const refused = await analyzeThrough(
    "anthropic",
    () => answer([], { stop_reason: "refusal" }),
  );
  assertEquals(refused.response.status, 503);
  assertEquals(refused.events, ["reserve", "usage:claude-haiku-5-5:0.0003", "report"]);
});

/** One photo with a real AiBudget, released the way index.ts releases it. */
async function analyzeWithBudget(respond: (sent: Sent) => Response | Promise<Response>) {
  const rpcs: string[] = [];
  const budget = new AiBudget((name, params) => {
    rpcs.push(name === "reserve_ai_budget_v2" ? `${name}:${params.ceiling_usd}` : name);
    return Promise.resolve({ data: "reservation-1", error: null });
  }, "11111111-1111-4111-8111-111111111111");
  const { events, store } = harness("anthropic");
  const { fetch } = fakeFetch(respond);
  const path = mealVisionPath({ environment: environment({ ...today, ...haiku }), fetch });
  let status: number;
  try {
    const response = await handleMealAnalyze(request, {
      userId: "11111111-1111-4111-8111-111111111111",
      provider: path.provider,
      analyze: path.analyze,
      store: {
        ...store,
        reserveBudget: () => reserveMealBudget(budget, path),
        keepBudget: () => budget.keep(),
      },
      log: { info: () => {}, warn: () => {}, error: () => {} },
      report: () => events.push("report"),
      now: () => 0,
    });
    status = response.status;
  } finally {
    await budget.release();
  }
  return { status, rpcs, usage: events.filter((event) => event.startsWith("usage:")).length };
}

Deno.test("budget: a meal refusal is recorded and released; a lost answer keeps its place", async () => {
  const refused = await analyzeWithBudget(() => answer([], { stop_reason: "refusal" }));
  assertEquals(refused, {
    status: 503,
    rpcs: ["reserve_ai_budget_v2:0.00175", "settle_ai_budget"],
    usage: 1,
  });
  const busy = await analyzeWithBudget(failing(429));
  assertEquals(busy, {
    status: 429,
    rpcs: ["reserve_ai_budget_v2:0.00175", "settle_ai_budget"],
    usage: 0,
  });
  const lost = await analyzeWithBudget(() => Promise.reject(new TypeError("reset")));
  assertEquals(lost, { status: 503, rpcs: ["reserve_ai_budget_v2:0.00175"], usage: 0 });
  // An unreadable 200 may have been billed: the place stays held (provider_error, no usage).
  const unreadable = await analyzeWithBudget(() => new Response("not json", { status: 200 }));
  assertEquals(unreadable, { status: 503, rpcs: ["reserve_ai_budget_v2:0.00175"], usage: 0 });
});

// Opus at the most output the route may allow: the worst case is above the USD 0.50 one
// reservation can hold.
const opusHuge = settings("meal_vision", {
  MODEL: "claude-opus-5-5",
  THINKING: "adaptive",
  MAX_OUTPUT_TOKENS: "32000",
  EVALUATED: "true",
});

Deno.test("a route above the reservation cap is unusable: nothing is reserved or sent", async () => {
  const rpcs: string[] = [];
  const rpc = (name: string) => {
    rpcs.push(name);
    return Promise.resolve({
      data: name === "get_ai_consent_v2"
        ? { granted: true, provider: "anthropic", notice_version: "meal-photo-ai-v2" }
        : "reservation-1",
      error: null,
    });
  };
  const { fetch, sent } = fakeFetch(() => answer([dal]));
  const path = mealVisionPath({ environment: environment({ ...today, ...opusHuge }), fetch });
  assertEquals(mealVisionCeilingUsd(path.route!), null);
  const logged: [string, unknown][] = [];
  const log = { error: (event: string, fields?: unknown) => logged.push([event, fields]) };
  // The consent read comes back unknown, so the handler answers 503 meal_analysis_unavailable.
  assertEquals(await readMealConsent(rpc, "user-1", path, log), null);
  assertEquals(logged, [[mealVisionRouteUnusable, {
    provider: "anthropic",
    model: "claude-opus-5-5",
  }]]);
  assertEquals(mealVisionRouteUnusable, "meal_vision_route_unusable");
  // Defence in depth: reserving and analysing refuse too.
  assertEquals(await reserveMealBudget(new AiBudget(rpc, "user-1"), path), false);
  await assertRejects(
    () => path.analyze(goldenJpeg, "image/jpeg", "anthropic"),
    Error,
    "meal_vision_disabled",
  );
  assertEquals([rpcs, sent.length], [[], 0]);
});

Deno.test("through the handler: an over-cap route answers unavailable and sends nothing", async () => {
  const rpcs: string[] = [];
  const rpc = (name: string) => {
    rpcs.push(name);
    return Promise.resolve({
      data: { granted: true, provider: "anthropic", notice_version: "meal-photo-ai-v2" },
      error: null,
    });
  };
  const { events, store } = harness("anthropic");
  const { fetch, sent } = fakeFetch(() => answer([dal]));
  const path = mealVisionPath({ environment: environment({ ...today, ...opusHuge }), fetch });
  const response = await handleMealAnalyze(request, {
    userId: "11111111-1111-4111-8111-111111111111",
    provider: path.provider,
    analyze: path.analyze,
    store: {
      ...store,
      consent: () => readMealConsent(rpc, "user-1", path),
      reserveBudget: () => reserveMealBudget(new AiBudget(rpc, "user-1"), path),
    },
    log: { info: () => {}, warn: () => {}, error: () => {} },
    report: () => events.push("report"),
    now: () => 0,
  });
  assertEquals([response.status, await response.json()], [503, {
    error: "meal_analysis_unavailable",
  }]);
  assertEquals([events, rpcs, sent.length], [[], [], 0]);
});

Deno.test("the intended Haiku and Sonnet routes stay under the cap; an unknown model is unusable", () => {
  const ceiling = (values: Record<string, string>) =>
    mealVisionCeilingUsd(
      mealVisionPath({ environment: environment({ ...today, ...values }) }).route!,
    );
  assertEquals(ceiling(haiku), 0.00175);
  assertEquals(
    ceiling(settings("meal_vision", {
      MODEL: "claude-sonnet-5-5",
      MAX_OUTPUT_TOKENS: "1500",
      EVALUATED: "true",
    })),
    0.035,
  );
  assertEquals(
    ceiling(settings("meal_vision", {
      MODEL: "claude-opus-5-5",
      THINKING: "adaptive",
      MAX_OUTPUT_TOKENS: "1500",
      EVALUATED: "true",
    })) !== null,
    true,
  );
});
