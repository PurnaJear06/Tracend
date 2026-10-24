import {
  goalPhaseInputsFromService,
  goalPhaseInputsReadKey,
} from "../coach_context/contributors/goal_phase.ts";
import {
  parsePlanState,
  type PlanState,
  planStateFromService,
  planStateReadKey,
} from "../coach_context/contributors/training_plan.ts";
import { type CoachContextInput, sharedRead } from "../coach_context/host.ts";
import { parseGoalPhaseInputs } from "../training/goal_phase/index.ts";
import type { PlanFacts } from "./plan_explanation.ts";

// What Coach chat tells the library about the athlete's plan when the athlete asks why it is the
// way it is (chunk E5): counts and enumerated values from the plan state and the goal, read once
// for the turn and shared with the plan and goal phase sections. No exercise name, load, weight or
// free text enters a search.

/** The facts of a plan state and a goal; null when neither is known. */
export function planFactsFrom(plan: PlanState | null, goalType: string | null): PlanFacts | null {
  if (plan === null && goalType === null) return null;
  const exercises = plan?.sessions.flatMap((session) => session.exercises) ?? [];
  const lows = exercises.map((exercise) => exercise.repMin).filter((reps) => reps > 0);
  const highs = exercises.map((exercise) => exercise.repMax).filter((reps) => reps > 0);
  return {
    sessionsPerWeek: plan?.sessionsPerWeek ?? (plan?.sessions.length || null),
    experience: plan?.experience ?? null,
    repMin: lows.length ? Math.min(...lows) : null,
    repMax: highs.length ? Math.max(...highs) : null,
    hasEffortTarget: exercises.some((exercise) => exercise.targetRpe !== null),
    goal: goalType,
    temporaryBlock: plan?.afterBlock != null,
  };
}

/**
 * The plan facts for this turn from the service: the plan state and the goal each count when read,
 * and the one that failed is left out rather than failing the other.
 */
export async function planFactsFromService(input: CoachContextInput): Promise<PlanFacts | null> {
  const [plan, goal] = await Promise.allSettled([
    sharedRead(input, planStateReadKey, () => planStateFromService(input.userId, input.localDate)),
    sharedRead(input, goalPhaseInputsReadKey, () => goalPhaseInputsFromService(input.userId)),
  ]);
  return planFactsFrom(
    plan.status === "fulfilled" ? parsePlanState(plan.value) : null,
    goal.status === "fulfilled" ? parseGoalPhaseInputs(goal.value, input.localDate).goalType : null,
  );
}
