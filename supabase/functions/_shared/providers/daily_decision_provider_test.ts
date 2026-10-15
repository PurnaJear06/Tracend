import { assert, assertEquals, assertInstanceOf, assertRejects } from "jsr:@std/assert@1.0.14";
import {
  captureLogs,
  claudeMessage,
  envOf,
  fakeFetch,
  jsonResponse,
  routeFor,
  settings,
  syntheticKey,
} from "../ai/fakes.ts";
import type { AiFailure, AiRoute } from "../ai/types.ts";
import {
  type CoachDecisionV1,
  parseCoachDecision,
  type PolicyOutcome,
} from "../contracts/coach_decision_v1.ts";
import type { CoachModelRequest } from "./coach_model_provider.ts";
import {
  dailyDecisionConsent,
  dailyDecisionPath,
  dailyDecisionProviderFor,
  decisionCeilingUsd,
  decisionSystemPrompt,
  failedRunProvenance,
  GatewayDecisionProvider,
  gatewayFailureCode,
  groundingFault,
  maxReservableCeilingUsd,
  reserveDailyDecision,
} from "./daily_decision_provider.ts";
import { DeepseekCoachModelProvider } from "./deepseek_coach_model_provider.ts";
import { MockCoachModelProvider } from "./mock_coach_model_provider.ts";

const environment = (values: Record<string, string>) => ({ get: (name: string) => values[name] });

const request: CoachModelRequest = {
  decisionKind: "daily",
  featureSnapshotId: "snapshot-a5",
  policyEvaluationId: "policy-a5",
  policyOutcome: "maintain_only",
  permittedEvidence: ["APPROVED_PLAN_ACTIVE", "RECOVERY_WITHIN_BASELINE"],
  featureContext: {
    local_date: "2026-09-07",
    check_in: null,
    today_raw: { sleep_minutes: null, resting_hr_bpm: 58 },
  },
  missingData: [],
};

const validDecision = (overrides: Partial<CoachDecisionV1> = {}): CoachDecisionV1 => ({
  schema_version: "1.0",
  decision_kind: "daily",
  training: {
    action: "PROCEED_AS_PLANNED",
    summary: "Complete today's session at the approved effort.",
    today_adjustments: [],
  },
  nutrition: {
    action: "MAINTAIN_TARGETS",
    summary: "Keep your approved targets.",
    today_adjustments: [],
  },
  head_coach: {
    final_decision: "Train as planned.",
    reason: "Your recovery is within your recent baseline.",
  },
  evidence: [{
    code: "RECOVERY_WITHIN_BASELINE",
    label: "Your recovery is within your recent baseline.",
    source: "feature_snapshot",
  }],
  confidence: "medium",
  missing_data: [],
  risk_flags: [],
  change_proposals: [],
  ...overrides,
});

const claudeAnswer = (decision: unknown, usage: Record<string, unknown> = {}) =>
  jsonResponse(
    claudeMessage({ content: [{ type: "text", text: JSON.stringify(decision) }] }, usage),
  );

const evaluatedRoute = (values: Record<string, string> = {}) =>
  routeFor("daily_decision", { MAX_OUTPUT_TOKENS: "1800", EVALUATED: "true", ...values });

type RpcCall = { name: string; params: Record<string, unknown> };
const recordingRpc = (data: unknown) => {
  const calls: RpcCall[] = [];
  const rpc = (name: string, params: Record<string, unknown>) => {
    calls.push({ name, params });
    return Promise.resolve({ data, error: null });
  };
  return { rpc, calls };
};

// --- No route: today's path, unchanged ------------------------------------------------------

Deno.test("no daily_decision route keeps today's path; the mock stays the default", async () => {
  assertEquals(dailyDecisionPath(envOf({})), { kind: "legacy" });
  // An incomplete route (no key, no output limit) is no route.
  assertEquals(
    dailyDecisionPath(envOf(settings("daily_decision", { ANTHROPIC_API_KEY: "" }))).kind,
    "legacy",
  );
  assertEquals(
    dailyDecisionPath(envOf(settings("daily_decision", { MAX_OUTPUT_TOKENS: "" }))).kind,
    "legacy",
  );
  const provider = dailyDecisionProviderFor({ kind: "legacy" }, "granted", {
    environment: environment({}),
  });
  assertInstanceOf(provider, MockCoachModelProvider);
  const generated = await provider.generateDecision(request);
  assertEquals(
    [generated.provider, generated.model, generated.estimatedCostUsd],
    ["mock", "deterministic-mock-v2", 0],
  );
  assertEquals(generated.decision.training, {
    action: "PROCEED_AS_PLANNED",
    summary: "Complete the scheduled session at the approved effort.",
    today_adjustments: [],
  });
  assertEquals(generated.decision.evidence.map((item) => item.code), ["RECOVERY_WITHIN_BASELINE"]);
  assertInstanceOf(
    dailyDecisionProviderFor({ kind: "legacy" }, "not_granted", {
      environment: environment({ COACH_MODEL_PROVIDER: "deepseek" }),
    }),
    MockCoachModelProvider,
  );
});

Deno.test("no route: today's consent and fixed budget ceiling are used", async () => {
  const { rpc, calls } = recordingRpc(true);
  assertEquals(await dailyDecisionConsent({ kind: "legacy" }, rpc, "user-a5"), "granted");
  assertEquals(calls, [{
    name: "has_ai_coaching_consent",
    params: { target_user_id: "user-a5", consent_purpose: "daily_coaching" },
  }]);
  const reserved: unknown[][] = [];
  const budget = {
    reserve: (...args: unknown[]) => {
      reserved.push(args);
      return Promise.resolve(true);
    },
  } as unknown as Parameters<typeof reserveDailyDecision>[1];
  assertEquals(await reserveDailyDecision({ kind: "legacy" }, budget), true);
  assertEquals(reserved, [["daily_coaching"]]);
});

Deno.test("no route: today's DeepSeek request is sent byte for byte", async () => {
  const deepseekEnv = {
    COACH_MODEL_PROVIDER: "deepseek",
    COACH_AI_ENABLED: "true",
    DEEPSEEK_API_KEY: syntheticKey,
    DEEPSEEK_MODEL: "deepseek-flash",
  };
  const bodies: string[] = [];
  const recorder = ((_: string | URL | Request, init?: RequestInit) => {
    bodies.push(String(init?.body));
    return Promise.resolve(new Response("{}", { status: 500 }));
  }) as typeof fetch;
  const saved = globalThis.fetch;
  globalThis.fetch = recorder;
  try {
    const provider = dailyDecisionProviderFor(dailyDecisionPath(envOf(deepseekEnv)), "granted", {
      environment: environment(deepseekEnv),
    });
    assertInstanceOf(provider, DeepseekCoachModelProvider);
    await captureLogs(() => assertRejects(() => provider.generateDecision(request)));
  } finally {
    globalThis.fetch = saved;
  }
  const today = new DeepseekCoachModelProvider({
    apiKey: syntheticKey,
    model: "deepseek-flash",
    inputCostPerMillionUsd: 0.3,
    outputCostPerMillionUsd: 1.2,
    fetcher: recorder,
  });
  await captureLogs(() => assertRejects(() => today.generateDecision(request)));
  assertEquals(bodies.length, 2);
  assertEquals(bodies[0], bodies[1]);
});

Deno.test("no route: a failed run records today's provenance", () => {
  const legacy = { kind: "legacy" } as const;
  const cases: [Record<string, string>, boolean, string, string][] = [
    [{}, false, "mock", "deterministic-mock-v2"],
    [{ COACH_MODEL_PROVIDER: "deepseek" }, false, "mock", "deterministic-mock-v2"],
    [{}, true, "mock", "deterministic-mock-v1"],
    [{ COACH_MODEL_PROVIDER: "openai" }, true, "mock", "deterministic-mock-v1"],
    [
      { COACH_MODEL_PROVIDER: "deepseek", DEEPSEEK_MODEL: "deepseek-flash" },
      true,
      "deepseek",
      "deepseek-flash",
    ],
    [{ COACH_MODEL_PROVIDER: "deepseek" }, true, "deepseek", "unconfigured"],
    [
      { COACH_MODEL_PROVIDER: "groq", GROQ_MODEL: "qwen/qwen3.6-27b" },
      true,
      "groq",
      "qwen/qwen3.6-27b",
    ],
    [{ COACH_MODEL_PROVIDER: "gemini" }, true, "gemini", "unconfigured"],
  ];
  for (const [env, usedModel, provider, model] of cases) {
    assertEquals(failedRunProvenance(legacy, usedModel, environment(env)), { provider, model });
  }
});

// --- A route that has not passed its eval -----------------------------------------------------

Deno.test("an unevaluated route sends nothing: no consent, no budget, the mock answers", async () => {
  const path = dailyDecisionPath(envOf(settings("daily_decision")));
  assertEquals(path, { kind: "unevaluated" });
  const { rpc, calls } = recordingRpc(true);
  assertEquals(await dailyDecisionConsent(path, rpc, "user-a5"), "not_granted");
  assertEquals(calls, []);
  const budget = {
    reserve: () => {
      throw new Error("no reservation expected");
    },
  } as unknown as Parameters<typeof reserveDailyDecision>[1];
  assertEquals(await reserveDailyDecision(path, budget), false);
  assertInstanceOf(dailyDecisionProviderFor(path, "granted"), MockCoachModelProvider);
});

// --- Through the gateway -----------------------------------------------------------------------

Deno.test("gateway consent counts only for a notice naming the route's vendor", async () => {
  const path = { kind: "gateway", route: evaluatedRoute() } as const;
  const answer = (granted: boolean, provider: string | null) =>
    recordingRpc({ schema_version: "1.0", granted, provider, notice_version: "v6" });
  const anthropic = answer(true, "anthropic");
  assertEquals(await dailyDecisionConsent(path, anthropic.rpc, "user-a5"), "granted");
  assertEquals(anthropic.calls, [{
    name: "get_ai_consent_v2",
    params: { target_user_id: "user-a5", consent_purpose: "daily_decision" },
  }]);
  assertEquals(
    await dailyDecisionConsent(path, answer(true, "deepseek").rpc, "user-a5"),
    "not_granted",
  );
  assertEquals(await dailyDecisionConsent(path, answer(true, null).rpc, "user-a5"), "not_granted");
  assertEquals(
    await dailyDecisionConsent(path, answer(false, "anthropic").rpc, "user-a5"),
    "not_granted",
  );
  assertEquals(
    await dailyDecisionConsent(path, recordingRpc("broken").rpc, "user-a5"),
    "unavailable",
  );
  assertInstanceOf(dailyDecisionProviderFor(path, "not_granted"), MockCoachModelProvider);
  assertInstanceOf(dailyDecisionProviderFor(path, "granted"), GatewayDecisionProvider);
});

Deno.test("gateway budget reserves the route's ceiling from the price table", async () => {
  const sonnet = evaluatedRoute();
  const ceiling = decisionCeilingUsd(sonnet);
  // Sonnet 5.5: about 17,000 prompt tokens at the cache-write rate plus 1,800 output tokens.
  assert(ceiling !== null && ceiling > 0.05 && ceiling < 0.07, `ceiling ${ceiling}`);
  const haiku = decisionCeilingUsd(evaluatedRoute({ MODEL: "claude-haiku-5-5" }));
  assert(haiku !== null && haiku < ceiling, `haiku ${haiku}`);
  const reserved: unknown[][] = [];
  const budget = {
    reserve: (...args: unknown[]) => {
      reserved.push(args);
      return Promise.resolve(false);
    },
  } as unknown as Parameters<typeof reserveDailyDecision>[1];
  assertEquals(await reserveDailyDecision({ kind: "gateway", route: sonnet }, budget), false);
  assertEquals(reserved, [["daily_decision", ceiling]]);
});

Deno.test("gateway route whose worst case passes the per-call limit reserves nothing", async () => {
  const route = evaluatedRoute({
    MODEL: "claude-opus-5-5",
    THINKING: "adaptive",
    MAX_OUTPUT_TOKENS: "32000",
  });
  const ceiling = decisionCeilingUsd(route);
  assert(ceiling !== null && ceiling > maxReservableCeilingUsd, `ceiling ${ceiling}`);
  const budget = {
    reserve: () => {
      throw new Error("no reservation expected: the ceiling must never be clamped");
    },
  } as unknown as Parameters<typeof reserveDailyDecision>[1];
  const logged: unknown[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => void logged.push(args);
  try {
    assertEquals(await reserveDailyDecision({ kind: "gateway", route }, budget), false);
  } finally {
    console.error = original;
  }
  assertEquals(logged.length, 1);
});

Deno.test("gateway request: cached stable rules, delimited context, no sampling", async () => {
  const fake = fakeFetch(() =>
    claudeAnswer(validDecision(), {
      input_tokens: 900,
      output_tokens: 300,
      cache_read_input_tokens: 1200,
    })
  );
  const provider = new GatewayDecisionProvider(evaluatedRoute(), { fetch: fake.fetch });
  const { result: generated } = await captureLogs(() => provider.generateDecision(request));
  assertEquals(fake.sent.length, 1);
  const body = fake.sent[0].body;
  assertEquals(fake.sent[0].url, "https://api.anthropic.com/v1/messages");
  assertEquals(body.model, "claude-sonnet-5-5");
  assertEquals(body.max_tokens, 1800);
  assertEquals(body.thinking, { type: "between_tools" });
  for (const field of ["temperature", "top_p", "top_k", "tools", "tool_choice"]) {
    assertEquals(field in body, false, field);
  }
  assertEquals(body.system, [{
    type: "text",
    text: decisionSystemPrompt,
    cache_control: { type: "ephemeral" },
  }]);
  const format = (body.output_config as Record<string, Record<string, unknown>>).format;
  assertEquals(format.type, "json_schema");
  const messages = body.messages as { role: string; content: { text: string }[] }[];
  assertEquals(messages.length, 1);
  assertEquals(messages[0].role, "user");
  const text = messages[0].content[0].text;
  const context = JSON.parse(
    text.slice(text.indexOf("<coaching_context>\n") + 19, text.indexOf("\n</coaching_context>")),
  );
  // Nulls survive as null (the null contract), and every request field is in the context.
  assertEquals(context, {
    decision_kind: "daily",
    policy_outcome: "maintain_only",
    permitted_evidence: ["APPROVED_PLAN_ACTIVE", "RECOVERY_WITHIN_BASELINE"],
    feature_context: request.featureContext,
    missing_data: [],
  });
  assertEquals(generated.provider, "anthropic");
  assertEquals(generated.model, "claude-sonnet-5-5");
  assertEquals(generated.inputUnits, 2100);
  assertEquals(generated.outputUnits, 300);
  // 900 x 2 + 300 x 10 + 1200 x 0.1 per million tokens.
  assertEquals(generated.estimatedCostUsd, 0.00492);
  assertEquals(generated.decision, validDecision());
});

Deno.test("gateway failures map to today's error-code forms", async () => {
  const safeReason = /^[a-z][a-z0-9_]{0,60}$/;
  const cases: [() => Response, string][] = [
    [() => jsonResponse({}, 429, { "retry-after": "3" }), "anthropic_request_failed_status_429"],
    [() => jsonResponse({}, 529), "anthropic_request_failed"],
    [() => jsonResponse({}, 500), "anthropic_request_failed"],
    [() => jsonResponse(claudeMessage({ stop_reason: "refusal" })), "anthropic_refused"],
    [() => jsonResponse(claudeMessage()), "anthropic_response_invalid"],
    // A proposal breaks the schema (maxItems 0), so it never reaches the contract.
    [
      () => claudeAnswer(validDecision({ change_proposals: [{}] as never })),
      "anthropic_response_invalid",
    ],
  ];
  for (const [respond, code] of cases) {
    const fake = fakeFetch(respond);
    const provider = new GatewayDecisionProvider(evaluatedRoute(), { fetch: fake.fetch });
    await captureLogs(() => assertRejects(() => provider.generateDecision(request), Error, code));
    assert(safeReason.test(code), code);
  }
  const reasons: AiFailure[] = [
    "consent_provider_mismatch",
    "refused",
    "rate_limited",
    "overloaded",
    "timeout",
    "network",
    "invalid_output",
    "provider_error",
  ];
  for (const reason of reasons) {
    for (const vendor of ["anthropic", "deepseek", "groq", "gemini"] as const) {
      assert(safeReason.test(gatewayFailureCode(vendor, reason)), `${vendor} ${reason}`);
    }
  }
  assertEquals(gatewayFailureCode("anthropic", "timeout"), "anthropic_timeout");
});

Deno.test("gateway: an oversized context or a router route sends nothing", async () => {
  const fake = fakeFetch(() => claudeAnswer(validDecision()));
  const provider = new GatewayDecisionProvider(evaluatedRoute(), { fetch: fake.fetch });
  await assertRejects(
    () =>
      provider.generateDecision({ ...request, featureContext: { padding: "x".repeat(12_000) } }),
    Error,
    "anthropic_context_too_large",
  );
  assertEquals(fake.sent.length, 0);
  const router: AiRoute = routeFor("daily_decision", {
    PROVIDER: "openai_compatible",
    MODEL: "deepseek-flash",
    VENDOR: "router",
    BASE_URL: "https://router.example/v1",
    OPENAI_COMPATIBLE_API_KEY_DAILY_DECISION: syntheticKey,
    EVALUATED: "true",
  });
  let refused = "";
  try {
    new GatewayDecisionProvider(router);
  } catch (error) {
    refused = (error as Error).message;
  }
  assertEquals(refused, "daily_decision_route_invalid");
  assertEquals(failedRunProvenance({ kind: "gateway", route: evaluatedRoute() }, true), {
    provider: "anthropic",
    model: "claude-sonnet-5-5",
  });
});

Deno.test("the gateway prompt names no model or company (D11)", () => {
  const names = /claude|anthropic|sonnet|haiku|opus|deepseek|groq|qwen|gemini|google|openai|gpt/i;
  assertEquals(names.test(decisionSystemPrompt), false);
});

// --- The policy holds on the gateway path (B0's property test pattern) -----------------------

const policies: readonly PolicyOutcome[] = [
  "allow",
  "maintain_only",
  "daily_adjustment_only",
  "request_data",
  "escalate",
];
const trainingActions = [
  "PROCEED_AS_PLANNED",
  "ADJUST_TODAY",
  "GATHER_DATA",
  "REVIEW_PROPOSAL",
  "ESCALATE",
] as const;
const nutritionActions = [
  "MAINTAIN_TARGETS",
  "PRIORITIZE_PROTEIN",
  "GATHER_DATA",
  "REVIEW_PROPOSAL",
  "ESCALATE",
] as const;

// What each policy forbids, written out independently of the contract.
function forbidden(policy: PolicyOutcome, training: string, nutrition: string): boolean {
  switch (policy) {
    case "request_data":
      return training !== "GATHER_DATA";
    case "maintain_only":
      return training === "ADJUST_TODAY" || training === "REVIEW_PROPOSAL";
    case "escalate":
      return training !== "ESCALATE" || nutrition !== "ESCALATE";
    default:
      return false;
  }
}

Deno.test("no model answer the active policy forbids passes the validator", async () => {
  const permitted = ["RECOVERY_WITHIN_BASELINE"];
  let checked = 0;
  let accepted = 0;
  for (const policyOutcome of policies) {
    for (const training of trainingActions) {
      for (const nutrition of nutritionActions) {
        for (const cited of ["RECOVERY_WITHIN_BASELINE", "TRAINING_LOAD_ELEVATED"]) {
          const answer = validDecision({
            training: { action: training, summary: "Today's session.", today_adjustments: [] },
            nutrition: { action: nutrition, summary: "Today's food.", today_adjustments: [] },
            evidence: [{ code: cited, label: "Evidence.", source: "feature_snapshot" }],
          });
          const fake = fakeFetch(() => claudeAnswer(answer));
          const provider = new GatewayDecisionProvider(evaluatedRoute(), { fetch: fake.fetch });
          const { result: generated } = await captureLogs(() =>
            provider.generateDecision({ ...request, policyOutcome, permittedEvidence: permitted })
          );
          // coach-decide stores a decision only after this check.
          let decision: CoachDecisionV1 | null = null;
          try {
            decision = parseCoachDecision(generated.decision, permitted, policyOutcome);
          } catch {
            decision = null;
          }
          const label = `${policyOutcome} ${training}/${nutrition} cites ${cited}`;
          if (forbidden(policyOutcome, training, nutrition) || !permitted.includes(cited)) {
            assertEquals(decision, null, label);
          } else {
            assert(decision !== null, label);
            accepted++;
          }
          checked++;
        }
      }
    }
  }
  assertEquals(checked, policies.length * trainingActions.length * nutritionActions.length * 2);
  assert(accepted > 0);
});

// --- Grounding --------------------------------------------------------------------------------

Deno.test("grounding: every number must come from the request data or the code reference", () => {
  const groundingRequest: CoachModelRequest = {
    ...request,
    missingData: ["health_context"],
    featureContext: {
      local_date: "2026-09-07",
      active_plan_version_id: "00000000-0000-4000-8000-000000000015",
      scores: { recovery: 34, acwr: 1.62, sleep_debt_minutes: 1800, weight_trend: -0.0714 },
      check_in: { energy: 2, pain_severity: 0 },
      eligibility: { detail: "1 comparable session(s), 33% adherence." },
    },
  };
  const withText = (reason: string, missing = ["health_context"]) =>
    validDecision({
      head_coach: { final_decision: "Keep your approved plan.", reason },
      missing_data: missing,
    });
  const fault = (reason: string, missing?: string[]) =>
    groundingFault(withText(reason, missing), groundingRequest);
  for (
    const grounded of [
      "Recovery is 34, below 40, and ACWR is 1.62 (above 1.5).",
      "Energy 2.0 today; 33% adherence over 1 session; 1,800 minutes of sleep debt.",
      "Your weight trend is -0.0714 kg/day over 7 days.",
      "No numbers at all.",
    ]
  ) assertEquals(fault(grounded), null, grounded);
  // Dates and ids supply no quantities, and a number is matched whole, never as a substring.
  for (
    const ungrounded of [
      "Trim volume by 15%.",
      "Rest for 9 minutes.",
      "Recovery is 3.",
      "Recovery is 340.",
      "ACWR is 1.6.",
      "Aim for 2026 steps.",
    ]
  ) assertEquals(fault(ungrounded), "ungrounded_number", ungrounded);
  assertEquals(fault("Sonnet suggests rest."), "names_model_or_company");
  assertEquals(fault("Keep going.", []), "missing_data_dropped");
});
