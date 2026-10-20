// What each Coach context contributor may ground in a reply's numbers check. Only values that are
// deterministic (Tracend calculated them) or recorded by the athlete may ground a figure; a model's
// words, an earlier reply of Coach's and library text may not stand in for a record. A new
// contributor has to be declared here (registry_test.ts fails otherwise), so its author decides.
//
//   records   the block holds Tracend's calculations, the athlete's records and what the athlete
//             approved or wrote; its figures count as given
//   guidance  general guidance for healthy adults (the principles digest): its figures ground only
//             a sentence that is not the athlete's own target
//   excluded  grounds nothing here: the library's excerpts count only when the reply cites the source
//
// The lookup rows have the same rule per field: see `lookupGrounding` in coach_lookups/render.ts.
export type ContributorGrounding = "records" | "guidance" | "excluded";

export const contributorGrounding: Readonly<Record<string, ContributorGrounding>> = Object.freeze({
  coaching_principles: "guidance",
  screening: "records",
  confirmed_facts: "records",
  goal_phase: "records",
  training_plan: "records",
  nutrition_state: "records",
  coach_proposals: "records",
  heart_rate_profile: "records",
  coach_notes: "records",
  watch_outs: "records",
  coverage_brief: "records",
  library: "excluded",
});

/** An id nobody declared grounds as records; the registry test keeps the table complete. */
export const groundingOf = (id: string): ContributorGrounding =>
  contributorGrounding[id] ?? "records";
