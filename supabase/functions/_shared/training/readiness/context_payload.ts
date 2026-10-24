// What the Coach is allowed to know about today's readiness card: the payload of
// public.get_readiness_context_v1 (service role, schema 1.0), with a strict parser. The reader
// already leaves out the athlete's answers, the red-flag codes and the pain severities; this parser
// goes one step further and keeps only what the Coach context renders, so a field that gets added
// to the reader later cannot reach the model by accident. A payload that is not exactly this
// shape, or that is for another day than the one asked for, yields null, never a half-read object.
import {
  type AdjustmentKind,
  adjustmentKinds,
  type AdjustmentStatus,
  adjustmentStatuses,
  type ReadinessBand,
  readinessBands,
  type SafetyRoute,
  safetyRoutes,
  type UnavailableReason,
  unavailableReasons,
} from "./payload.ts";

export const readinessContextRpc = "get_readiness_context_v1";

export const contextJointAreas = ["knee", "back", "shoulder", "other"] as const;
export type ContextJointArea = typeof contextJointAreas[number];

export const contextJointStates = ["held", "limited", "watch"] as const;
export type ContextJointState = typeof contextJointStates[number];

export type ContextJoint = Readonly<{
  area: ContextJointArea;
  state: ContextJointState;
  /** The area has been limited or held for two weeks or more. */
  persistent: boolean;
}>;

export type ReadinessContext = Readonly<{
  localDate: string;
  band: ReadinessBand;
  /** The kind in force; none when nothing applies. */
  kind: AdjustmentKind | "none";
  status: AdjustmentStatus;
  available: boolean;
  unavailableReason: UnavailableReason | null;
  safetyRoute: SafetyRoute | null;
  confidence: "high" | "medium" | "low" | null;
  jointStates: readonly ContextJoint[];
}>;

type Json = Record<string, unknown>;

const record = (value: unknown): Json | null =>
  typeof value === "object" && value !== null && !Array.isArray(value) ? value as Json : null;
const oneOf = <T extends string>(list: readonly T[], value: unknown): T | null =>
  typeof value === "string" && (list as readonly string[]).includes(value) ? value as T : null;

/** undefined: the value is present but mistyped; null: JSON null. */
function nullable<T>(value: unknown, read: (value: unknown) => T | null): T | null | undefined {
  if (value === null) return null;
  const parsed = read(value);
  return parsed === null ? undefined : parsed;
}

function joints(raw: unknown): ContextJoint[] | null {
  if (!Array.isArray(raw)) return null;
  const parsed: ContextJoint[] = [];
  for (const item of raw) {
    const row = record(item);
    const area = oneOf(contextJointAreas, row?.area);
    const state = oneOf(contextJointStates, row?.state);
    if (!row || !area || !state || typeof row.persistent !== "boolean") return null;
    // One state a joint: a repeated area is a payload that contradicts itself.
    if (parsed.some((joint) => joint.area === area)) return null;
    parsed.push({ area, state, persistent: row.persistent });
  }
  return parsed;
}

/**
 * Parses a readiness-context payload for `localDate`. Null for anything that is not exactly that
 * shape: another schema version or day, an unknown band, kind, status, route or reason, a card that
 * names a route and a training change at once, an answer state that disagrees with its kind, or a
 * closed card with no reason (or an open one with a reason).
 */
export function parseReadinessContext(raw: unknown, localDate: string): ReadinessContext | null {
  const row = record(raw);
  if (!row || row.schema_version !== "1.0" || row.local_date !== localDate) return null;
  const band = oneOf(readinessBands, row.band);
  const status = oneOf(adjustmentStatuses, row.status);
  const kind = row.kind === "none" ? "none" as const : oneOf(adjustmentKinds, row.kind);
  const reason = nullable(row.unavailable_reason, (v) => oneOf(unavailableReasons, v));
  const route = nullable(row.safety_route, (v) => oneOf(safetyRoutes, v));
  const confidence = nullable(row.confidence, (v) => oneOf(["high", "medium", "low"] as const, v));
  const states = joints(row.joint_states);
  if (
    !band || !status || !kind || reason === undefined || route === undefined ||
    confidence === undefined || !states || typeof row.available !== "boolean" ||
    row.available !== (reason === null) || (kind === "none") !== (status === "none") ||
    (route !== null && kind !== "none")
  ) return null;
  return {
    localDate,
    band,
    kind,
    status,
    available: row.available,
    unavailableReason: reason,
    safetyRoute: route,
    confidence,
    jointStates: states,
  };
}
