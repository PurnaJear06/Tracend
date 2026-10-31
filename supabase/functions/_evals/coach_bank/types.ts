// The Coach eval bank (A11): synthetic athletes as data, graded by code. A case is an athlete (the
// prepared Coach context plus the reference-data contributors that turn renders), one question,
// and what a good reply must and must not do. Nothing here is a real athlete.
import type { RedFlagCategory } from "../../_shared/coach_safety/red_flags.ts";
import type { ProposalKind, RefusalCode } from "../../_shared/coach_proposals/types.ts";
import type { CoachFact } from "../../_shared/coach_memory/facts.ts";
import type { CoachNote } from "../../_shared/coach_memory/notes.ts";

/**
 * One message of the thread, as recent_messages holds it; a labelled data summary the app gave
 * instead of a model reply carries answer_source "data_summary" (prepare_coach_chat_v10).
 */
export type Turn = Readonly<{
  role: "user" | "assistant";
  content: string;
  answer_source?: "data_summary";
}>;

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
  "proposals",
  "library",
  "investigation",
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
  /** A get_coach_plan_state_v1 payload for the training_plan contributor, or none. */
  trainingPlan?: unknown;
  /**
   * A get_coach_data_index_v1 payload for the Coverage Brief; without one the harness builds one
   * shaped like the athlete file (`bankIndex`).
   */
  dataIndex?: unknown;
  /** Rows a data lookup returns, by lookup name (see lookups.ts); empty without lookups. */
  lookupRows?: Readonly<Record<string, readonly LookupRow[]>>;
  /** A get_coach_watch_outs_v1 payload for the watch_outs contributor, or none. */
  watchFacts?: unknown;
  /** A plan_history "schedule" payload for the last four weeks (repeated misses), or none. */
  schedule?: unknown;
  /**
   * A get_coach_standing_state_v1 payload (a break, a can't-train check-in, held areas, the goal,
   * recent decisions) for the standing_state contributor, the plan and the watch-outs; or none.
   */
  standingState?: unknown;
  /**
   * The library sources (manifest keys, best first) whose chunks retrieval returned for the
   * question, rendered from the real library content as the library contributor renders them. An
   * empty list is a search that found nothing. Absent: the turn has no library block.
   */
  library?: readonly string[];
  /**
   * What the athlete's memory holds (A10 part 2): the facts they confirmed, rendered by the real
   * confirmed-facts contributor, and the Coach's notes, rendered by the real notes contributor.
   * `remember: false` is a conversation the athlete asked Coach not to remember: the model is not
   * offered fact suggestions.
   */
  memory?: Readonly<{
    facts?: readonly CoachFact[];
    notes?: readonly CoachNote[];
    remember?: boolean;
  }>;
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

/**
 * What the reply's `proposal_intent` (A8) must be. `none`: the reply must not propose anything.
 * `intent`: the intent must parse, be of this kind and hold these fields (camel case, as the
 * engine reads them); `refusedWith` names the refusal the rules give when the intent is run for
 * the standard athlete (a reply that refuses to propose and says why is also accepted when
 * `orNone` is set).
 */
export type ProposalExpectation =
  | Readonly<{ kind: "none" }>
  | Readonly<{
    kind: "intent";
    intent: ProposalKind;
    has?: Readonly<Record<string, unknown>>;
    refusedWith?: RefusalCode;
    orNone?: boolean;
  }>;

/**
 * A kind of record (a Coverage Brief domain) the question turns on. The baseline covers it when the
 * athlete file or a contributor already shows it for the period; otherwise a lookup in the kind
 * must have been requested. `since`: the kind is needed from this date, which the baseline's
 * window may not reach. `detail`: the summary the baseline gives is not enough (sets and loads
 * behind a session total, the plan beyond the next seven days).
 */
export type DomainNeed = Readonly<{
  domain: string;
  since?: string;
  /**
   * The last date the need reaches; the coaching date when absent. A need for the plan ahead names
   * the future date it must reach ("next week"), and a lookup covers it only through that date.
   */
  until?: string;
  detail?: boolean;
}>;

/** What the reply's data requests must show about how the turn investigated. */
export type InvestigationChecks = Readonly<{
  /** Every kind here is in the baseline or was looked up (the `domain_coverage` grader). */
  domains?: readonly DomainNeed[];
  /** Most lookups the turn may request in all: a bound on over-fetching (`over_fetch`). */
  maxRequests?: number;
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
  /** How the turn investigated: the kinds of record it covered, and how much it fetched. */
  checks?: InvestigationChecks;
  /** The proposal the reply must (or must not) carry. Without it, a reply must carry none. */
  proposal?: ProposalExpectation;
  /**
   * The library sources the reply's evidence must cite: at least one of `anyOf`, or "none" for a
   * reply that cites nothing (the library found nothing relevant). Library cases only.
   */
  cites?: Readonly<{ anyOf: readonly string[] }> | "none";
}>;

export type ExampleReply = Readonly<{
  reply: string;
  /** For a bad reply: the grader that must catch it. */
  fails?: string;
  /** The data requests the example's first answer carried. */
  requests?: readonly DataRequest[];
  /** The `proposal_intent` the example's answer carried. */
  intent?: unknown;
  /** The library source ids the example's evidence cited; the case's `goodCitations` if absent. */
  citations?: readonly string[];
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
  /** The `proposal_intent` the good replies carried (proposal cases). */
  goodIntent?: unknown;
  /** The library source ids the good replies cited (library cases). */
  goodCitations?: readonly string[];
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
  /** The model's `proposal_intent`, as written; undefined when it proposed nothing. */
  proposalIntent?: unknown;
  /** The library source ids the reply's evidence cites (source `library`); none when absent. */
  citations?: readonly string[];
  costUsd: number;
  latencyMs: number;
  failureCode?: string;
}>;
