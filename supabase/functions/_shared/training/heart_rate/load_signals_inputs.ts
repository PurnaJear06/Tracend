import { loadHeartRateInputs } from "./inputs.ts";
import {
  computeLoadSignals,
  type LoadSignals,
  type LoadSignalSession,
  type LoadSignalSet,
  type WorkoutLoadInputs,
} from "./load_signals.ts";
import { buildHeartRateProfile, type HeartRateInputs } from "./profile.ts";

// Reads `get_workout_load_inputs_v1` (service role only) and the heart-rate profile's inputs, and
// works the load signals out. Anything malformed is dropped, never repaired; a failed read gives no
// signals, so the plan and its progression stand exactly as they would without heart rate (D9).

export const workoutLoadInputsRpc = "get_workout_load_inputs_v1";

type RpcClient = Readonly<{
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { message: string } | null }>;
}>;

const datePattern = /^\d{4}-\d{2}-\d{2}$/;

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function numberOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function setRow(value: unknown): LoadSignalSet | null {
  if (!isObject(value)) return null;
  const exerciseOrder = numberOrNull(value.exercise_order);
  const setNumber = numberOrNull(value.set_number);
  const coverage = numberOrNull(value.coverage);
  const samples = numberOrNull(value.sample_count);
  if (
    exerciseOrder === null || setNumber === null || coverage === null || samples === null ||
    (value.source !== "watch_workout" && value.source !== "background")
  ) return null;
  return {
    exercise_order: exerciseOrder,
    set_number: setNumber,
    rest_before_seconds: numberOrNull(value.rest_before_seconds),
    start_bpm: numberOrNull(value.start_bpm),
    peak_bpm: numberOrNull(value.peak_bpm),
    end_bpm: numberOrNull(value.end_bpm),
    drop_30s_bpm: numberOrNull(value.drop_30s_bpm),
    drop_60s_bpm: numberOrNull(value.drop_60s_bpm),
    coverage,
    sample_count: samples,
    source: value.source,
  };
}

function sessionRow(value: unknown): LoadSignalSession | null {
  if (!isObject(value)) return null;
  const completed = numberOrNull(value.completed_sets);
  if (
    typeof value.local_date !== "string" || !datePattern.test(value.local_date) ||
    completed === null || !Array.isArray(value.sets)
  ) return null;
  return {
    local_date: value.local_date,
    completed_sets: completed,
    sets: value.sets.map(setRow).filter((set): set is LoadSignalSet => set !== null),
  };
}

/** The inputs from the RPC payload, or null when it is not an inputs object. */
export function parseWorkoutLoadInputs(value: unknown): WorkoutLoadInputs | null {
  if (
    !isObject(value) || typeof value.as_of !== "string" || !datePattern.test(value.as_of) ||
    !Array.isArray(value.sessions)
  ) return null;
  return {
    schema_version: typeof value.schema_version === "string" ? value.schema_version : "",
    as_of: value.as_of,
    sessions: value.sessions.map(sessionRow).filter((s): s is LoadSignalSession => s !== null),
  };
}

/**
 * One athlete's load signals for a coaching date; null when either read fails or has no payload.
 * `readHeartRateInputs` is the profile's inputs for the same athlete and date; pass the turn's
 * shared read so `get_heart_rate_inputs_v1` runs once.
 */
export async function loadWorkoutLoadSignals(
  client: RpcClient,
  userId: string,
  localDate: string,
  readHeartRateInputs: () => Promise<HeartRateInputs | null> = () =>
    loadHeartRateInputs(client, userId, localDate),
): Promise<LoadSignals | null> {
  const [profileInputs, workouts] = await Promise.all([
    readHeartRateInputs(),
    client.rpc(workoutLoadInputsRpc, { target_user: userId, local_date: localDate }),
  ]);
  if (profileInputs === null || workouts.error) return null;
  const inputs = parseWorkoutLoadInputs(workouts.data);
  return inputs === null ? null : computeLoadSignals(inputs, buildHeartRateProfile(profileInputs));
}
