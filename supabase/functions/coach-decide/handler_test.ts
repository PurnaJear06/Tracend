// coach-decide end to end with fake Supabase clients and a fake model: which run is stored and
// what happens to the AI budget place on each outcome.

import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import {
  captureLogs,
  claudeMessage,
  fakeFetch,
  jsonResponse,
  routeFor,
} from "../_shared/ai/fakes.ts";
import type { CoachDecisionV1 } from "../_shared/contracts/coach_decision_v1.ts";
import type { DailyDecisionPath } from "../_shared/providers/daily_decision_provider.ts";
import { type Auth, coachDecideHandler } from "./handler.ts";

type Call = { name: string; params: Record<string, unknown> };

const features = { local_date: "2026-09-07", scores: { recovery: 68, sleep_quality: 93 } };
const prepared = {
  replayed: false,
  feature_snapshot_id: "00000000-0000-4000-8000-0000000000a1",
  policy_evaluation_id: "00000000-0000-4000-8000-0000000000a2",
  policy_outcome: "maintain_only",
  permitted_evidence: ["APPROVED_PLAN_ACTIVE", "RECOVERY_WITHIN_BASELINE"],
  missing_data: [],
};

function fakeAuth(options: { consentVendor?: string | null; snapshot?: boolean } = {}) {
  const calls: Call[] = [];
  const answers: Record<string, unknown> = {
    has_ai_coaching_consent: true,
    get_ai_consent_v2: {
      schema_version: "1.0",
      granted: true,
      provider: options.consentVendor === undefined ? "anthropic" : options.consentVendor,
      notice_version: "ai-coaching-v6",
    },
    prepare_daily_coaching: prepared,
    reserve_ai_budget: "reservation-legacy",
    reserve_ai_budget_v2: "reservation-gateway",
    settle_ai_budget: null,
    persist_daily_coaching_result_v2: { decision_id: "decision-1" },
    persist_failed_coaching_run_v2: { model_run_id: "run-1" },
  };
  const rpc = (name: string, params: Record<string, unknown>) => {
    calls.push({ name, params });
    return Promise.resolve({ data: answers[name] ?? null, error: null });
  };
  const query = {
    select: () => query,
    eq: () => query,
    single: () =>
      Promise.resolve(
        options.snapshot === false
          ? { data: null, error: { message: "missing" } }
          : { data: { features }, error: null },
      ),
  };
  const auth = {
    userId: "00000000-0000-4000-8000-0000000000b1",
    userEmail: "athlete@example.test",
    userClient: {},
    serviceClient: { rpc, from: () => query },
  } as unknown as Auth;
  return { auth, calls };
}

const request = () =>
  new Request("https://edge.test/coach-decide", {
    method: "POST",
    body: JSON.stringify({
      schema_version: "1.0",
      local_date: "2026-09-07",
      timezone: "Asia/Kolkata",
      idempotency_key: "00000000-0000-4000-8000-0000000000c1",
    }),
  });

const gateway = (): DailyDecisionPath => ({
  kind: "gateway",
  route: routeFor("daily_decision", { EVALUATED: "true", MAX_OUTPUT_TOKENS: "1800" }),
});

const decision = (reason: string): CoachDecisionV1 => ({
  schema_version: "1.0",
  decision_kind: "daily",
  training: {
    action: "PROCEED_AS_PLANNED",
    summary: "Train as planned today.",
    today_adjustments: [],
  },
  nutrition: { action: "MAINTAIN_TARGETS", summary: "Keep your targets.", today_adjustments: [] },
  head_coach: { final_decision: "Keep your approved plan.", reason },
  evidence: [{
    code: "RECOVERY_WITHIN_BASELINE",
    label: "Your recovery is within your recent baseline.",
    source: "feature_snapshot",
  }],
  confidence: "medium",
  missing_data: [],
  risk_flags: [],
  change_proposals: [],
});

const claude = (reason: string) =>
  jsonResponse(
    claudeMessage({ content: [{ type: "text", text: JSON.stringify(decision(reason)) }] }),
  );

async function run(
  options: {
    path: () => DailyDecisionPath;
    respond?: () => Response | Promise<Response>;
    consentVendor?: string | null;
    snapshot?: boolean;
  },
) {
  const { auth, calls } = fakeAuth(options);
  const fake = fakeFetch(options.respond ?? (() => claude("Your recovery score is 68.")));
  const handler = coachDecideHandler({
    requireAuth: () => Promise.resolve(auth),
    path: options.path,
    provider: { environment: { get: () => undefined }, gateway: { fetch: fake.fetch } },
  });
  const { result: response } = await captureLogs(() => handler(request()));
  const body = await response.json();
  const named = (name: string) => calls.filter((call) => call.name === name);
  return { status: response.status, body, calls, named, sent: fake.sent.length };
}

Deno.test("no route: the mock answers, the budget place is settled, as today", async () => {
  const result = await run({ path: () => ({ kind: "legacy" }) });
  assertEquals(result.status, 200);
  assertEquals(result.named("has_ai_coaching_consent").length, 1);
  assertEquals(result.named("reserve_ai_budget")[0].params.run_purpose, "daily_coaching");
  const persisted = result.named("persist_daily_coaching_result_v2")[0].params;
  assertEquals([persisted.run_provider, persisted.run_model], ["mock", "deterministic-mock-v2"]);
  assertEquals(result.named("settle_ai_budget").length, 1);
  assertEquals(result.sent, 0);
});

Deno.test("no route: a failure keeps the budget place open, as today", async () => {
  const result = await run({ path: () => ({ kind: "legacy" }), snapshot: false });
  assertEquals(result.status, 503);
  const failed = result.named("persist_failed_coaching_run_v2")[0].params;
  assertEquals(failed.error_code, "feature_context_unavailable");
  assertEquals([failed.run_provider, failed.run_model], ["mock", "deterministic-mock-v1"]);
  assertEquals(result.named("settle_ai_budget").length, 0);
});

Deno.test("gateway: a grounded answer is stored with its vendor, model and cost", async () => {
  const result = await run({ path: gateway });
  assertEquals(result.status, 200);
  assertEquals(result.named("get_ai_consent_v2")[0].params.consent_purpose, "daily_decision");
  const reserve = result.named("reserve_ai_budget_v2")[0].params;
  assertEquals(reserve.run_purpose, "daily_decision");
  assert(typeof reserve.ceiling_usd === "number" && reserve.ceiling_usd < 0.1);
  const persisted = result.named("persist_daily_coaching_result_v2")[0].params;
  assertEquals([persisted.run_provider, persisted.run_model], ["anthropic", "claude-sonnet-5-5"]);
  assertEquals(persisted.run_estimated_cost_usd, 0.004);
  assertEquals(result.named("settle_ai_budget").length, 1);
});

Deno.test("gateway: unbilled failures release the budget place", async () => {
  const cases: [Parameters<typeof run>[0], string, number][] = [
    [
      { path: gateway, respond: () => jsonResponse({}, 429) },
      "anthropic_request_failed_status_429",
      1,
    ],
    [{ path: gateway, respond: () => jsonResponse({}, 529) }, "anthropic_request_failed", 1],
    [{ path: gateway, respond: () => jsonResponse({}, 500) }, "anthropic_request_failed", 1],
    [{ path: gateway, snapshot: false }, "feature_context_unavailable", 0],
  ];
  for (const [options, code, sent] of cases) {
    const result = await run(options);
    assertEquals(result.status, 503, code);
    const failed = result.named("persist_failed_coaching_run_v2")[0].params;
    assertEquals([failed.error_code, failed.run_provider], [code, "anthropic"]);
    assertEquals(result.named("settle_ai_budget").length, 1, code);
    assertEquals(result.sent, sent, code);
  }
});

Deno.test("gateway: billed or unknown spend keeps the budget place open", async () => {
  const cases: [Parameters<typeof run>[0], string][] = [
    // Rejected after an answer arrived (billed).
    [{ path: gateway, respond: () => claude("Your recovery score is 72.") }, "ungrounded_number"],
    [{ path: gateway, respond: () => jsonResponse(claudeMessage()) }, "anthropic_response_invalid"],
    [
      { path: gateway, respond: () => jsonResponse(claudeMessage({ stop_reason: "refusal" })) },
      "anthropic_refused",
    ],
    // The connection broke: the request may have been answered.
    [
      { path: gateway, respond: () => Promise.reject(new TypeError("reset")) },
      "anthropic_request_failed",
    ],
  ];
  for (const [options, code] of cases) {
    const result = await run(options);
    assertEquals(result.status, 503, code);
    assertEquals(result.named("persist_failed_coaching_run_v2")[0].params.error_code, code);
    assertEquals(result.named("persist_daily_coaching_result_v2").length, 0, code);
    assertEquals(result.named("settle_ai_budget").length, 0, code);
  }
});

Deno.test("gateway: a notice naming another vendor gets the deterministic decision", async () => {
  const result = await run({ path: gateway, consentVendor: "deepseek" });
  assertEquals(result.status, 200);
  assertEquals(result.sent, 0);
  assertEquals(result.named("reserve_ai_budget_v2").length, 0);
  const persisted = result.named("persist_daily_coaching_result_v2")[0].params;
  assertEquals(persisted.run_provider, "mock");
});
