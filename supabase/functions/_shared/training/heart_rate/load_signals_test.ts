import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1.0.14";
import {
  computeLoadSignals,
  type LoadSignals,
  type LoadSignalSession,
  type LoadSignalSet,
  loadSignalWindowDays,
  settleElevatedFraction,
  settleMinimumSessions,
  settleMinimumSets,
  shortRestSeconds,
  trackedMinimumCoverage,
  type WorkoutLoadInputs,
} from "./load_signals.ts";
import { loadWorkoutLoadSignals, parseWorkoutLoadInputs } from "./load_signals_inputs.ts";
import { buildHeartRateProfile, type HeartRateInputs } from "./profile.ts";

const asOf = "2026-10-23";

// Born 1990: 36 years old, so the maximum is 208 - 0.7 x 36 = 183 (rounded). Resting 60 gives a
// reserve of 123, so a start of 125 bpm is 53% of reserve and 100 bpm is 33%.
const profileInputs: HeartRateInputs = {
  schema_version: "1.0",
  as_of: asOf,
  birth_year: 1990,
  resting: [22, 21, 20, 19, 18].map((day) => ({ local_date: `2026-10-${day}`, bpm: 60 })),
  sets: [],
  peak_candidates: [],
};
const profile = buildHeartRateProfile(profileInputs);

function set(index: number, start: number | null, rest: number | null, extra = {}): LoadSignalSet {
  return {
    exercise_order: 1 + Math.floor(index / 4),
    set_number: 1 + (index % 4),
    rest_before_seconds: rest,
    start_bpm: start,
    peak_bpm: 150,
    end_bpm: 140,
    drop_30s_bpm: 12,
    drop_60s_bpm: 24,
    coverage: 0.9,
    sample_count: 20,
    source: "watch_workout",
    ...extra,
  };
}

function session(
  localDate: string,
  starts: readonly number[],
  rest: number | null = 90,
  extra = {},
): LoadSignalSession {
  return {
    local_date: localDate,
    completed_sets: starts.length,
    sets: starts.map((start, index) => set(index, start, rest, extra)),
  };
}

function inputs(...sessions: LoadSignalSession[]): WorkoutLoadInputs {
  return { schema_version: "1.0", as_of: asOf, sessions };
}

// Two workouts of eight tracked sets each; `start` is the heart rate when every set began.
function workouts(start: number, rest: number | null): LoadSignalSession[] {
  const starts = Array(8).fill(start);
  return [session("2026-10-22", starts, rest), session("2026-10-20", starts, rest)];
}

const quiet: LoadSignals["engine"] = {
  confidence: "none",
  rest: "none",
  reasons: [],
};

const engineOf = (...sessions: LoadSignalSession[]) =>
  computeLoadSignals(inputs(...sessions), profile).engine;

Deno.test("a heart rate that had not settled after a short rest allows a longer rest", () => {
  assertEquals(engineOf(...workouts(125, 90)), {
    confidence: "none",
    rest: "allow_longer",
    reasons: ["rest_short"],
  });
});

Deno.test("a heart rate that had not settled after a long rest lowers confidence", () => {
  assertEquals(engineOf(...workouts(125, 150)), {
    confidence: "lower",
    rest: "none",
    reasons: ["slow_settling"],
  });
});

Deno.test("the rest length that separates the two causes is the stated one", () => {
  assertEquals(shortRestSeconds, 120);
  assertEquals(engineOf(...workouts(125, shortRestSeconds - 1)).reasons, ["rest_short"]);
  assertEquals(engineOf(...workouts(125, shortRestSeconds)).reasons, ["slow_settling"]);
});

Deno.test("a heart rate that had settled changes nothing", () => {
  assertEquals(engineOf(...workouts(100, 90)), quiet);
});

Deno.test("the elevated line is the stated share of reserve", () => {
  // 60 + 0.5 x 123 = 121.5: 121 is just under it, 122 just over.
  assertEquals(settleElevatedFraction, 0.5);
  assertEquals(engineOf(...workouts(121, 90)), quiet);
  assertEquals(engineOf(...workouts(122, 90)).reasons, ["rest_short"]);
});

Deno.test("too few sets or workouts fires nothing", () => {
  assertEquals(settleMinimumSets, 12);
  assertEquals(
    engineOf(session("2026-10-22", Array(6).fill(130)), session("2026-10-20", Array(5).fill(130))),
    quiet,
  );
  assertEquals(
    engineOf(session("2026-10-22", Array(6).fill(130)), session("2026-10-20", Array(6).fill(130)))
      .reasons,
    ["rest_short"],
  );
  assertEquals(settleMinimumSessions, 2);
  assertEquals(engineOf(session("2026-10-22", Array(16).fill(130))), quiet);
});

Deno.test("only tracked sets with a start and a real rest are judged", () => {
  const steady = Array(6).fill(100);
  const excluded = (extra: Record<string, unknown>, rest: number | null = 90) =>
    session("2026-10-21", Array(10).fill(140), rest, extra);
  assertEquals(
    engineOf(
      session("2026-10-22", steady),
      session("2026-10-20", steady),
      excluded({ source: "background" }),
      excluded({ coverage: 0.59 }),
      excluded({ start_bpm: null }),
      excluded({}, null),
      excluded({}, 29),
    ),
    quiet,
  );
});

Deno.test("a set at the minimum rest and the minimum coverage is judged", () => {
  assertEquals(trackedMinimumCoverage, 0.6);
  const edge = Array(6).fill(130);
  assertEquals(
    engineOf(
      session("2026-10-22", edge, 30, { coverage: 0.6 }),
      session("2026-10-20", edge, 30, { coverage: 0.6 }),
    ).reasons,
    ["rest_short"],
  );
});

Deno.test("the window is the last 28 days and nothing from the future", () => {
  assertEquals(loadSignalWindowDays, 28);
  const high = Array(8).fill(130);
  // Two workouts inside the window fire; one of them 28 days old or in the future leaves one.
  assertEquals(engineOf(session("2026-09-26", high), session("2026-10-22", high)).reasons, [
    "rest_short",
  ]);
  assertEquals(engineOf(session("2026-09-25", high), session("2026-10-22", high)), quiet);
  assertEquals(engineOf(session("2026-10-24", high), session("2026-10-22", high)), quiet);
});

Deno.test("a workout with no finished sets counts for nothing", () => {
  const high = Array(8).fill(130);
  assertEquals(
    engineOf(session("2026-10-22", high), { ...session("2026-10-20", high), completed_sets: 0 }),
    quiet,
  );
});

Deno.test("without a resting rate or a maximum there is no start judgment", () => {
  const noResting = buildHeartRateProfile({ ...profileInputs, resting: [] });
  assertEquals(computeLoadSignals(inputs(...workouts(150, 150)), noResting).engine, quiet);
  const noMaximum = buildHeartRateProfile({ ...profileInputs, birth_year: null });
  assertEquals(computeLoadSignals(inputs(...workouts(150, 150)), noMaximum).engine, quiet);
});

function recoveryProfile(recentDrop: number, priorDrop: number) {
  const row = (date: string, drop: number) => ({
    local_date: date,
    start_bpm: 110,
    peak_bpm: 150,
    end_bpm: 140,
    drop_30s_bpm: 10,
    drop_60s_bpm: drop,
    coverage: 0.9,
    sample_count: 20,
    source: "watch_workout" as const,
  });
  return buildHeartRateProfile({
    ...profileInputs,
    sets: [
      ...Array(6).fill(0).map(() => row("2026-10-15", recentDrop)),
      ...Array(6).fill(0).map(() => row("2026-09-10", priorDrop)),
    ],
  });
}

Deno.test("a slower recovery lowers confidence, even when the start settled", () => {
  const slower = recoveryProfile(10, 20);
  assertEquals(slower.recovery.state, "slower");
  assertEquals(computeLoadSignals(inputs(...workouts(100, 90)), slower).engine, {
    confidence: "lower",
    rest: "none",
    reasons: ["recovery_slower"],
  });
});

Deno.test("a steady or improving recovery changes nothing and nothing ever raises confidence", () => {
  for (const [recent, prior] of [[20, 20], [30, 20]]) {
    assertEquals(
      computeLoadSignals(inputs(...workouts(100, 90)), recoveryProfile(recent, prior)).engine,
      quiet,
    );
  }
});

Deno.test("both causes together keep both reasons", () => {
  assertEquals(
    computeLoadSignals(inputs(...workouts(125, 90)), recoveryProfile(10, 20)).engine,
    { confidence: "lower", rest: "allow_longer", reasons: ["rest_short", "recovery_slower"] },
  );
});

function allKeys(value: unknown, into = new Set<string>()): Set<string> {
  if (Array.isArray(value)) value.forEach((item) => allKeys(item, into));
  else if (typeof value === "object" && value !== null) {
    for (const [key, item] of Object.entries(value)) {
      into.add(key);
      allKeys(item, into);
    }
  }
  return into;
}

Deno.test("D9: the signals carry no load, repetitions, sets to do or sleeping heart rate", () => {
  const results: LoadSignals[] = [];
  for (const start of [90, 110, 125, 150]) {
    for (const rest of [null, 20, 60, 120, 240]) {
      for (const drops of [[10, 20], [20, 20], [30, 20]]) {
        results.push(
          computeLoadSignals(inputs(...workouts(start, rest)), recoveryProfile(drops[0], drops[1])),
        );
      }
    }
  }
  const forbidden = [
    "load",
    "load_kg",
    "repetitions",
    "reps",
    "rir",
    "rpe",
    "sets_to_do",
    "target",
    "prescription",
    "weight",
    "sleeping",
  ];
  for (const result of results) {
    const keys = allKeys(result);
    for (const name of forbidden) assertFalse(keys.has(name), `no ${name} in the output`);
    assertEquals(Object.keys(result).sort(), ["engine"]);
    assertEquals(Object.keys(result.engine).sort(), ["confidence", "reasons", "rest"]);
    assert(result.engine.confidence === "none" || result.engine.confidence === "lower");
    assert(result.engine.rest === "none" || result.engine.rest === "allow_longer");
  }
  // A grid this wide reaches every outcome.
  assert(results.some((r) => r.engine.confidence === "lower"));
  assert(results.some((r) => r.engine.rest === "allow_longer"));
  assert(results.some((r) => r.engine.confidence === "none" && r.engine.rest === "none"));
});

Deno.test("the inputs hold no load, repetitions or reps in reserve to depend on", () => {
  const payload = parseWorkoutLoadInputs({
    schema_version: "1.0",
    as_of: asOf,
    sessions: [{
      local_date: "2026-10-22",
      completed_sets: 3,
      sets: [{ ...set(0, 100, 90), load_kg: 80, repetitions: 5, rir: 2 }],
    }],
  })!;
  const keys = allKeys(payload);
  for (const name of ["load_kg", "repetitions", "rir"]) assertFalse(keys.has(name));
});

Deno.test("a payload is read and malformed rows are dropped, never repaired", () => {
  const parsed = parseWorkoutLoadInputs({
    schema_version: "1.0",
    as_of: asOf,
    sessions: [
      {
        local_date: "2026-10-22",
        completed_sets: 4,
        sets: [
          set(0, 100, 90),
          { ...set(1, 100, 90), source: "phone" },
          {
            ...set(2, 100, 90),
            coverage: "1",
          },
          { ...set(3, null, null) },
          7,
        ],
      },
      { local_date: "yesterday", completed_sets: 1, sets: [] },
      { local_date: "2026-10-21", completed_sets: 1, sets: "none" },
      5,
    ],
  })!;
  assertEquals(parsed.sessions.length, 1);
  assertEquals(parsed.sessions[0].sets.length, 2);
  assertEquals(parsed.sessions[0].sets[1].start_bpm, null);
  assertEquals(parsed.sessions[0].sets[1].rest_before_seconds, null);
});

Deno.test("anything that is not an inputs object reads as null", () => {
  assertEquals(parseWorkoutLoadInputs(null), null);
  assertEquals(parseWorkoutLoadInputs([]), null);
  assertEquals(parseWorkoutLoadInputs({ as_of: "yesterday", sessions: [] }), null);
  assertEquals(parseWorkoutLoadInputs({ as_of: asOf }), null);
});

function fakeClient(
  workoutPayload: unknown,
  options: { profileError?: boolean; workoutError?: boolean } = {},
) {
  const calls: Array<[string, Record<string, unknown>]> = [];
  return {
    calls,
    client: {
      rpc: (name: string, args: Record<string, unknown>) => {
        calls.push([name, args]);
        if (name === "get_heart_rate_inputs_v1") {
          return Promise.resolve(
            options.profileError
              ? { data: null, error: { message: "denied" } }
              : { data: profileInputs, error: null },
          );
        }
        return Promise.resolve(
          options.workoutError
            ? { data: null, error: { message: "denied" } }
            : { data: workoutPayload, error: null },
        );
      },
    },
  };
}

Deno.test("the loader reads both service-role functions and works the signals out", async () => {
  const payload = { schema_version: "1.0", as_of: asOf, sessions: workouts(125, 150) };
  const { client, calls } = fakeClient(payload);
  const signals = await loadWorkoutLoadSignals(client, "user-1", asOf);
  assertEquals(
    calls.map(([name, args]) => [name, args]).sort((a, b) =>
      String(a[0]).localeCompare(String(b[0]))
    ),
    [
      ["get_heart_rate_inputs_v1", { target_user: "user-1", local_date: asOf }],
      ["get_workout_load_inputs_v1", { target_user: "user-1", local_date: asOf }],
    ],
  );
  assertEquals(signals, computeLoadSignals(payload as WorkoutLoadInputs, profile));
  assertEquals(signals?.engine.confidence, "lower");
});

Deno.test("a failed or malformed read gives no signals, so the plan stands as it is", async () => {
  const payload = { schema_version: "1.0", as_of: asOf, sessions: workouts(125, 150) };
  assertEquals(
    await loadWorkoutLoadSignals(fakeClient(payload, { profileError: true }).client, "u", asOf),
    null,
  );
  assertEquals(
    await loadWorkoutLoadSignals(fakeClient(payload, { workoutError: true }).client, "u", asOf),
    null,
  );
  assertEquals(await loadWorkoutLoadSignals(fakeClient("nothing").client, "u", asOf), null);
});

Deno.test("a shared read of the profile's inputs replaces the loader's own", async () => {
  const payload = { schema_version: "1.0", as_of: asOf, sessions: workouts(125, 150) };
  const { client, calls } = fakeClient(payload);
  let shared = 0;
  const signals = await loadWorkoutLoadSignals(client, "user-1", asOf, () => {
    shared += 1;
    return Promise.resolve(profileInputs);
  });
  assertEquals(shared, 1);
  assertEquals(calls.map(([name]) => name), ["get_workout_load_inputs_v1"]);
  assertEquals(signals?.engine.reasons, ["slow_settling"]);
  assertEquals(
    await loadWorkoutLoadSignals(client, "user-1", asOf, () => Promise.resolve(null)),
    null,
  );
});
