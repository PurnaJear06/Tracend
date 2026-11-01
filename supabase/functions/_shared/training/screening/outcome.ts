// Contract 8 (coaching platform): the pre-exercise screening outcome. B6 computes it from the
// athlete's answers; the rules plan (B2) reads it to cap intensity.
export const screeningOutcomes = ["cleared", "moderate_until_cleared", "see_professional"] as const;

export type ScreeningOutcome = typeof screeningOutcomes[number];

/**
 * What the gates act on: the stored outcome, or "unscreened" when the athlete never answered the
 * health check (an account from before it was asked). Unscreened is never cleared: no onboarding
 * plan is built or approved until the check is answered, and everywhere else it carries the
 * moderate_until_cleared effort cap. private.current_screening_outcome returns the same values.
 */
export const screeningGates = [...screeningOutcomes, "unscreened"] as const;

export type ScreeningGate = typeof screeningGates[number];

/** Effort is held to moderate: the health check asks for it, or it was never answered. */
export const capsEffortToModerate = (gate: ScreeningGate): boolean =>
  gate === "moderate_until_cleared" || gate === "unscreened";
