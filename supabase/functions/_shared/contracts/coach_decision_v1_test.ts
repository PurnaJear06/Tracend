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
