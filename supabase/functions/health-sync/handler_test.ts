// health-sync's answers: a refused batch stays 422 with its SQLSTATE, the hourly limit is 429, and
// a server fault is 503. The last two are logged and reported by code only.

import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { captureLogs } from "../_shared/ai/fakes.ts";
import { createLogger } from "../_shared/logger.ts";
import { handleHealthSync, type HealthSyncWrite } from "./handler.ts";

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

async function run(body: unknown, write: () => Promise<HealthSyncWrite>) {
  const reports: [string, string][] = [];
  const { result, lines } = await captureLogs(() =>
    handleHealthSync(body, {
      log: createLogger("correlation-test"),
      persist: write,
      report: (failureCode, errorCode) => reports.push([failureCode, errorCode]),
    })
  );
  return { status: result.status, body: await result.json(), lines, reports };
}

const failing = (code: string | undefined, message = "row 6400 steps for athlete") => () =>
  Promise.resolve({ data: null, error: { code, message } });

Deno.test("a stored sync answers with its result", async () => {
  const { status, body, reports } = await run(
    valid,
    () => Promise.resolve({ data: { accepted_count: 1 }, error: null }),
  );
  assertEquals(status, 200);
  assertEquals(body, { schema_version: "1.0", accepted_count: 1 });
  assertEquals(reports, []);
});

Deno.test("a payload outside the contract is 422 and never reaches the database", async () => {
  let written = false;
  const { status, body, reports } = await run({ ...valid, summaries: "x" }, () => {
    written = true;
    return Promise.resolve({ data: {}, error: null });
  });
  assertEquals(status, 422);
  assertEquals(body, { error: "invalid_health_sync" });
  assertEquals(written, false);
  assertEquals(reports, []);
});

for (const code of ["22023", "22P02", "23514", "P0002"]) {
  Deno.test(`a batch the database refuses (${code}) stays 422 with its code`, async () => {
    const { status, body, lines, reports } = await run(valid, failing(code));
    assertEquals(status, 422);
    assertEquals(body, { error: "health_sync_rejected", code });
    assertEquals(reports, []);
    assertEquals(lines.length, 1);
    assert(lines[0].includes(`"error_code":"${code}"`));
  });
}

Deno.test("the hourly limit is 429, logged and reported", async () => {
  const { status, body, lines, reports } = await run(valid, failing("54000"));
  assertEquals(status, 429);
  assertEquals(body, { error: "health_sync_limit", code: "54000" });
  assertEquals(reports, [["health_sync_limit", "54000"]]);
  assertEquals(lines.length, 1);
});

for (
  const [name, write] of [
    ["a timeout", failing("57014")],
    ["a missing grant", failing("42501")],
    ["a lost connection", failing("", "TypeError: fetch failed")],
    ["a code that is not a SQLSTATE", failing("not a code at all")],
    ["no result", () => Promise.resolve({ data: null, error: null })],
    ["a thrown call", () => Promise.reject(new Error("socket closed"))],
  ] as const
) {
  Deno.test(`${name} is 503, logged and reported by code`, async () => {
    const { status, body, lines, reports } = await run(valid, write);
    assertEquals(status, 503);
    assertEquals(body.error, "health_sync_unavailable");
    assertEquals(reports.length, 1);
    assertEquals(reports[0][0], "health_sync_unavailable");
    assertEquals(reports[0][1], body.code);
    assertEquals(lines.length, 1);
    const line = JSON.parse(lines[0]);
    assertEquals(line.level, "error");
    assertEquals(line.msg, "health_sync_unavailable");
    assertEquals(line.correlation_id, "correlation-test");
  });
}

Deno.test("no log line or report holds the payload or the database's message", async () => {
  for (const code of ["22023", "54000", "57014"]) {
    const { lines, reports } = await run(valid, failing(code));
    const said = JSON.stringify([lines, reports]);
    for (const secret of ["6400", "athlete", "Asia/Kolkata", "a".repeat(64)]) {
      assert(!said.includes(secret), `${code} leaked ${secret}`);
    }
  }
});
