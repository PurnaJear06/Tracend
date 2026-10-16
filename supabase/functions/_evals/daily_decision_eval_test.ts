// The daily decision eval's scoring, offline: a fake Claude answers each day with the
// deterministic decision (or a broken one), so the gates are checked without a key or a network.

import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import {
  captureLogs,
  claudeMessage,
  fakeFetch,
  jsonResponse,
  type Sent,
} from "../_shared/ai/fakes.ts";
import { parseCoachDecision } from "../_shared/contracts/coach_decision_v1.ts";
import type { CoachModelRequest } from "../_shared/providers/coach_model_provider.ts";
import { MockCoachModelProvider } from "../_shared/providers/mock_coach_model_provider.ts";
import { decisionCases, runEval } from "./daily_decision_eval.ts";

const env = (values: Record<string, string> = {}) => (name: string) =>
  ({ ANTHROPIC_API_KEY: "synthetic-test-key", ...values } as Record<string, string>)[name];

function contextOf(sent: Sent): CoachModelRequest {
  const text = (sent.body.messages as { content: { text: string }[] }[])[0].content[0].text;
  const context = JSON.parse(
    text.slice(text.indexOf("<coaching_context>\n") + 19, text.indexOf("\n</coaching_context>")),
  );
  return {
    decisionKind: context.decision_kind,
    featureSnapshotId: "eval",
    policyEvaluationId: "eval",
    policyOutcome: context.policy_outcome,
    permittedEvidence: context.permitted_evidence,
    featureContext: context.feature_context,
    missingData: context.missing_data,
  };
}

const answering = (edit: (decision: Record<string, unknown>) => Record<string, unknown>) =>
  fakeFetch(async (sent) => {
    const { decision } = await new MockCoachModelProvider().generateDecision(contextOf(sent));
    return jsonResponse(
      claudeMessage({ content: [{ type: "text", text: JSON.stringify(edit({ ...decision })) }] }),
    );
  });

Deno.test("eval days follow the SQL rules and the deterministic decision accepts them all", async () => {
  const cases = decisionCases();
  assertEquals(cases.length, 13);
  const byName = Object.fromEntries(cases.map((item) => [item.name, item.request]));
  assertEquals(byName["recorded-day"].policyOutcome, "maintain_only");
  assertEquals(byName["recorded-day"].permittedEvidence, [
    "APPROVED_PLAN_ACTIVE",
    "HEALTH_CONTEXT_AVAILABLE",
    "RECOVERY_WITHIN_BASELINE",
    "SLEEP_QUALITY_GOOD",
    "WEIGHT_STABLE",
    "NUTRITION_ON_TRACK",
    "DATA_CONFIDENCE_HIGH",
  ]);
  assertEquals(byName["no-check-in-no-health"].missingData, [
    "recovery_check_in",
    "health_context",
  ]);
  assertEquals(byName["pain-escalation"].policyOutcome, "escalate");
  assert(byName["elevated-load"].permittedEvidence.includes("TRAINING_LOAD_ELEVATED"));
  assertEquals(byName["scores-unavailable"].featureContext.scores_unavailable, true);
  for (const item of cases) {
    const { decision } = await new MockCoachModelProvider().generateDecision(item.request);
    parseCoachDecision(decision, item.request.permittedEvidence, item.request.policyOutcome);
  }
});

Deno.test("eval gates pass when every answer is valid and grounded", async () => {
  const fake = answering((decision) => decision);
  const { result } = await captureLogs(() => runEval(env(), { fetch: fake.fetch }, () => {}));
  assertEquals(result.route.model, "claude-sonnet-5-5");
  assertEquals(result.summary.answers, 13);
  assertEquals(result.summary.valid, 13);
  assertEquals(result.summary.training_action_matches_reference, 13);
  assertEquals(Object.values(result.gates).every(Boolean), true);
  assertEquals(result.stopped_at_spend_limit, false);
});

Deno.test("eval gates catch a missed escalation and a model name", async () => {
  const fake = answering((decision) => ({
    ...decision,
    training: { action: "PROCEED_AS_PLANNED", summary: "Train as planned.", today_adjustments: [] },
    head_coach: { final_decision: "Claude says train.", reason: "Recovery is fine." },
  }));
  const { result } = await captureLogs(() => runEval(env(), { fetch: fake.fetch }, () => {}));
  assertEquals(result.gates.every_escalation_escalates, false);
  assertEquals(result.gates.no_model_or_company_names, false);
  assert(result.summary.failures["contract:policy_requires_escalation"] >= 2);
});

Deno.test("eval stops before a call that could pass its spend limit", async () => {
  const fake = answering((decision) => decision);
  const { result } = await captureLogs(() =>
    runEval(env({ EVAL_MAX_USD: "0.0001" }), { fetch: fake.fetch }, () => {})
  );
  assertEquals(result.stopped_at_spend_limit, true);
  assertEquals(fake.sent.length, 0);
});

Deno.test("eval retries a transport failure, never a model answer", async () => {
  let calls = 0;
  const fake = fakeFetch(async (sent) => {
    calls++;
    if (calls === 1) return jsonResponse({}, 529);
    const { decision } = await new MockCoachModelProvider().generateDecision(contextOf(sent));
    return jsonResponse(
      claudeMessage({ content: [{ type: "text", text: JSON.stringify(decision) }] }),
    );
  });
  const { result } = await captureLogs(() =>
    runEval(env({ EVAL_ATTEMPTS: "3" }), { fetch: fake.fetch }, () => {})
  );
  assertEquals(result.summary.valid, 13);
  assertEquals(result.summary.transport_retries, 1);
  assertEquals(fake.sent.length, 14);
  const broken = answering((decision) => ({ ...decision, change_proposals: [{}] }));
  const { result: invalid } = await captureLogs(() =>
    runEval(env({ EVAL_ATTEMPTS: "3" }), { fetch: broken.fetch }, () => {})
  );
  assertEquals(invalid.summary.transport_retries, 0);
  assertEquals(broken.sent.length, 13);
});

Deno.test("eval reserves every attempt of a day against its spend limit", async () => {
  const fake = answering((decision) => decision);
  // One request can cost about USD 0.06 (Sonnet): 0.1 allows one attempt per day, not three.
  const { result: one } = await captureLogs(() =>
    runEval(env({ EVAL_MAX_USD: "0.1" }), { fetch: fake.fetch }, () => {})
  );
  assert(one.summary.answers > 0);
  const { result: three } = await captureLogs(() =>
    runEval(env({ EVAL_MAX_USD: "0.1", EVAL_ATTEMPTS: "3" }), { fetch: fake.fetch }, () => {})
  );
  assertEquals(three.summary.answers, 0);
  assertEquals(three.stopped_at_spend_limit, true);
});

Deno.test("eval counts an attempt that lost its usage at the full ceiling and says at most", async () => {
  // The first request of the run times out, so nothing says what it cost.
  let calls = 0;
  const fake = fakeFetch(async (sent) => {
    calls++;
    if (calls === 1) throw new TypeError("connection dropped");
    const { decision } = await new MockCoachModelProvider().generateDecision(contextOf(sent));
    return jsonResponse(
      claudeMessage({ content: [{ type: "text", text: JSON.stringify(decision) }] }),
    );
  });
  const { result } = await captureLogs(() =>
    runEval(env({ EVAL_ATTEMPTS: "2" }), { fetch: fake.fetch }, () => {})
  );
  const first = result.results[0];
  assertEquals(first.attempts, 2);
  assertEquals(first.cost_known, false);
  // The lost attempt counts at the ceiling, so the day costs more than its answered attempt.
  const answered = result.results[1];
  assert(first.cost_usd > answered.cost_usd * 5);
  assertEquals(result.summary.attempts_with_unknown_cost, 1);
  assert(result.summary.spend.startsWith("at most $"));
  const clean = answering((decision) => decision);
  const { result: exact } = await captureLogs(() =>
    runEval(env(), { fetch: clean.fetch }, () => {})
  );
  assertEquals(exact.summary.attempts_with_unknown_cost, 0);
  assert(exact.summary.spend.startsWith("$"));
});
