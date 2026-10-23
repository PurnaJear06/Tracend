import type { HeartRateInputs, HeartRateSetRow } from "./profile.ts";

// Reads `get_heart_rate_inputs_v1` (service role only; the athlete's own app reads
// `get_my_heart_rate_inputs_v1`, the same object). Anything malformed is dropped, never repaired.

export const heartRateInputsRpc = "get_heart_rate_inputs_v1";

/** The key under which the turn reads the profile's inputs once for every contributor that needs them. */
export const heartRateInputsReadKey = "heart_rate_inputs";

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

function setRow(value: unknown): HeartRateSetRow | null {
  if (!isObject(value)) return null;
  const coverage = numberOrNull(value.coverage);
  const samples = numberOrNull(value.sample_count);
  if (
    typeof value.local_date !== "string" || !datePattern.test(value.local_date) ||
    coverage === null || samples === null ||
    (value.source !== "watch_workout" && value.source !== "background")
  ) return null;
  return {
    local_date: value.local_date,
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

function rows<T>(value: unknown, read: (item: unknown) => T | null): T[] {
  if (!Array.isArray(value)) return [];
  return value.map(read).filter((item): item is T => item !== null);
}

/** The inputs from the RPC payload, or null when it is not an inputs object. */
export function parseHeartRateInputs(value: unknown): HeartRateInputs | null {
  if (!isObject(value) || typeof value.as_of !== "string" || !datePattern.test(value.as_of)) {
    return null;
  }
  return {
    schema_version: typeof value.schema_version === "string" ? value.schema_version : "",
    as_of: value.as_of,
    birth_year: numberOrNull(value.birth_year),
    resting: rows(value.resting, (item) => {
      if (!isObject(item) || typeof item.local_date !== "string") return null;
      const bpm = numberOrNull(item.bpm);
      return bpm === null || !datePattern.test(item.local_date)
        ? null
        : { local_date: item.local_date, bpm };
    }),
    sets: rows(value.sets, setRow),
    peak_candidates: rows(value.peak_candidates, setRow),
  };
}

/** Loads one athlete's inputs for a coaching date; null when the read fails or has no payload. */
export async function loadHeartRateInputs(
  client: RpcClient,
  userId: string,
  localDate: string,
): Promise<HeartRateInputs | null> {
  const { data, error } = await client.rpc(heartRateInputsRpc, {
    target_user: userId,
    local_date: localDate,
  });
  return error ? null : parseHeartRateInputs(data);
}
