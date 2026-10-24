// Contract 7 contributor (A10): the athlete's plan as Coach needs it to answer "what do I do
// today?". It reads get_coach_plan_state_v1 (service role) and renders, with deterministic code,
// today's planned session (or the next one) with each exercise's sets, reps, rest and plan load,
// the next-session target Tracend computed from the sets the athlete logged (B3) and the last
// logged result, the next seven days from the athlete's own date with each session's muscles and
// any muscle trained on consecutive days (not bounded by the calendar week), the rest of the plan
// by day, the plan's sets per muscle for the week, and catalog alternatives for bodyweight and
// minimal home kit. Coach explains and chooses among these; it never changes the plan or a
// target. Replaces the progression contributor (B3), which only listed the targets.
import type { AvoidablePattern } from "../../onboarding/catalog.ts";
import {
  avoidablePatterns,
  type ExperienceLevel,
  experienceLevels,
} from "../../onboarding/catalog.ts";
import { catalogV2BySlug } from "../../onboarding/catalog_v2.ts";
import { homeAlternativesFor, minimalHomeKit } from "../../training/home_alternatives.ts";
import {
  type DayExercise,
  sessionMuscles,
  type TrainedMuscle,
} from "../../training/schedule/muscles.ts";
import {
  addDays,
  buildWeekAhead,
  dayOf,
  renderWeekAheadMarked,
  type ScheduleNote,
  type SchedulePoint,
  type WeekAhead,
  weekAheadDays,
} from "../../training/schedule/week_ahead.ts";
import {
  describeLastSessionMarked,
  describeTargetAdviceMarked,
  parseProgressionSummary,
  type ProgressionTarget,
} from "../../training/progression/targets.ts";
import { plain, record } from "../../recorded_text.ts";
import { heartRateInputsReadKey } from "../../training/heart_rate/inputs.ts";
import type { HeartRateInputs } from "../../training/heart_rate/profile.ts";
import { loadWorkoutLoadSignals } from "../../training/heart_rate/load_signals_inputs.ts";
import type { LoadSignals } from "../../training/heart_rate/load_signals.ts";
import { heartRateInputsFromService } from "./heart_rate.ts";
import {
  blockOf,
  type CoachContextContributor,
  type CoachContextInput,
  sharedRead,
} from "../host.ts";
import { coachServiceRpc, type StateSource, stateSourceFromRpc } from "../service_source.ts";

export const trainingPlanContributorId = "training_plan";
/** The key under which the turn's plan state is read once for every contributor that needs it. */
export const planStateReadKey = "plan_state";
// Sized for the largest plan the app allows: 7 sessions of 9 exercises with long names is about
// 9,900 characters (training_plan_test.ts), and the host's own ceiling is 12,000.
export const trainingPlanContributorBudgetChars = 12_000;

type Json = Record<string, unknown>;
const rec = (value: unknown): Json =>
  value && typeof value === "object" && !Array.isArray(value) ? value as Json : {};
const list = (value: unknown): Json[] => Array.isArray(value) ? value.map(rec) : [];
const num = (value: unknown): number | null =>
  typeof value === "number" && Number.isFinite(value) ? value : null;
const str = (value: unknown): string => typeof value === "string" ? value : "";

export type PlanExercise = Readonly<{
  id: string;
  name: string;
  slug: string | null;
  sets: number;
  repMin: number;
  repMax: number;
  restSeconds: number | null;
  targetRpe: number | null;
  loadKg: number | null;
}>;

export type PlanSession = Readonly<{
  id: string;
  order: number | null;
  name: string;
  weekday: number | null;
  minutes: number | null;
  exercises: readonly PlanExercise[];
}>;

export type PlanState = Readonly<{
  localDate: string;
  weekday: number;
  /** The equipment named at onboarding; null when the athlete never answered. */
  equipment: readonly string[] | null;
  avoid: readonly AvoidablePattern[];
  /** The athlete's level (get_coach_plan_state_v1 1.2); intermediate from an older payload. */
  experience: ExperienceLevel;
  title: string;
  version: number | null;
  sessionsPerWeek: number | null;
  sessions: readonly PlanSession[];
  /**
   * When the active version is a temporary block: its last day and the sessions the athlete
   * returns to after it. Null for an ordinary plan.
   */
  afterBlock: Readonly<{ endsOn: string; sessions: readonly PlanSession[] }> | null;
  /** Sessions finished this ISO week: planned workout id and date. */
  completed: readonly Readonly<{
    id: string;
    localDate: string;
    /** The finished workout's name, day and order: it may belong to an earlier plan version. */
    name: string;
    weekday: number | null;
    order: number | null;
  }>[];
  /**
   * Sessions finished yesterday and today whatever the calendar week, with their exercises: the
   * week-ahead schedule needs yesterday on a Monday. Empty from an older payload.
   */
  recent: readonly Readonly<{
    id: string;
    localDate: string;
    name: string;
    exercises: readonly DayExercise[];
  }>[];
  /**
   * Workouts the athlete logged sets in and left unfinished that they have not saved or discarded
   * (get_coach_plan_state_v1 1.3), the last 28 days. Empty from an older payload. They trained:
   * they are neither done nor missed.
   */
  unfinished: readonly UnfinishedWorkout[];
  targets: readonly ProgressionTarget[];
}>;

export type UnfinishedWorkout = Readonly<{
  id: string;
  localDate: string;
  name: string;
  loggedSets: number;
  /** The athlete can still save or discard it on Today (7 days after its own day). */
  offerable: boolean;
}>;

/** The sessions in a plan state's `sessions` or `after_block.sessions` list. */
function parseSessions(value: unknown): PlanSession[] {
  return list(value).map((session): PlanSession => ({
    id: str(session.planned_workout_id),
    order: num(session.order),
    name: str(session.name),
    weekday: num(session.weekday),
    minutes: num(session.minutes),
    exercises: list(session.exercises).map((exercise): PlanExercise => ({
      id: str(exercise.planned_exercise_id),
      name: str(exercise.name),
      slug: typeof exercise.slug === "string" ? exercise.slug : null,
      sets: num(exercise.sets) ?? 0,
      repMin: num(exercise.rep_min) ?? 0,
      repMax: num(exercise.rep_max) ?? 0,
      restSeconds: num(exercise.rest_seconds),
      targetRpe: num(exercise.target_rpe),
      loadKg: num(exercise.load_kg),
    })),
  }));
}

/** The plan state in a get_coach_plan_state_v1 payload, or null without an active plan. */
export function parsePlanState(payload: unknown): PlanState | null {
  const body = rec(payload);
  if (!str(body.schema_version).startsWith("1.")) return null;
  const plan = rec(body.plan);
  if (Object.keys(plan).length === 0) return null;
  const weekday = num(body.weekday);
  if (weekday === null || typeof body.local_date !== "string") return null;
  const sessions = parseSessions(body.sessions);
  const afterBlock = rec(body.after_block);
  const avoid = Array.isArray(body.avoid_patterns)
    ? body.avoid_patterns.filter((item): item is AvoidablePattern =>
      avoidablePatterns.includes(item as AvoidablePattern)
    )
    : [];
  return {
    localDate: body.local_date,
    weekday,
    equipment: Array.isArray(body.equipment)
      ? body.equipment.filter((item): item is string => typeof item === "string")
      : null,
    avoid,
    experience: experienceLevels.find((level) => level === body.experience) ?? "intermediate",
    title: str(plan.title),
    version: num(plan.version_number),
    sessionsPerWeek: num(plan.sessions_per_week),
    sessions,
    afterBlock: typeof afterBlock.ends_on === "string"
      ? { endsOn: afterBlock.ends_on, sessions: parseSessions(afterBlock.sessions) }
      : null,
    completed: list(body.completed_this_week).map((row) => ({
      id: str(row.planned_workout_id),
      localDate: str(row.local_date),
      name: str(row.name),
      weekday: num(row.weekday),
      order: num(row.order),
    })),
    recent: list(body.recent_completed).map((row) => ({
      id: str(row.planned_workout_id),
      localDate: str(row.local_date),
      name: str(row.name),
      exercises: list(row.exercises).map((exercise) => ({
        slug: typeof exercise.slug === "string" ? exercise.slug : null,
        sets: num(exercise.sets) ?? 0,
      })),
    })),
    unfinished: list(body.unfinished).map((row): UnfinishedWorkout => ({
      id: str(row.planned_workout_id),
      localDate: str(row.local_date),
      name: str(row.name),
      loggedSets: num(row.logged_sets) ?? 0,
      offerable: row.offerable !== false,
    })).filter((row) => row.localDate !== "" && row.loggedSets > 0),
    targets: parseProgressionSummary(body.progression),
  };
}

const dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
const dayName = (weekday: number | null) =>
  weekday === null ? "no set day" : dayNames[weekday - 1] ?? "no set day";

// The plan's sets, reps, rest, loads and names are the athlete's approved plan: records, marked as
// such (`../../recorded_text.ts`). The rules of the block, its windows and its home options are
// Tracend's fixed wording and ground nothing.
const prescription = (exercise: PlanExercise) =>
  record(
    `${exercise.sets} x ${
      exercise.repMin === exercise.repMax
        ? exercise.repMin
        : `${exercise.repMin}-${exercise.repMax}`
    }`,
  );

export type FinishedWorkout = PlanState["completed"][number];

const finishedCache = new WeakMap<PlanState, ReadonlyMap<string, FinishedWorkout>>();

/** ISO weekday (1 is Monday) of a YYYY-MM-DD date. */
const isoWeekday = (date: string) => ((dayOf(date) + 3) % 7) + 1;

/**
 * Which of the sessions in force this week each finished workout counts for, as a map from the
 * session's id to the workout. One workout finishes at most one session, and a session is finished
 * by at most one workout.
 * - A workout finishes the session with its own id.
 * - Otherwise it was finished under another plan version, and counts for a session of the plan in
 *   force whose pool does not hold its id (inside a plan, a different id is a different workout,
 *   whatever its name): first every such workout takes the session with the same name nearest to
 *   the day it was done (a name that exists but is taken finishes nothing), then a workout whose
 *   name no session has takes the session with the same day and order.
 * Names are not unique and are never the only evidence against an id the plan knows.
 */
export function matchFinished(state: PlanState): ReadonlyMap<string, FinishedWorkout> {
  const cached = finishedCache.get(state);
  if (cached) return cached;
  const candidates = weekSessions(state);
  const poolHolding = (session: PlanSession): readonly PlanSession[] =>
    state.afterBlock?.sessions.some((item) => item.id === session.id)
      ? state.afterBlock.sessions
      : state.sessions;
  const result = new Map<string, FinishedWorkout>();
  const rows = [...state.completed].sort((a, b) => a.localDate.localeCompare(b.localDate));
  const placed = new Set<FinishedWorkout>();
  for (const row of rows) {
    const own = candidates.find((session) => session.id === row.id && !result.has(session.id));
    if (own) {
      result.set(own.id, row);
      placed.add(row);
    }
  }
  const sameName = (session: PlanSession, row: FinishedWorkout) =>
    row.name !== "" && session.name.toLowerCase() === row.name.toLowerCase();
  const eligibleFor = (row: FinishedWorkout) =>
    candidates.filter((session) =>
      !result.has(session.id) && !poolHolding(session).some((item) => item.id === row.id)
    );
  // Phase 1: every leftover workout counts for a session of the same name, nearest to the day it
  // was done. A workout whose name exists in the plan but whose sessions are all taken finishes
  // nothing: it must not spill onto another session.
  for (const row of rows) {
    if (placed.has(row)) continue;
    const doneWeekday = isoWeekday(row.localDate);
    const nearest = eligibleFor(row).filter((session) =>
      sameName(session, row)
    ).sort((a, b) =>
      Math.abs((a.weekday ?? 99) - doneWeekday) - Math.abs((b.weekday ?? 99) - doneWeekday) ||
      (a.weekday ?? 99) - (b.weekday ?? 99)
    )[0];
    if (nearest) {
      result.set(nearest.id, row);
      placed.add(row);
    }
  }
  // Phase 2: only a workout whose name no session of the plan in force has (the session was
  // renamed) counts for the session in the same day and place.
  for (const row of rows) {
    if (placed.has(row) || candidates.some((session) => sameName(session, row))) continue;
    const sameSlot = eligibleFor(row).find((session) =>
      row.weekday != null && row.weekday === session.weekday && row.order != null &&
      row.order === session.order
    );
    if (sameSlot) {
      result.set(sameSlot.id, row);
      placed.add(row);
    }
  }
  finishedCache.set(state, result);
  return result;
}

/** The date a session of the plan in force this week was finished, or null (`matchFinished`). */
export function finishedOn(state: PlanState, session: PlanSession): string | null {
  return matchFinished(state).get(session.id)?.localDate ?? null;
}

/**
 * The workout left unfinished this ISO week that a session of the plan in force stands for: the
 * one with its id, else, when its plan version is gone, the one with its name. One from an earlier
 * week is another day's workout and never stands for this week's session.
 */
export function unfinishedFor(
  state: PlanState,
  session: PlanSession,
): UnfinishedWorkout | undefined {
  const monday = addDays(state.localDate, 1 - state.weekday);
  const thisWeek = state.unfinished.filter((row) => row.localDate >= monday);
  const known = new Set(
    [...state.sessions, ...(state.afterBlock?.sessions ?? [])].map((item) => item.id),
  );
  return thisWeek.find((row) => row.id === session.id) ??
    thisWeek.find((row) =>
      row.name !== "" && !known.has(row.id) &&
      row.name.toLowerCase() === session.name.toLowerCase()
    );
}

/**
 * The session a finished workout (by id, else by name) stands for, searching the plan and the plan
 * a temporary block hands back to.
 */
function sessionOfWorkout(
  state: PlanState,
  row: Readonly<{ id: string; name: string }>,
): PlanSession | undefined {
  const all = [...state.sessions, ...(state.afterBlock?.sessions ?? [])];
  return all.find((session) => session.id === row.id) ??
    (row.name === ""
      ? undefined
      : all.find((session) => session.name.toLowerCase() === row.name.toLowerCase()));
}

const exercisesOf = (session: PlanSession): DayExercise[] =>
  session.exercises.map((exercise) => ({ slug: exercise.slug, sets: exercise.sets }));

/**
 * The plan's sessions in force on a date. After a temporary block's last day they are those of the
 * plan the block hands back to, so nothing dated after `ends_on` is read from the block.
 */
function poolOn(state: PlanState, date: string): readonly PlanSession[] {
  return state.afterBlock !== null && date > state.afterBlock.endsOn
    ? state.afterBlock.sessions
    : state.sessions;
}

/** The sessions in force on each day of the athlete's ISO week; the plan's own list without a block. */
export function weekSessions(state: PlanState): readonly PlanSession[] {
  if (state.afterBlock === null) return state.sessions;
  const monday = addDays(state.localDate, 1 - state.weekday);
  const week = [1, 2, 3, 4, 5, 6, 7].flatMap((weekday) =>
    poolOn(state, addDays(monday, weekday - 1)).filter((session) => session.weekday === weekday)
  );
  return [
    ...week,
    ...poolOn(state, state.localDate).filter((session) => session.weekday === null),
  ];
}

/**
 * The plan's sessions on the day `offset` days after today (1 to 6), resolved against the athlete's
 * ISO week. Inside the current week a session already finished is not planned again: its slot
 * reads done (`doneEarly`). From the next ISO week on, every session is planned again. Days after a
 * temporary block's last day take the sessions of the plan it hands back to.
 */
export function sessionsOn(state: PlanState, offset: number): Readonly<{
  planned: readonly PlanSession[];
  doneEarly: readonly Readonly<{ session: PlanSession; doneOn: string }>[];
}> {
  const weekday = ((state.weekday - 1 + offset) % 7) + 1;
  const onDay = poolOn(state, addDays(state.localDate, offset)).filter((session) =>
    session.weekday === weekday
  );
  if (offset > 7 - state.weekday) return { planned: onDay, doneEarly: [] };
  return {
    planned: onDay.filter((session) => finishedOn(state, session) === null),
    doneEarly: onDay.flatMap((session) => {
      const doneOn = finishedOn(state, session);
      return doneOn === null ? [] : [{ session, doneOn }];
    }),
  };
}

/** The muscles two groups of sessions both train. */
function sharedMuscles(
  first: readonly PlanSession[],
  second: readonly PlanSession[],
): TrainedMuscle[] {
  const later = sessionMuscles(second.flatMap(exercisesOf)).muscles;
  return sessionMuscles(first.flatMap(exercisesOf)).muscles.filter((muscle) =>
    later.includes(muscle)
  );
}

export type FocusSession = Readonly<{
  session: PlanSession | null;
  isToday: boolean;
  /** Today's slot holds a session that is already done this week; `doneOn` is its date. */
  doneToday: PlanSession | null;
  doneOn: string | null;
  missed: boolean;
  nextWeek: boolean;
  /** Sessions of earlier days this week that are still undone, in weekday order. */
  undone: readonly PlanSession[];
  /** An undone session Tracend does not set for today because it repeats tomorrow's muscles. */
  deferred: Readonly<{ session: PlanSession; shared: readonly TrainedMuscle[] }> | null;
}>;

/**
 * What the athlete does next: today's session unless it was already done this week (today or
 * earlier), else the next unfinished one later in the week, else a session from earlier this week
 * that is still undone, else next week's first. A workout finished this week is never prescribed
 * again. An undone session is made up today only if it is not tomorrow's session (tomorrow covers
 * that one) and does not train the muscles tomorrow's session trains: the first undone session that
 * is not tomorrow's is the candidate, and when it repeats tomorrow's muscles nothing is made up.
 */
export function pickFocusSession(state: PlanState): FocusSession {
  const byDay = (a: PlanSession, b: PlanSession) => a.weekday! - b.weekday!;
  const dated = weekSessions(state).filter((session) => session.weekday !== null).sort(byDay);
  // Next week's first session, from the plan in force then.
  const nextFirst = poolOn(state, addDays(state.localDate, 8 - state.weekday))
    .filter((session) => session.weekday !== null).sort(byDay)[0] ?? null;
  const todays = dated.find((session) => session.weekday === state.weekday) ?? null;
  const slotDone = todays && finishedOn(state, todays) !== null ? todays : null;
  const unfinished = (session: PlanSession) => finishedOn(state, session) === null;
  // Only a session in force today can be undone: the block's own sessions lapse after its last day.
  const inForceToday = new Set(poolOn(state, state.localDate).map((session) => session.id));
  // A session the athlete logged sets in and left unfinished is neither undone nor made up: it is
  // theirs to save or discard, and the plan block says so.
  const undone = dated.filter((session) =>
    session.weekday! < state.weekday && unfinished(session) && inForceToday.has(session.id) &&
    unfinishedFor(state, session) === undefined
  );
  const base = {
    doneToday: slotDone,
    doneOn: slotDone ? finishedOn(state, slotDone) : null,
    undone,
    deferred: null,
  };
  if (todays && !slotDone) {
    return { ...base, session: todays, isToday: true, missed: false, nextWeek: false };
  }
  const later = dated.find((session) => session.weekday! > state.weekday && unfinished(session));
  if (later) return { ...base, session: later, isToday: false, missed: false, nextWeek: false };
  const tomorrow = sessionsOn(state, 1).planned;
  const candidate = undone.find((session) => !tomorrow.some((item) => item.id === session.id));
  if (candidate) {
    const shared = sharedMuscles([candidate], tomorrow);
    if (shared.length === 0) {
      return { ...base, session: candidate, isToday: false, missed: true, nextWeek: false };
    }
    return {
      ...base,
      deferred: { session: candidate, shared },
      session: nextFirst,
      isToday: false,
      missed: false,
      nextWeek: true,
    };
  }
  return { ...base, session: nextFirst, isToday: false, missed: false, nextWeek: true };
}

// Heart-rate load signals (C4) add fixed sentences and nothing else: they never change a target or
// a prescription (D9). They carry no figure, are not marked with `record`, and so ground nothing a
// reply could quote. "Than usual" is a comparison with the athlete's earlier weeks and only the
// recovery trend makes one; the other rule is a fixed line and gets neutral wording.
export const slowerRecoverySentence =
  "Heart rate shows slower recovery than usual: treat this step as less certain (the target is unchanged).";
export const incompleteRecoverySentence =
  "Heart rate between sets suggests incomplete recovery: treat this step as less certain (the target is unchanged).";
export const longerRestSentence =
  "Heart rate suggests resting a little longer between sets (the plan's rest times are unchanged).";

/**
 * The sentence for a step up when the signals lower confidence: only a step up (`add_load` or
 * `add_reps`), never a hold or a cut, and the wording follows the rule that fired.
 */
function lessCertainSentence(
  target: ProgressionTarget | undefined,
  signals: LoadSignals | null,
): string | null {
  if (
    signals === null || signals.engine.confidence !== "lower" || target === undefined ||
    (target.action !== "add_load" && target.action !== "add_reps")
  ) return null;
  return signals.engine.reasons.includes("recovery_slower")
    ? slowerRecoverySentence
    : signals.engine.reasons.includes("slow_settling")
    ? incompleteRecoverySentence
    : null;
}

function exerciseLine(
  exercise: PlanExercise,
  index: number,
  state: PlanState,
  target: ProgressionTarget | undefined,
  signals: LoadSignals | null,
): string {
  const parts = [`${prescription(exercise)}`];
  if (exercise.restSeconds !== null) parts.push(`rest ${record(exercise.restSeconds)} s`);
  if (exercise.targetRpe !== null) parts.push(`RPE ${record(exercise.targetRpe)}`);
  if (exercise.loadKg !== null) parts.push(`plan load ${record(exercise.loadKg)} kg`);
  let line = `${index + 1}. ${record(exercise.name)}: ${parts.join(", ")}.`;
  line += target
    ? ` Next target (Tracend, from the logged sets): ${
      describeTargetAdviceMarked(target)
    }. Last logged ${describeLastSessionMarked(target)}.`
    : " No sets logged for it yet; the plan's prescription stands.";
  const caution = lessCertainSentence(target, signals);
  if (caution !== null) line += ` ${caution}`;
  line += ` ${homeText(exercise, state)}`;
  return line;
}

function homeText(exercise: PlanExercise, state: PlanState): string {
  const home = homeAlternativesFor(exercise.slug, state.experience, state.avoid);
  if (home.already === "bodyweight") return "Home: needs no equipment.";
  const bits = [
    home.already === "minimal" ? "needs only home-size kit" : null,
    home.bodyweight.length ? `bodyweight ${home.bodyweight.join(" / ")}` : null,
    home.minimal.length ? `minimal kit ${home.minimal.join(" / ")}` : null,
  ].filter(Boolean);
  return bits.length ? `Home: ${bits.join("; ")}.` : "Home: no catalog alternative.";
}

const unfinishedText = (row: UnfinishedWorkout) =>
  `${record(row.name || "a session")} on ${record(row.localDate)} (${record(row.loggedSets)} ${
    row.loggedSets === 1 ? "set" : "sets"
  } logged)`;

function compactSession(session: PlanSession, state: PlanState, doneOn: string | null): string {
  const exercises = session.exercises.map((exercise) => {
    const home = homeAlternativesFor(exercise.slug, state.experience, state.avoid);
    const options = [...home.bodyweight.slice(0, 1), ...home.minimal.slice(0, 1)];
    return `${record(exercise.name)} ${prescription(exercise)}${
      home.already ? " (home-ready)" : options.length ? ` (home: ${options.join(" / ")})` : ""
    }`;
  });
  const left = doneOn === null ? unfinishedFor(state, session) : undefined;
  return `- ${dayName(session.weekday)}, ${record(session.name)}: ${exercises.join("; ")}${
    doneOn === null ? "" : ` [done ${record(doneOn)}]`
  }${
    left === undefined
      ? ""
      : ` [logged ${record(left.loggedSets)} ${left.loggedSets === 1 ? "set" : "sets"} on ${
        record(left.localDate)
      }, not finished]`
  }`;
}

/**
 * The schedule Coach reads: the sessions of the next seven days from the athlete's date plus
 * yesterday's and today's finished ones, and the facts about the days that are not sessions. One
 * resolved schedule feeds both the lines and the overlap check. The plan repeats weekly: inside the
 * athlete's ISO week a session already finished is not shown as planned again (its slot says when
 * it was done), from next week on every session is planned. Today shows what Coach prescribes:
 * today's planned session, or an undone earlier session when `pickFocusSession` makes it up today.
 */
export function resolveSchedule(
  state: PlanState,
  focus: FocusSession,
): Readonly<{ points: SchedulePoint[]; notes: ScheduleNote[] }> {
  const points: SchedulePoint[] = [];
  const notes: ScheduleNote[] = [];
  const yesterday = addDays(state.localDate, -1);
  for (const row of state.recent) {
    if (row.localDate !== yesterday && row.localDate !== state.localDate) continue;
    const planned = sessionOfWorkout(state, row);
    points.push({
      date: row.localDate,
      kind: "done",
      name: row.name || planned?.name || "a session",
      exercises: row.exercises.length > 0 ? row.exercises : planned ? exercisesOf(planned) : [],
    });
  }
  if (focus.session && focus.isToday) {
    points.push({
      date: state.localDate,
      kind: "planned",
      name: focus.session.name,
      exercises: exercisesOf(focus.session),
    });
  } else if (focus.session && focus.missed) {
    points.push({
      date: state.localDate,
      kind: "make_up",
      name: `${dayName(focus.session.weekday)} session ${focus.session.name}`,
      exercises: exercisesOf(focus.session),
    });
  }
  if (!focus.missed && focus.undone.length > 0) {
    notes.push({
      date: state.localDate,
      text: `undone earlier this week: ${
        focus.undone.map((session) => `${record(session.name)} (${dayName(session.weekday)})`)
          .join(", ")
      }`,
    });
  }
  if (focus.deferred) {
    notes.push({
      date: state.localDate,
      text: `${record(focus.deferred.session.name)} is not set for today: it would train ${
        focus.deferred.shared.join(", ")
      } on consecutive days with tomorrow's session`,
    });
  }
  for (let offset = 1; offset < weekAheadDays; offset += 1) {
    const date = addDays(state.localDate, offset);
    const { planned, doneEarly } = sessionsOn(state, offset);
    for (const session of planned) {
      points.push({ date, kind: "planned", name: session.name, exercises: exercisesOf(session) });
    }
    for (const { session, doneOn } of doneEarly) {
      notes.push({
        date,
        text: `${record(session.name)} was already done this week, on ${record(doneOn)}`,
      });
    }
  }
  return { points, notes };
}

/** The next seven days of a plan state, with the muscles shared on consecutive days. */
export function weekAheadOf(
  state: PlanState,
  focus: FocusSession = pickFocusSession(state),
): WeekAhead {
  const { points, notes } = resolveSchedule(state, focus);
  return buildWeekAhead(state.localDate, state.weekday, points, notes);
}

/** Sets a week of the plan in force today gives each target muscle, from the catalog's first-listed muscle. */
function weeklySets(state: PlanState): string {
  const totals = new Map<string, number>();
  for (const session of poolOn(state, state.localDate)) {
    for (const exercise of session.exercises) {
      const muscle = exercise.slug === null
        ? undefined
        : catalogV2BySlug.get(exercise.slug)?.muscles[0];
      totals.set(muscle ?? "other", (totals.get(muscle ?? "other") ?? 0) + exercise.sets);
    }
  }
  return [...totals].sort((a, b) => b[1] - a[1]).map(([muscle, sets]) =>
    `${muscle} ${record(sets)}`
  ).join(", ");
}

/**
 * The text for one plan state, or null without an active plan. Exposed for tests. The short, fixed
 * parts come first (the rules for naming exercises, the week's sets, the equipment, the 7-day
 * schedule); the lists whose length follows the plan come last, so a cut for size (the host drops
 * whole trailing lines) can only shorten the lists, never remove a rule.
 */
export function renderTrainingPlan(
  state: PlanState | null,
  signals: LoadSignals | null = null,
): string | null {
  const marked = trainingPlanMarked(state, signals);
  return marked === null ? null : plain(marked);
}

function trainingPlanMarked(
  state: PlanState | null,
  signals: LoadSignals | null = null,
): string | null {
  if (state === null || state.sessions.length === 0) return null;
  const focus = pickFocusSession(state);
  const targetById = new Map(state.targets.map((target) => [target.plannedExerciseId, target]));
  const lines = [
    `Active plan: ${record(state.title)}${
      state.version === null ? "" : ` v${record(state.version)}`
    }, ${record(state.sessionsPerWeek ?? state.sessions.length)} sessions a week. Today is ${
      dayName(state.weekday)
    } ${record(state.localDate)}.`,
  ];
  const done = state.completed.map((row) => {
    const session = state.sessions.find((item) => item.id === row.id);
    return `${record(session?.name ?? (row.name || "a session"))} (${record(row.localDate)})`;
  });
  lines.push(
    done.length
      ? `Finished this week (Monday to today): ${done.join(", ")}.`
      : "Finished this week (Monday to today): no session logged.",
  );
  const offerable = state.unfinished.filter((row) => row.offerable);
  const lapsed = state.unfinished.filter((row) => !row.offerable);
  if (offerable.length > 0) {
    lines.push(
      "Logged but not finished (the athlete has not saved or discarded them yet): " +
        `${offerable.map(unfinishedText).join(", ")}. Each was trained: say its sets were ` +
        "logged but the workout was not finished, never that it was not done, skipped or " +
        "missed; the athlete can save or discard it on Today.",
    );
  }
  if (lapsed.length > 0) {
    lines.push(
      "Logged but never finished, and no longer offered to the athlete to save: " +
        `${lapsed.map(unfinishedText).join(", ")}. Each was trained: say its sets were logged ` +
        "but the workout was not finished, never that it was not done, skipped or missed.",
    );
  }
  if (focus.doneToday) {
    lines.push(
      focus.doneOn === state.localDate
        ? `Today's planned session, ${record(focus.doneToday.name)}, is already logged as done.`
        : `Today's planned session, ${record(focus.doneToday.name)}, was already done this week (${
          record(focus.doneOn ?? "")
        }); it is not prescribed again.`,
    );
  }
  lines.push(
    "Home options are catalog exercises that need no equipment (bodyweight) or only " +
      `${minimalHomeKit.join(", ").replaceAll("_", " ")}. To plan days away from the gym, build ` +
      "the routine from these options and the plan's sets a week for each muscle; name only " +
      "exercises listed here, and ask what kit the athlete has at home when it changes the choice.",
  );
  lines.push(`Sets a week by main muscle in the plan: ${weeklySets(state)}.`);
  lines.push(
    state.equipment === null
      ? "Equipment profile: not on file."
      : `Equipment profile (from onboarding): ${
        state.equipment.length ? state.equipment.join(", ").replaceAll("_", " ") : "bodyweight only"
      }.`,
  );
  lines.push(...renderWeekAheadMarked(weekAheadOf(state, focus)));
  if (focus.session) {
    const label = focus.isToday
      ? "Today's planned session"
      : focus.missed
      ? "A session from earlier this week is still undone"
      : focus.nextWeek
      ? "No session is set for the rest of this week; the next one is next week's first"
      : "Today has no planned session. The next planned session";
    lines.push(
      `${label}: ${record(focus.session.name)} (${dayName(focus.session.weekday)}${
        focus.session.minutes === null ? "" : `, about ${record(focus.session.minutes)} min`
      }).`,
    );
    if (signals !== null && signals.engine.rest === "allow_longer") {
      lines.push(longerRestSentence);
    }
    lines.push(
      ...focus.session.exercises.map((exercise, index) =>
        "  " + exerciseLine(exercise, index, state, targetById.get(exercise.id), signals)
      ),
    );
  }
  const rest = weekSessions(state).filter((session) =>
    session.id !== focus.session?.id && session.id !== focus.doneToday?.id
  );
  if (rest.length) {
    lines.push("Other sessions in the plan (a day-by-day list; home options in brackets):");
    lines.push(
      ...rest.map((session) => compactSession(session, state, finishedOn(state, session))),
    );
  }
  if (state.afterBlock !== null && state.localDate <= state.afterBlock.endsOn) {
    const back = state.afterBlock.sessions.filter((session) => session.weekday !== null)
      .sort((a, b) => a.weekday! - b.weekday!);
    lines.push(
      `After the temporary block (last day ${
        record(state.afterBlock.endsOn)
      }) the plan returns to: ${
        back.map((session) => `${dayName(session.weekday)} ${record(session.name)}`).join("; ")
      }.`,
    );
  }
  return lines.join("\n");
}

/** Who answered a turn's load-signals read: the trace reports it, never a value. */
export type LoadSignalsStatus = "off" | "ok" | "unavailable" | "failed" | "timeout";

/** How long the plan waits for the signals before it renders without them. */
export const loadSignalsDeadlineMs = 1_000;

/**
 * The athlete's heart-rate load signals for a coaching date; null when there are none. The third
 * argument is the turn's shared read of the heart-rate profile's inputs.
 */
export type LoadSignalsSource = (
  userId: string,
  localDate: string,
  heartRateInputs: () => Promise<HeartRateInputs | null>,
) => Promise<LoadSignals | null>;

/** Reads the signals over the service-role caller; null when the reads fail. */
export const loadSignalsFromService: LoadSignalsSource = (
  userId,
  localDate,
  heartRateInputs,
) =>
  loadWorkoutLoadSignals(
    {
      rpc: async (name, args) => {
        const { data, error } = await coachServiceRpc(name, args);
        return { data, error: error ? { message: "load_signals_unavailable" } : null };
      },
    },
    userId,
    localDate,
    heartRateInputs,
  );

type SignalsRead = Readonly<{
  /** Settles within the deadline and never rejects. */
  result: Promise<{ signals: LoadSignals | null; status: LoadSignalsStatus }>;
  /** Drops the deadline timer when the result is not wanted. */
  stop(): void;
}>;

/** Starts the signals read now. */
function readSignals(
  signals: LoadSignalsSource,
  input: CoachContextInput,
  deadlineMs: number,
): SignalsRead {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<"timeout">((resolve) => {
    timer = setTimeout(() => resolve("timeout"), deadlineMs);
  });
  const read = Promise.resolve().then(() =>
    signals(
      input.userId,
      input.localDate,
      () =>
        sharedRead(
          input,
          heartRateInputsReadKey,
          () => heartRateInputsFromService(input.userId, input.localDate),
        ) as Promise<HeartRateInputs | null>,
    )
  );
  const result = Promise.race([read, late]).then(
    (value): { signals: LoadSignals | null; status: LoadSignalsStatus } =>
      value === "timeout"
        ? { signals: null, status: "timeout" }
        : { signals: value, status: value === null ? "unavailable" : "ok" },
    () => ({ signals: null, status: "failed" as const }),
  ).finally(() => clearTimeout(timer));
  return { result, stop: () => clearTimeout(timer) };
}

export function createTrainingPlanContributor(
  source: StateSource,
  signals?: LoadSignalsSource,
  signalsDeadlineMs: number = loadSignalsDeadlineMs,
): CoachContextContributor {
  return {
    id: trainingPlanContributorId,
    slot: "volatile",
    budgetChars: trainingPlanContributorBudgetChars,
    async render(input) {
      // The signals read starts with the plan read, so the plan waits for the slower of the two,
      // never for both, and for the signals no longer than their own deadline.
      const reading = signals === undefined ? null : readSignals(signals, input, signalsDeadlineMs);
      try {
        const state = parsePlanState(
          await sharedRead(input, planStateReadKey, () => source(input.userId, input.localDate)),
        );
        if (state === null) return null;
        const read = reading === null ? null : await reading.result;
        const marked = trainingPlanMarked(state, read?.signals ?? null);
        return marked === null
          ? null
          : blockOf(marked, read === null ? {} : { trace: { load_signals: read.status } });
      } finally {
        reading?.stop();
      }
    },
  };
}

/** The plan state for a user and coaching date (the service-role RPC every reader of it shares). */
export const planStateFromService: StateSource = stateSourceFromRpc(
  coachServiceRpc,
  "get_coach_plan_state_v1",
);

export const trainingPlanContributor: CoachContextContributor = createTrainingPlanContributor(
  planStateFromService,
  loadSignalsFromService,
);
