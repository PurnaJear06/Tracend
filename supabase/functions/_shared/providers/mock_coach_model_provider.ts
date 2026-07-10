import {
  coachDecisionSchemaVersion,
  type CoachDecisionV1,
} from "../contracts/coach_decision_v1.ts";
import type {
  CoachModelGeneration,
  CoachModelProvider,
  CoachModelRequest,
} from "./coach_model_provider.ts";

const recoveryWithinBaseline = "RECOVERY_WITHIN_BASELINE";

export class MockCoachModelProvider implements CoachModelProvider {
  async generateDecision(request: CoachModelRequest): Promise<CoachModelGeneration> {
    const decision = await this.#decision(request);
    return {
      decision,
      provider: "mock",
      model: "deterministic-mock-v1",
      inputUnits: 0,
      outputUnits: 0,
      estimatedCostUsd: 0,
    };
  }

  #decision(request: CoachModelRequest): Promise<CoachDecisionV1> {
    if (request.policyOutcome === "escalate") {
      return Promise.resolve({
        schema_version: coachDecisionSchemaVersion,
        decision_kind: request.decisionKind,
        training: {
          action: "ESCALATE",
          summary: "Stop training and seek appropriate medical guidance.",
          today_adjustments: [],
        },
        nutrition: {
          action: "ESCALATE",
          summary: "Pause routine coaching while the safety concern is addressed.",
          today_adjustments: [],
        },
        head_coach: {
          final_decision: "Do not continue the planned session.",
          reason: "Your check-in reached Tracend's safety escalation threshold.",
        },
        evidence: [{
          code: "CHECK_IN_SAFETY_ESCALATION",
          label: "The current check-in requires safety escalation",
          source: "policy_evaluation",
        }],
        confidence: "high",
        missing_data: [],
        risk_flags: ["safety_escalation"],
        change_proposals: [],
      });
    }
    if (!request.permittedEvidence.includes(recoveryWithinBaseline)) {
      return Promise.resolve({
        schema_version: coachDecisionSchemaVersion,
        decision_kind: request.decisionKind,
        training: {
          action: "GATHER_DATA",
          summary: "Keep the approved plan available while recovery data is missing.",
          today_adjustments: [],
        },
        nutrition: {
          action: "MAINTAIN_TARGETS",
          summary: "Keep the approved nutrition targets.",
          today_adjustments: [],
        },
        head_coach: {
          final_decision: "Keep the approved plan and add a check-in.",
          reason: "There is not enough current evidence for a new coaching decision.",
        },
        evidence: [],
        confidence: "low",
        missing_data: ["recovery_check_in"],
        risk_flags: [],
        change_proposals: [],
      });
    }

    return Promise.resolve({
      schema_version: coachDecisionSchemaVersion,
      decision_kind: request.decisionKind,
      training: {
        action: "PROCEED_AS_PLANNED",
        summary: "Complete the scheduled session at the approved effort.",
        today_adjustments: [],
      },
      nutrition: {
        action: "MAINTAIN_TARGETS",
        summary: "Keep the approved nutrition targets.",
        today_adjustments: [],
      },
      head_coach: {
        final_decision: "Keep today's approved plan.",
        reason: "Current recovery evidence remains within the recent baseline.",
      },
      evidence: [{
        code: recoveryWithinBaseline,
        label: "Recovery indicators are within the recent baseline",
        source: "feature_snapshot",
      }],
      confidence: "medium",
      missing_data: [],
      risk_flags: [],
      change_proposals: [],
    });
  }
}
