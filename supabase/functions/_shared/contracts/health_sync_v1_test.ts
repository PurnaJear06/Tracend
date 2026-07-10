import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { parseHealthSyncRequest } from "./health_sync_v1.ts";

const valid = {
  schema_version: "1.0",
  idempotency_key: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  requested_start: "2026-06-30",
  requested_end: "2026-07-01",
  requested_types: ["steps", "sleep"],
  returned_types: ["steps"],
  summaries: [{
    local_date: "2026-07-01",
    timezone: "Asia/Kolkata",
    steps: 6400,
    present_types: ["steps"],
    source_refs: [{
      type: "steps",
      source_id_hash: "a".repeat(64),
      sample_id_hash: "b".repeat(64),
    }],
    source_checksum: "c".repeat(64),
    completeness: "partial",
    observed_through: "2026-07-01T08:00:00.000Z",
  }],
};

Deno.test("health sync accepts canonical partial summaries", () => {
  const parsed = parseHealthSyncRequest(valid);
  assertEquals(parsed.summaries[0].steps, 6400);
});

Deno.test("health sync rejects out-of-range health values", () => {
  assertThrows(
    () =>
      parseHealthSyncRequest({
        ...valid,
        summaries: [{ ...valid.summaries[0], steps: 900000 }],
      }),
    Error,
    "invalid_health_summary",
  );
});

Deno.test("health sync rejects summaries outside the requested window", () => {
  assertThrows(
    () =>
      parseHealthSyncRequest({
        ...valid,
        summaries: [{ ...valid.summaries[0], local_date: "2026-06-01" }],
      }),
    Error,
    "invalid_health_sync_window",
  );
});

Deno.test("health sync rejects ownership fields and duplicate types", () => {
  assertThrows(() =>
    parseHealthSyncRequest({
      ...valid,
      user_id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
      requested_types: ["steps", "steps"],
    })
  );
});

Deno.test("health sync rejects inconsistent completeness", () => {
  assertThrows(() =>
    parseHealthSyncRequest({
      ...valid,
      requested_types: ["steps"],
      returned_types: ["steps"],
      summaries: [{ ...valid.summaries[0], completeness: "partial" }],
    })
  );
});

Deno.test("health sync rejects missing source provenance", () => {
  assertThrows(
    () =>
      parseHealthSyncRequest({
        ...valid,
        summaries: [{ ...valid.summaries[0], source_refs: [] }],
      }),
    Error,
    "invalid_health_summary",
  );
});

Deno.test("health sync requires explicit HRV metric and unit", () => {
  assertThrows(
    () =>
      parseHealthSyncRequest({
        ...valid,
        requested_types: ["hrv_sdnn"],
        returned_types: ["hrv_sdnn"],
        summaries: [{
          ...valid.summaries[0],
          steps: undefined,
          hrv_value_ms: 48,
          hrv_metric: "sdnn",
          present_types: ["hrv_sdnn"],
          source_refs: [{
            ...valid.summaries[0].source_refs[0],
            type: "hrv_sdnn",
          }],
          completeness: "complete",
        }],
      }),
    Error,
    "invalid_health_summary",
  );
});
