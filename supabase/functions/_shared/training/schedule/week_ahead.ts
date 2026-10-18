// The athlete's next seven days as Coach reads them, and the muscles two sessions share on
// consecutive days. Deterministic arithmetic over the plan and the sessions logged: the model
// explains the result and may offer a change as a proposal the athlete approves; it never works
// out which days overlap or edits the plan.
//
// The schedule runs from the athlete's own date (the coaching date), not from the calendar week:
// on a Sunday, Monday is tomorrow and is shown as such.
import type { Muscle } from "../../onboarding/catalog.ts";
import { minimumDaysBetweenSessionsPerMuscle } from "../standard/volume.ts";
import { type DayExercise, sessionMuscles } from "./muscles.ts";

/** Days listed from today, today included. */
export const weekAheadDays = 7;

/** Pairs of consecutive sessions are checked up to this many days after today. */
export const overlapAheadDays = 2;

/** How a session sits on its day. */
export type SessionKind = "done" | "planned" | "make_up";

/** One session on one date, as the contributor found it in the plan or the log. */
export type SchedulePoint = Readonly<{
  date: string;
  kind: SessionKind;
  name: string;
  exercises: readonly DayExercise[];
}>;

export type ScheduleDay = Readonly<{
  date: string;
  weekday: number;
  /** Offset from today: -1 yesterday, 0 today. */
  offset: number;
  sessions: readonly Readonly<{ kind: SessionKind; name: string }>[];
  /** Muscles trained, most sets first. */
  muscles: readonly Muscle[];
  /** Exercises whose muscles the catalog does not know (no slug, or a custom exercise). */
  unknownExercises: number;
}>;

export type MuscleOverlap = Readonly<
  { from: ScheduleDay; to: ScheduleDay; muscles: readonly Muscle[] }
>;

export type WeekAhead = Readonly<{
  /** Yesterday (when it holds a session) and today to six days ahead. */
  days: readonly ScheduleDay[];
  overlaps: readonly MuscleOverlap[];
}>;

const dayMs = 86_400_000;

/** Days since 1970-01-01 of a YYYY-MM-DD date (UTC arithmetic: no clock, no time zone). */
export const dayOf = (date: string): number => Date.parse(`${date}T00:00:00Z`) / dayMs;

export const addDays = (date: string, days: number): string =>
  new Date((dayOf(date) + days) * dayMs).toISOString().slice(0, 10);

/** One date's sessions as a schedule day: their combined muscles. */
export function scheduleDay(
  date: string,
  weekday: number,
  offset: number,
  here: readonly Pick<SchedulePoint, "kind" | "name" | "exercises">[],
): ScheduleDay {
  const { muscles, unknown } = sessionMuscles(here.flatMap((point) => point.exercises));
  return {
    date,
    weekday,
    offset,
    sessions: here.map(({ kind, name }) => ({ kind, name })),
    muscles,
    unknownExercises: unknown,
  };
}

/**
 * Pairs of sessions on consecutive dates (fewer calendar days between them than the standard's
 * minimum) that train a common muscle. Days without a session are skipped over, so a rest day
 * between two sessions ends the pair. `keep` narrows the pairs by their later day.
 */
export function consecutiveOverlaps(
  days: readonly ScheduleDay[],
  keep: (later: ScheduleDay) => boolean = () => true,
): MuscleOverlap[] {
  const withSessions = days.filter((day) => day.sessions.length > 0);
  const overlaps: MuscleOverlap[] = [];
  for (let index = 1; index < withSessions.length; index += 1) {
    const from = withSessions[index - 1];
    const to = withSessions[index];
    if (dayOf(to.date) - dayOf(from.date) - 1 >= minimumDaysBetweenSessionsPerMuscle.value) {
      continue;
    }
    if (!keep(to)) continue;
    const shared = to.muscles.filter((muscle) => from.muscles.includes(muscle));
    if (shared.length > 0) overlaps.push({ from, to, muscles: shared });
  }
  return overlaps;
}

/**
 * The schedule from today and the muscle overlaps. A session counts once per date; two on one date
 * are merged. An overlap is two sessions on consecutive dates that train a common muscle, where
 * the later one is today or in the next `overlapAheadDays` days. Done and planned sessions count
 * alike.
 */
export function buildWeekAhead(
  today: string,
  todayWeekday: number,
  points: readonly SchedulePoint[],
): WeekAhead {
  const days: ScheduleDay[] = [];
  for (let offset = -1; offset < weekAheadDays; offset += 1) {
    const date = addDays(today, offset);
    const here = points.filter((point) => point.date === date);
    if (offset < 0 && here.length === 0) continue;
    days.push(scheduleDay(date, ((todayWeekday - 1 + offset + 7) % 7) + 1, offset, here));
  }
  return {
    days,
    overlaps: consecutiveOverlaps(
      days,
      (later) => later.offset >= 0 && later.offset <= overlapAheadDays,
    ),
  };
}

const dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
export const stamp = (day: Pick<ScheduleDay, "weekday" | "date">) =>
  `${dayNames[day.weekday - 1]} ${day.date}`;

function describeDay(day: ScheduleDay): string {
  const when = day.offset === 0 ? " (today)" : day.offset === 1 ? " (tomorrow)" : "";
  if (day.sessions.length === 0) return `- ${stamp(day)}${when}: no session`;
  const what = day.sessions.map((session) =>
    session.kind === "make_up"
      ? `no session is planned today; make up the undone ${session.name}`
      : session.kind === "done"
      ? `done: ${session.name}`
      : session.name
  ).join(" + ");
  const muscles = day.muscles.length ? ` (${day.muscles.join(", ")})` : "";
  const unknown = day.unknownExercises > 0
    ? ` [muscles of ${day.unknownExercises} exercises unknown]`
    : "";
  return `- ${stamp(day)}${when}: ${what}${muscles}${unknown}`;
}

/**
 * The back-to-back muscle fact as one compact line, or null when there is no overlap. The structured
 * value is `MuscleOverlap[]` (from `consecutiveOverlaps` or `buildWeekAhead`); this line is its
 * rendering, so another block can carry the fact without rebuilding the text.
 */
export function renderOverlapFact(overlaps: readonly MuscleOverlap[]): string | null {
  if (overlaps.length === 0) return null;
  return "Same muscles on consecutive days (Tracend calculated; under a day between sessions): " +
    overlaps.map((overlap) =>
      `${stamp(overlap.from)} then ${stamp(overlap.to)}: ${overlap.muscles.join(", ")}`
    ).join("; ") +
    ". Say so when you explain these days. A change of day or exercise is a proposal the " +
    "athlete approves.";
}

/**
 * The block Coach reads: the days from today with their muscles, then, only when there is one,
 * the muscles shared on consecutive days. Nothing about overlap is said when there is none.
 */
export function renderWeekAhead(schedule: WeekAhead): string[] {
  const lines = [
    "Next 7 days from today, by the athlete's own dates (muscles from the sets in each session; " +
    "Tracend calculated them):",
    ...schedule.days.map(describeDay),
  ];
  const fact = renderOverlapFact(schedule.overlaps);
  if (fact !== null) lines.push(fact);
  return lines;
}
