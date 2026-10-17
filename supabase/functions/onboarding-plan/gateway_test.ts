// Onboarding plan and follow-up questions through the AI gateway: offline, with the gateway's fake
// fetch and a real AiBudget over a fake database. No test touches the network.

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import { athletes, evalRoutes, health, history } from "../_evals/onboarding_plan_eval.ts";
import { AiBudget } from "../_shared/ai_budget.ts";
import type { AiConsentWithProvider } from "../_shared/ai_consent.ts";
import {
  claudeMessage,
  envOf,
  fakeFetch,
  jsonResponse,
  routeFor,
  settings,
} from "../_shared/ai/fakes.ts";
import type { AiRoute } from "../_shared/ai/types.ts";
import { parseOnboardingAnswers } from "../_shared/onboarding/answers.ts";
import { exerciseCatalogV1 } from "../_shared/onboarding/catalog.ts";
import { policiesFor, validRulesPlan } from "../_shared/onboarding/generate.ts";
import {
  gatewayCeilingUsd,
  maxReservableCeilingUsd,
  onboardingGatewayRoute,
} from "../_shared/providers/onboarding_plan_provider.ts";
import {
  failureCode,
  namesModelOrCompany,
  onboardingPlanJsonSchema,
  preparePlan,
  prepareQuestions,
  resultSpend,
} from "./gateway.ts";
import {
  type GenerationClaim,
  handleOnboardingPlan,
  type HandlerDeps,
  type OnboardingStore,
  type StoredQuestions,
} from "./handler.ts";
import golden from "./legacy_requests_golden.json" with { type: "json" };
import { legacyCaseNames, runLegacyCase, syntheticDrafts } from "./legacy_golden_harness.ts";

// --- Fixtures ----------------------------------------------------------------------------------

const catalog = [...exerciseCatalogV1];
const answersFor = (draft: typeof syntheticDrafts.plan | typeof syntheticDrafts.questions) => {
  const parsed = parseOnboardingAnswers(draft.path, draft.payload, 2026);
  if (!parsed.ok) throw new Error(`synthetic draft incomplete: ${parsed.missing.join(", ")}`);
  return parsed.answers;
};

/** A plan the contract accepts: the rules plan for the synthetic athlete. */
const validPlan = () =>
  validRulesPlan(policiesFor(answersFor(syntheticDrafts.plan), catalog)) as unknown as Record<
    string,
    unknown
  >;
const planWith = (change: (plan: Record<string, unknown>) => void) => {
  const plan = structuredClone(validPlan());
  change(plan);
  return JSON.stringify(plan);
};

const granted = (provider: AiConsentWithProvider["provider"]): AiConsentWithProvider => ({
  consent: "granted",
  provider,
  noticeVersion: "coaching-v6",
});

const planRoute = (values: Record<string, string> = {}) =>
  routeFor("onboarding_plan", {
    MAX_OUTPUT_TOKENS: "8000",
    TIMEOUT_MS: "60000",
    EVALUATED: "true",
    ...values,
  });
const questionsRoute = (values: Record<string, string> = {}) =>
  routeFor("onboarding_questions", {
    MAX_OUTPUT_TOKENS: "1500",
    TIMEOUT_MS: "30000",
    EVALUATED: "true",
    ...values,
  });

const claude = (text: string, usage: Record<string, unknown> = {}) =>
  jsonResponse(claudeMessage({ content: [{ type: "text", text }] }, {
    input_tokens: 7000,
    output_tokens: 2500,
    ...usage,
  }));

type Harness = ReturnType<typeof harness>;

/** A store over a real AiBudget, so budget outcomes are the production ones. */
function harness(options: {
  draft?: typeof syntheticDrafts.plan | typeof syntheticDrafts.questions;
  consent?: AiConsentWithProvider;
  reserve?: boolean;
} = {}) {
  const log: string[] = [];
  const rpc: { fn: string; args: Record<string, unknown> }[] = [];
  const usage: { provider: string; model: string; estimatedCostUsd: number; inputUnits: number }[] =
    [];
  const persisted: { proposal: { training: Record<string, unknown> } }[] = [];
  const saved = new Map<string, StoredQuestions>();
  const released: string[] = [];
  let consentReads = 0;
  let reserves = 0;
  const budget = new AiBudget((fn, args) => {
    rpc.push({ fn, args });
    if (fn === "reserve_ai_budget_v2") {
      return Promise.resolve(
        options.reserve === false
          ? { data: null, error: { code: "P0001" } }
          : { data: `reservation-${++reserves}`, error: null },
      );
    }
    if (fn === "settle_ai_budget") log.push("settle");
    return Promise.resolve({ data: null, error: null });
  }, "user-1");
  const draft = options.draft ?? syntheticDrafts.plan;
  const store: OnboardingStore = {
    loadDraft: () => Promise.resolve(draft),
    claim: () =>
      Promise.resolve(
        { generation_id: "gen-1", status: "running", started: true } as GenerationClaim,
      ),
    loadCatalog: () => Promise.resolve(catalog),
    timezone: () => Promise.resolve("UTC"),
    screening: () => Promise.resolve("cleared"),
    loadHealth: () => Promise.resolve({ days: [], workouts: [] }),
    loadHealthHistory: () => Promise.resolve([]),
    claimQuestions: (hash) => {
      const stored = saved.get(hash);
      return Promise.resolve(stored ? { started: false, stored } : { started: true });
    },
    saveQuestions: (hash, stored) => {
      saved.set(hash, stored);
      return Promise.resolve(stored);
    },
    releaseQuestions: (hash) => {
      released.push(hash);
      return Promise.resolve();
    },
    recordQuestionUsage: (event) => {
      log.push("usage");
      usage.push(event);
      return Promise.resolve();
    },
    consent: () => Promise.reject(new Error("the settings path was not expected")),
    budgetAvailable: () => Promise.reject(new Error("the settings path was not expected")),
    gatewayConsent: () => {
      consentReads++;
      return Promise.resolve(options.consent ?? granted("anthropic"));
    },
    reserveGatewayBudget: (feature, ceiling) => budget.reserve(feature, ceiling),
    releaseBudget: () => budget.release(),
    keepBudget: () => {
      log.push("keep");
      budget.keep();
    },
    recordUsage: (event) => {
      log.push("usage");
      usage.push(event);
      return Promise.resolve();
    },
    persist: (_id, _hash, _snapshot, proposal) => {
      persisted.push({ proposal });
      return Promise.resolve("stored");
    },
    fail: () => Promise.resolve(),
  };
  return {
    store,
    log,
    rpc,
    usage,
    persisted,
    saved,
    released,
    reads: () => consentReads,
    settled: () => rpc.filter((entry) => entry.fn === "settle_ai_budget").length,
    reserved: () => rpc.filter((entry) => entry.fn === "reserve_ai_budget_v2"),
  };
}

async function run(
  mode: "plan" | "questions",
  h: Harness,
  routes: { plan?: AiRoute | null; questions?: AiRoute | null },
  fetcher: typeof fetch,
  extra: Partial<HandlerDeps> = {},
) {
  const work: Promise<void>[] = [];
  const events: { level: string; event: string; fields: Record<string, unknown> }[] = [];
  const response = await handleOnboardingPlan({
    mode,
    store: h.store,
    resolution: () => ({ kind: "rules", reason: "provider_mock" }),
    currentYear: 2026,
    now: () => new Date("2026-10-02T09:00:00Z"),
    background: (promise) => work.push(promise),
    observer: {
      info: (event, fields) => events.push({ level: "info", event, fields }),
      warn: (event, fields) => events.push({ level: "warn", event, fields }),
      error: (event, _error, fields) => events.push({ level: "error", event, fields }),
    },
    routes: { plan: () => routes.plan ?? null, questions: () => routes.questions ?? null },
    gateway: { gateway: { fetch: fetcher } },
    sleep: () => Promise.resolve(),
    ...extra,
  });
  await Promise.all(work);
  return { response, body: await response.json(), events };
}

const training = (h: Harness) => h.persisted[0].proposal.training;

// --- No route: today's requests, byte for byte -------------------------------------------------

const goldenCatalog = golden.catalog as unknown as typeof catalog;

for (const name of legacyCaseNames) {
  const recorded = golden.cases.find((entry) => entry.name === name)!;
  const variants: [string, Parameters<typeof runLegacyCase>[2]][] = [
    ["no route", undefined],
    // A route without EVALUATED=true, and one with a missing setting, both read as no route.
    ["route not evaluated", {
      plan: () => onboardingGatewayRoute("onboarding_plan", envOf(settings("onboarding_plan"))),
      questions: () =>
        onboardingGatewayRoute("onboarding_questions", envOf(settings("onboarding_questions"))),
    }],
    ["incomplete settings", {
      plan: () =>
        onboardingGatewayRoute(
          "onboarding_plan",
          envOf(settings("onboarding_plan", { EVALUATED: "true", MODEL: "" })),
        ),
      questions: () =>
        onboardingGatewayRoute(
          "onboarding_questions",
          envOf(settings("onboarding_questions", { EVALUATED: "true", TIMEOUT_MS: "" })),
        ),
    }],
  ];
  for (const [variant, routes] of variants) {
    Deno.test(`${name}: ${variant} sends the request recorded from origin/main`, async () => {
      const replay = await runLegacyCase(name, goldenCatalog, routes);
      assertEquals(replay.requests.length, recorded.requests.length);
      assertEquals(replay.requests, recorded.requests);
    });
  }
}

Deno.test("the eval router never receives athlete data: its route is ignored", () => {
  const values = settings("onboarding_plan", {
    PROVIDER: "openai_compatible",
    MODEL: "deepseek-flash",
    VENDOR: "router",
    BASE_URL: "https://router.example.com/v1",
    EVALUATED: "true",
  });
  values.OPENAI_COMPATIBLE_API_KEY_ONBOARDING_PLAN = "synthetic-router-key";
  delete values.ANTHROPIC_API_KEY;
  assertEquals(onboardingGatewayRoute("onboarding_plan", envOf(values)), null);
});

// --- The plan through the gateway --------------------------------------------------------------

Deno.test("a plan goes to Claude with the cached rules, the structured shape and no sampling", async () => {
  const h = harness();
  const { fetch, sent } = fakeFetch(() => claude(JSON.stringify(validPlan())));
  const { response, events } = await run("plan", h, { plan: planRoute() }, fetch);
  assertEquals(response.status, 202);
  assertEquals(sent.length, 1);
  const body = sent[0].body;
  assertEquals(sent[0].url, "https://api.anthropic.com/v1/messages");
  assertEquals(body.model, "claude-sonnet-5-5");
  assertEquals(body.max_tokens, 8000);
  for (const key of ["temperature", "top_p", "top_k", "tool_choice", "tools"]) {
    assert(!(key in body), key);
  }
  const system = body.system as { type: string; text: string; cache_control?: unknown }[];
  assertEquals(system.length, 1);
  assertEquals(system[0].cache_control, { type: "ephemeral" });
  assert(!system[0].text.includes("Exercise catalog"));
  const message = (body.messages as { role: string; content: { text: string }[] }[])[0];
  assertEquals(message.role, "user");
  assertEquals(message.content.length, 1);
  assert(message.content[0].text.includes("Exercise catalog"));
  assert(JSON.stringify(body.output_config).includes("json_schema"));
  assertEquals(h.reads(), 1);
  assertEquals(training(h).origin, "ai");
  assertEquals(training(h).provider, "anthropic");
  assertEquals(training(h).model, "claude-sonnet-5-5");
  assertEquals(training(h).fallback_reason, null);
  // The usage is recorded at the real cost, then the place is given back.
  assertEquals(h.usage.length, 1);
  assertEquals(h.usage[0].provider, "anthropic");
  assertEquals(h.usage[0].model, "claude-sonnet-5-5");
  assertEquals(h.usage[0].inputUnits, 7000);
  assertEquals(h.usage[0].estimatedCostUsd, (7000 * 2 + 2500 * 10) / 1_000_000);
  assertEquals(h.log, ["usage", "settle"]);
  assert(!events.some((event) => event.level === "warn"));
});

Deno.test("the reservation is the worst case of both attempts and is never clamped", async () => {
  const h = harness();
  const route = planRoute();
  const { fetch } = fakeFetch(() => claude(JSON.stringify(validPlan())));
  await run("plan", h, { plan: route }, fetch);
  const [reserve] = h.reserved();
  assertEquals(reserve.args.run_purpose, "onboarding_plan");
  const ceiling = reserve.args.ceiling_usd as number;
  // Two attempts of every output token the route allows, plus both prompts.
  assert(ceiling >= 2 * (8000 * 10) / 1_000_000, `${ceiling}`);
  assert(ceiling <= maxReservableCeilingUsd);
  const prepared = preparePlan(
    route,
    answersFor(syntheticDrafts.plan),
    catalog,
    null,
    null,
  );
  assertEquals(prepared.kind, "ready");
  if (prepared.kind === "ready") assertEquals(prepared.prepared.ceilingUsd, ceiling);
  assertEquals(h.reserved().length, 1);
});

Deno.test("a route whose worst case passes what the budget accepts is not used", async () => {
  const h = harness();
  // 32,000 output tokens on Sonnet cost USD 0.32 an attempt: 0.64 for two.
  const route = planRoute({ MAX_OUTPUT_TOKENS: "32000" });
  const answers = answersFor(syntheticDrafts.plan);
  const prepared = preparePlan(route, answers, catalog, null, null);
  assertEquals(prepared.kind, "unusable");
  const { fetch, sent } = fakeFetch(() => claude("{}"));
  const { events } = await run("plan", h, { plan: route }, fetch);
  // Nothing is sent or reserved; the settings path (here the rules plan) answers.
  assertEquals(sent.length, 0);
  assertEquals(h.reserved().length, 0);
  assertEquals(h.reads(), 0);
  assertEquals(training(h).origin, "rules");
  const warn = events.find((event) => event.event === "onboarding_plan_route_unusable");
  assert(warn);
  assert(String(warn.fields.fallbackReason).includes("exceeds"));
});

Deno.test("the ceiling follows the model price and has no floor below the real cost", () => {
  const sonnet = planRoute();
  const haiku = planRoute({ MODEL: "claude-haiku-5-5" });
  const sonnetCeiling = gatewayCeilingUsd(sonnet, [10_000])!;
  const haikuCeiling = gatewayCeilingUsd(haiku, [10_000])!;
  assert(sonnetCeiling > haikuCeiling);
  // One attempt: 11,000 prompt tokens at the dearer of input and cache write, 8,000 output.
  assertEquals(sonnetCeiling, (11_000 * 2.5 + 8_000 * 10) / 1_000_000);
});

Deno.test("a notice that names another vendor sends nothing and reserves nothing", async () => {
  for (const consent of [granted("deepseek"), granted(null)]) {
    const h = harness({ consent });
    const { fetch, sent } = fakeFetch(() => claude("{}"));
    await run("plan", h, { plan: planRoute() }, fetch);
    assertEquals(sent.length, 0);
    assertEquals(h.reserved().length, 0);
    assertEquals(training(h).origin, "rules");
    assertEquals(training(h).fallback_reason, "ai_consent_not_granted");
  }
  const none = harness({
    consent: { consent: "not_granted", provider: "anthropic", noticeVersion: "x" },
  });
  const { fetch, sent } = fakeFetch(() => claude("{}"));
  await run("plan", none, { plan: planRoute() }, fetch);
  assertEquals(sent.length, 0);
});

Deno.test("a budget that refuses the place sends nothing", async () => {
  const h = harness({ reserve: false });
  const { fetch, sent } = fakeFetch(() => claude("{}"));
  await run("plan", h, { plan: planRoute() }, fetch);
  assertEquals(sent.length, 0);
  assertEquals(training(h).origin, "rules");
  assertEquals(training(h).fallback_reason, "ai_usage_limit");
});

Deno.test("an invalid plan is repaired once from the same cached prompt", async () => {
  const h = harness();
  const answers = [
    planWith((plan) => {
      (plan.workouts as { exercises: { slug: string }[] }[])[0].exercises[0].slug =
        "not-in-the-catalog";
    }),
    JSON.stringify(validPlan()),
  ];
  const { fetch, sent } = fakeFetch(() => claude(answers.shift()!));
  await run("plan", h, { plan: planRoute() }, fetch);
  assertEquals(sent.length, 2);
  const first = sent[0].body as { system: unknown; messages: { content: { text: string }[] }[] };
  const second = sent[1].body as typeof first;
  assertEquals(second.system, first.system);
  assertEquals(second.messages[0].content[0], first.messages[0].content[0]);
  assertEquals(second.messages[0].content.length, 2);
  assert(second.messages[0].content[1].text.includes("<invalid_candidate>"));
  assert(second.messages[0].content[1].text.includes("untrusted"));
  assertEquals(training(h).origin, "ai");
  // One reservation covered both attempts; both are in the recorded usage.
  assertEquals(h.reserved().length, 1);
  assertEquals(h.usage.length, 1);
  assertEquals(h.usage[0].inputUnits, 14_000);
  assertEquals(h.usage[0].estimatedCostUsd, 2 * (7000 * 2 + 2500 * 10) / 1_000_000);
  assertEquals(h.log, ["usage", "settle"]);
});

Deno.test("a plan still invalid after the repair becomes the rules plan, both calls billed", async () => {
  const h = harness();
  const bad = planWith((plan) => {
    plan.block_weeks = 99;
  });
  const { fetch, sent } = fakeFetch(() => claude(bad));
  const { events } = await run("plan", h, { plan: planRoute() }, fetch);
  assertEquals(sent.length, 2);
  assertEquals(training(h).origin, "rules");
  assertNotEquals(training(h).fallback_reason, null);
  assertEquals(h.usage[0].inputUnits, 14_000);
  assertEquals(h.log, ["usage", "settle"]);
  assert(events.some((event) => event.event === "onboarding_plan_model_fallback"));
});

Deno.test("a plan that names a model or company is repaired, then dropped (D11)", async () => {
  const named = planWith((plan) => {
    plan.assessment = "Claude by Anthropic suggests this block for you.";
  });
  const h = harness();
  const { fetch, sent } = fakeFetch(() => claude(named));
  await run("plan", h, { plan: planRoute() }, fetch);
  assertEquals(sent.length, 2);
  assertEquals(training(h).origin, "rules");
  assertEquals(training(h).fallback_reason, "names_model_or_company");
  const again = harness();
  const answers = [named, JSON.stringify(validPlan())];
  const second = fakeFetch(() => claude(answers.shift()!));
  await run("plan", again, { plan: planRoute() }, second.fetch);
  assertEquals(training(again).origin, "ai");
  // The stored provenance names the vendor and model for the audit trail; nothing the
  // athlete reads does.
  const { provider: _provider, model: _model, ...athleteFacing } = training(again);
  assert(!namesModelOrCompany(JSON.stringify(athleteFacing)));
});

Deno.test("the rules the model reads name no model or company beyond the instruction not to", () => {
  const prepared = preparePlan(
    planRoute(),
    answersFor(syntheticDrafts.plan),
    catalog,
    null,
    null,
  );
  assertEquals(prepared.kind, "ready");
  if (prepared.kind !== "ready") return;
  const rules = prepared.prepared.system.split("\n").filter((line) =>
    !line.startsWith("- Never name an AI model")
  ).join("\n");
  assert(!namesModelOrCompany(rules));
  assert(prepared.prepared.system.includes("Never name an AI model"));
});

Deno.test("the plan shape is structure only and the contract keeps its limits", () => {
  const text = JSON.stringify(onboardingPlanJsonSchema);
  for (const keyword of ["maxLength", "minimum", "maxItems", "minLength"]) {
    assert(!text.includes(keyword), keyword);
  }
  const required = (onboardingPlanJsonSchema as { required: string[] }).required;
  assertEquals(required.length, 14);
});

// --- Budget outcomes ---------------------------------------------------------------------------

type Outcome = {
  name: string;
  respond: () => Response;
  spend: "none" | "billed" | "unknown";
  fallback: string;
};
const outcomes: Outcome[] = [
  {
    name: "429",
    respond: () => jsonResponse({ error: { type: "rate_limit_error" } }, 429),
    spend: "none",
    fallback: "provider_rate_limited",
  },
  {
    name: "529",
    respond: () => jsonResponse({ error: { type: "overloaded_error" } }, 529),
    spend: "none",
    fallback: "provider_http_error",
  },
  {
    name: "503",
    respond: () => jsonResponse({}, 503),
    spend: "none",
    fallback: "provider_http_error",
  },
  {
    name: "HTTP 500",
    respond: () => jsonResponse({}, 500),
    spend: "none",
    fallback: "provider_http_error",
  },
  {
    name: "refusal",
    respond: () =>
      jsonResponse(
        claudeMessage({ content: [], stop_reason: "refusal" }, {
          input_tokens: 6000,
          output_tokens: 3,
        }),
      ),
    spend: "billed",
    fallback: "provider_refused",
  },
];

for (const outcome of outcomes) {
  Deno.test(
    `plan: ${outcome.name} ${
      outcome.spend === "none" ? "releases the place" : "settles at the real cost"
    }`,
    async () => {
      const h = harness();
      const { fetch, sent } = fakeFetch(outcome.respond);
      const { events } = await run("plan", h, { plan: planRoute() }, fetch);
      assertEquals(sent.length, 1, "no repair for an error or a refusal");
      assertEquals(training(h).origin, "rules");
      assertEquals(training(h).fallback_reason, outcome.fallback);
      assertEquals(h.settled(), 1);
      assert(!h.log.includes("keep"));
      if (outcome.spend === "none") {
        assertEquals(h.usage.length, 0);
        assertEquals(h.log, ["settle"]);
      } else {
        assertEquals(h.usage.length, 1);
        assertEquals(h.usage[0].estimatedCostUsd, (6000 * 2 + 3 * 10) / 1_000_000);
        assertEquals(h.log, ["usage", "settle"]);
      }
      assert(events.some((event) => event.event === "onboarding_plan_model_fallback"));
    },
  );
}

Deno.test("plan: a lost connection keeps the place at its ceiling", async () => {
  const h = harness();
  const { fetch, sent } = fakeFetch(() => {
    throw new TypeError("connection reset");
  });
  await run("plan", h, { plan: planRoute() }, fetch);
  assertEquals(sent.length, 1);
  assertEquals(training(h).origin, "rules");
  assertEquals(h.usage.length, 0);
  assertEquals(h.log, ["keep"]);
  assertEquals(h.settled(), 0);
});

Deno.test("plan: a timeout keeps the place", async () => {
  const h = harness();
  const { fetch } = fakeFetch((sent) =>
    new Promise<Response>((_resolve, reject) =>
      sent.signal?.addEventListener(
        "abort",
        () => reject(new DOMException("aborted", "AbortError")),
      )
    )
  );
  await run("plan", h, { plan: planRoute({ TIMEOUT_MS: "1000" }) }, fetch);
  assertEquals(training(h).origin, "rules");
  assertEquals(training(h).fallback_reason, "provider_timeout");
  assertEquals(h.usage.length, 0);
  assertEquals(h.log, ["keep"]);
  assertEquals(h.settled(), 0);
});

Deno.test("plan: a repair is not sent when too little of the deadline is left", async () => {
  const h = harness();
  let clock = 0;
  const bad = planWith((plan) => {
    plan.block_weeks = 99;
  });
  const { fetch, sent } = fakeFetch(() => {
    clock += 115_000;
    return claude(bad);
  });
  await run("plan", h, { plan: planRoute() }, fetch, {
    gateway: { gateway: { fetch }, now: () => clock },
  });
  assertEquals(sent.length, 1);
  assertEquals(training(h).origin, "rules");
  assertEquals(training(h).fallback_reason, "provider_timeout");
  // The one answer that arrived is billed and recorded, then the place is given back.
  assertEquals(h.log, ["usage", "settle"]);
});

Deno.test("plan: a cut-off answer earns one repair; an unknown-cost repair keeps the place", async () => {
  const h = harness();
  let calls = 0;
  const { fetch, sent } = fakeFetch(() => {
    calls++;
    if (calls === 1) {
      return jsonResponse(
        claudeMessage({
          content: [{ type: "text", text: '{"title":"Cut' }],
          stop_reason: "max_tokens",
        }, {
          input_tokens: 7000,
          output_tokens: 8000,
        }),
      );
    }
    throw new TypeError("connection reset");
  });
  await run("plan", h, { plan: planRoute() }, fetch);
  assertEquals(sent.length, 2);
  assertEquals(training(h).origin, "rules");
  // The cut-off first answer is billed and recorded; the lost repair keeps the place.
  assertEquals(h.usage.length, 1);
  assertEquals(h.usage[0].estimatedCostUsd, (7000 * 2 + 8000 * 10) / 1_000_000);
  assertEquals([...h.log].sort(), ["keep", "usage"]);
  assertEquals(h.settled(), 0);
});

Deno.test("a long route timeout is bounded by the plan deadline and the clamp is logged", async () => {
  const h = harness();
  const { fetch, sent } = fakeFetch(() => claude(JSON.stringify(validPlan())));
  let clock = 1_000;
  const { events } = await run("plan", h, { plan: planRoute({ TIMEOUT_MS: "150000" }) }, fetch, {
    gateway: { gateway: { fetch }, now: () => clock++ },
  });
  assertEquals(sent.length, 1);
  assert(sent[0].signal !== null);
  const clamp = events.find((event) => event.event === "onboarding_plan_timeout_clamped");
  assert(clamp);
  assertEquals(clamp.fields.configuredMs, 150_000);
  assert((clamp.fields.appliedMs as number) < 150_000);
});

// --- Follow-up questions through the gateway ---------------------------------------------------

const questionsAnswer = (questions: unknown[]) =>
  claude(JSON.stringify({ questions }), {
    input_tokens: 900,
    output_tokens: 150,
  });

const oneQuestion = {
  category: "stalled_lift",
  question: "How often do you bench each week?",
  choices: ["Once", "Twice"],
};

Deno.test("questions go to Claude, are stored under the answers' hash and settle at the real cost", async () => {
  const h = harness({ draft: syntheticDrafts.questions });
  const { fetch, sent } = fakeFetch(() => questionsAnswer([oneQuestion]));
  const { body } = await run("questions", h, { questions: questionsRoute() }, fetch);
  assertEquals(sent.length, 1);
  const request = sent[0].body;
  assertEquals(request.max_tokens, 1500);
  assert(!("temperature" in request));
  assertEquals((request.system as { cache_control?: unknown }[])[0].cache_control, {
    type: "ephemeral",
  });
  assertEquals(h.reserved()[0].args.run_purpose, "onboarding_questions");
  assertEquals(body.questions.length, 1);
  assertEquals(body.skipped_reason, undefined);
  assertEquals(h.saved.size, 1);
  assertEquals(h.usage[0].provider, "anthropic");
  assertEquals(h.usage[0].estimatedCostUsd, (900 * 2 + 150 * 10) / 1_000_000);
  assertEquals(h.log, ["usage", "settle"]);
});

Deno.test("questions: another vendor's notice or an exhausted budget asks nothing and stores nothing", async () => {
  const wrong = harness({ draft: syntheticDrafts.questions, consent: granted("deepseek") });
  const a = fakeFetch(() => questionsAnswer([]));
  const first = await run("questions", wrong, { questions: questionsRoute() }, a.fetch);
  assertEquals(first.body.skipped_reason, "ai_consent_not_granted");
  assertEquals(a.sent.length, 0);
  assertEquals(wrong.reserved().length, 0);
  assertEquals(wrong.saved.size, 0);
  const broke = harness({ draft: syntheticDrafts.questions, reserve: false });
  const b = fakeFetch(() => questionsAnswer([]));
  const second = await run("questions", broke, { questions: questionsRoute() }, b.fetch);
  assertEquals(second.body.skipped_reason, "ai_usage_limit");
  assertEquals(b.sent.length, 0);
  assertEquals(broke.saved.size, 0);
});

for (const outcome of outcomes) {
  Deno.test(`questions: ${outcome.name} is not stored, so a retry may ask again`, async () => {
    const h = harness({ draft: syntheticDrafts.questions });
    const { fetch } = fakeFetch(outcome.respond);
    const { body } = await run("questions", h, { questions: questionsRoute() }, fetch);
    assertEquals(body.skipped_reason, outcome.fallback);
    assertEquals(body.questions, []);
    assertEquals(h.saved.size, 0);
    assertEquals(h.released.length, 1);
    assertEquals(h.settled(), 1);
    assert(!h.log.includes("keep"));
    assertEquals(h.usage.length, outcome.spend === "none" ? 0 : 1);
  });
}

Deno.test("questions: a lost connection keeps the place", async () => {
  const h = harness({ draft: syntheticDrafts.questions });
  const { fetch } = fakeFetch(() => {
    throw new TypeError("connection reset");
  });
  const { body } = await run("questions", h, { questions: questionsRoute() }, fetch);
  assertEquals(body.skipped_reason, "provider_http_error");
  assertEquals(h.log, ["keep"]);
  assertEquals(h.settled(), 0);
  assertEquals(h.saved.size, 0);
});

Deno.test("questions: out-of-scope or model-naming questions are dropped whole", async () => {
  for (
    const question of [
      { ...oneQuestion, question: "Does your old injury hurt when you bench?" },
      { ...oneQuestion, question: "Would Claude suggest more bench volume?" },
      { ...oneQuestion, choices: ["Ask Google", "Twice"] },
    ]
  ) {
    const h = harness({ draft: syntheticDrafts.questions });
    const { fetch } = fakeFetch(() => questionsAnswer([question]));
    const { body } = await run("questions", h, { questions: questionsRoute() }, fetch);
    assertEquals(body.questions, []);
    assertEquals(body.skipped_reason, "questions_invalid");
    // The answer was billed and is final for these answers.
    assertEquals(h.usage.length, 1);
    assertEquals(h.saved.size, 1);
  }
});

Deno.test("questions: no questions needed is a valid answer", async () => {
  const h = harness({ draft: syntheticDrafts.questions });
  const { fetch } = fakeFetch(() => questionsAnswer([]));
  const { body } = await run("questions", h, { questions: questionsRoute() }, fetch);
  assertEquals(body.skipped_reason, "no_questions_needed");
  assertEquals(h.saved.size, 1);
});

Deno.test("questions: the app's 45 s wait bounds a longer route timeout, and the clamp is logged", async () => {
  const h = harness({ draft: syntheticDrafts.questions });
  const { fetch, sent } = fakeFetch(() => questionsAnswer([]));
  const { events } = await run(
    "questions",
    h,
    { questions: questionsRoute({ TIMEOUT_MS: "90000" }) },
    fetch,
  );
  assert(sent[0].signal !== null);
  const clamp = events.find((event) => event.event === "onboarding_questions_timeout_clamped");
  assert(clamp);
  assertEquals(clamp.fields.configuredMs, 90_000);
  assertEquals(clamp.fields.appliedMs, 40_000);
  // A route at or under the bound is not clamped.
  const quiet = harness({ draft: syntheticDrafts.questions });
  const again = fakeFetch(() => questionsAnswer([]));
  const second = await run("questions", quiet, { questions: questionsRoute() }, again.fetch);
  assert(!second.events.some((event) => event.event === "onboarding_questions_timeout_clamped"));
});

Deno.test("questions: an unusable route asks through the settings path instead", async () => {
  const h = harness({ draft: syntheticDrafts.questions });
  const route = questionsRoute({
    MAX_OUTPUT_TOKENS: "32000",
    MODEL: "claude-opus-5-5",
    THINKING: "adaptive",
  });
  const answers = answersFor(syntheticDrafts.questions);
  // Opus at 32,000 tokens: USD 0.64 an answer.
  assertEquals(prepareQuestions(route, answers, null, null).kind, "unusable");
  const { fetch, sent } = fakeFetch(() => questionsAnswer([]));
  const { body, events } = await run("questions", h, { questions: route }, fetch);
  assertEquals(sent.length, 0);
  assertEquals(h.reserved().length, 0);
  assertEquals(h.reads(), 0);
  assertEquals(body.skipped_reason, "provider_mock");
  assert(events.some((event) => event.event === "onboarding_questions_route_unusable"));
});

// --- Mapping ----------------------------------------------------------------------------------

Deno.test("failures map to the codes the settings path uses", () => {
  assertEquals(failureCode("timeout", false), "provider_timeout");
  assertEquals(failureCode("rate_limited", false), "provider_rate_limited");
  assertEquals(failureCode("overloaded", false), "provider_http_error");
  assertEquals(failureCode("network", false), "provider_http_error");
  assertEquals(failureCode("provider_error", false), "provider_http_error");
  assertEquals(failureCode("invalid_output", true), "provider_response_truncated");
  assertEquals(failureCode("invalid_output", false), "provider_response_invalid");
  assertEquals(failureCode("refused", false), "provider_refused");
});

Deno.test("spend: an answer is billed, an HTTP error is not, a lost request is unknown", () => {
  const usage = {
    inputTokens: 1,
    outputTokens: 1,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
    costUsd: 0,
  };
  assertEquals(resultSpend({ ok: false, reason: "refused", usage }), "billed");
  assertEquals(resultSpend({ ok: false, reason: "invalid_output", usage }), "billed");
  assertEquals(resultSpend({ ok: false, reason: "rate_limited", usage: null }), "none");
  assertEquals(resultSpend({ ok: false, reason: "overloaded", usage: null }), "none");
  assertEquals(resultSpend({ ok: false, reason: "provider_error", usage: null }), "none");
  assertEquals(
    resultSpend({ ok: false, reason: "consent_provider_mismatch", usage: null }),
    "none",
  );
  assertEquals(resultSpend({ ok: false, reason: "timeout", usage: null }), "unknown");
  assertEquals(resultSpend({ ok: false, reason: "network", usage: null }), "unknown");
});

Deno.test("every eval athlete is feasible and the eval's default routes are usable", () => {
  const routes = evalRoutes((name) =>
    name === "ANTHROPIC_API_KEY" ? "synthetic-test-key" : undefined
  );
  assert(routes.plan && routes.questions);
  for (const [name, answers] of Object.entries(athletes)) {
    const plan = preparePlan(
      routes.plan,
      answers,
      catalog,
      health[name] ?? null,
      history[name] ?? null,
    );
    assertEquals(plan.kind, "ready", name);
    const questions = prepareQuestions(
      routes.questions,
      answers,
      health[name] ?? null,
      history[name] ?? null,
    );
    assertEquals(questions.kind, "ready", name);
  }
});

Deno.test("the gateway prompt and policies carry the screening outcome", () => {
  const route = planRoute();
  const answers = answersFor(syntheticDrafts.plan);
  const moderate = preparePlan(route, answers, catalog, null, null, "moderate_until_cleared");
  const cleared = preparePlan(route, answers, catalog, null, null);
  assertEquals(moderate.kind, "ready");
  assertEquals(cleared.kind, "ready");
  if (moderate.kind !== "ready" || cleared.kind !== "ready") return;
  assertEquals(moderate.prepared.policies.screening, "moderate_until_cleared");
  assertEquals(cleared.prepared.policies.screening, undefined);
  assert(moderate.prepared.system !== cleared.prepared.system, "the prompt names the cap");
});
