import type { ScreeningOutcome } from "./outcome.ts";

// The pre-exercise screening gate (coaching platform Contract 8, chunk B6). Four plain questions
// asked before the first plan; the outcome only caps the plan's intensity or stops plan building.
// It never names or suspects a condition. The mapping follows the ACSM 2015 preparticipation
// logic in our own words, and public.record_screening_v1 applies the same rule in the database
// (private.screening_outcome); screening_test.ts and onboarding_screening_test.sql hold the same
// sixteen-row table, so the two cannot drift apart unnoticed.

export type ScreeningAnswers = Readonly<{
  /** Exercises regularly now (the athlete's own reading of "regularly"). */
  exercisesRegularly: boolean;
  /** Knows of a heart, metabolic or kidney condition. */
  knownDisease: boolean;
  /** Notices signs or symptoms that could point to one, now. */
  symptoms: boolean;
  /** A professional has cleared the athlete to exercise. False when not asked. */
  clearedByProfessional: boolean;
}>;

/**
 * The outcome of the four answers:
 * - any current sign or symptom: see a professional first;
 * - a known condition, no clearance, not exercising regularly: see a professional first;
 * - a known condition, no clearance, exercising regularly: moderate effort until cleared;
 * - anything else: cleared.
 */
export function screeningOutcome(answers: ScreeningAnswers): ScreeningOutcome {
  if (answers.symptoms) return "see_professional";
  if (answers.knownDisease && !answers.clearedByProfessional) {
    return answers.exercisesRegularly ? "moderate_until_cleared" : "see_professional";
  }
  return "cleared";
}

/**
 * The outcome for an athlete who may never have been screened (an app build that does not ask, or
 * plans made before B6): missing answers read as cleared (Contract 8).
 */
export function screeningOutcomeOf(answers: ScreeningAnswers | null | undefined): ScreeningOutcome {
  return answers ? screeningOutcome(answers) : "cleared";
}

export type ScreeningParse =
  | { kind: "absent" }
  | { kind: "invalid" }
  | { kind: "answers"; answers: ScreeningAnswers };

/**
 * Reads the draft payload's `screening` object: `exercises_regularly`, `known_disease` and
 * `symptoms` are required booleans, `cleared_by_professional` an optional one (false when
 * missing). Nothing at all is "absent" (an older app build); anything else wrong is "invalid", so
 * a malformed answer asks the athlete again instead of reading as cleared.
 */
export function parseScreeningAnswers(value: unknown): ScreeningParse {
  if (value === undefined || value === null) return { kind: "absent" };
  if (typeof value !== "object" || Array.isArray(value)) return { kind: "invalid" };
  const entry = value as Record<string, unknown>;
  const { exercises_regularly: exercises, known_disease: disease, symptoms } = entry;
  const cleared = entry.cleared_by_professional ?? false;
  if (
    typeof exercises !== "boolean" || typeof disease !== "boolean" ||
    typeof symptoms !== "boolean" || typeof cleared !== "boolean"
  ) return { kind: "invalid" };
  return {
    kind: "answers",
    answers: {
      exercisesRegularly: exercises,
      knownDisease: disease,
      symptoms,
      clearedByProfessional: cleared,
    },
  };
}

/** The answers as stored in the onboarding snapshot (same keys the app sends). */
export function screeningSnapshot(answers: ScreeningAnswers): Record<string, unknown> {
  return {
    exercises_regularly: answers.exercisesRegularly,
    known_disease: answers.knownDisease,
    symptoms: answers.symptoms,
    cleared_by_professional: answers.clearedByProfessional,
    outcome: screeningOutcome(answers),
  };
}
