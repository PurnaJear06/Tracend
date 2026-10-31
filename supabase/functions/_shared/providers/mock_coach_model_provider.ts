import {
  coachDecisionSchemaVersion,
  type CoachDecisionV1,
  parseCoachDecision,
} from "../contracts/coach_decision_v1.ts";
import type {
  CoachModelGeneration,
  CoachModelProvider,
  CoachModelRequest,
} from "./coach_model_provider.ts";

// The deterministic daily decision, used without AI consent or budget. It
// words a candidate decision for each piece of evidence, most pressing first,
// and returns the first one the decision contract accepts under the request's
// policy outcome. The contract is the only authority on what a policy permits
// (request_data allows only gathering data, maintain_only no same-day change,
// escalate only escalation), so the mock keeps no copy of those rules and its
// output is never rejected.

type DecisionBody = Omit<CoachDecisionV1, "schema_version" | "decision_kind" | "change_proposals">;

// The gaps a daily decision may ask the athlete to fill (prepare_daily_coaching
// names the first two; the app labels all three).
const decisionGaps: readonly string[] = ["recovery_check_in", "health_context", "nutrition_data"];

export class MockCoachModelProvider implements CoachModelProvider {
  generateDecision(request: CoachModelRequest): Promise<CoachModelGeneration> {
    return Promise.resolve({
      decision: mockDecision(request),
      provider: "mock",
      model: "deterministic-mock-v2",
      inputUnits: 0,
      outputUnits: 0,
      estimatedCostUsd: 0,
    });
  }
}

function mockDecision(request: CoachModelRequest): CoachDecisionV1 {
  const decision = (body: DecisionBody): CoachDecisionV1 => ({
    schema_version: coachDecisionSchemaVersion,
    decision_kind: request.decisionKind,
    ...body,
    change_proposals: [],
  });
  const has = (code: string) => request.permittedEvidence.includes(code);

  // What a holding decision asks for: the gaps the policy named, or today's
  // check-in when it named none.
  const named = request.missingData.filter((code) => decisionGaps.includes(code));
  const missing = named.length ? named : ["recovery_check_in"];

  // Keeps the approved plan and asks for the missing data. Every policy short
  // of escalation accepts it, so it is the answer when no candidate fits.
  const hold = decision({
    training: {
      action: "GATHER_DATA",
      summary: "Keep the approved plan available until the missing data arrives.",
      today_adjustments: [],
    },
    nutrition: {
      action: "MAINTAIN_TARGETS",
      summary: "Keep the approved nutrition targets.",
      today_adjustments: [],
    },
    head_coach: {
      final_decision: "Keep the approved plan and add the missing data.",
      reason: "There is not enough current evidence for a new coaching decision.",
    },
    evidence: [],
    confidence: "low",
    missing_data: missing,
    risk_flags: [],
  });

  const candidates: CoachDecisionV1[] = [];
  if (request.policyOutcome === "rest_as_chosen") {
    const paused = has("TRAINING_PAUSED");
    candidates.push(decision({
      training: {
        action: "REST_AS_CHOSEN",
        summary: paused
          ? "You're on a break, so no session is due today."
          : "You said you can't train today, so today is a rest day.",
        today_adjustments: [],
      },
      nutrition: {
        action: "MAINTAIN_TARGETS",
        summary: "Keep the approved nutrition targets.",
        today_adjustments: [],
      },
      head_coach: {
        final_decision: paused ? "Rest: you're on a break." : "Rest today, as you chose.",
        reason: paused
          ? "You approved a break that covers today; your plan resumes after it."
          : "Your check-in says you can't train today; your plan continues on your next training day.",
      },
      evidence: paused
        ? [{
          code: "TRAINING_PAUSED",
          label: "You're on a break you approved",
          source: "policy_evaluation",
        }]
        : has("ATHLETE_UNAVAILABLE_TODAY")
        ? [{
          code: "ATHLETE_UNAVAILABLE_TODAY",
          label: "Your check-in says you can't train today",
          source: "policy_evaluation",
        }]
        : [],
      confidence: "high",
      missing_data: [],
      risk_flags: [],
    }));
  }
  if (request.policyOutcome === "escalate") {
    candidates.push(decision({
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
      evidence: has("CHECK_IN_SAFETY_ESCALATION")
        ? [{
          code: "CHECK_IN_SAFETY_ESCALATION",
          label: "The current check-in requires safety escalation",
          source: "policy_evaluation",
        }]
        : [],
      confidence: "high",
      missing_data: [],
      risk_flags: ["safety_escalation"],
    }));
  }
  if (has("RECOVERY_BELOW_BASELINE")) {
    candidates.push(decision({
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
    }));
  }
  if (has("TRAINING_LOAD_ELEVATED")) {
    const evidence = [{
      code: "TRAINING_LOAD_ELEVATED",
      label: "Training load is above the safe zone",
      source: "feature_snapshot",
    }] as const;
    // A same-day change where the policy allows one; otherwise the plan stays
    // and the elevated load is still reported.
    candidates.push(
      decision({
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
        evidence,
        confidence: "high",
        missing_data: [],
        risk_flags: ["elevated_load"],
      }),
      decision({
        training: {
          action: "GATHER_DATA",
          summary:
            "Training load is elevated. Keep the approved session and note how hard it feels.",
          today_adjustments: [],
        },
        nutrition: {
          action: "MAINTAIN_TARGETS",
          summary: "Keep approved nutrition targets.",
          today_adjustments: [],
        },
        head_coach: {
          final_decision: "Keep today's approved plan and watch the load.",
          reason:
            "Acute-to-chronic workload ratio is elevated (> 1.5); today's policy keeps the plan unchanged.",
        },
        evidence,
        confidence: "medium",
        missing_data: [],
        risk_flags: ["elevated_load"],
      }),
    );
  }
  if (has("DATA_CONFIDENCE_LOW")) {
    candidates.push(decision({
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
    }));
  }
  if (has("RECOVERY_WITHIN_BASELINE")) {
    const evidence = [{
      code: "RECOVERY_WITHIN_BASELINE",
      label: "Recovery indicators are within the recent baseline",
      source: "feature_snapshot",
    }] as const;
    // Proceeding needs a policy that allows it; otherwise the plan stays and
    // the missing data is asked for.
    candidates.push(
      decision({
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
        evidence,
        confidence: "medium",
        missing_data: [],
        risk_flags: [],
      }),
      decision({
        training: {
          action: "GATHER_DATA",
          summary:
            "Recovery is within the recent baseline. Add the missing data to confirm the session.",
          today_adjustments: [],
        },
        nutrition: {
          action: "MAINTAIN_TARGETS",
          summary: "Keep the approved nutrition targets.",
          today_adjustments: [],
        },
        head_coach: {
          final_decision: "Keep the approved plan and add the missing data.",
          reason: "Recovery is within the recent baseline, but today's policy needs more data.",
        },
        evidence,
        confidence: "low",
        missing_data: missing,
        risk_flags: [],
      }),
    );
  }

  return candidates.find((candidate) => accepted(candidate, request)) ?? hold;
}

function accepted(decision: CoachDecisionV1, request: CoachModelRequest): boolean {
  try {
    parseCoachDecision(decision, request.permittedEvidence, request.policyOutcome);
    return true;
  } catch {
    return false;
  }
}
