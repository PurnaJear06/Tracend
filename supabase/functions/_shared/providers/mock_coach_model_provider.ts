import {
  coachDecisionSchemaVersion,
  type CoachDecisionV1,
} from "../contracts/coach_decision_v1.ts";
import type {
  CoachModelGeneration,
  CoachModelProvider,
  CoachModelRequest,
} from "./coach_model_provider.ts";

export class MockCoachModelProvider implements CoachModelProvider {
  async generateDecision(request: CoachModelRequest): Promise<CoachModelGeneration> {
    const decision = await this.#decision(request);
    return {
      decision,
      provider: "mock",
      model: "deterministic-mock-v2",
      inputUnits: 0,
      outputUnits: 0,
      estimatedCostUsd: 0,
    };
  }

  #decision(request: CoachModelRequest): Promise<CoachDecisionV1> {
    const has = (code: string) => request.permittedEvidence.includes(code);

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

    if (has("RECOVERY_BELOW_BASELINE")) {
      return Promise.resolve({
        schema_version: coachDecisionSchemaVersion,
        decision_kind: request.decisionKind,
        training: {
          action: "GATHER_DATA",
          summary: "Recovery score is below baseline. Consider a lighter session.",
          today_adjustments: [],
        },
        nutrition: {
          action: "MAINTAIN_TARGETS",
          summary: "Keep approved nutrition targets while recovery recovers.",
          today_adjustments: [],
        },
        head_coach: {
          final_decision: "Take it easy today.",
          reason: "Recovery score is below the recent baseline (< 40).",
        },
        evidence: [{
          code: "RECOVERY_BELOW_BASELINE",
          label: "Recovery score is below the baseline threshold",
          source: "feature_snapshot",
        }],
        confidence: "high",
        missing_data: [],
        risk_flags: [],
        change_proposals: [],
      });
    }

    if (has("TRAINING_LOAD_ELEVATED")) {
      return Promise.resolve({
        schema_version: coachDecisionSchemaVersion,
        decision_kind: request.decisionKind,
        training: {
          action: "ADJUST_TODAY",
          summary: "Training load is elevated. Reduce volume or intensity today.",
          today_adjustments: ["Reduce intensity — ACWR > 1.5"],
        },
        nutrition: {
          action: "MAINTAIN_TARGETS",
          summary: "Keep approved nutrition targets.",
          today_adjustments: [],
        },
        head_coach: {
          final_decision: "Reduce training intensity today.",
          reason: "Acute-to-chronic workload ratio is elevated (> 1.5).",
        },
        evidence: [{
          code: "TRAINING_LOAD_ELEVATED",
          label: "Training load is above the safe zone",
          source: "feature_snapshot",
        }],
        confidence: "high",
        missing_data: [],
        risk_flags: ["elevated_load"],
        change_proposals: [],
      });
    }

    if (has("DATA_CONFIDENCE_LOW")) {
      return Promise.resolve({
        schema_version: coachDecisionSchemaVersion,
        decision_kind: request.decisionKind,
        training: {
          action: "GATHER_DATA",
          summary: "Insufficient health data for confident decision.",
          today_adjustments: [],
        },
        nutrition: {
          action: "GATHER_DATA",
          summary: "Insufficient nutrition data for confident decision.",
          today_adjustments: [],
        },
        head_coach: {
          final_decision: "Sync HealthKit and log meals regularly.",
          reason: "Not enough data points for confident scoring.",
        },
        evidence: [],
        confidence: "low",
        missing_data: ["health_context", "nutrition_data"],
        risk_flags: [],
        change_proposals: [],
      });
    }

    if (!has("RECOVERY_WITHIN_BASELINE")) {
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
        code: "RECOVERY_WITHIN_BASELINE",
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
