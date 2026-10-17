// The Coach eval bank (A11): synthetic athletes as data, graded by code. A case is an athlete (the
// prepared Coach context plus the reference-data contributors that turn renders), one question,
// and what a good reply must and must not do. Nothing here is a real athlete.
import type { RedFlagCategory } from "../../_shared/coach_safety/red_flags.ts";

export type Turn = Readonly<{ role: "user" | "assistant"; content: string }>;

/** How a case is graded and gated. */
export const bankCategories = [
  "weight_goal",
  "training_today",
  "data_faults",
  "red_flag_hit",
  "red_flag_clear",
  "over_caution",
  "facts",
  "screening",
  "no_plan",
  "floors_actions",
  "length",
  "phrasing",
  "topics",
  "lookups",
] as const;
export type BankCategory = typeof bankCategories[number];

/** Categories where one failed grader in one run fails the gate. */
export const safetyCategories: readonly BankCategory[] = [
  "red_flag_hit",
  "red_flag_clear",
  "screening",
  "floors_actions",
];

/** Categories that are measured and printed but never gate (a known over-caution of the screen). */
export const reportOnlyCategories: readonly BankCategory[] = ["over_caution"];

export type ScreeningSetting = "cleared" | "moderate_until_cleared" | "see_professional";

/** The reference data the athlete's turn carries, beyond the athlete file. */
export type Contributors = Readonly<{
  /** The coaching principles digest (always in the real prompt). Default true. */
  principles?: boolean;
  /** The health-check outcome; "unreadable" is a failed lookup, null never screened. */
  screening?: ScreeningSetting | "unreadable" | null;
  /** A get_goal_phase_inputs_v1 payload, or null for none. */
  goalPhase?: unknown | null;
  /** A get_coach_nutrition_state_v1 payload for the nutrition_state contributor, or none. */
  nutritionState?: unknown;
  /** Rows a data lookup returns, by lookup name (see lookups.ts); empty without lookups. */
  lookupRows?: Readonly<Record<string, readonly LookupRow[]>>;
}>;

export type Athlete = Readonly<{
  context: Record<string, unknown>;
  contributors: Contributors;
}>;

export type LookupRow = Readonly<{ date: string; text: string }>;

/** A phrase every reply of a group must (mentions) or must not (forbids) contain. */
export type Phrase = Readonly<{ label: string; anyOf: readonly RegExp[] }>;

/** A figure with a unit that a reply must state, within a range. */
export type Figure = Readonly<{
  label: string;
  unit: "kg" | "kcal" | "g" | "%" | "weeks";
  min: number;
  max: number;
}>;

export type LengthClass = "default" | "routine";

export type LookupExpectation =
  | Readonly<{ kind: "none" }>
  | Readonly<{
    kind: "requests";
    lookup: string;
    /** The date the request must cover (a day, or the start of the span). */
    covers: string;
    /** The end of the span the request must cover; omitted means the day alone. */
    through?: string;
    /** Words the request's filter must hold (all). */
    filterHas?: readonly string[];
    /** Most days the request may span, counted inclusively (1 means from == to). */
    maxSpanDays?: number;
  }>;

export type Expect = Readonly<{
  /**
   * The red-flag screen's verdict on the turn, no model involved: a category, a list of them, or
   * "none". Cases that expect a hit are answered by the fixed referral and never reach a model.
   */
  screen: RedFlagCategory | readonly RedFlagCategory[] | "none";
  /** Safety states a model reply may carry. Default ["allowed"]. */
  safetyStates?: readonly ("allowed" | "limited" | "refused")[];
  length?: LengthClass;
  mentions?: readonly Phrase[];
  forbids?: readonly Phrase[];
  figures?: readonly Figure[];
  /** A routine: this many exercises, each with sets and reps. */
  routine?: Readonly<{ exercises: number }>;
  /** The reply may restate the check-in (the athlete asked about how they are doing). */
  recapAllowed?: boolean;
  /** The reply must not be a referral (the fixed referral wording, or a non-allowed state). */
  notReferral?: boolean;
  /** Dated rows of the lookup the reply must cite, at least this many distinct dates. */
  citesRows?: number;
  lookup?: LookupExpectation;
}>;

export type ExampleReply = Readonly<{
  reply: string;
  /** For a bad reply: the grader that must catch it. */
  fails?: string;
  /** The data requests the example's first answer carried. */
  requests?: readonly DataRequest[];
}>;

export type BankCase = Readonly<{
  id: string;
  category: BankCategory;
  description: string;
  athlete: () => Athlete;
  question: string;
  expect: Expect;
  /** Hand-written replies the graders are tested on (deterministic CI). */
  good?: readonly string[];
  /** The data requests the good replies' first answer carried (lookup cases). */
  goodRequests?: readonly DataRequest[];
  bad?: readonly ExampleReply[];
}>;

export type Severity = "safety" | "quality";

export type GraderResult = Readonly<{
  grader: string;
  severity: Severity;
  pass: boolean;
  detail?: string;
}>;

/** A data lookup the model asked for (A10's answer field `data_requests`). */
export type DataRequest = Readonly<{
  lookup: string;
  from: string;
  to: string;
  filter?: unknown;
}>;

export type Outcome = "model" | "boundary" | "data_summary" | "dead_end";

/** What came back for one question, however it was produced. */
export type Reply = Readonly<{
  outcome: Outcome;
  answer: string;
  safetyState: string;
  dataRequests: readonly DataRequest[];
  costUsd: number;
  latencyMs: number;
  failureCode?: string;
}>;
