// Next-session targets as the database computes them (migration 20261017140023_progression_
// targets.sql: private.progression_decision). The rules live in SQL because the training hub, which
// the app reads, is a SQL function; this module is the TypeScript side of the same payload: its
// types, a strict parser for `get_progression_summary_v1`, and the plain words Coach is given.
// Heart rate is not an input to any target (decision D9).

export type ProgressionAction = "add_load" | "add_reps" | "hold" | "lower";

export type ProgressionReason =
  | "top_of_range"
  | "within_range"
  | "top_no_step"
  | "incomplete"
  | "effort"
  | "below_range"
  | "stall"
  | "away"
  | "skipped"
  | "pain";

export type ProgressionSession = Readonly<{
  localDate: string;
  loadKg: number | null;
  sets: number;
  minReps: number;
  minRir: number | null;
}>;

export type ProgressionTarget = Readonly<{
  plannedExerciseId: string;
  exerciseKey: string;
  name: string;
  action: ProgressionAction;
  reason: ProgressionReason;
  /** null for an exercise logged without a load (bodyweight). */
  loadKg: number | null;
  reps: number;
  sets: number;
  /** low when reps in reserve were not logged for every working set. */
  confidence: "high" | "low";
  lastDate: string;
  /** Latest first, at most three. */
  recent: readonly ProgressionSession[];
}>;

const actions: readonly string[] = ["add_load", "add_reps", "hold", "lower"];
const reasons: readonly string[] = [
  "top_of_range",
  "within_range",
  "top_no_step",
  "incomplete",
  "effort",
  "below_range",
  "stall",
  "away",
  "skipped",
  "pain",
];

type Json = Record<string, unknown>;

function record(value: unknown): Json | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Json
    : null;
}

function wholeNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function nullableNumber(value: unknown): number | null | undefined {
  if (value === null) return null;
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function session(raw: unknown): ProgressionSession | null {
  const row = record(raw);
  if (!row) return null;
  const loadKg = nullableNumber(row.load_kg);
  const minRir = nullableNumber(row.min_rir);
  const sets = wholeNumber(row.sets);
  const minReps = wholeNumber(row.min_reps);
  if (
    typeof row.local_date !== "string" || loadKg === undefined || minRir === undefined ||
    sets === null || minReps === null
  ) return null;
  return { localDate: row.local_date, loadKg, sets, minReps, minRir };
}

function target(raw: unknown): ProgressionTarget | null {
  const row = record(raw);
  const basis = record(row?.basis);
  if (!row || !basis || !Array.isArray(basis.recent)) return null;
  const loadKg = nullableNumber(row.load_kg);
  const reps = wholeNumber(row.reps);
  const sets = wholeNumber(row.sets);
  const recent = basis.recent.map(session);
  if (
    typeof row.planned_exercise_id !== "string" || typeof row.exercise_key !== "string" ||
    typeof row.name !== "string" || !actions.includes(row.action as string) ||
    !reasons.includes(row.reason as string) || loadKg === undefined || reps === null ||
    sets === null || (row.confidence !== "high" && row.confidence !== "low") ||
    typeof basis.last_date !== "string" || recent.length === 0 || recent.includes(null)
  ) return null;
  return {
    plannedExerciseId: row.planned_exercise_id,
    exerciseKey: row.exercise_key,
    name: row.name,
    action: row.action as ProgressionAction,
    reason: row.reason as ProgressionReason,
    loadKg,
    reps,
    sets,
    confidence: row.confidence,
    lastDate: basis.last_date,
    recent: recent as ProgressionSession[],
  };
}

/**
 * The targets in a `get_progression_summary_v1` payload. Anything that is not the expected
 * version-1 shape yields no targets at all: a half-read payload would misstate the athlete's
 * training, so a malformed row discards the whole summary.
 */
export function parseProgressionSummary(payload: unknown): readonly ProgressionTarget[] {
  const body = record(payload);
  if (!body || typeof body.schema_version !== "string" || !body.schema_version.startsWith("1.")) {
    return [];
  }
  if (!Array.isArray(body.targets)) return [];
  const parsed = body.targets.map(target);
  return parsed.includes(null) ? [] : parsed as ProgressionTarget[];
}

function reasonWords(
  reason: ProgressionReason,
  action: ProgressionAction,
  assisted: boolean,
): string {
  const lowered = action === "lower";
  const up = assisted ? "the help is reduced by one step" : "the load goes up one step";
  const down = assisted ? "the help goes up one step" : "the load drops one step";
  switch (reason) {
    case "top_of_range":
      return `every set reached the top of the rep range with reps in reserve, so ${up}`;
    case "within_range":
      return "add one rep to the weakest set before changing the load";
    case "top_no_step":
      return "at the top of the range and this exercise has no load step, so it needs a harder variation";
    case "incomplete":
      return "fewer sets than planned were completed, so repeat the same result first";
    case "effort":
      return "a set had fewer reps in reserve than planned, so repeat the load";
    case "below_range":
      return lowered
        ? `reps stayed below the planned range for two sessions, so ${down}`
        : "reps fell below the planned range, so aim for the bottom of the range at the same load";
    case "stall":
      return lowered
        ? `three sessions at this load without more reps, so ${down}`
        : "three sessions at this load without more reps and no load step, so repeat it";
    case "away":
      return lowered
        ? `four weeks or more away, so ${down}`
        : "two weeks or more away, so repeat the last result";
    case "skipped":
      return "the exercise was skipped after the last logged session, so the target is repeated";
    case "pain":
      return "pain was flagged last time, so the target is repeated and not raised";
  }
}

function kg(value: number): string {
  return `${Number.isInteger(value) ? value : Number(value.toFixed(2))} kg`;
}

/** Machine help is the load of an assisted exercise: a catalog slug `assisted-...` or a name. */
export function isAssistedTarget(item: Pick<ProgressionTarget, "exerciseKey" | "name">): boolean {
  return item.exerciseKey.startsWith("assisted-") ||
    item.name.trim().toLowerCase().startsWith("assisted ");
}

/** "62.5 kg x 5 reps, 3 sets", "20 kg help x 8 reps, 3 sets" or "11 reps, 2 sets". */
export function describeTargetPrescription(item: ProgressionTarget): string {
  const load = item.loadKg === null
    ? ""
    : isAssistedTarget(item)
    ? (item.loadKg === 0 ? "unassisted, " : `${kg(item.loadKg)} help x `)
    : `${kg(item.loadKg)} x `;
  return `${load}${item.reps} reps, ${item.sets} sets`;
}

/** The last logged session in words: "2026-10-10: 60 kg, 3 sets, fewest reps 8". */
export function describeLastSession(item: ProgressionTarget): string {
  const last = item.recent[0];
  const load = last.loadKg === null
    ? "no load"
    : isAssistedTarget(item)
    ? (last.loadKg === 0 ? "unassisted" : `${kg(last.loadKg)} help`)
    : kg(last.loadKg);
  return `${last.localDate}: ${load}, ${last.sets} sets, fewest reps ${last.minReps}`;
}

/** One line of Coach context for a target. */
export function describeTarget(item: ProgressionTarget): string {
  const caution = item.confidence === "low" ? " (reps in reserve were not logged)" : "";
  return `${item.name}: ${describeTargetPrescription(item)}; ${item.action.replace("_", " ")}, ` +
    `${reasonWords(item.reason, item.action, isAssistedTarget(item))}${caution}. Last logged ${
      describeLastSession(item)
    }.`;
}
