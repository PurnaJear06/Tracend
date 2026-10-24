// The training guidance as the database returns it (public.get_my_training_guidance_v1 and
// public.get_training_guidance_for_v1, schema 1.0 and 1.1), with a strict parser. A later reader
// (Coach context) must parse before it uses a field: a payload that is not exactly this shape
// yields null, never a half-read object. Keys added in a later schema version are ignored; a
// missing or mistyped key is not. Schema 1.1 (B5-4) adds the cardio week and the reason it is
// withheld; a 1.0 payload parses with both empty.
import { type SafetyRoute, safetyRoutes } from "../readiness/payload.ts";

export const deloadStatuses = ["not_due", "suggested", "pending", "running"] as const;
export type DeloadStatus = typeof deloadStatuses[number];

export const deloadReasons = ["performance_drop", "run_down", "block_done"] as const;
export type DeloadReason = typeof deloadReasons[number];

export const deloadSuppressions = [
  "screening",
  "block_running",
  "recent_deload",
  "not_enough_training",
  "no_plan",
  "safety_route",
] as const;
export type DeloadSuppression = typeof deloadSuppressions[number];

export const cardioWithheldReasons = ["safety_route", "screening"] as const;
export type CardioWithheld = typeof cardioWithheldReasons[number];

export type DeloadGuidance = Readonly<{
  status: DeloadStatus;
  reasons: readonly DeloadReason[];
  lastEndedOn: string | null;
  weeksSince: number | null;
  proposalId: string | null;
  suppressedBy: DeloadSuppression | null;
}>;

export type CardioWeek = Readonly<{
  targetMin: number;
  stretchMax: number | null;
  /** null when fewer than five of the seven days have Apple Health data; never 0 for missing data. */
  doneMin: number | null;
  /** false: every counted minute is read as moderate, because a workout record has no intensity. */
  intensityKnown: boolean;
  vigorousAllowed: boolean;
  vigorousSessionsMax: number;
  vigorousCountsAs: number;
  liftSeparationHours: number;
  /** Easy effort stays below this share of heart-rate reserve. */
  easyHrReserveMax: number;
  windowFrom: string;
  windowTo: string;
}>;

export type TrainingGuidance = Readonly<{
  schemaVersion: "1.0" | "1.1";
  localDate: string;
  safetyRoute: SafetyRoute | null;
  deload: DeloadGuidance;
  cardioWithheld: CardioWithheld | null;
  /** Null in 1.0, and whenever cardioWithheld names a reason. */
  cardioWeek: CardioWeek | null;
}>;

type Json = Record<string, unknown>;

const record = (value: unknown): Json | null =>
  typeof value === "object" && value !== null && !Array.isArray(value) ? value as Json : null;
const whole = (value: unknown): number | null =>
  typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : null;
const date = (value: unknown): string | null =>
  typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null;
const oneOf = <T extends string>(list: readonly T[], value: unknown): T | null =>
  typeof value === "string" && (list as readonly string[]).includes(value) ? value as T : null;

/** undefined: the value is present but mistyped; null: JSON null. */
function nullable<T>(value: unknown, read: (value: unknown) => T | null): T | null | undefined {
  if (value === null) return null;
  const parsed = read(value);
  return parsed === null ? undefined : parsed;
}

const uuid = (value: unknown): string | null =>
  typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value)
    ? value
    : null;

function parseDeload(raw: unknown): DeloadGuidance | null {
  const row = record(raw);
  if (!row) return null;
  const status = oneOf(deloadStatuses, row.status);
  const reasons = Array.isArray(row.reasons)
    ? row.reasons.map((r) => oneOf(deloadReasons, r))
    : null;
  const lastEndedOn = nullable(row.last_ended_on, date);
  const weeksSince = nullable(row.weeks_since, whole);
  const proposalId = nullable(row.proposal_id, uuid);
  const suppressedBy = nullable(row.suppressed_by, (v) => oneOf(deloadSuppressions, v));
  if (
    !status || !reasons || reasons.includes(null) || lastEndedOn === undefined ||
    weeksSince === undefined || proposalId === undefined || suppressedBy === undefined
  ) return null;
  const named = reasons as DeloadReason[];
  // The status and its parts must agree: a suggestion has reasons and nothing in its way, a
  // proposal or a running block names its proposal, and a suppression leaves no reasons.
  if (
    (status === "suggested" &&
      (named.length === 0 || suppressedBy !== null || proposalId !== null)) ||
    ((status === "running" || status === "pending") && proposalId === null) ||
    (status === "running" && (named.length > 0 || suppressedBy !== null)) ||
    (suppressedBy !== null && named.length > 0) ||
    (status === "not_due" && named.length > 0)
  ) return null;
  return { status, reasons: named, lastEndedOn, weeksSince, proposalId, suppressedBy };
}

function parseCardioWeek(raw: unknown): CardioWeek | null {
  const row = record(raw);
  if (!row) return null;
  const targetMin = whole(row.target_min);
  const stretchMax = nullable(row.stretch_max, whole);
  const doneMin = nullable(row.done_min, whole);
  const sessionsMax = whole(row.vigorous_sessions_max);
  const countsAs = whole(row.vigorous_counts_as);
  const separation = whole(row.lift_separation_hours);
  const reserve = whole(row.easy_hr_reserve_max);
  const from = date(row.window_from);
  const to = date(row.window_to);
  if (
    targetMin === null || targetMin === 0 || stretchMax === undefined || doneMin === undefined ||
    typeof row.intensity_known !== "boolean" || typeof row.vigorous_allowed !== "boolean" ||
    sessionsMax === null || countsAs === null || separation === null || reserve === null ||
    reserve === 0 || reserve > 100 || from === null || to === null || from > to ||
    (stretchMax !== null && stretchMax <= targetMin) ||
    // Hard cardio is open only to an athlete the health check cleared for it.
    (row.vigorous_allowed && sessionsMax === 0)
  ) return null;
  return {
    targetMin,
    stretchMax,
    doneMin,
    intensityKnown: row.intensity_known,
    vigorousAllowed: row.vigorous_allowed,
    vigorousSessionsMax: sessionsMax,
    vigorousCountsAs: countsAs,
    liftSeparationHours: separation,
    easyHrReserveMax: reserve,
    windowFrom: from,
    windowTo: to,
  };
}

/** Parses a guidance payload (schema 1.0 or 1.1). Null for anything that is not exactly that shape. */
export function parseTrainingGuidance(raw: unknown): TrainingGuidance | null {
  const row = record(raw);
  if (!row || (row.schema_version !== "1.0" && row.schema_version !== "1.1")) return null;
  const localDate = date(row.local_date);
  const route = nullable(row.safety_route, (v) => oneOf(safetyRoutes, v));
  const deload = parseDeload(row.deload);
  if (localDate === null || route === undefined || !deload) return null;
  // A day with a safety route is never offered a deload.
  if (route !== null && deload.status === "suggested") return null;
  if (row.schema_version === "1.0") {
    return {
      schemaVersion: "1.0",
      localDate,
      safetyRoute: route,
      deload,
      cardioWithheld: null,
      cardioWeek: null,
    };
  }
  const withheld = nullable(row.cardio_withheld, (v) => oneOf(cardioWithheldReasons, v));
  const week = row.cardio_week === null ? null : parseCardioWeek(row.cardio_week);
  if (withheld === undefined || (row.cardio_week !== null && week === null)) return null;
  // The dose is given exactly when nothing withholds it, and a safety route always withholds it.
  if ((withheld === null) !== (week !== null)) return null;
  if (route !== null && withheld !== "safety_route") return null;
  return {
    schemaVersion: "1.1",
    localDate,
    safetyRoute: route,
    deload,
    cardioWithheld: withheld,
    cardioWeek: week,
  };
}
