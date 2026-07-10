export type CoachRequestV1 = Readonly<{
  schema_version: "1.0";
  local_date: string;
  timezone: string;
  idempotency_key: string;
}>;

export function parseCoachRequest(value: unknown): CoachRequestV1 {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("invalid_request");
  }
  const input = value as Record<string, unknown>;
  const keys = Object.keys(input);
  if (
    keys.length !== 4 ||
    !keys.every((key) =>
      ["schema_version", "local_date", "timezone", "idempotency_key"].includes(key)
    ) ||
    input.schema_version !== "1.0" ||
    typeof input.local_date !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(input.local_date) ||
    typeof input.timezone !== "string" ||
    input.timezone.length < 1 || input.timezone.length > 64 ||
    typeof input.idempotency_key !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      input.idempotency_key,
    )
  ) throw new Error("invalid_request");
  return input as CoachRequestV1;
}
