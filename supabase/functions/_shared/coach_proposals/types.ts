// Coach proposals (chunk A8). Coach may ask for a change in chat; deterministic rules decide whether
// the change is allowed and compute every number in it; the athlete approves with one tap, which
// writes a new version and an audit event (Architecture 2 and 3). The model supplies only an
// intent: a kind, parameters from closed vocabularies, dates and the athlete's own figures. Nothing
// in this file or its neighbours calls a model.
import type { AvoidablePattern, EquipmentItem, ExperienceLevel } from "../onboarding/catalog.ts";
import type { DailyActivity, Goal, Sex } from "../onboarding/answers.ts";
import type { Muscle } from "../onboarding/catalog.ts";
import type { ScreeningOutcome } from "../training/screening/outcome.ts";
import type { GoalPhaseSummary, GoalTarget } from "../training/goal_phase/types.ts";
import type { ProgressionTarget } from "../training/progression/targets.ts";

export const proposalKinds = [
  "temporary_block",
  "training_schedule",
  "exercise_swap",
  "intensity_or_phase",
  "goal_or_phase",
  "nutrition_targets",
  "next_session_adjustment",
] as const;
export type ProposalKind = typeof proposalKinds[number];

/** Why the athlete or Coach wants the change; the card words each one itself. */
export const proposalReasons = [
  "travel",
  "time",
  "fatigue",
  "missed_sessions",
  "illness_recovery",
  "plateau",
  "preference",
  "equipment_change",
  "diet_fatigue",
  "injury_caution",
  "athlete_request",
] as const;
export type ProposalReason = typeof proposalReasons[number];

export const blockSettings = ["bodyweight", "minimal_equipment"] as const;
export type BlockSetting = typeof blockSettings[number];

export const intensityLevels = ["deload", "moderate", "normal"] as const;
export type IntensityLevel = typeof intensityLevels[number];

export const trainingFocuses = ["strength", "size"] as const;
export type TrainingFocus = typeof trainingFocuses[number];

export const goalPhases = ["cut", "maintenance", "diet_break", "gain"] as const;
export type GoalPhase = typeof goalPhases[number];

export const nutritionDirections = ["lower", "raise", "maintenance"] as const;
export type NutritionDirection = typeof nutritionDirections[number];

export const sessionDirections = ["lighter", "heavier"] as const;
export type SessionDirection = typeof sessionDirections[number];

type Common = Readonly<{ reason: ProposalReason; note?: string }>;

/**
 * What Coach asks for. Every number is either an athlete's own figure copied from their message
 * (requestedCalories, targetWeightKg, a date, a count of days or weeks) or absent. The rules check
 * each one and compute everything that becomes durable.
 */
export type CoachProposalIntent =
  | (
    & Common
    & Readonly<{
      kind: "temporary_block";
      setting: BlockSetting;
      startDate: string;
      endDate: string;
    }>
  )
  | (
    & Common
    & Readonly<{
      kind: "training_schedule";
      daysPerWeek?: number;
      weekdays?: readonly number[];
      sessionMinutes?: number;
      weeks: number;
    }>
  )
  | (Common & Readonly<{ kind: "exercise_swap"; fromSlug: string; toSlug?: string }>)
  | (
    & Common
    & Readonly<{
      kind: "intensity_or_phase";
      level?: IntensityLevel;
      focus?: TrainingFocus;
      weeks: number;
    }>
  )
  | (
    & Common
    & Readonly<{
      kind: "goal_or_phase";
      phase: GoalPhase;
      targetWeightKg?: number;
      targetDate?: string;
    }>
  )
  | (
    & Common
    & Readonly<{
      kind: "nutrition_targets";
      direction: NutritionDirection;
      requestedCalories?: number;
    }>
  )
  | (
    & Common
    & Readonly<{
      kind: "next_session_adjustment";
      direction: SessionDirection;
      session: "today" | "next";
    }>
  );

// ---------------------------------------------------------------------------------------------
// Athlete state: what the builder reads. The service assembles it from the database; tests build
// it directly.

export type BlockKind = "temporary_block" | "intensity" | "focus" | "next_session";

export type StatePlanExercise = Readonly<{
  /**
   * The planned exercise's id: a next-session target belongs to it, not to the slug (a lift on a
   * heavy and a light day has two). Null from an older payload, which then has no target.
   */
  plannedExerciseId: string | null;
  slug: string | null;
  name: string;
  sets: number;
  repMin: number;
  repMax: number;
  targetRpe: number | null;
  restSeconds: number;
  notes: string;
  targetLoadKg: number | null;
}>;

export type StatePlanWorkout = Readonly<{
  name: string;
  objective: string;
  /** ISO weekday, 1 = Monday; null for a plan without fixed days. */
  weekday: number | null;
  estimatedMinutes: number;
  warmUp: string;
  coolDown: string;
  exercises: readonly StatePlanExercise[];
}>;

export type StatePlan = Readonly<{
  versionId: string;
  planId: string;
  versionNumber: number;
  title: string;
  blockWeeks: number;
  workouts: readonly StatePlanWorkout[];
  /** Set while the active version is a temporary block: the last day it applies. */
  blockEndsOn: string | null;
  blockKind: BlockKind | null;
}>;

export type StateNutrition = Readonly<{
  versionId: string;
  calories: number;
  proteinG: number;
  carbohydrateG: number;
  fatG: number;
}>;

export type StateGoal = Readonly<{
  id: string;
  goalType: Goal;
  activatedOn: string | null;
  target: GoalTarget;
  /** The phase recorded by an approved proposal, or null. */
  phase: GoalPhase | null;
  phaseEndsOn: string | null;
}>;

export type StateEligibility = Readonly<{
  trainingEligible: boolean;
  trainingDetail: string;
  nutritionEligible: boolean;
  nutritionDetail: string;
}>;

export type StateProfile = Readonly<{
  sex: Sex;
  age: number;
  birthYear: number;
  heightCm: number;
  experience: ExperienceLevel;
  dailyActivity: DailyActivity;
  equipment: readonly EquipmentItem[];
  avoidPatterns: readonly AvoidablePattern[];
  trainingWeekdays: readonly number[];
  sessionMinutes: number;
  priorityMuscles: readonly Muscle[];
  strongMuscles: readonly Muscle[];
}>;

export type AthleteState = Readonly<{
  /** The athlete's local date (YYYY-MM-DD). */
  today: string;
  profile: StateProfile;
  screening: ScreeningOutcome;
  plan: StatePlan | null;
  nutrition: StateNutrition | null;
  goal: StateGoal | null;
  /** The goal phase summary computed from the athlete's weight readings (B7). */
  goalPhase: GoalPhaseSummary;
  eligibility: StateEligibility;
  /** Next-session targets from the sets the athlete logged (B3); empty without history. */
  progression: readonly ProgressionTarget[];
  /** True when today's workout is already logged as completed. */
  todayWorkoutDone: boolean;
  /** The athlete's message in this turn; used to confirm a figure came from the athlete. */
  athleteMessage?: string;
}>;

// ---------------------------------------------------------------------------------------------
// The proposal the builder returns and the database stores.

export type TrainingPayloadExercise = Readonly<{
  exercise_order: number;
  slug: string | null;
  name: string;
  sets: number;
  rep_min: number;
  rep_max: number;
  target_rpe: number | null;
  rest_seconds: number;
  notes: string;
  start_load_kg?: number;
}>;

export type TrainingPayloadWorkout = Readonly<{
  workout_order: number;
  name: string;
  objective: string;
  preferred_weekday: number | null;
  estimated_minutes: number;
  warm_up_guidance: string;
  cool_down_guidance: string;
  exercises: readonly TrainingPayloadExercise[];
}>;

/**
 * How approval changes the plan. `new_version` replaces the active version; `block` replaces it
 * until `ends_on`, after which the previous plan is restored; `end_block` restores it now.
 */
export type TrainingChange =
  | Readonly<{
    mode: "new_version";
    title: string;
    block_weeks: number;
    weekly_structure: readonly TrainingPayloadWorkout[];
    profile?: Readonly<{ training_days: readonly number[]; session_minutes: number }>;
  }>
  | Readonly<{
    mode: "block";
    block_kind: BlockKind;
    /** On an effort block: which one. The deload rules read it to tell a deload from moderate effort. */
    intensity_level?: Exclude<IntensityLevel, "normal">;
    title: string;
    block_weeks: number;
    ends_on: string;
    weekly_structure: readonly TrainingPayloadWorkout[];
  }>
  | Readonly<{ mode: "end_block" }>;

export type NutritionChange = Readonly<{
  calories: number;
  protein_g: number;
  carbohydrate_g: number;
  fat_g: number;
  rationale: string;
}>;

export type GoalChange = Readonly<{
  goal_type: Goal;
  phase: GoalPhase;
  phase_started_on: string;
  phase_ends_on: string | null;
  target?: Readonly<{ weight_kg?: number; date?: string }>;
}>;

export type ProposalPayload = Readonly<{
  training?: TrainingChange;
  nutrition?: NutritionChange;
  goal?: GoalChange;
}>;

/** One line of the card's before or after column: a label and its value. */
export type DisplayRow = Readonly<{ label: string; value: string }>;

export type DisplaySession = Readonly<{
  weekday: number | null;
  name: string;
  exercises: number;
  minutes: number;
}>;

export type ProposalSnapshot = Readonly<{
  rows: readonly DisplayRow[];
  sessions?: readonly DisplaySession[];
}>;

export type ProposalEvidence = Readonly<{ code: string; label: string; source: string }>;

/** The versions the proposal was computed from; approval refuses if any has changed. */
export type ProposalBasis = Readonly<{
  training_version_id: string | null;
  nutrition_version_id: string | null;
  goal_id: string | null;
  screening: ScreeningOutcome;
  /**
   * The change-eligibility gates the build required (nutrition_change, training_change). Approval
   * runs them again and expires the proposal when one no longer passes.
   */
  gates: readonly ("nutrition_change" | "training_change")[];
}>;

export type CoachProposal = Readonly<{
  kind: ProposalKind;
  title: string;
  rationale: string;
  benefit: string;
  downside: string;
  confidence: "low" | "medium" | "high";
  evidence: readonly ProposalEvidence[];
  /** Hours the athlete has to answer. */
  expiresInHours: number;
  /** Last day a temporary change applies, when it has one. */
  endsOn: string | null;
  before: ProposalSnapshot;
  after: ProposalSnapshot;
  payload: ProposalPayload;
  basis: ProposalBasis;
}>;

/** Why a change was refused; `refusals.ts` words each one for the athlete. */
export const refusalCodes = [
  "screening_see_professional",
  "screening_caps_intensity",
  "no_active_plan",
  "no_active_nutrition",
  "no_active_goal",
  "no_recent_weight",
  "not_enough_logging",
  "not_enough_training_evidence",
  "below_calorie_floor",
  "above_calorie_ceiling",
  "weight_loss_too_fast",
  "weight_near_healthy_floor",
  "target_below_healthy_floor",
  "target_wrong_direction",
  "target_date_invalid",
  "cut_too_long",
  "diet_break_needs_fat_loss",
  "already_on_target",
  "already_in_phase",
  "no_change",
  "dates_invalid",
  "block_too_long",
  "block_start_too_far",
  "block_already_active",
  "plan_infeasible",
  "exercise_not_in_plan",
  "no_substitute",
  "substitute_not_allowed",
  "invalid_schedule",
  "no_upcoming_session",
  "heavier_not_supported",
  "figure_not_from_athlete",
  "invalid_intent",
  "profile_incomplete",
  "plan_changed",
  "screening_changed",
  "evidence_changed",
] as const;
export type RefusalCode = typeof refusalCodes[number];

export type BuildResult =
  | Readonly<{ ok: true; proposal: CoachProposal }>
  | Readonly<{ ok: false; code: RefusalCode; reason: string }>;
