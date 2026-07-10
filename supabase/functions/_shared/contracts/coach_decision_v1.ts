export const coachDecisionSchemaVersion = "1.0" as const;

export type Confidence = "low" | "medium" | "high";

export type TrainingAction =
  | "PROCEED_AS_PLANNED"
  | "ADJUST_TODAY"
  | "GATHER_DATA"
  | "REVIEW_PROPOSAL"
  | "ESCALATE";

export type NutritionAction =
  | "MAINTAIN_TARGETS"
  | "PRIORITIZE_PROTEIN"
  | "GATHER_DATA"
  | "REVIEW_PROPOSAL"
  | "ESCALATE";

export type ChangeProposalV1 = Readonly<{
  domain: "training" | "nutrition";
  action: "replace_training_plan" | "replace_nutrition_targets";
  current: Readonly<Record<string, unknown>>;
  proposed: Readonly<Record<string, unknown>>;
  evidence: readonly EvidenceReference[];
  expected_benefit: string;
  downside: string;
  confidence: Confidence;
  effective_date: string;
}>;

export type EvidenceReference = Readonly<{
  code: string;
  label: string;
  source: "feature_snapshot" | "policy_evaluation";
}>;

export type CoachDecisionV1 = Readonly<{
  schema_version: typeof coachDecisionSchemaVersion;
  decision_kind: "onboarding" | "daily" | "weekly" | "on_demand";
  training: Readonly<{
    action: TrainingAction;
    summary: string;
    today_adjustments: readonly string[];
  }>;
  nutrition: Readonly<{
    action: NutritionAction;
    summary: string;
    today_adjustments: readonly string[];
  }>;
  head_coach: Readonly<{
    final_decision: string;
    reason: string;
  }>;
  evidence: readonly EvidenceReference[];
  confidence: Confidence;
  missing_data: readonly string[];
  risk_flags: readonly string[];
  change_proposals: readonly ChangeProposalV1[];
}>;

export type PolicyOutcome =
  | "allow"
  | "maintain_only"
  | "daily_adjustment_only"
  | "request_data"
  | "escalate";

const rootKeys = [
  "schema_version",
  "decision_kind",
  "training",
  "nutrition",
  "head_coach",
  "evidence",
  "confidence",
  "missing_data",
  "risk_flags",
  "change_proposals",
] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(
  value: Record<string, unknown>,
  allowed: readonly string[],
): boolean {
  return Object.keys(value).every((key) => allowed.includes(key));
}

function isBoundedText(value: unknown, maximum = 1000): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= maximum;
}

function isStringArray(value: unknown, maximum = 20): value is string[] {
  return Array.isArray(value) && value.length <= maximum &&
    value.every((item) => isBoundedText(item, 160));
}

export function parseCoachDecision(
  value: unknown,
  permittedEvidence: readonly string[],
  policyOutcome: PolicyOutcome,
): CoachDecisionV1 {
  if (!isRecord(value) || !hasOnlyKeys(value, rootKeys)) {
    throw new Error("invalid_decision_root");
  }
  if (
    value.schema_version !== coachDecisionSchemaVersion ||
    !["onboarding", "daily", "weekly", "on_demand"].includes(
      String(value.decision_kind),
    ) ||
    !["low", "medium", "high"].includes(String(value.confidence)) ||
    !isStringArray(value.missing_data) ||
    !isStringArray(value.risk_flags)
  ) {
    throw new Error("invalid_decision_metadata");
  }

  const training = value.training;
  const nutrition = value.nutrition;
  const headCoach = value.head_coach;
  if (
    !isRecord(training) ||
    !hasOnlyKeys(training, ["action", "summary", "today_adjustments"]) ||
    !["PROCEED_AS_PLANNED", "ADJUST_TODAY", "GATHER_DATA", "REVIEW_PROPOSAL", "ESCALATE"].includes(
      String(training.action),
    ) ||
    !isBoundedText(training.summary) ||
    !isStringArray(training.today_adjustments, 8) ||
    !isRecord(nutrition) ||
    !hasOnlyKeys(nutrition, ["action", "summary", "today_adjustments"]) ||
    !["MAINTAIN_TARGETS", "PRIORITIZE_PROTEIN", "GATHER_DATA", "REVIEW_PROPOSAL", "ESCALATE"]
      .includes(
        String(nutrition.action),
      ) ||
    !isBoundedText(nutrition.summary) ||
    !isStringArray(nutrition.today_adjustments, 8) ||
    !isRecord(headCoach) ||
    !hasOnlyKeys(headCoach, ["final_decision", "reason"]) ||
    !isBoundedText(headCoach.final_decision) ||
    !isBoundedText(headCoach.reason)
  ) {
    throw new Error("invalid_decision_sections");
  }

  if (!Array.isArray(value.evidence) || value.evidence.length > 20) {
    throw new Error("invalid_decision_evidence");
  }
  for (const item of value.evidence) {
    if (
      !isRecord(item) || !hasOnlyKeys(item, ["code", "label", "source"]) ||
      !isBoundedText(item.code, 80) || !isBoundedText(item.label, 240) ||
      !["feature_snapshot", "policy_evaluation"].includes(String(item.source)) ||
      !permittedEvidence.includes(item.code)
    ) {
      throw new Error("unpermitted_decision_evidence");
    }
  }

  if (!Array.isArray(value.change_proposals) || value.change_proposals.length > 2) {
    throw new Error("invalid_change_proposals");
  }
  if (value.change_proposals.length > 0) {
    throw new Error("phase_5_initial_slice_proposals_disabled");
  }

  const trainingAction = String(training.action);
  const nutritionAction = String(nutrition.action);
  if (
    policyOutcome === "request_data" &&
    trainingAction !== "GATHER_DATA"
  ) {
    throw new Error("policy_requires_data");
  }
  if (
    policyOutcome === "maintain_only" &&
    ["ADJUST_TODAY", "REVIEW_PROPOSAL"].includes(trainingAction)
  ) {
    throw new Error("policy_requires_maintenance");
  }
  if (
    policyOutcome === "escalate" &&
    (trainingAction !== "ESCALATE" || nutritionAction !== "ESCALATE")
  ) {
    throw new Error("policy_requires_escalation");
  }

  return value as CoachDecisionV1;
}
