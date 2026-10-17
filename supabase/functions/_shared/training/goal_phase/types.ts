// Shapes of the goal phase review: its inputs (body readings and the active goal) and what it
// computes. All of it is deterministic arithmetic on the athlete's own data (Architecture rule 1);
// Coach only explains the result.

export type WeightReading = Readonly<{ date: string; kg: number }>;

/** What the athlete set as the end point of the goal; every field is optional. */
export type GoalTarget = Readonly<{
  weightKg: number | null;
  bodyFatMinPct: number | null;
  bodyFatMaxPct: number | null;
  physique: string | null;
  physiqueNote: string | null;
  date: string | null;
}>;

export const noGoalTarget: GoalTarget = Object.freeze({
  weightKg: null,
  bodyFatMinPct: null,
  bodyFatMaxPct: null,
  physique: null,
  physiqueNote: null,
  date: null,
});

export type GoalPhaseInputs = Readonly<{
  /** The coaching date (YYYY-MM-DD) the review is made for. */
  today: string;
  goalType: string | null;
  /** The date the goal became active, or null when unknown. */
  activatedOn: string | null;
  heightCm: number | null;
  target: GoalTarget;
  readings: readonly WeightReading[];
}>;

export type ExcludedReading = Readonly<{
  date: string;
  kg: number;
  reason: "implausible_jump";
}>;

export type PhaseConfidence = "high" | "medium" | "low";

/** Every recorded weight reading, from the first one; present only when it starts before the phase. */
export type RecordedHistory = Readonly<{
  startDate: string;
  startWeightKg: number;
  /** Current minus start, in kg; negative is a loss. */
  changeKg: number;
  changePct: number;
  weeks: number;
  readingsUsed: number;
  /** Too few readings or too long a gap to confirm the trend between the two ends. */
  sparse: boolean;
  /** The input held the most readings the RPC returns, so older ones may exist. */
  capped: boolean;
}>;

/**
 * The run of falling weight that ends now, from its high point (a rise smaller than the
 * tolerance does not end it). Present only when it differs from the goal phase: it began before
 * the goal phase, or after the phase began (weight rose, then fell).
 */
export type ContinuousLoss = Readonly<{
  startDate: string;
  startWeightKg: number;
  changeKg: number;
  changePct: number;
  weeks: number;
  /** Average kg a week over the run; negative is a loss. */
  weeklyRateKg: number;
  /** Enough readings, none too far apart; only a confirmed run feeds the review. */
  confirmed: boolean;
  beganBeforeGoalPhase: boolean;
}>;

export type GoalPhaseSummary = Readonly<{
  hasGoal: boolean;
  goalType: string | null;
  /** Goal activation, or the first reading when activation is unknown. */
  phaseStart: string | null;
  phaseStartSource: "goal_activation" | "first_reading" | null;
  /** Date of the first reading on or after the phase start. */
  firstReadingDate: string | null;
  startWeightKg: number | null;
  currentWeightKg: number | null;
  currentDate: string | null;
  /** Current minus start, in kg; negative is a loss. */
  changeKg: number | null;
  /** The change as a percentage of the start weight. */
  changePct: number | null;
  weeks: number | null;
  weeklyRateKg: number | null;
  /** Average weekly rate as a percentage of the start weight. */
  weeklyRatePct: number | null;
  /** Least-squares kg a week over the last 28 days, when there are enough readings. */
  recentRateKgPerWeek: number | null;
  bmi: number | null;
  heightCm: number | null;
  hasTarget: boolean;
  target: GoalTarget;
  readingsUsed: number;
  /** The latest reading is older than the freshness limit (staleReadingDays). */
  latestReadingStale: boolean;
  /** Whole days from the latest reading to the coaching date, or null without a reading. */
  latestReadingAgeDays: number | null;
  history: RecordedHistory | null;
  continuousLoss: ContinuousLoss | null;
  excluded: readonly ExcludedReading[];
  confidence: PhaseConfidence;
  notes: readonly string[];
}>;

export const reviewOutcomes = [
  "continue",
  "ask_target",
  "consider_maintenance_or_diet_break",
  "target_reached",
  "slow_down",
] as const;

export type ReviewOutcome = typeof reviewOutcomes[number];

export type ReviewReason = Readonly<{
  code: string;
  detail: string;
  sources: readonly string[];
}>;

export type GoalPhaseReview = Readonly<{
  outcome: ReviewOutcome;
  reasons: readonly ReviewReason[];
  /** True whenever no target exists, whatever the outcome: Coach asks for one. */
  needsTarget: boolean;
}>;
