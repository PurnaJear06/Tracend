// The same-day adjustment as the database returns it (public.get_my_day_adjustment_v1 and
// public.respond_to_day_adjustment_v1, schema 1.0 and 1.1), with a strict parser. A later reader
// (Coach context) must parse before it uses a field: a payload that is not exactly this shape
// yields null, never a half-read object. Keys added in a later schema version are ignored; a
// missing or mistyped key is not. Schema 1.1 (B5-1) adds the joint_adjust kind, the joint fields of
// a change, joint_states, exercise_joint_options and the safety routes urgent, clinician_today and
// clinician; a 1.0 payload parses with those parts empty.
import { isRedFlagCode, type RedFlagCode } from "../joints/red_flags.ts";

export const adjustmentKinds = [
  "hold_load",
  "reduce_sets",
  "swap_to_easy_cardio",
  "joint_adjust",
] as const;
export type AdjustmentKind = typeof adjustmentKinds[number];

export const readinessBands = ["green", "amber", "red", "unknown"] as const;
export type ReadinessBand = typeof readinessBands[number];

export const adjustmentStatuses = ["none", "proposed", "accepted", "declined"] as const;
export type AdjustmentStatus = typeof adjustmentStatuses[number];

export const readinessTriggers = [
  "not_available",
  "no_check_in",
  "sleep_very_poor",
  "sleep_poor",
  "sleep_short",
  "energy_very_low",
  "energy_low",
  "very_sore",
  "sore",
  "mood_very_low",
  "pain_moderate",
  "pain_mild",
  "recovery_low",
  "pain_severe",
  /** A day a break the athlete approved covers (20261101200000). */
  "paused",
] as const;
/** A trigger code, or red_flag:<code> for a red flag behind a safety route (schema 1.1). */
export type ReadinessTrigger = typeof readinessTriggers[number] | `red_flag:${RedFlagCode}`;

export const unavailableReasons = [
  "no_plan",
  "rest_day",
  "session_started",
  "session_done",
  "coach_adjusted",
] as const;
export type UnavailableReason = typeof unavailableReasons[number];

export const safetyRoutes = ["pain_referral", "urgent", "clinician_today", "clinician"] as const;
export type SafetyRoute = typeof safetyRoutes[number];

const safetyOutcomes = ["urgent", "clinician_today", "clinician"] as const;
export const jointActions = ["swap", "limit", "drop"] as const;
export const jointNames = ["knee", "back", "shoulder"] as const;
export const jointStateNames = ["held", "limited", "watch"] as const;
export type JointName = typeof jointNames[number];
export type JointStateName = typeof jointStateNames[number];

/** What a joint state changes about one exercise (schema 1.1); null on an exercise no joint touches. */
export type JointChange = Readonly<{
  action: typeof jointActions[number];
  joint: JointName;
  state: JointStateName;
  swapToSlug: string | null;
  swapToName: string | null;
  rangeNoteCode: string | null;
  /** Every cue a limited exercise needs, in joint order; null unless the action is limit. */
  rangeNoteCodes: readonly string[] | null;
}>;

export type AdjustmentChange = Readonly<{
  exerciseOrder: number;
  plannedExerciseId: string;
  name: string;
  setsFrom: number;
  setsTo: number;
  loadNote: string | null;
  loadKgFrom: number | null;
  loadKgTo: number | null;
  repsFrom: number | null;
  repsTo: number | null;
  rpeTo: number | null;
  joint: JointChange | null;
}>;

export type JointState = Readonly<{
  area: "knee" | "back" | "shoulder" | "other";
  state: JointStateName;
  since: string;
  severity: number;
  persistent: boolean;
  /** held only: the strictest outcome of the hold in force; null otherwise (and in 1.0). */
  holdOutcome: "urgent" | "clinician_today" | "clinician" | null;
}>;

/** The gentlest swap per joint for one exercise of today's session, for the in-workout pain chip. */
export type ExerciseJointOptions = Readonly<{
  exerciseOrder: number;
  plannedExerciseId: string;
  name: string;
  knee: Readonly<{ slug: string; name: string }> | null;
  back: Readonly<{ slug: string; name: string }> | null;
  shoulder: Readonly<{ slug: string; name: string }> | null;
}>;

export type AdjustmentCardio = Readonly<{
  minutesMin: number;
  minutesMax: number;
  effort: "easy";
  talkTest: boolean;
  vigorousAllowed: boolean;
}>;

export type AdjustmentOption = Readonly<{
  kind: AdjustmentKind;
  explanation: string;
  setsTotalTo: number;
  changes: readonly AdjustmentChange[];
  cardio: AdjustmentCardio | null;
}>;

export type DayAdjustment = Readonly<{
  schemaVersion: "1.0" | "1.1";
  localDate: string;
  band: ReadinessBand;
  triggers: readonly ReadinessTrigger[];
  /** The kind in force: proposed, accepted or declined; none when nothing applies. */
  kind: AdjustmentKind | "none";
  changes: readonly AdjustmentChange[];
  explanation: string;
  status: AdjustmentStatus;
  available: boolean;
  unavailableReason: UnavailableReason | null;
  safetyRoute: SafetyRoute | null;
  confidence: "high" | "medium" | "low" | null;
  missing: readonly ("sleep" | "recovery")[];
  cardio: AdjustmentCardio | null;
  plannedWorkoutId: string | null;
  workoutName: string | null;
  setsTotalFrom: number;
  setsTotalTo: number;
  previousAnswer:
    | Readonly<{
      kind: AdjustmentKind;
      status: "accepted" | "declined";
      /** Why it no longer stands: a different check-in, or data that arrived since. */
      reason: "check_in" | "new_data";
    }>
    | null;
  answeredAt: string | null;
  rulesVersion: string;
  origin: "proposed" | "chosen" | null;
  options: readonly AdjustmentOption[];
  signals: Readonly<{
    recoveryScore: number | null;
    recoveryConfidence: string | null;
    recoveryMode: string | null;
    recoveryLow: boolean;
    sleepMinutes: number | null;
  }>;
  jointStates: readonly JointState[];
  exerciseJointOptions: readonly ExerciseJointOptions[];
}>;

type Json = Record<string, unknown>;

const record = (value: unknown): Json | null =>
  typeof value === "object" && value !== null && !Array.isArray(value) ? value as Json : null;
const whole = (value: unknown): number | null =>
  typeof value === "number" && Number.isInteger(value) ? value : null;
const text = (value: unknown): string | null => typeof value === "string" ? value : null;
const oneOf = <T extends string>(list: readonly T[], value: unknown): T | null =>
  typeof value === "string" && (list as readonly string[]).includes(value) ? value as T : null;

/** undefined: the value is present but mistyped; null: absent (JSON null). */
function nullable<T>(value: unknown, read: (value: unknown) => T | null): T | null | undefined {
  if (value === null) return null;
  const parsed = read(value);
  return parsed === null ? undefined : parsed;
}
const number = (value: unknown): number | null =>
  typeof value === "number" && Number.isFinite(value) ? value : null;

function jointOf(row: Json): JointChange | null | undefined {
  const action = row.joint_action;
  const others = [
    row.joint,
    row.joint_state,
    row.swap_to_slug,
    row.swap_to_name,
    row.range_note_code,
  ];
  if (action === undefined || action === null) {
    return others.every((value) => value === undefined || value === null) ? null : undefined;
  }
  const kind = oneOf(jointActions, action);
  const joint = oneOf(jointNames, row.joint);
  const state = oneOf(jointStateNames, row.joint_state);
  const slug = nullable(row.swap_to_slug, text);
  const name = nullable(row.swap_to_name, text);
  const note = nullable(row.range_note_code, text);
  const notes = row.range_note_codes === undefined || row.range_note_codes === null
    ? null
    : Array.isArray(row.range_note_codes) &&
        row.range_note_codes.every((item) => typeof item === "string")
    ? row.range_note_codes as string[]
    : undefined;
  if (
    !kind || !joint || !state || slug === undefined || name === undefined || note === undefined ||
    (kind === "swap") !== (slug !== null && name !== null) ||
    (kind !== "swap" && (slug !== null || name !== null)) ||
    (kind === "limit") !== (note !== null) || notes === undefined ||
    (kind === "limit") !== (notes !== null) ||
    (notes !== null && note !== null && !notes.includes(note))
  ) return undefined;
  return {
    action: kind,
    joint,
    state,
    swapToSlug: slug,
    swapToName: name,
    rangeNoteCode: note,
    rangeNoteCodes: notes,
  };
}

function change(raw: unknown, withJoint: boolean): AdjustmentChange | null {
  const row = record(raw);
  if (!row) return null;
  const joint = withJoint ? jointOf(row) : null;
  const loadNote = nullable(row.load_note, text);
  const loadFrom = nullable(row.load_kg_from, number);
  const loadTo = nullable(row.load_kg_to, number);
  const repsFrom = nullable(row.reps_from, whole);
  const repsTo = nullable(row.reps_to, whole);
  const rpeTo = nullable(row.rpe_to, number);
  const order = whole(row.exercise_order);
  const from = whole(row.sets_from);
  const to = whole(row.sets_to);
  if (
    order === null || typeof row.planned_exercise_id !== "string" || typeof row.name !== "string" ||
    from === null || to === null || to < 0 || to > from || loadNote === undefined ||
    loadFrom === undefined || loadTo === undefined || repsFrom === undefined ||
    repsTo === undefined || rpeTo === undefined || joint === undefined ||
    (joint?.action === "drop" && to !== 0)
  ) return null;
  return {
    exerciseOrder: order,
    plannedExerciseId: row.planned_exercise_id,
    name: row.name,
    setsFrom: from,
    setsTo: to,
    loadNote,
    loadKgFrom: loadFrom,
    loadKgTo: loadTo,
    repsFrom,
    repsTo,
    rpeTo,
    joint,
  };
}

function changes(raw: unknown, withJoint: boolean): AdjustmentChange[] | null {
  if (!Array.isArray(raw)) return null;
  const parsed = raw.map((item) => change(item, withJoint));
  return parsed.includes(null) ? null : parsed as AdjustmentChange[];
}

function cardio(raw: unknown): AdjustmentCardio | null | undefined {
  if (raw === null) return null;
  const row = record(raw);
  const min = whole(row?.minutes_min);
  const max = whole(row?.minutes_max);
  if (
    !row || min === null || max === null || min > max || row.effort !== "easy" ||
    typeof row.talk_test !== "boolean" || typeof row.vigorous_allowed !== "boolean"
  ) return undefined;
  return {
    minutesMin: min,
    minutesMax: max,
    effort: "easy",
    talkTest: row.talk_test,
    vigorousAllowed: row.vigorous_allowed,
  };
}

function option(raw: unknown, withJoint: boolean): AdjustmentOption | null {
  const row = record(raw);
  const kind = oneOf(adjustmentKinds, row?.kind);
  const list = changes(row?.changes, withJoint);
  const dose = cardio(row?.cardio);
  const total = whole(row?.sets_total_to);
  if (
    !row || !kind || !list || dose === undefined || total === null ||
    typeof row.explanation !== "string" || (kind === "swap_to_easy_cardio") !== (dose !== null)
  ) return null;
  return { kind, explanation: row.explanation, setsTotalTo: total, changes: list, cardio: dose };
}

const trigger = (value: unknown): ReadinessTrigger | null => {
  if (typeof value !== "string") return null;
  if (value.startsWith("red_flag:")) {
    const code = value.slice("red_flag:".length);
    return isRedFlagCode(code) ? value as ReadinessTrigger : null;
  }
  return oneOf(readinessTriggers, value);
};

function jointStates(raw: unknown): JointState[] | null {
  if (!Array.isArray(raw)) return null;
  const parsed = raw.map((item): JointState | null => {
    const row = record(item);
    const area = oneOf(["knee", "back", "shoulder", "other"] as const, row?.area);
    const state = oneOf(jointStateNames, row?.state);
    const severity = whole(row?.severity);
    const hold = nullable(row?.hold_outcome, (v) => oneOf(safetyOutcomes, v));
    if (
      !row || !area || !state || typeof row.since !== "string" || severity === null ||
      severity < 0 || severity > 10 || typeof row.persistent !== "boolean" || hold === undefined ||
      (state === "held") !== (hold !== null)
    ) return null;
    return {
      area,
      state,
      since: row.since,
      severity,
      persistent: row.persistent,
      holdOutcome: hold,
    };
  });
  return parsed.includes(null) ? null : parsed as JointState[];
}

function jointSwap(value: unknown): Readonly<{ slug: string; name: string }> | null | undefined {
  if (value === null) return null;
  const row = record(value);
  return row && typeof row.slug === "string" && typeof row.name === "string"
    ? { slug: row.slug, name: row.name }
    : undefined;
}

function exerciseJointOptions(raw: unknown): ExerciseJointOptions[] | null {
  if (!Array.isArray(raw)) return null;
  const parsed = raw.map((item): ExerciseJointOptions | null => {
    const row = record(item);
    const options = record(row?.joint_options);
    const order = whole(row?.exercise_order);
    const knee = jointSwap(options?.knee);
    const back = jointSwap(options?.back);
    const shoulder = jointSwap(options?.shoulder);
    if (
      !row || !options || order === null || typeof row.planned_exercise_id !== "string" ||
      typeof row.name !== "string" || knee === undefined || back === undefined ||
      shoulder === undefined
    ) return null;
    return {
      exerciseOrder: order,
      plannedExerciseId: row.planned_exercise_id,
      name: row.name,
      knee,
      back,
      shoulder,
    };
  });
  return parsed.includes(null) ? null : parsed as ExerciseJointOptions[];
}

/**
 * Parses a day-adjustment payload (schema 1.0 or 1.1). Null for anything that is not exactly that
 * shape: a wrong schema version, an unknown kind, band, trigger, status or reason, a change that
 * adds sets or lists more sets than the plan has, a cardio dose on a kind that is not easy cardio,
 * a joint change that contradicts itself.
 */
export function parseDayAdjustment(raw: unknown): DayAdjustment | null {
  const row = record(raw);
  if (
    !row || (row.schema_version !== "1.0" && row.schema_version !== "1.1") ||
    typeof row.local_date !== "string"
  ) return null;
  const withJoint = row.schema_version === "1.1";
  const band = oneOf(readinessBands, row.band);
  const status = oneOf(adjustmentStatuses, row.status);
  const kind = row.kind === "none" ? "none" as const : oneOf(adjustmentKinds, row.kind);
  const list = changes(row.changes, withJoint);
  const dose = cardio(row.cardio);
  const reason = nullable(row.unavailable_reason, (v) => oneOf(unavailableReasons, v));
  const route = nullable(row.safety_route, (v) => oneOf(safetyRoutes, v));
  const confidence = nullable(row.confidence, (v) => oneOf(["high", "medium", "low"] as const, v));
  const workoutId = nullable(row.planned_workout_id, text);
  const workoutName = nullable(row.workout_name, text);
  const answeredAt = nullable(row.answered_at, text);
  const origin = nullable(row.origin, (v) => oneOf(["proposed", "chosen"] as const, v));
  const from = whole(row.sets_total_from);
  const to = whole(row.sets_total_to);
  const triggers = Array.isArray(row.triggers) ? row.triggers.map(trigger) : null;
  const missing = Array.isArray(row.missing)
    ? row.missing.map((item) => oneOf(["sleep", "recovery"] as const, item))
    : null;
  const options = Array.isArray(row.options)
    ? row.options.map((item) => option(item, withJoint))
    : null;
  const states = withJoint ? jointStates(row.joint_states) : [];
  const exercises = withJoint ? exerciseJointOptions(row.exercise_joint_options) : [];
  const signals = record(row.signals);
  const previous = row.previous_answer === null ? null : record(row.previous_answer);
  const previousKind = previous ? oneOf(adjustmentKinds, previous.kind) : null;
  const previousStatus = previous
    ? oneOf(["accepted", "declined"] as const, previous.status)
    : null;
  const previousReason = previous
    ? oneOf(["check_in", "new_data"] as const, previous.reason)
    : null;
  const score = nullable(signals?.recovery_score, whole);
  const sleep = nullable(signals?.sleep_minutes, whole);
  const recoveryConfidence = nullable(signals?.recovery_confidence, text);
  const recoveryMode = nullable(signals?.recovery_mode, text);
  if (
    !band || !status || !kind || !list || dose === undefined || reason === undefined ||
    route === undefined || confidence === undefined || workoutId === undefined ||
    workoutName === undefined || answeredAt === undefined || origin === undefined ||
    from === null || to === null || to > from || !triggers || triggers.includes(null) ||
    !missing || missing.includes(null) || !options || options.includes(null) || !signals ||
    typeof row.available !== "boolean" || typeof row.explanation !== "string" ||
    typeof row.rules_version !== "string" || typeof signals.recovery_low !== "boolean" ||
    score === undefined || sleep === undefined || recoveryConfidence === undefined ||
    recoveryMode === undefined || !states || !exercises ||
    (previous !== null && (!previousKind || !previousStatus || !previousReason)) ||
    row.available !== (reason === null) || (kind === "swap_to_easy_cardio") !== (dose !== null) ||
    (kind === "none") !== (status === "none") || (route !== null && kind !== "none") ||
    (kind === "joint_adjust" && (list.length === 0 || list.some((c) => c.joint === null)))
  ) return null;
  return {
    schemaVersion: row.schema_version,
    localDate: row.local_date,
    band,
    triggers: triggers as ReadinessTrigger[],
    kind,
    changes: list,
    explanation: row.explanation,
    status,
    available: row.available,
    unavailableReason: reason,
    safetyRoute: route,
    confidence,
    missing: missing as ("sleep" | "recovery")[],
    cardio: dose,
    plannedWorkoutId: workoutId,
    workoutName,
    setsTotalFrom: from,
    setsTotalTo: to,
    previousAnswer: previous && previousKind && previousStatus && previousReason
      ? { kind: previousKind, status: previousStatus, reason: previousReason }
      : null,
    answeredAt,
    rulesVersion: row.rules_version,
    origin,
    options: options as AdjustmentOption[],
    signals: {
      recoveryScore: score,
      recoveryConfidence,
      recoveryMode,
      recoveryLow: signals.recovery_low,
      sleepMinutes: sleep,
    },
    jointStates: states,
    exerciseJointOptions: exercises,
  };
}
