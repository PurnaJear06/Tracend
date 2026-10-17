import { assertEquals } from "jsr:@std/assert@1.0.14";
import { heartRateInputsRpc, loadHeartRateInputs, parseHeartRateInputs } from "./inputs.ts";

const set = {
  local_date: "2026-10-10",
  start_bpm: 110,
  peak_bpm: 150,
  end_bpm: 140,
  drop_30s_bpm: 12,
  drop_60s_bpm: 24,
  coverage: 0.9,
  sample_count: 20,
  source: "watch_workout",
};

Deno.test("a payload is read and malformed rows are dropped, never repaired", () => {
  const parsed = parseHeartRateInputs({
    schema_version: "1.0",
    as_of: "2026-10-17",
    birth_year: 1990,
    resting: [{ local_date: "2026-10-16", bpm: 58 }, { local_date: "bad", bpm: 58 }, 5],
    sets: [set, { ...set, source: "phone" }, { ...set, coverage: "1" }, {
      ...set,
      drop_60s_bpm: null,
    }],
    peak_candidates: "none",
  })!;
  assertEquals(parsed.resting, [{ local_date: "2026-10-16", bpm: 58 }]);
  assertEquals(parsed.sets.length, 2);
  assertEquals(parsed.sets[1].drop_60s_bpm, null);
  assertEquals(parsed.peak_candidates, []);
  assertEquals(parsed.birth_year, 1990);
});

Deno.test("anything that is not an inputs object reads as null", () => {
  assertEquals(parseHeartRateInputs(null), null);
  assertEquals(parseHeartRateInputs([]), null);
  assertEquals(parseHeartRateInputs({ as_of: "yesterday" }), null);
});

Deno.test("the loader asks the service-role function for one athlete and date", async () => {
  const calls: Array<[string, Record<string, unknown>]> = [];
  const payload = { schema_version: "1.0", as_of: "2026-10-17", birth_year: null };
  const loaded = await loadHeartRateInputs(
    {
      rpc: (name, args) => {
        calls.push([name, args]);
        return Promise.resolve({ data: payload, error: null });
      },
    },
    "user-1",
    "2026-10-17",
  );
  assertEquals(calls, [[heartRateInputsRpc, { target_user: "user-1", local_date: "2026-10-17" }]]);
  assertEquals(loaded?.as_of, "2026-10-17");
  const failed = await loadHeartRateInputs(
    {
      rpc: () => Promise.resolve({ data: null, error: { message: "denied" } }),
    },
    "user-1",
    "2026-10-17",
  );
  assertEquals(failed, null);
});
