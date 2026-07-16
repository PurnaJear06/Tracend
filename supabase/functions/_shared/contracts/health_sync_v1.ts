export const healthTypes = [
  "steps",
  "active_energy",
  "sleep",
  "workouts",
  "weight",
  "resting_heart_rate",
  "hrv_sdnn",
] as const;

export type HealthType = typeof healthTypes[number];

export type HealthSummaryV1 = {
  local_date: string;
  timezone: string;
  steps?: number;
  active_energy_kcal?: number;
  sleep_minutes?: number;
  sleep_awake_minutes?: number;
  sleep_light_minutes?: number;
  sleep_deep_minutes?: number;
  sleep_rem_minutes?: number;
  workout_count?: number;
  workout_minutes?: number;
  weight_kg?: number;
  resting_heart_rate_bpm?: number;
  hrv_value_ms?: number;
  hrv_metric?: "sdnn";
  hrv_unit?: "ms";
  present_types: HealthType[];
  source_refs: Array<{
    type: HealthType;
    source_id_hash: string;
    sample_id_hash: string;
  }>;
  source_checksum: string;
  completeness: "complete" | "partial";
  observed_through: string;
};

export type HealthSyncRequestV1 = {
  schema_version: "1.0";
  idempotency_key: string;
  requested_start: string;
  requested_end: string;
  requested_types: HealthType[];
  returned_types: HealthType[];
  summaries: HealthSummaryV1[];
  workouts: HealthWorkoutReferenceV1[];
};

export type HealthWorkoutReferenceV1 = {
  sample_id_hash: string;
  source_id_hash: string;
  activity_type: string;
  started_at: string;
  ended_at: string;
  duration_seconds: number;
  energy_kcal?: number;
  local_date: string;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;
const hashPattern = /^[0-9a-f]{64}$/;
const requestKeys = new Set([
  "schema_version",
  "idempotency_key",
  "requested_start",
  "requested_end",
  "requested_types",
  "returned_types",
  "summaries",
  "workouts",
]);
const workoutKeys = new Set([
  "sample_id_hash",
  "source_id_hash",
  "activity_type",
  "started_at",
  "ended_at",
  "duration_seconds",
  "energy_kcal",
  "local_date",
]);
const summaryKeys = new Set([
  "local_date",
  "timezone",
  "steps",
  "active_energy_kcal",
  "sleep_minutes",
  "sleep_awake_minutes",
  "sleep_light_minutes",
  "sleep_deep_minutes",
  "sleep_rem_minutes",
  "workout_count",
  "workout_minutes",
  "weight_kg",
  "resting_heart_rate_bpm",
  "hrv_value_ms",
  "hrv_metric",
  "hrv_unit",
  "present_types",
  "source_refs",
  "source_checksum",
  "completeness",
  "observed_through",
]);
const referenceKeys = new Set([
  "type",
  "source_id_hash",
  "sample_id_hash",
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isNumber(value: unknown, minimum: number, maximum: number): boolean {
  return typeof value === "number" && Number.isFinite(value) &&
    value >= minimum && value <= maximum;
}

function isHealthType(value: unknown): value is HealthType {
  return typeof value === "string" &&
    (healthTypes as readonly string[]).includes(value);
}

function validOptionalNumber(
  object: Record<string, unknown>,
  key: string,
  minimum: number,
  maximum: number,
): boolean {
  return object[key] === undefined ||
    isNumber(object[key], minimum, maximum);
}

function hasOnlyKeys(
  object: Record<string, unknown>,
  allowed: ReadonlySet<string>,
): boolean {
  return Object.keys(object).every((key) => allowed.has(key));
}

function isUnique(values: readonly unknown[]): boolean {
  return new Set(values).size === values.length;
}

export function parseHealthSyncRequest(value: unknown): HealthSyncRequestV1 {
  if (
    !isRecord(value) || value.schema_version !== "1.0" ||
    typeof value.idempotency_key !== "string" ||
    !uuidPattern.test(value.idempotency_key) ||
    typeof value.requested_start !== "string" ||
    !datePattern.test(value.requested_start) ||
    typeof value.requested_end !== "string" ||
    !datePattern.test(value.requested_end) ||
    !Array.isArray(value.requested_types) ||
    !Array.isArray(value.returned_types) ||
    !Array.isArray(value.summaries) || value.summaries.length > 32 ||
    (value.workouts !== undefined &&
      (!Array.isArray(value.workouts) || value.workouts.length > 100)) ||
    !hasOnlyKeys(value, requestKeys)
  ) {
    throw new Error("invalid_health_sync_request");
  }
  const requestedStart = value.requested_start;
  const requestedEnd = value.requested_end;
  const requestedTypes = value.requested_types;
  const returnedTypes = value.returned_types;
  if (
    !requestedTypes.every(isHealthType) ||
    requestedTypes.length === 0 ||
    !returnedTypes.every(isHealthType) ||
    !returnedTypes.every((type) => requestedTypes.includes(type)) ||
    !isUnique(requestedTypes) || !isUnique(returnedTypes)
  ) {
    throw new Error("invalid_health_sync_request");
  }

  const summaries = value.summaries.map((summary) => {
    if (
      !isRecord(summary) || !hasOnlyKeys(summary, summaryKeys) ||
      !Array.isArray(summary.present_types) ||
      !Array.isArray(summary.source_refs)
    ) {
      throw new Error("invalid_health_summary");
    }
    const presentTypes = summary.present_types;
    const sourceRefs = summary.source_refs;
    if (
      typeof summary.local_date !== "string" ||
      !datePattern.test(summary.local_date) ||
      typeof summary.timezone !== "string" ||
      summary.timezone.length < 1 || summary.timezone.length > 64 ||
      presentTypes.length === 0 ||
      !presentTypes.every(isHealthType) ||
      !isUnique(presentTypes) ||
      !presentTypes.every((type) => returnedTypes.includes(type)) ||
      typeof summary.source_checksum !== "string" ||
      !hashPattern.test(summary.source_checksum) ||
      sourceRefs.length === 0 ||
      (summary.completeness !== "complete" &&
        summary.completeness !== "partial") ||
      typeof summary.observed_through !== "string" ||
      Number.isNaN(Date.parse(summary.observed_through)) ||
      !validOptionalNumber(summary, "steps", 0, 200000) ||
      (summary.steps !== undefined && !Number.isInteger(summary.steps)) ||
      !validOptionalNumber(summary, "active_energy_kcal", 0, 30000) ||
      !validOptionalNumber(summary, "sleep_minutes", 0, 1440) ||
      (summary.sleep_minutes !== undefined &&
        !Number.isInteger(summary.sleep_minutes)) ||
      !validOptionalNumber(summary, "sleep_awake_minutes", 0, 1440) ||
      (summary.sleep_awake_minutes !== undefined &&
        !Number.isInteger(summary.sleep_awake_minutes)) ||
      !validOptionalNumber(summary, "sleep_light_minutes", 0, 1440) ||
      (summary.sleep_light_minutes !== undefined &&
        !Number.isInteger(summary.sleep_light_minutes)) ||
      !validOptionalNumber(summary, "sleep_deep_minutes", 0, 1440) ||
      (summary.sleep_deep_minutes !== undefined &&
        !Number.isInteger(summary.sleep_deep_minutes)) ||
      !validOptionalNumber(summary, "sleep_rem_minutes", 0, 1440) ||
      (summary.sleep_rem_minutes !== undefined &&
        !Number.isInteger(summary.sleep_rem_minutes)) ||
      !validOptionalNumber(summary, "workout_count", 0, 50) ||
      (summary.workout_count !== undefined &&
        !Number.isInteger(summary.workout_count)) ||
      !validOptionalNumber(summary, "workout_minutes", 0, 1440) ||
      (summary.workout_minutes !== undefined &&
        !Number.isInteger(summary.workout_minutes)) ||
      !validOptionalNumber(summary, "weight_kg", 20, 500) ||
      !validOptionalNumber(summary, "resting_heart_rate_bpm", 20, 250) ||
      !validOptionalNumber(summary, "hrv_value_ms", 0, 1000) ||
      (new Set([
        summary.hrv_value_ms !== undefined,
        summary.hrv_metric !== undefined,
        summary.hrv_unit !== undefined,
      ]).size > 1) ||
      (summary.hrv_value_ms !== undefined &&
        (summary.hrv_metric !== "sdnn" || summary.hrv_unit !== "ms")) ||
      ((summary.completeness === "complete") !==
        requestedTypes.every((type) => presentTypes.includes(type))) ||
      !sourceRefs.every((reference) =>
        isRecord(reference) && hasOnlyKeys(reference, referenceKeys) &&
        isHealthType(reference.type) &&
        presentTypes.includes(reference.type) &&
        typeof reference.source_id_hash === "string" &&
        hashPattern.test(reference.source_id_hash) &&
        typeof reference.sample_id_hash === "string" &&
        hashPattern.test(reference.sample_id_hash)
      ) ||
      presentTypes.some((type) =>
        !sourceRefs.some((reference) => isRecord(reference) && reference.type === type)
      )
    ) {
      throw new Error("invalid_health_summary");
    }
    const metricPresence: ReadonlyArray<[HealthType, string]> = [
      ["steps", "steps"],
      ["active_energy", "active_energy_kcal"],
      ["sleep", "sleep_minutes"],
      ["weight", "weight_kg"],
      ["resting_heart_rate", "resting_heart_rate_bpm"],
      ["hrv_sdnn", "hrv_value_ms"],
    ];
    if (
      metricPresence.some(([type, key]) =>
        presentTypes.includes(type) !== (summary[key] !== undefined)
      ) ||
      (presentTypes.includes("workouts") !==
        (summary.workout_count !== undefined &&
          summary.workout_minutes !== undefined))
    ) {
      throw new Error("invalid_health_summary");
    }
    return summary as HealthSummaryV1;
  });

  const workouts = (value.workouts ?? []).map((workout) => {
    if (
      !isRecord(workout) || !hasOnlyKeys(workout, workoutKeys) ||
      typeof workout.sample_id_hash !== "string" || !hashPattern.test(workout.sample_id_hash) ||
      typeof workout.source_id_hash !== "string" || !hashPattern.test(workout.source_id_hash) ||
      typeof workout.activity_type !== "string" || workout.activity_type.length < 1 ||
      workout.activity_type.length > 80 ||
      typeof workout.started_at !== "string" || Number.isNaN(Date.parse(workout.started_at)) ||
      typeof workout.ended_at !== "string" || Number.isNaN(Date.parse(workout.ended_at)) ||
      Date.parse(workout.ended_at) <= Date.parse(workout.started_at) ||
      !isNumber(workout.duration_seconds, 1, 86400) ||
      !Number.isInteger(workout.duration_seconds) ||
      !validOptionalNumber(workout, "energy_kcal", 0, 30000) ||
      typeof workout.local_date !== "string" || !datePattern.test(workout.local_date)
    ) throw new Error("invalid_health_workout");
    return workout as HealthWorkoutReferenceV1;
  });

  const start = Date.parse(`${requestedStart}T00:00:00Z`);
  const end = Date.parse(`${requestedEnd}T00:00:00Z`);
  if (
    end < start || end - start > 31 * 86_400_000 ||
    summaries.some((summary) =>
      summary.local_date < requestedStart ||
      summary.local_date > requestedEnd
    )
  ) {
    throw new Error("invalid_health_sync_window");
  }

  return { ...value, summaries, workouts } as HealthSyncRequestV1;
}
