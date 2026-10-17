// The proposal builder: a pure function from an intent and the athlete's state to either a
// proposal (every number computed by rules) or a plain refusal. Nothing here reads a clock, a
// database or a model.
import { buildGoalOrPhase } from "./goal.ts";
import { parseCoachProposalIntent } from "./intent.ts";
import { buildNutritionTargets } from "./nutrition.ts";
import { refusals } from "./refusals.ts";
import {
  buildExerciseSwap,
  buildIntensityOrPhase,
  buildNextSessionAdjustment,
  buildTemporaryBlock,
  buildTrainingSchedule,
} from "./training.ts";
import type { AthleteState, BuildResult, CoachProposalIntent } from "./types.ts";

export function buildCoachProposal(intent: CoachProposalIntent, state: AthleteState): BuildResult {
  switch (intent.kind) {
    case "temporary_block":
      return buildTemporaryBlock(intent, state);
    case "training_schedule":
      return buildTrainingSchedule(intent, state);
    case "exercise_swap":
      return buildExerciseSwap(intent, state);
    case "intensity_or_phase":
      return buildIntensityOrPhase(intent, state);
    case "goal_or_phase":
      return buildGoalOrPhase(intent, state);
    case "nutrition_targets":
      return buildNutritionTargets(intent, state);
    case "next_session_adjustment":
      return buildNextSessionAdjustment(intent, state);
  }
}

/** Parses the model's raw intent, then builds. An intent outside the vocabulary is refused. */
export function buildFromRawIntent(raw: unknown, state: AthleteState): BuildResult {
  const parsed = parseCoachProposalIntent(raw);
  return parsed.ok
    ? buildCoachProposal(parsed.intent, state)
    : refusals.invalidIntent(parsed.problem);
}
