// Contract 8 (coaching platform): the pre-exercise screening outcome. B6 computes it from the
// athlete's answers; the rules plan (B2) reads it to cap intensity. A missing outcome means the
// athlete was never screened (plans made before B6) and reads as "cleared".
export const screeningOutcomes = ["cleared", "moderate_until_cleared", "see_professional"] as const;

export type ScreeningOutcome = typeof screeningOutcomes[number];
