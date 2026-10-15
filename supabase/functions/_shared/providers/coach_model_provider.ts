import type { CoachDecisionV1 } from "../contracts/coach_decision_v1.ts";
import type { PolicyOutcome } from "../contracts/coach_decision_v1.ts";

export type CoachModelRequest = Readonly<{
  decisionKind: CoachDecisionV1["decision_kind"];
  featureSnapshotId: string;
  policyEvaluationId: string;
  policyOutcome: PolicyOutcome;
  permittedEvidence: readonly string[];
  featureContext: Readonly<Record<string, unknown>>;
  missingData: readonly string[];
}>;

/** Who answered a run, as model_runs stores it: a vendor, or the deterministic mock. */
export type CoachRunProvider = "mock" | "gemini" | "groq" | "deepseek" | "anthropic";

export type CoachModelGeneration = Readonly<{
  decision: CoachDecisionV1;
  provider: CoachRunProvider;
  model: string;
  inputUnits: number;
  outputUnits: number;
  estimatedCostUsd: number;
}>;

export interface CoachModelProvider {
  generateDecision(request: CoachModelRequest): Promise<CoachModelGeneration>;
}
