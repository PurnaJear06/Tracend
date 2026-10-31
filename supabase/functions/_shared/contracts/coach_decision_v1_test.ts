import { parseCoachDecision } from "./coach_decision_v1.ts";
import { MockCoachModelProvider } from "../providers/mock_coach_model_provider.ts";

Deno.test("validated mock decision cites only permitted evidence", async () => {
  const { decision } = await new MockCoachModelProvider().generateDecision({
    decisionKind: "daily",
    featureSnapshotId: "snapshot-1",
    policyEvaluationId: "policy-1",
    policyOutcome: "maintain_only",
    permittedEvidence: ["RECOVERY_WITHIN_BASELINE"],
    featureContext: {},
    missingData: [],
  });

  const parsed = parseCoachDecision(
    decision,
    ["RECOVERY_WITHIN_BASELINE"],
    "maintain_only",
  );
  if (parsed.training.action !== "PROCEED_AS_PLANNED") {
    throw new Error("Expected the approved plan to remain active.");
  }
});

Deno.test("unknown fields reject the whole decision", async () => {
  const { decision } = await new MockCoachModelProvider().generateDecision({
    decisionKind: "daily",
    featureSnapshotId: "snapshot-1",
    policyEvaluationId: "policy-1",
    policyOutcome: "request_data",
    permittedEvidence: [],
    featureContext: {},
    missingData: ["recovery_check_in"],
  });

  let rejected = false;
  try {
    parseCoachDecision({ ...decision, hidden_mutation: true }, [], "request_data");
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("Unknown output must be rejected.");
});

Deno.test("unsupported evidence rejects the whole decision", async () => {
  const { decision } = await new MockCoachModelProvider().generateDecision({
    decisionKind: "daily",
    featureSnapshotId: "snapshot-1",
    policyEvaluationId: "policy-1",
    policyOutcome: "maintain_only",
    permittedEvidence: ["RECOVERY_WITHIN_BASELINE"],
    featureContext: {},
    missingData: [],
  });

  let rejected = false;
  try {
    parseCoachDecision(decision, [], "maintain_only");
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("Unsupported evidence must be rejected.");
});

Deno.test("policy prevents a same-day adjustment in maintain-only mode", async () => {
  const { decision: base } = await new MockCoachModelProvider().generateDecision({
    decisionKind: "daily",
    featureSnapshotId: "snapshot-1",
    policyEvaluationId: "policy-1",
    policyOutcome: "maintain_only",
    permittedEvidence: ["RECOVERY_WITHIN_BASELINE"],
    featureContext: {},
    missingData: [],
  });
  const decision = {
    ...base,
    training: { ...base.training, action: "ADJUST_TODAY" },
  };

  let rejected = false;
  try {
    parseCoachDecision(decision, ["RECOVERY_WITHIN_BASELINE"], "maintain_only");
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("Policy widening must be rejected.");
});

const restRequest = (code: string) => ({
  decisionKind: "daily" as const,
  featureSnapshotId: "snapshot-1",
  policyEvaluationId: "policy-1",
  policyOutcome: "rest_as_chosen" as const,
  permittedEvidence: ["APPROVED_PLAN_ACTIVE", "RECOVERY_WITHIN_BASELINE", code],
  featureContext: {},
  missingData: [],
});

Deno.test("a rest the athlete chose can never proceed as planned, and a rest is never declared otherwise", async () => {
  for (const code of ["ATHLETE_UNAVAILABLE_TODAY", "TRAINING_PAUSED"]) {
    const request = restRequest(code);
    const { decision } = await new MockCoachModelProvider().generateDecision(request);
    const parsed = parseCoachDecision(decision, request.permittedEvidence, "rest_as_chosen");
    if (parsed.training.action !== "REST_AS_CHOSEN") throw new Error("expected a rest");
    if (parsed.evidence[0]?.code !== code) throw new Error(`expected ${code} cited`);
    const proceeding = {
      ...decision,
      training: { ...decision.training, action: "PROCEED_AS_PLANNED" },
    };
    let refused = "";
    try {
      parseCoachDecision(proceeding, request.permittedEvidence, "rest_as_chosen");
    } catch (error) {
      refused = (error as Error).message;
    }
    if (refused !== "policy_requires_rest_as_chosen") throw new Error(refused || "accepted");
    let outside = "";
    try {
      parseCoachDecision(decision, request.permittedEvidence, "maintain_only");
    } catch (error) {
      outside = (error as Error).message;
    }
    if (outside !== "rest_not_chosen") throw new Error(outside || "accepted");
  }
});
