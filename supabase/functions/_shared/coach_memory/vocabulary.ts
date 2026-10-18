// The closed vocabularies of Coach memory (A10 part 2). A confirmed fact has one of a fixed set of
// kinds; a Coach note has topics and concerns from fixed lists. Nothing in memory is free-form
// except the athlete's own words, so a model can never invent a kind of fact, and the code that
// matches an athlete's statement to a saved fact compares only these words.

export const factKinds = [
  "injury_limitation",
  "schedule_constraint",
  "equipment",
  "food_like",
  "food_dislike",
  "allergy",
  "exercise_like",
  "exercise_dislike",
  "coaching_style",
  "other_preference",
] as const;
export type FactKind = typeof factKinds[number];

/** The heading each kind has on the memory screen and in the Coach's file. */
export const factKindLabels: Readonly<Record<FactKind, string>> = {
  injury_limitation: "Injuries and limitations",
  schedule_constraint: "Schedule and life constraints",
  equipment: "Equipment",
  food_like: "Foods they like",
  food_dislike: "Foods they dislike",
  allergy: "Allergies and intolerances",
  exercise_like: "Exercises they like",
  exercise_dislike: "Exercises they dislike",
  coaching_style: "Coaching style",
  other_preference: "Other preferences",
};

/** Kinds whose truth changes with time; the database sets their re-confirm date. */
export const volatileFactKinds: readonly FactKind[] = ["injury_limitation", "schedule_constraint"];

export const factSources = ["athlete_typed", "coach_suggestion_confirmed", "onboarding"] as const;
export type FactSource = typeof factSources[number];

export const factSourceLabels: Readonly<Record<FactSource, string>> = {
  athlete_typed: "typed by the athlete",
  coach_suggestion_confirmed: "suggested by Coach, confirmed by the athlete",
  onboarding: "from onboarding",
};

export const maxActiveFacts = 60;
export const maxFactSubjectChars = 60;
export const maxFactStatementChars = 200;

export function isFactKind(value: unknown): value is FactKind {
  return typeof value === "string" && (factKinds as readonly string[]).includes(value);
}

export function isFactSource(value: unknown): value is FactSource {
  return typeof value === "string" && (factSources as readonly string[]).includes(value);
}

// Coach notes -------------------------------------------------------------------------------

export const maxCoachNotes = 20;
export const coachNoteLifetimeDays = 60;

export const noteTopics = [
  "training",
  "nutrition",
  "recovery",
  "sleep",
  "weight",
  "goal",
  "plan",
  "pain_injury",
  "motivation",
  "schedule",
  "supplements",
  "equipment",
] as const;
export type NoteTopic = typeof noteTopics[number];

export const noteTopicLabels: Readonly<Record<NoteTopic, string>> = {
  training: "training",
  nutrition: "nutrition",
  recovery: "recovery",
  sleep: "sleep",
  weight: "body weight",
  goal: "their goal",
  plan: "their plan",
  pain_injury: "pain or injury",
  motivation: "motivation",
  schedule: "their schedule",
  supplements: "supplements",
  equipment: "equipment",
};

export const noteConcerns = [
  "pain",
  "fatigue",
  "soreness",
  "poor_sleep",
  "plateau",
  "hunger",
  "low_motivation",
  "time_pressure",
  "stress",
] as const;
export type NoteConcern = typeof noteConcerns[number];

export const noteConcernLabels: Readonly<Record<NoteConcern, string>> = {
  pain: "pain",
  fatigue: "tiredness",
  soreness: "soreness",
  poor_sleep: "poor sleep",
  plateau: "a plateau",
  hunger: "hunger",
  low_motivation: "low motivation",
  time_pressure: "little time",
  stress: "stress",
};

export const maxNoteTopics = 4;
export const maxNoteConcerns = 3;
export const maxNoteAdvice = 4;
export const maxNoteCommitments = 3;
export const maxNoteSummaryChars = 400;
export const maxCommitmentChars = 100;
