// Contract 7 contributor (A10): the athlete's plan as Coach needs it to answer "what do I do
// today?". It reads get_coach_plan_state_v1 (service role) and renders, with deterministic code,
// today's planned session (or the next one) with each exercise's sets, reps, rest and plan load,
// the next-session target Tracend computed from the sets the athlete logged (B3) and the last
// logged result, the rest of the week by day, the plan's sets per muscle for the week, and catalog
// alternatives for bodyweight and minimal home kit. Coach explains and chooses among these; it
// never changes the plan or a target. Replaces the progression contributor (B3), which only
// listed the targets.
import type { AvoidablePattern } from "../../onboarding/catalog.ts";
import { avoidablePatterns } from "../../onboarding/catalog.ts";
import { catalogV2BySlug } from "../../onboarding/catalog_v2.ts";
import { homeAlternativesFor, minimalHomeKit } from "../../training/home_alternatives.ts";
import {
  describeLastSession,
  describeTargetAdvice,
  parseProgressionSummary,
  type ProgressionTarget,
} from "../../training/progression/targets.ts";
import type { CoachContextContributor } from "../host.ts";
import { coachServiceRpc, type StateSource, stateSourceFromRpc } from "../service_source.ts";

export const trainingPlanContributorId = "training_plan";
export const trainingPlanContributorBudgetChars = 7_000;

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
  completed: readonly Readonly<{ id: string; localDate: string }>[];
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

/** What the athlete does next: today's session unless it is done, else the next one in the week. */
export function pickFocusSession(state: PlanState): Readonly<{
  session: PlanSession | null;
  isToday: boolean;
  doneToday: PlanSession | null;
  nextWeek: boolean;
}> {
  const doneIds = new Set(state.completed.map((row) => row.id));
  const doneTodayIds = new Set(
    state.completed.filter((row) => row.localDate === state.localDate).map((row) => row.id),
  );
  const dated = state.sessions.filter((session) => session.weekday !== null);
  const todays = dated.find((session) => session.weekday === state.weekday) ?? null;
  const doneToday = todays && doneTodayIds.has(todays.id) ? todays : null;
  if (todays && !doneToday) {
    return { session: todays, isToday: true, doneToday: null, nextWeek: false };
  }
  const later =
    dated.filter((session) => session.weekday! > state.weekday && !doneIds.has(session.id)).sort((
      a,
      b,
    ) => a.weekday! - b.weekday!)[0];
  if (later) return { session: later, isToday: false, doneToday, nextWeek: false };
  const first = [...dated].sort((a, b) => a.weekday! - b.weekday!)[0] ?? null;
  return { session: first, isToday: false, doneToday, nextWeek: true };
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

function compactSession(session: PlanSession, state: PlanState): string {
  const exercises = session.exercises.map((exercise) => {
    const home = homeAlternativesFor(exercise.slug, state.avoid);
    const options = [...home.bodyweight.slice(0, 1), ...home.minimal.slice(0, 1)];
    return `${exercise.name} ${prescription(exercise)}${
      home.already ? " (home-ready)" : options.length ? ` (home: ${options.join(" / ")})` : ""
    }`;
  });
  return `- ${dayName(session.weekday)}, ${session.name}: ${exercises.join("; ")}`;
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
    return `${session?.name ?? "a session"} (${row.localDate})`;
  });
  lines.push(
    done.length
      ? `Finished this week (Monday to today): ${done.join(", ")}.`
      : "Finished this week (Monday to today): no session logged.",
  );
  if (focus.doneToday) {
    lines.push(`Today's planned session, ${focus.doneToday.name}, is already logged as done.`);
  }
  if (focus.session) {
    const label = focus.isToday
      ? "Today's planned session"
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
  const doneIds = new Set(state.completed.map((row) => row.id));
  const rest = state.sessions.filter((session) =>
    session.id !== focus.session?.id && session.id !== focus.doneToday?.id
  );
  if (rest.length) {
    lines.push("Other sessions in the plan (a day-by-day list; home options in brackets):");
    lines.push(
      ...rest.map((session) =>
        compactSession(session, state) + (doneIds.has(session.id) ? " [done this week]" : "")
      ),
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
