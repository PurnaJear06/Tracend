// The athlete's next seven days as Coach reads them, and the muscles two sessions share on
// consecutive days (stated in the watch-outs block). Deterministic arithmetic over the plan and the sessions logged: the model
// explains the result and may offer a change as a proposal the athlete approves; it never works
// out which days overlap or edits the plan.
//
// The schedule runs from the athlete's own date (the coaching date), not from the calendar week:
// on a Sunday, Monday is tomorrow and is shown as such.
import { minimumDaysBetweenSessionsPerMuscle } from "../standard/volume.ts";
import { type DayExercise, sessionMuscles, type TrainedMuscle } from "./muscles.ts";

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
  muscles: readonly TrainedMuscle[];
  /** Exercises whose muscles the catalog does not know (no slug, or a custom exercise). */
  unknownExercises: number;
  /** Facts about the day that are not a session: a session done early, one left undone. */
  notes: readonly string[];
}>;

/** A fact about one date, shown with its day and never counted as a session. */
export type ScheduleNote = Readonly<{ date: string; text: string }>;

export type MuscleOverlap = Readonly<
  { from: ScheduleDay; to: ScheduleDay; muscles: readonly TrainedMuscle[] }
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
  notes: readonly string[] = [],
): ScheduleDay {
  const { muscles, unknown } = sessionMuscles(here.flatMap((point) => point.exercises));
  return {
    date,
    weekday,
    offset,
    sessions: here.map(({ kind, name }) => ({ kind, name })),
    muscles,
    unknownExercises: unknown,
    notes,
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
  notes: readonly ScheduleNote[] = [],
): WeekAhead {
  const days: ScheduleDay[] = [];
  for (let offset = -1; offset < weekAheadDays; offset += 1) {
    const date = addDays(today, offset);
    const here = points.filter((point) => point.date === date);
    if (offset < 0 && here.length === 0) continue;
    days.push(
      scheduleDay(
        date,
        ((todayWeekday - 1 + offset + 7) % 7) + 1,
        offset,
        here,
        notes.filter((note) => note.date === date).map((note) => note.text),
      ),
    );
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

/** The caveat for a day whose sessions hold exercises the catalog has no muscles for. */
export const unknownNote = (day: Pick<ScheduleDay, "unknownExercises">): string =>
  day.unknownExercises > 0 ? ` [muscles of ${day.unknownExercises} exercises unknown]` : "";

function describeDay(day: ScheduleDay): string {
  const when = day.offset === 0 ? " (today)" : day.offset === 1 ? " (tomorrow)" : "";
  const what = day.sessions.map((session) =>
    session.kind === "make_up"
      ? `no session is planned today; undone earlier this week: ${session.name}`
      : session.kind === "done"
      ? `done: ${session.name}`
      : session.name
  );
  const muscles = day.muscles.length ? ` (${day.muscles.join(", ")})` : "";
  const facts = [
    ...(what.length ? [`${what.join(" + ")}${muscles}${unknownNote(day)}`] : [
      "no session",
    ]),
    ...day.notes,
  ];
  return `- ${stamp(day)}${when}: ${facts.join("; ")}`;
}

/**
 * The back-to-back muscle fact as one compact line, or null when there is no overlap, without the
 * advice that follows it. The structured value is `MuscleOverlap[]` (from `consecutiveOverlaps` or
 * `buildWeekAhead`); this line is its rendering, so another block can carry the fact without
 * rebuilding the text. The watch-outs block carries it with its own instruction.
 */
export function overlapFactLine(overlaps: readonly MuscleOverlap[]): string | null {
  if (overlaps.length === 0) return null;
  return "Same muscles on consecutive days, with no rest day between (Tracend calculated from the dates): " +
    overlaps.map((overlap) =>
      `${stamp(overlap.from)} then ${stamp(overlap.to)}: ${overlap.muscles.join(", ")}`
    ).join("; ") + ".";
}

/** The fact with the advice a lookup result carries after it. */
export function renderOverlapFact(overlaps: readonly MuscleOverlap[]): string | null {
  const line = overlapFactLine(overlaps);
  return line === null ? null : `${line} Say so when you explain these days. A change of day or ` +
    "exercise is a proposal the athlete approves.";
}

/**
 * The block Coach reads: the days from today with their muscles. The muscles two sessions share on
 * consecutive days are not here: the watch-outs block states that fact (`overlapFactLine`).
 */
export function renderWeekAhead(schedule: WeekAhead): string[] {
  return [
    "Next 7 days from today, by the athlete's own dates (muscles from the sets of each session: " +
    "logged sets for a finished one, planned sets for the rest; Tracend calculated them):",
    ...schedule.days.map(describeDay),
  ];
}
