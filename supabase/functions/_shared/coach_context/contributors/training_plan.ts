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
import { avoidablePatterns } from "../../onboarding/catalog.ts";
import { catalogV2BySlug } from "../../onboarding/catalog_v2.ts";
import { homeAlternativesFor, minimalHomeKit } from "../../training/home_alternatives.ts";
import { type DayExercise } from "../../training/schedule/muscles.ts";
import {
  addDays,
  buildWeekAhead,
  renderWeekAhead,
  type SchedulePoint,
  weekAheadDays,
} from "../../training/schedule/week_ahead.ts";
import {
  describeLastSession,
  describeTargetAdvice,
  parseProgressionSummary,
  type ProgressionTarget,
} from "../../training/progression/targets.ts";
import type { CoachContextContributor } from "../host.ts";
import { coachServiceRpc, type StateSource, stateSourceFromRpc } from "../service_source.ts";

export const trainingPlanContributorId = "training_plan";
export const trainingPlanContributorBudgetChars = 8_000;

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
  title: string;
  version: number | null;
  sessionsPerWeek: number | null;
  sessions: readonly PlanSession[];
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
  targets: readonly ProgressionTarget[];
}>;

/** The plan state in a get_coach_plan_state_v1 payload, or null without an active plan. */
export function parsePlanState(payload: unknown): PlanState | null {
  const body = rec(payload);
  if (!str(body.schema_version).startsWith("1.")) return null;
  const plan = rec(body.plan);
  if (Object.keys(plan).length === 0) return null;
  const weekday = num(body.weekday);
  if (weekday === null || typeof body.local_date !== "string") return null;
  const sessions = list(body.sessions).map((session): PlanSession => ({
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
    title: str(plan.title),
    version: num(plan.version_number),
    sessionsPerWeek: num(plan.sessions_per_week),
    sessions,
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
    targets: parseProgressionSummary(body.progression),
  };
}

const dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
const dayName = (weekday: number | null) =>
  weekday === null ? "no set day" : dayNames[weekday - 1] ?? "no set day";

const prescription = (exercise: PlanExercise) =>
  `${exercise.sets} x ${
    exercise.repMin === exercise.repMax ? exercise.repMin : `${exercise.repMin}-${exercise.repMax}`
  }`;

/**
 * The date a session was finished this week, or null. A workout finished under an earlier plan
 * version (the plan changed mid-week) is matched to the active plan's session by its id, else by
 * name, else by day and order, so it is not prescribed again.
 */
export function finishedOn(state: PlanState, session: PlanSession): string | null {
  const row = state.completed.find((item) =>
    item.id === session.id ||
    (item.name !== "" && item.name.toLowerCase() === session.name.toLowerCase()) ||
    (item.weekday !== null && item.weekday === session.weekday && item.order !== null &&
      item.order === session.order)
  );
  return row?.localDate ?? null;
}

/**
 * What the athlete does next: today's session unless it was already done this week (today or
 * earlier), else the next unfinished one later in the week, else one from earlier this week that is
 * still undone, else next week's first. A workout finished this week is never prescribed again.
 */
export function pickFocusSession(state: PlanState): Readonly<{
  session: PlanSession | null;
  isToday: boolean;
  /** Today's slot holds a session that is already done this week; `doneOn` is its date. */
  doneToday: PlanSession | null;
  doneOn: string | null;
  missed: boolean;
  nextWeek: boolean;
}> {
  const byDay = (a: PlanSession, b: PlanSession) => a.weekday! - b.weekday!;
  const dated = state.sessions.filter((session) => session.weekday !== null).sort(byDay);
  const todays = dated.find((session) => session.weekday === state.weekday) ?? null;
  const slotDone = todays && finishedOn(state, todays) !== null ? todays : null;
  const base = { doneToday: slotDone, doneOn: slotDone ? finishedOn(state, slotDone) : null };
  if (todays && !slotDone) {
    return { ...base, session: todays, isToday: true, missed: false, nextWeek: false };
  }
  const unfinished = (session: PlanSession) => finishedOn(state, session) === null;
  const later = dated.find((session) => session.weekday! > state.weekday && unfinished(session));
  if (later) return { ...base, session: later, isToday: false, missed: false, nextWeek: false };
  const missed = dated.find((session) => session.weekday! < state.weekday && unfinished(session));
  if (missed) return { ...base, session: missed, isToday: false, missed: true, nextWeek: false };
  return { ...base, session: dated[0] ?? null, isToday: false, missed: false, nextWeek: true };
}

function exerciseLine(
  exercise: PlanExercise,
  index: number,
  state: PlanState,
  target: ProgressionTarget | undefined,
): string {
  const parts = [`${prescription(exercise)}`];
  if (exercise.restSeconds !== null) parts.push(`rest ${exercise.restSeconds} s`);
  if (exercise.targetRpe !== null) parts.push(`RPE ${exercise.targetRpe}`);
  if (exercise.loadKg !== null) parts.push(`plan load ${exercise.loadKg} kg`);
  let line = `${index + 1}. ${exercise.name}: ${parts.join(", ")}.`;
  line += target
    ? ` Next target (Tracend, from the logged sets): ${describeTargetAdvice(target)}. Last logged ${
      describeLastSession(target)
    }.`
    : " No sets logged for it yet; the plan's prescription stands.";
  line += ` ${homeText(exercise, state)}`;
  return line;
}

function homeText(exercise: PlanExercise, state: PlanState): string {
  const home = homeAlternativesFor(exercise.slug, state.avoid);
  if (home.already === "bodyweight") return "Home: needs no equipment.";
  const bits = [
    home.already === "minimal" ? "needs only home-size kit" : null,
    home.bodyweight.length ? `bodyweight ${home.bodyweight.join(" / ")}` : null,
    home.minimal.length ? `minimal kit ${home.minimal.join(" / ")}` : null,
  ].filter(Boolean);
  return bits.length ? `Home: ${bits.join("; ")}.` : "Home: no catalog alternative.";
}

function compactSession(session: PlanSession, state: PlanState, doneOn: string | null): string {
  const exercises = session.exercises.map((exercise) => {
    const home = homeAlternativesFor(exercise.slug, state.avoid);
    const options = [...home.bodyweight.slice(0, 1), ...home.minimal.slice(0, 1)];
    return `${exercise.name} ${prescription(exercise)}${
      home.already ? " (home-ready)" : options.length ? ` (home: ${options.join(" / ")})` : ""
    }`;
  });
  return `- ${dayName(session.weekday)}, ${session.name}: ${exercises.join("; ")}${
    doneOn === null ? "" : ` [done ${doneOn}]`
  }`;
}

const exercisesOf = (session: PlanSession): DayExercise[] =>
  session.exercises.map((exercise) => ({ slug: exercise.slug, sets: exercise.sets }));

/**
 * The sessions of the next seven days from the athlete's date, plus yesterday's and today's
 * finished ones. The plan repeats weekly, so a day after today takes the session whose weekday it
 * is whatever was done earlier this week (a Monday session finished this Monday is still
 * tomorrow's when tomorrow is Monday). When today has no unfinished session of its own and one
 * from earlier this week is undone, that session is today's make-up, which is what Coach
 * prescribes today.
 */
export function schedulePoints(
  state: PlanState,
  focus: ReturnType<typeof pickFocusSession>,
): SchedulePoint[] {
  const points: SchedulePoint[] = [];
  const yesterday = addDays(state.localDate, -1);
  for (const row of state.recent) {
    if (row.localDate !== yesterday && row.localDate !== state.localDate) continue;
    const planned = state.sessions.find((session) =>
      session.id === row.id || (row.name !== "" && session.name === row.name)
    );
    points.push({
      date: row.localDate,
      kind: "done",
      name: row.name || planned?.name || "a session",
      exercises: row.exercises.length > 0 ? row.exercises : planned ? exercisesOf(planned) : [],
    });
  }
  const loggedToday = points.some((point) => point.date === state.localDate);
  if (!loggedToday && focus.session) {
    if (focus.isToday) {
      points.push({
        date: state.localDate,
        kind: "planned",
        name: focus.session.name,
        exercises: exercisesOf(focus.session),
      });
    } else if (focus.missed) {
      points.push({
        date: state.localDate,
        kind: "make_up",
        name: `${dayName(focus.session.weekday)} session ${focus.session.name}`,
        exercises: exercisesOf(focus.session),
      });
    }
  }
  for (let offset = 1; offset < weekAheadDays; offset += 1) {
    const weekday = ((state.weekday - 1 + offset) % 7) + 1;
    for (const session of state.sessions.filter((item) => item.weekday === weekday)) {
      points.push({
        date: addDays(state.localDate, offset),
        kind: "planned",
        name: session.name,
        exercises: exercisesOf(session),
      });
    }
  }
  return points;
}

/** Sets a week of the plan gives each target muscle, from the catalog's first-listed muscle. */
function weeklySets(state: PlanState): string {
  const totals = new Map<string, number>();
  for (const session of state.sessions) {
    for (const exercise of session.exercises) {
      const muscle = exercise.slug === null
        ? undefined
        : catalogV2BySlug.get(exercise.slug)?.muscles[0];
      totals.set(muscle ?? "other", (totals.get(muscle ?? "other") ?? 0) + exercise.sets);
    }
  }
  return [...totals].sort((a, b) => b[1] - a[1]).map(([muscle, sets]) => `${muscle} ${sets}`)
    .join(", ");
}

/** The text for one plan state, or null without an active plan. Exposed for tests. */
export function renderTrainingPlan(state: PlanState | null): string | null {
  if (state === null || state.sessions.length === 0) return null;
  const focus = pickFocusSession(state);
  const targetById = new Map(state.targets.map((target) => [target.plannedExerciseId, target]));
  const lines = [
    `Active plan: ${state.title}${state.version === null ? "" : ` v${state.version}`}, ${
      state.sessionsPerWeek ?? state.sessions.length
    } sessions a week. Today is ${dayName(state.weekday)} ${state.localDate}.`,
  ];
  const done = state.completed.map((row) => {
    const session = state.sessions.find((item) => item.id === row.id);
    return `${session?.name ?? (row.name || "a session")} (${row.localDate})`;
  });
  lines.push(
    done.length
      ? `Finished this week (Monday to today): ${done.join(", ")}.`
      : "Finished this week (Monday to today): no session logged.",
  );
  if (focus.doneToday) {
    lines.push(
      focus.doneOn === state.localDate
        ? `Today's planned session, ${focus.doneToday.name}, is already logged as done.`
        : `Today's planned session, ${focus.doneToday.name}, was already done this week (${focus.doneOn}); it is not prescribed again.`,
    );
  }
  lines.push(
    ...renderWeekAhead(
      buildWeekAhead(state.localDate, state.weekday, schedulePoints(state, focus)),
    ),
  );
  if (focus.session) {
    const label = focus.isToday
      ? "Today's planned session"
      : focus.missed
      ? "A session from earlier this week is still undone"
      : focus.nextWeek
      ? "No session is left this week; the next one is next week's first"
      : "Today has no planned session. The next planned session";
    lines.push(
      `${label}: ${focus.session.name} (${dayName(focus.session.weekday)}${
        focus.session.minutes === null ? "" : `, about ${focus.session.minutes} min`
      }).`,
    );
    lines.push(
      ...focus.session.exercises.map((exercise, index) =>
        "  " + exerciseLine(exercise, index, state, targetById.get(exercise.id))
      ),
    );
  }
  const rest = state.sessions.filter((session) =>
    session.id !== focus.session?.id && session.id !== focus.doneToday?.id
  );
  if (rest.length) {
    lines.push("Other sessions in the plan (a day-by-day list; home options in brackets):");
    lines.push(
      ...rest.map((session) => compactSession(session, state, finishedOn(state, session))),
    );
  }
  lines.push(`Sets a week by main muscle in the plan: ${weeklySets(state)}.`);
  lines.push(
    state.equipment === null
      ? "Equipment profile: not on file."
      : `Equipment profile (from onboarding): ${
        state.equipment.length ? state.equipment.join(", ").replaceAll("_", " ") : "bodyweight only"
      }.`,
  );
  lines.push(
    "Home options are catalog exercises that need no equipment (bodyweight) or only " +
      `${minimalHomeKit.join(", ").replaceAll("_", " ")}. To plan days away from the gym, build ` +
      "the routine from these options and the plan's sets a week for each muscle; name only " +
      "exercises listed here, and ask what kit the athlete has at home when it changes the choice.",
  );
  return lines.join("\n");
}

export function createTrainingPlanContributor(source: StateSource): CoachContextContributor {
  return {
    id: trainingPlanContributorId,
    slot: "volatile",
    budgetChars: trainingPlanContributorBudgetChars,
    async render(input) {
      return renderTrainingPlan(parsePlanState(await source(input.userId, input.localDate)));
    },
  };
}

export const trainingPlanContributor: CoachContextContributor = createTrainingPlanContributor(
  stateSourceFromRpc(coachServiceRpc, "get_coach_plan_state_v1"),
);
