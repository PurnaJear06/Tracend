// Training proposals: a temporary block, a new weekly schedule, an exercise swap, an intensity or
// focus phase and a next-session adjustment. The content of every session comes from the rules
// plan or from a catalog link (B1); the model only chose which kind of change to ask for.
import {
  allowedExercises,
  catalogBySlug,
  type CatalogExercise,
  type EquipmentItem,
  exerciseCatalogV1,
} from "../onboarding/catalog.ts";
import { catalogV2BySlug, loadStepKgFor } from "../onboarding/catalog_v2.ts";
import { moderateEffortRpe } from "../onboarding/policy.ts";
import { jointStressLevels } from "../training/standard/joint_stress.ts";
import {
  addDays,
  basisOf,
  daysBetween,
  isoWeekday,
  minutesFor,
  payloadSessionSummary,
  planAsPayload,
  proposalExpiryHours,
  reasonText,
  sessionSummary,
  shortDate,
  weekdayName,
} from "./common.ts";
import { isRefusal, nextDateOnWeekdays, rulesTraining, spreadWeekdays } from "./plan_rules.ts";
import { refusals } from "./refusals.ts";
import type {
  AthleteState,
  BuildResult,
  CoachProposal,
  CoachProposalIntent,
  DisplayRow,
  ProposalEvidence,
  TrainingChange,
  TrainingPayloadExercise,
  TrainingPayloadWorkout,
} from "./types.ts";

type Refused = Extract<BuildResult, { ok: false }>;

/** The longest a temporary block may run. A longer change is a new schedule. */
export const maxBlockDays = 42;
/** A block starts when approved, so a start date may be at most this many days ahead. */
export const maxBlockStartLeadDays = 2;

/**
 * The deload: half the sets of every exercise (rounded up, at least one) at an effort of 7 or
 * lower. The reduction is in the range coaches use (about 40 to 60% of the volume) and is an
 * in-house choice; B5 (deloads) replaces it with the full rule when it ships.
 */
export const deloadRules = Object.freeze({ setFraction: 0.5, rpeCap: 7 });

/** Equipment that travels or fits a small space. */
export const minimalEquipment: readonly EquipmentItem[] = [
  "dumbbells",
  "kettlebells",
  "bands",
  "pull_up_bar",
  "bench",
];

const trainingEvidence = (extra: ProposalEvidence[] = []): ProposalEvidence[] => [
  {
    code: "TRAINING_STANDARD",
    label: "Tracend's weekly volume, effort and rest limits for your experience",
    source: "policy_evaluation",
  },
  {
    code: "ACTIVE_PLAN",
    label: "Your current plan",
    source: "plan_version",
  },
  ...extra,
];

/** Refusals that apply to every change to the plan; null when the plan may change. */
export function planChangeRefusal(state: AthleteState, allowDuringBlock = false): Refused | null {
  if (state.screening === "see_professional") return refusals.seeProfessional();
  if (!state.plan) return refusals.noPlan();
  if (!allowDuringBlock && state.plan.blockEndsOn !== null) {
    return refusals.blockActive(state.plan.blockEndsOn);
  }
  return null;
}

function build(
  state: AthleteState,
  fields: Readonly<{
    kind: CoachProposal["kind"];
    title: string;
    rationale: string;
    benefit: string;
    downside: string;
    confidence?: CoachProposal["confidence"];
    evidence?: ProposalEvidence[];
    endsOn?: string | null;
    expiresInHours?: number;
    beforeRows: DisplayRow[];
    afterRows: DisplayRow[];
    beforeSessions: ReturnType<typeof sessionSummary>;
    afterSessions: ReturnType<typeof sessionSummary>;
    change: TrainingChange;
  }>,
): BuildResult {
  return {
    ok: true,
    proposal: {
      kind: fields.kind,
      title: fields.title,
      rationale: fields.rationale,
      benefit: fields.benefit,
      downside: fields.downside,
      confidence: fields.confidence ?? "medium",
      evidence: trainingEvidence(fields.evidence),
      expiresInHours: fields.expiresInHours ?? proposalExpiryHours.default,
      endsOn: fields.endsOn ?? null,
      before: { rows: fields.beforeRows, sessions: fields.beforeSessions },
      after: { rows: fields.afterRows, sessions: fields.afterSessions },
      payload: { training: fields.change },
      basis: basisOf(state),
    },
  };
}

const plural = (count: number, word: string) => `${count} ${word}${count === 1 ? "" : "s"}`;

// ---------------------------------------------------------------------------------------------
// Temporary block

export function buildTemporaryBlock(
  intent: Extract<CoachProposalIntent, { kind: "temporary_block" }>,
  state: AthleteState,
): BuildResult {
  const blocked = planChangeRefusal(state);
  if (blocked) return blocked;
  const plan = state.plan!;
  const today = state.today;
  if (intent.endDate < intent.startDate || intent.endDate < today) return refusals.datesInvalid();
  if (daysBetween(today, intent.startDate) > maxBlockStartLeadDays) {
    return refusals.blockStartTooFar();
  }
  const days = daysBetween(intent.startDate < today ? today : intent.startDate, intent.endDate) + 1;
  if (days > maxBlockDays) return refusals.blockTooLong(maxBlockDays);

  const owned = state.profile.equipment.filter((item) => minimalEquipment.includes(item));
  const equipment: EquipmentItem[] = intent.setting === "bodyweight" ? [] : owned;
  const rules = rulesTraining(state, { equipment }, null);
  if (isRefusal(rules)) return rules;

  const setupText = equipment.length === 0
    ? "bodyweight only"
    : equipment.map((item) => item.replace("_", " ")).join(", ");
  const blockWeeks = Math.max(1, Math.ceil(days / 7));
  const title = `${equipment.length === 0 ? "Bodyweight" : "Home"} block until ${
    shortDate(intent.endDate)
  }`;
  return build(state, {
    kind: "temporary_block",
    title,
    rationale:
      `${reasonText(intent.reason, intent.note)} Until ${
        shortDate(intent.endDate)
      } your sessions use ${setupText}, with the same weekly volume limits as your plan. Your ` +
      "current plan comes back the day after.",
    benefit: "You keep training on the same days without the gym.",
    downside: equipment.length === 0
      ? "Bodyweight work can't load strength movements as heavily, so strength may stall for " +
        "the block. Your loads are still there when the block ends."
      : "Home equipment limits how heavy you can go, so strength may stall for the block. " +
        "Your loads are still there when the block ends.",
    endsOn: intent.endDate,
    beforeRows: [
      { label: "Plan", value: plan.title },
      { label: "Sessions", value: `${plural(plan.workouts.length, "session")} a week` },
      { label: "Equipment", value: "Your usual setup" },
    ],
    afterRows: [
      { label: "Plan", value: title },
      { label: "Sessions", value: `${plural(rules.workouts.length, "session")} a week` },
      { label: "Equipment", value: setupText },
      { label: "Ends", value: shortDate(intent.endDate) },
    ],
    beforeSessions: sessionSummary(plan.workouts),
    afterSessions: payloadSessionSummary(rules.workouts),
    change: {
      mode: "block",
      block_kind: "temporary_block",
      title,
      block_weeks: blockWeeks,
      ends_on: intent.endDate,
      weekly_structure: rules.workouts,
    },
  });
}

// ---------------------------------------------------------------------------------------------
// Weekly schedule

export function buildTrainingSchedule(
  intent: Extract<CoachProposalIntent, { kind: "training_schedule" }>,
  state: AthleteState,
): BuildResult {
  const blocked = planChangeRefusal(state);
  if (blocked) return blocked;
  const plan = state.plan!;
  const profile = state.profile;
  if (
    intent.weekdays !== undefined && intent.daysPerWeek !== undefined &&
    intent.weekdays.length !== intent.daysPerWeek
  ) {
    return refusals.invalidSchedule("The number of days doesn't match the days you listed.");
  }
  const count = intent.weekdays?.length ?? intent.daysPerWeek ?? profile.trainingWeekdays.length;
  const weekdays = intent.weekdays
    ? [...intent.weekdays]
    : spreadWeekdays(profile.trainingWeekdays, count);
  const minutes = intent.sessionMinutes ?? profile.sessionMinutes;
  const sameDays = weekdays.length === profile.trainingWeekdays.length &&
    weekdays.every((day, index) => day === profile.trainingWeekdays[index]);
  if (sameDays && minutes === profile.sessionMinutes) {
    return refusals.noChange("That is the schedule you already have.");
  }
  const rules = rulesTraining(state, { trainingWeekdays: weekdays, sessionMinutes: minutes }, plan);
  if (isRefusal(rules)) return rules;

  const dayList = (days: readonly number[]) => days.map(weekdayName).join(", ");
  return build(state, {
    kind: "training_schedule",
    title: `Train ${plural(weekdays.length, "day")} a week`,
    rationale: `${reasonText(intent.reason, intent.note)} Your plan is rebuilt for ${
      plural(weekdays.length, "session")
    } a week (${dayList(weekdays)}) of about ${minutes} minutes, for the next ${
      plural(intent.weeks, "week")
    }. Tracend's weekly volume and effort limits apply to the new week.`,
    benefit: "A week that fits the days and time you have.",
    downside: "Rebuilding the week reshuffles your exercises, so some loads need re-finding. " +
      "Loads for exercises you keep are carried over.",
    beforeRows: [
      { label: "Days", value: dayList(profile.trainingWeekdays) },
      { label: "Session length", value: `${profile.sessionMinutes} min` },
      { label: "Sessions", value: `${plural(plan.workouts.length, "session")} a week` },
    ],
    afterRows: [
      { label: "Days", value: dayList(weekdays) },
      { label: "Session length", value: `${minutes} min` },
      { label: "Sessions", value: `${plural(rules.workouts.length, "session")} a week` },
      { label: "Review after", value: plural(intent.weeks, "week") },
    ],
    beforeSessions: sessionSummary(plan.workouts),
    afterSessions: payloadSessionSummary(rules.workouts),
    change: {
      mode: "new_version",
      title: plan.title,
      block_weeks: intent.weeks,
      weekly_structure: rules.workouts,
      profile: { training_days: weekdays, session_minutes: minutes },
    },
  });
}

// ---------------------------------------------------------------------------------------------
// Exercise swap

const stressRank = (level: string) => jointStressLevels.indexOf(level as never);

/** A substitute is no harder on the knee, back or shoulder than the exercise it replaces. */
function noHarsherOnJoints(from: string, to: string): boolean {
  const before = catalogV2BySlug.get(from)?.jointStress;
  const after = catalogV2BySlug.get(to)?.jointStress;
  if (!before || !after) return false;
  return (["knee", "back", "shoulder"] as const).every((joint) =>
    stressRank(after[joint]) <= stressRank(before[joint])
  );
}

function jointTotal(slug: string): number {
  const stress = catalogV2BySlug.get(slug)?.jointStress;
  return stress
    ? stressRank(stress.knee) + stressRank(stress.back) + stressRank(stress.shoulder)
    : 99;
}

export function swapCandidates(
  fromSlug: string,
  state: AthleteState,
  alreadyIn: readonly string[],
): CatalogExercise[] {
  const links = catalogV2BySlug.get(fromSlug)?.substitutes ?? [];
  const allowed = new Set(
    allowedExercises(
      exerciseCatalogV1,
      state.profile.equipment,
      state.profile.experience,
      state.profile.avoidPatterns,
    ).map((exercise) => exercise.slug),
  );
  return links
    .filter((slug) => allowed.has(slug) && !alreadyIn.includes(slug))
    .filter((slug) => noHarsherOnJoints(fromSlug, slug))
    .map((slug) => catalogBySlug.get(slug)!)
    .sort((a, b) => jointTotal(a.slug) - jointTotal(b.slug));
}

export function buildExerciseSwap(
  intent: Extract<CoachProposalIntent, { kind: "exercise_swap" }>,
  state: AthleteState,
): BuildResult {
  const blocked = planChangeRefusal(state);
  if (blocked) return blocked;
  const plan = state.plan!;
  const from = catalogBySlug.get(intent.fromSlug);
  const holders = plan.workouts.filter((workout) =>
    workout.exercises.some((exercise) => exercise.slug === intent.fromSlug)
  );
  if (!from || holders.length === 0) return refusals.notInPlan();

  const inPlan = plan.workouts.flatMap((workout) =>
    workout.exercises.map((exercise) => exercise.slug).filter((slug): slug is string => !!slug)
  );
  const candidates = swapCandidates(intent.fromSlug, state, inPlan);
  let chosen: CatalogExercise | undefined;
  if (intent.toSlug !== undefined) {
    chosen = candidates.find((exercise) => exercise.slug === intent.toSlug);
    if (!chosen) {
      return inPlan.includes(intent.toSlug)
        ? refusals.noChange("That exercise is already in your plan.")
        : refusals.substituteNotAllowed();
    }
  } else {
    chosen = candidates[0];
    if (!chosen) return refusals.noSubstitute();
  }
  const to = chosen;

  const swapped = (workout: TrainingPayloadWorkout): TrainingPayloadWorkout => {
    const exercises: TrainingPayloadExercise[] = workout.exercises.map((exercise) => {
      if (exercise.slug !== intent.fromSlug) return exercise;
      // A new exercise has no logged load: the athlete finds it in the first session.
      const { start_load_kg: _dropped, ...rest } = exercise;
      return { ...rest, slug: to.slug, name: to.name, notes: `Replaces ${from.name}.` };
    });
    return { ...workout, exercises, estimated_minutes: minutesFor(exercises) };
  };
  const workouts = planAsPayload(plan).map((workout, index) =>
    plan.workouts[index].exercises.some((exercise) => exercise.slug === intent.fromSlug)
      ? swapped(workout)
      : workout
  );

  // Weekly sets for the new exercise's target muscle stay inside the policy maximum.
  const maxWeekly = state.profile.experience === "beginner" ? 12 : 20;
  const weekly = new Map<string, number>();
  for (const workout of workouts) {
    for (const exercise of workout.exercises) {
      const muscle = exercise.slug ? catalogBySlug.get(exercise.slug)?.muscles[0] : undefined;
      if (muscle) weekly.set(muscle, (weekly.get(muscle) ?? 0) + exercise.sets);
    }
  }
  if ((weekly.get(to.muscles[0]) ?? 0) > maxWeekly) {
    return refusals.infeasible(
      `${to.name} would push ${to.muscles[0]} past ${maxWeekly} sets a week.`,
    );
  }

  const sessionNames = holders.map((workout) => workout.name).join(", ");
  return build(state, {
    kind: "exercise_swap",
    title: `Swap ${from.name} for ${to.name}`,
    rationale:
      `${
        reasonText(intent.reason, intent.note)
      } ${to.name} replaces ${from.name} in ${sessionNames}, ` +
      "with the same sets, reps and effort. It trains the same movement and is no harder on " +
      "the knee, back or shoulder, and fits your equipment.",
    benefit: "The same training stimulus with an exercise that suits you better.",
    downside: "A new exercise has no logged load yet, so the first session is a feel-out.",
    beforeRows: [{ label: "Exercise", value: from.name }, {
      label: "In",
      value: sessionNames,
    }],
    afterRows: [{ label: "Exercise", value: to.name }, { label: "In", value: sessionNames }],
    beforeSessions: sessionSummary(plan.workouts),
    afterSessions: payloadSessionSummary(workouts),
    change: {
      mode: "new_version",
      title: plan.title,
      block_weeks: plan.blockWeeks,
      weekly_structure: workouts,
    },
  });
}

// ---------------------------------------------------------------------------------------------
// Intensity or focus phase

function capEffort(
  workouts: readonly TrainingPayloadWorkout[],
  cap: number,
  setFraction: number,
): { workouts: TrainingPayloadWorkout[]; changed: boolean } {
  let changed = false;
  const out = workouts.map((workout) => {
    const exercises = workout.exercises.map((exercise) => {
      const sets = setFraction === 1
        ? exercise.sets
        : Math.max(1, Math.ceil(exercise.sets * setFraction));
      const rpe = exercise.target_rpe === null ? null : Math.min(exercise.target_rpe, cap);
      if (sets !== exercise.sets || rpe !== exercise.target_rpe) changed = true;
      return { ...exercise, sets, target_rpe: rpe };
    });
    return { ...workout, exercises, estimated_minutes: minutesFor(exercises) };
  });
  return { workouts: out, changed };
}

const sumSets = (workouts: readonly { exercises: readonly { sets: number }[] }[]) =>
  workouts.reduce((total, workout) => total + workout.exercises.reduce((n, e) => n + e.sets, 0), 0);

export function buildIntensityOrPhase(
  intent: Extract<CoachProposalIntent, { kind: "intensity_or_phase" }>,
  state: AthleteState,
): BuildResult {
  const plan = state.plan;
  const endsBlockNow = intent.level === "normal";
  const blocked = planChangeRefusal(state, endsBlockNow);
  if (blocked) return blocked;
  const current = plan!;
  const endsOn = addDays(state.today, intent.weeks * 7 - 1);

  if (intent.level === "normal") {
    if (current.blockKind !== "intensity" && current.blockKind !== "focus") {
      return refusals.noChange("You're already training at your normal intensity.");
    }
    return build(state, {
      kind: "intensity_or_phase",
      title: "Return to your regular plan",
      rationale: `${reasonText(intent.reason, intent.note)} The current phase ends today and the ` +
        "plan it replaced returns.",
      benefit: "Back to your regular training.",
      downside: "If you were still feeling worn down, the regular plan asks more of you.",
      beforeRows: [{ label: "Plan", value: current.title }],
      afterRows: [{ label: "Plan", value: "Your regular plan" }],
      beforeSessions: sessionSummary(current.workouts),
      afterSessions: [],
      change: { mode: "end_block" },
    });
  }

  if (intent.level !== undefined) {
    if (state.screening === "moderate_until_cleared" && intent.level !== "deload") {
      return refusals.noChange(
        "Your plan is already held to moderate effort by your health check.",
      );
    }
    const cap = intent.level === "deload" ? deloadRules.rpeCap : moderateEffortRpe;
    const fraction = intent.level === "deload" ? deloadRules.setFraction : 1;
    const result = capEffort(planAsPayload(current), cap, fraction);
    if (!result.changed) return refusals.noChange("Your plan is already at that effort.");
    const label = intent.level === "deload" ? "Deload" : "Moderate effort";
    const title = `${label} until ${shortDate(endsOn)}`;
    return build(state, {
      kind: "intensity_or_phase",
      title,
      rationale:
        `${reasonText(intent.reason, intent.note)} For ${plural(intent.weeks, "week")} your ` +
        (intent.level === "deload"
          ? `sets are halved and effort stays at ${deloadRules.rpeCap} or below.`
          : `effort stays at ${moderateEffortRpe} or below (about three reps left in the tank).`) +
        ` Your regular plan returns after ${shortDate(endsOn)}.`,
      benefit: intent.level === "deload"
        ? "Recovery while you keep the habit and the movement patterns."
        : "Steadier training while you recover.",
      downside: "Less training stress for a short while, so progress pauses.",
      endsOn,
      beforeRows: [
        { label: "Effort", value: "Your regular effort" },
        { label: "Weekly sets", value: String(sumSets(planAsPayload(current))) },
      ],
      afterRows: [
        { label: "Effort", value: `RPE ${cap} or lower` },
        { label: "Weekly sets", value: String(sumSets(result.workouts)) },
        { label: "Until", value: shortDate(endsOn) },
      ],
      beforeSessions: sessionSummary(current.workouts),
      afterSessions: payloadSessionSummary(result.workouts),
      change: {
        mode: "block",
        block_kind: "intensity",
        title,
        block_weeks: intent.weeks,
        ends_on: endsOn,
        weekly_structure: result.workouts,
      },
    });
  }

  // A focus phase: the week rebuilt for strength or size, for a number of weeks.
  const focus = intent.focus!;
  if (focus === "strength" && state.screening === "moderate_until_cleared") {
    return refusals.screeningCapsIntensity();
  }
  const goal = focus === "strength" ? "strength" : "muscle_gain";
  if (state.goal?.goalType === goal) {
    return refusals.noChange(
      `Your plan is already built for ${focus === "strength" ? "strength" : "muscle size"}.`,
    );
  }
  if (focus === "strength" && !state.eligibility.trainingEligible) {
    return refusals.notEnoughTraining(state.eligibility.trainingDetail);
  }
  const rules = rulesTraining(state, { goal }, current);
  if (isRefusal(rules)) return rules;
  const title = `${focus === "strength" ? "Strength" : "Size"} phase until ${shortDate(endsOn)}`;
  return build(state, {
    kind: "intensity_or_phase",
    title,
    rationale:
      `${reasonText(intent.reason, intent.note)} For ${plural(intent.weeks, "week")} your ` +
      `sessions are built for ${focus === "strength" ? "strength" : "muscle size"}, inside ` +
      `Tracend's volume and effort limits. Your regular plan returns after ${shortDate(endsOn)}.`,
    benefit: focus === "strength"
      ? "A focused block on heavier, lower-rep work."
      : "A focused block on volume for muscle size.",
    downside: "Other qualities get less attention during the phase.",
    confidence: "medium",
    endsOn,
    beforeRows: [
      {
        label: "Built for",
        value: state.goal ? state.goal.goalType.replace("_", " ") : "your goal",
      },
      { label: "Sessions", value: `${plural(current.workouts.length, "session")} a week` },
    ],
    afterRows: [
      { label: "Built for", value: focus === "strength" ? "strength" : "muscle size" },
      { label: "Sessions", value: `${plural(rules.workouts.length, "session")} a week` },
      { label: "Until", value: shortDate(endsOn) },
    ],
    beforeSessions: sessionSummary(current.workouts),
    afterSessions: payloadSessionSummary(rules.workouts),
    change: {
      mode: "block",
      block_kind: "focus",
      title,
      block_weeks: intent.weeks,
      ends_on: endsOn,
      weekly_structure: rules.workouts,
    },
  });
}

// ---------------------------------------------------------------------------------------------
// Next-session adjustment

const kgText = (value: number) => `${Number.isInteger(value) ? value : value.toFixed(1)} kg`;

export function buildNextSessionAdjustment(
  intent: Extract<CoachProposalIntent, { kind: "next_session_adjustment" }>,
  state: AthleteState,
): BuildResult {
  const blocked = planChangeRefusal(state);
  if (blocked) return blocked;
  const plan = state.plan!;
  const scheduled = plan.workouts.filter((workout) => workout.weekday !== null);

  let date: string | null;
  if (intent.session === "today") {
    const todaysDay = isoWeekday(state.today);
    date = scheduled.some((workout) => workout.weekday === todaysDay) && !state.todayWorkoutDone
      ? state.today
      : null;
  } else {
    date = nextDateOnWeekdays(state.today, scheduled.map((workout) => workout.weekday!));
  }
  if (date === null) return refusals.noUpcomingSession();
  const index = plan.workouts.findIndex((workout) => workout.weekday === isoWeekday(date));
  const target = plan.workouts[index];

  if (intent.direction === "heavier" && !state.eligibility.trainingEligible) {
    return refusals.notEnoughTraining(state.eligibility.trainingDetail);
  }

  let changed = false;
  const rows: DisplayRow[] = [];
  const afterRows: DisplayRow[] = [];
  const exercises: TrainingPayloadExercise[] = planAsPayload(plan)[index].exercises.map(
    (exercise, order) => {
      const entry = target.exercises[order];
      const catalog = entry.slug ? catalogBySlug.get(entry.slug) : undefined;
      const step = catalog ? loadStepKgFor(catalog) : null;
      const progression = state.progression.find((item) => item.exerciseKey === entry.slug);
      const baseLoad = progression?.loadKg ?? entry.targetLoadKg;
      if (intent.direction === "lighter") {
        const sets = exercise.sets >= 3 ? exercise.sets - 1 : exercise.sets;
        const rpe = exercise.target_rpe === null ? null : Math.max(6, exercise.target_rpe - 1);
        const load = baseLoad !== null && step !== null ? Math.max(0, baseLoad - step) : null;
        if (sets !== exercise.sets || rpe !== exercise.target_rpe || load !== null) {
          changed = true;
          rows.push({
            label: entry.name,
            value: `${exercise.sets} sets${baseLoad === null ? "" : `, ${kgText(baseLoad)}`}`,
          });
          afterRows.push({
            label: entry.name,
            value: `${sets} sets${load === null ? "" : `, ${kgText(load)}`}`,
          });
        }
        return {
          ...exercise,
          sets,
          target_rpe: rpe,
          ...(load === null ? {} : { start_load_kg: load }),
        };
      }
      const qualifies = progression !== undefined && progression.confidence === "high" &&
        (progression.action === "add_load" || progression.action === "add_reps") &&
        progression.loadKg !== null && step !== null;
      if (!qualifies) return exercise;
      const load = progression!.loadKg! + step!;
      changed = true;
      rows.push({ label: entry.name, value: kgText(progression!.loadKg!) });
      afterRows.push({ label: entry.name, value: kgText(load) });
      return { ...exercise, start_load_kg: load };
    },
  );
  if (!changed) {
    return intent.direction === "heavier"
      ? refusals.heavierNotSupported(
        "Your logged sets don't support going heavier on that session: they say to hold " +
          "your current loads or you haven't logged enough yet.",
      )
      : refusals.noChange("That session is already as light as it goes.");
  }
  const adjusted: TrainingPayloadWorkout = {
    ...planAsPayload(plan)[index],
    exercises: exercises.map((exercise) => ({
      ...exercise,
      notes: [
        exercise.notes,
        intent.direction === "lighter" ? "Coach: lighter today." : "Coach: a step heavier today.",
      ]
        .filter(Boolean).join(" "),
    })),
  };
  const workouts = planAsPayload(plan).map((workout, i) =>
    i === index ? { ...adjusted, estimated_minutes: minutesFor(adjusted.exercises) } : workout
  );
  const when = intent.session === "today"
    ? "today"
    : `on ${weekdayName(isoWeekday(date))} ${shortDate(date)}`;
  const title = `${intent.direction === "lighter" ? "Lighter" : "Heavier"} ${target.name} ${when}`
    .slice(0, 120);
  return build(state, {
    kind: "next_session_adjustment",
    title,
    rationale: `${reasonText(intent.reason, intent.note)} ${target.name} ${when} is adjusted` +
      (intent.direction === "lighter"
        ? ": one set fewer on longer exercises, effort one point lower, and loads one step lighter."
        : ": loads one step above your target where your logged sets say you're ready.") +
      ` The rest of your plan is unchanged and your regular plan returns after ${shortDate(date)}.`,
    benefit: intent.direction === "lighter"
      ? "A session you can finish well while you recover."
      : "A little more load where your logged sets support it.",
    downside: intent.direction === "lighter"
      ? "Less training stress this session, so that day's progress pauses."
      : "A heavier session is harder to recover from; stop sets early if form slips.",
    confidence: "medium",
    expiresInHours: proposalExpiryHours.next_session,
    endsOn: date,
    evidence: [{
      code: "LOGGED_SETS",
      label: "Your recently logged sets and next-session targets",
      source: "workout_history",
    }],
    beforeRows: rows,
    afterRows,
    beforeSessions: sessionSummary([target]),
    afterSessions: payloadSessionSummary([workouts[index]]),
    change: {
      mode: "block",
      block_kind: "next_session",
      title,
      block_weeks: 1,
      ends_on: date,
      weekly_structure: workouts,
    },
  });
}
