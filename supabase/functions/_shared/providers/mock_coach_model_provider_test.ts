import { assertEquals } from "jsr:@std/assert@1.0.14";
import { parseCoachDecision, type PolicyOutcome } from "../contracts/coach_decision_v1.ts";
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

const policyOutcomes: readonly PolicyOutcome[] = [
  "allow",
  "maintain_only",
  "daily_adjustment_only",
  "request_data",
  "escalate",
];

// Codes the mock reacts to, plus ones it ignores; every subset is a
// representative day (the SQL rules make some impossible, which is the point).
const evidenceCodes = [
  "RECOVERY_WITHIN_BASELINE",
  "RECOVERY_BELOW_BASELINE",
  "CHECK_IN_RECOVERY_MIXED",
  "TRAINING_LOAD_ELEVATED",
  "DATA_CONFIDENCE_LOW",
  "CHECK_IN_SAFETY_ESCALATION",
  "APPROVED_PLAN_ACTIVE",
] as const;

function subsets<T>(items: readonly T[]): T[][] {
  return items.reduce<T[][]>(
    (all, item) => all.flatMap((subset) => [subset, [...subset, item]]),
    [[]],
  );
}

Deno.test("every mock decision passes the decision contract under every policy", async () => {
  const provider = new MockCoachModelProvider();
  let checked = 0;
  for (const policyOutcome of policyOutcomes) {
    for (const permittedEvidence of subsets(evidenceCodes)) {
      for (const missingData of [[], ["recovery_check_in", "health_context"]]) {
        for (const decisionKind of ["daily", "on_demand"] as const) {
          const { decision } = await provider.generateDecision({
            decisionKind,
            featureSnapshotId: "snapshot-property",
            policyEvaluationId: "policy-property",
            policyOutcome,
            permittedEvidence,
            featureContext: {},
            missingData,
          });
          const label = `${policyOutcome} [${permittedEvidence.join(",")}]`;
          try {
            parseCoachDecision(decision, permittedEvidence, policyOutcome);
          } catch (error) {
            throw new Error(`${label}: ${(error as Error).message}`);
          }
          assertEquals(decision.decision_kind, decisionKind, label);
          assertEquals(decision.change_proposals, [], label);
          checked++;
        }
      }
    }
  }
  assertEquals(checked, policyOutcomes.length * 2 ** evidenceCodes.length * 2 * 2);
});

Deno.test("each policy gets the most specific action it permits", async () => {
  const provider = new MockCoachModelProvider();
  const actions = async (policyOutcome: PolicyOutcome, permittedEvidence: string[]) => {
    const { decision } = await provider.generateDecision({
      decisionKind: "daily",
      featureSnapshotId: "snapshot-policy",
      policyEvaluationId: "policy-policy",
      policyOutcome,
      permittedEvidence,
      featureContext: {},
      missingData: [],
    });
    return [decision.training.action, decision.nutrition.action, decision.risk_flags];
  };
  const elevated = ["TRAINING_LOAD_ELEVATED", "RECOVERY_WITHIN_BASELINE"];
  // A same-day change only where the policy allows one; the load is still flagged.
  assertEquals(await actions("allow", elevated), [
    "ADJUST_TODAY",
    "MAINTAIN_TARGETS",
    ["elevated_load"],
  ]);
  assertEquals(await actions("daily_adjustment_only", elevated), [
    "ADJUST_TODAY",
    "MAINTAIN_TARGETS",
    ["elevated_load"],
  ]);
  assertEquals(await actions("maintain_only", elevated), [
    "GATHER_DATA",
    "MAINTAIN_TARGETS",
    ["elevated_load"],
  ]);
  assertEquals(await actions("request_data", elevated), [
    "GATHER_DATA",
    "MAINTAIN_TARGETS",
    ["elevated_load"],
  ]);
  // Recovery within baseline proceeds, except while the check-in is missing.
  assertEquals(await actions("maintain_only", ["RECOVERY_WITHIN_BASELINE"]), [
    "PROCEED_AS_PLANNED",
    "MAINTAIN_TARGETS",
    [],
  ]);
  assertEquals(await actions("request_data", ["RECOVERY_WITHIN_BASELINE"]), [
    "GATHER_DATA",
    "MAINTAIN_TARGETS",
    [],
  ]);
  // Escalation never cites evidence the policy did not permit.
  const { decision } = await provider.generateDecision({
    decisionKind: "daily",
    featureSnapshotId: "snapshot-policy",
    policyEvaluationId: "policy-policy",
    policyOutcome: "escalate",
    permittedEvidence: [],
    featureContext: {},
    missingData: [],
  });
  assertEquals([decision.training.action, decision.evidence], ["ESCALATE", []]);
});
