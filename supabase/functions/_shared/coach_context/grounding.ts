// What each Coach context contributor may ground in a reply's numbers check, in the words of
// `../grounding.ts`. Only values that are deterministic (Tracend calculated them) or recorded by the
// athlete may ground a figure; a model's words, an earlier reply of Coach's and library text may not
// stand in for a record. A contributor has to be declared here (grounding_test.ts fails otherwise)
// and one that is not declared grounds nothing, so its author decides.
//
//   records   the block states Tracend's calculations, the athlete's records and what the athlete
//             approved or wrote, mixed with fixed wording (windows, thresholds, definitions of a
//             baseline, ids). Only the values the contributor marked with `record`
//             (`RenderedBlock.records`, `../recorded_text.ts`) count as given; the rest of its
//             text grounds nothing, and a records contributor that marks nothing grounds nothing.
//             Values marked with `figure` (`RenderedBlock.figures`) are the exception: they ground
//             a figure, but never one that states the athlete's own target
//   guidance  general guidance for healthy adults (the principles digest): its whole text is the
//             ground, and its figures ground only a sentence that is not the athlete's own target
//   excluded  grounds nothing here: the library's excerpts count only when the reply cites the source
//
// The athlete's names (the plan's title, its workouts and exercises) are records in every contributor
// that shows them, as everywhere (`columnGrounding`). The lookup rows have the same rule per field:
// see `lookupGrounding` in coach_lookups/render.ts.
export type ContributorGrounding = "records" | "guidance" | "excluded";

export const contributorGrounding: Readonly<Record<string, ContributorGrounding>> = Object.freeze({
  coaching_principles: "guidance",
  screening: "records",
  confirmed_facts: "records",
  goal_phase: "records",
  training_plan: "records",
  readiness: "records",
  training_guidance: "records",
  nutrition_state: "records",
  coach_proposals: "records",
  heart_rate_profile: "records",
  coach_notes: "records",
  watch_outs: "records",
  coverage_brief: "records",
  library: "excluded",
  standing_state: "records",
});

/** An id nobody declared grounds nothing: a contributor is evidence only once it says so. */
export const groundingOf = (id: string): ContributorGrounding =>
  contributorGrounding[id] ?? "excluded";
