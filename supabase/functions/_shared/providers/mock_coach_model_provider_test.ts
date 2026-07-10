import { MockCoachModelProvider } from "./mock_coach_model_provider.ts";

Deno.test("mock provider maintains the plan when recovery evidence exists", async () => {
  const provider = new MockCoachModelProvider();
  const { decision } = await provider.generateDecision({
    decisionKind: "daily",
    featureSnapshotId: "snapshot-fixture-1",
    policyEvaluationId: "policy-fixture-1",
    policyOutcome: "maintain_only",
    permittedEvidence: ["RECOVERY_WITHIN_BASELINE"],
    featureContext: {},
    missingData: [],
  });

  if (decision.training.action !== "PROCEED_AS_PLANNED") {
    throw new Error(`Unexpected action: ${decision.training.action}`);
  }
  if (decision.change_proposals.length !== 0) {
    throw new Error(
      "The Phase 1 mock must never create a persistent proposal.",
    );
  }
});

Deno.test("mock provider requests data when recovery evidence is absent", async () => {
  const provider = new MockCoachModelProvider();
  const { decision } = await provider.generateDecision({
    decisionKind: "daily",
    featureSnapshotId: "snapshot-fixture-2",
    policyEvaluationId: "policy-fixture-2",
    policyOutcome: "request_data",
    permittedEvidence: [],
    featureContext: {},
    missingData: ["recovery_check_in"],
  });

  if (decision.training.action !== "GATHER_DATA") {
    throw new Error(`Unexpected action: ${decision.training.action}`);
  }
  if (!decision.missing_data.includes("recovery_check_in")) {
    throw new Error("Missing recovery data must be explicit.");
  }
});

Deno.test("safety escalation stops routine coaching without a proposal", async () => {
  const provider = new MockCoachModelProvider();
  const { decision } = await provider.generateDecision({
    decisionKind: "daily",
    featureSnapshotId: "snapshot-safety-1",
    policyEvaluationId: "policy-safety-1",
    policyOutcome: "escalate",
    permittedEvidence: ["CHECK_IN_SAFETY_ESCALATION"],
    featureContext: {},
    missingData: [],
  });
  if (decision.training.action !== "ESCALATE") {
    throw new Error("Safety policy must stop routine training advice.");
  }
  if (decision.change_proposals.length !== 0) {
    throw new Error("Escalation must never mutate the approved plan.");
  }
});
