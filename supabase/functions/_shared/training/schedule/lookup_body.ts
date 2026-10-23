// Reads the payload of the plan_history lookup with the filter "schedule" (SQL
// private.coach_plan_schedule): each date's planned sessions and finished ones, matched. The lookup
// renderer (coach_lookups/render.ts) and the watch-outs (coach_context/contributors/watch_outs.ts)
// both read the payload through here, so "a planned session that was not logged" means the same
// thing in both.
import type { DayExercise } from "./muscles.ts";

type Json = Record<string, unknown>;
const rec = (value: unknown): Json =>
  value && typeof value === "object" && !Array.isArray(value) ? value as Json : {};
const list = (value: unknown): Json[] => Array.isArray(value) ? value.map(rec) : [];

const exercisesOf = (value: unknown): DayExercise[] =>
  list(value).map((exercise): DayExercise => ({
    slug: typeof exercise.slug === "string" ? exercise.slug : null,
    sets: Number(exercise.sets) || 0,
  }));

/** A finished session on a date. */
export type DoneSession = Readonly<{
  /** The planned workout's id. */
  id: string;
  name: string;
  exercises: readonly DayExercise[];
}>;

/** A session the plan holds for a date. */
export type PlannedSession = Readonly<{ id: string; name: string }>;

/** One date of the schedule payload. */
export type ScheduleBodyDay = Readonly<{
  date: string;
  weekday: number;
  /** The id of the plan version in force on the date. */
  versionId: string;
  version: unknown;
  /** The date is inside a temporary block. */
  block: boolean;
  done: readonly DoneSession[];
  /** The day's planned sessions that no finished session answers. */
  unlogged: readonly PlannedSession[];
  /** Every planned session of the day, by the planned workout's id, with whether it was logged. */
  planned: readonly (PlannedSession & Readonly<{ logged: boolean }>)[];
}>;

export type ScheduleBody = Readonly<{
  /** The athlete's own today, else the last date of the range. */
  today: string;
  to: string;
  /** The id of the plan version in force now, or null without a plan. */
  planId: string | null;
  planVersion: unknown;
  days: readonly ScheduleBodyDay[];
  /** The ids of the planned workouts of the plan version in force now. */
  currentWorkoutIds: ReadonlySet<string>;
  /** The exercises (slug and planned sets) of each planned workout, by the workout's id. */
  exercisesByWorkout: ReadonlyMap<string, readonly DayExercise[]>;
}>;

/**
 * The days of a schedule payload. A finished session answers the planned one with its id. One
 * whose id is not a workout of that day's own plan version (it was finished under another version,
 * for instance logged this morning before a change took effect today) is matched by its name.
 */
export function readScheduleBody(body: unknown): ScheduleBody {
  const root = rec(body);
  const plan = rec(root.plan);
  const exercisesByWorkout = new Map(
    list(root.sessions).map((session) => [String(session.id), exercisesOf(session.exercises)]),
  );
  const idsByVersion = new Map<string, Set<string>>();
  for (const session of list(root.sessions)) {
    const version = String(session.version_id);
    idsByVersion.set(version, (idsByVersion.get(version) ?? new Set()).add(String(session.id)));
  }
  const to = String(root.to ?? "");
  const today = root.today !== null && root.today !== undefined && root.today !== ""
    ? String(root.today)
    : to;
  const days = list(root.days).map((row): ScheduleBodyDay => {
    const done = list(row.done).map((item): DoneSession => ({
      id: String(item.planned_workout_id),
      name: String(item.name),
      exercises: exercisesOf(item.exercises),
    }));
    const dayWorkouts = idsByVersion.get(String(row.version_id)) ?? new Set<string>();
    const isDone = (id: string, name: string) =>
      done.some((item) => item.id === id || (!dayWorkouts.has(item.id) && item.name === name));
    const planned = list(row.planned).map((item) => {
      const id = String(item.id);
      const name = String(item.name);
      return { id, name, logged: isDone(id, name) };
    });
    return {
      date: String(row.date),
      weekday: Number(row.weekday),
      versionId: String(row.version_id),
      version: row.version,
      block: row.block === true,
      done,
      unlogged: planned.filter((item) => !item.logged).map(({ id, name }) => ({ id, name })),
      planned,
    };
  });
  return {
    today,
    to,
    planId: plan.id === undefined || plan.id === null ? null : String(plan.id),
    planVersion: plan.version,
    currentWorkoutIds: idsByVersion.get(String(plan.id)) ?? new Set<string>(),
    days,
    exercisesByWorkout,
  };
}
