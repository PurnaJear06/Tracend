import { assertEquals } from "jsr:@std/assert@1";
import { MealVisionBilledError } from "../_shared/providers/gemini_meal_vision_provider.ts";
import { handleMealAnalyze, type MealAnalyzeStore, type MealVisionResult } from "./handler.ts";

const user = "11111111-1111-4111-8111-111111111111";
const mealId = "22222222-2222-4222-8222-222222222222";
const body = { schema_version: "1.0", meal_id: mealId };
const usage = {
  model: "qwen/qwen3.8-27b",
  inputUnits: 900,
  outputUnits: 200,
  estimatedCostUsd: 0.0015,
};
const dal = {
  name: "Dal",
  serving_label: "1 bowl",
  calories: 180,
  protein_g: 9,
  carbohydrate_g: 24,
  fat_g: 5,
  confidence: "low" as const,
  assumptions: ["Oil is uncertain"],
  question: "Was ghee added?",
};

function harness(overrides: Partial<MealAnalyzeStore> = {}) {
  const events: string[] = [];
  const store: MealAnalyzeStore = {
    consent: () => Promise.resolve({ granted: true, provider: "groq" }),
    reserveBudget: () => {
      events.push("reserve");
      return Promise.resolve(true);
    },
    keepBudget: () => {
      events.push("keep");
    },
    loadDraft: () =>
      Promise.resolve({ objectKey: `${user}/meal/${mealId}.jpg`, contentType: "image/jpeg" }),
    download: () => Promise.resolve(new Uint8Array([1])),
    recordUsage: (recorded) => {
      events.push(`usage:${recorded.outputUnits}`);
      return Promise.resolve();
    },
    persistCandidates: (_meal, candidates) => {
      events.push(`persist:${candidates.length}`);
      return Promise.resolve(true);
    },
    discardDraft: () => {
      events.push("discard");
      return Promise.resolve(true);
    },
    ...overrides,
  };
  const log = { info: () => {}, warn: () => {}, error: () => {} };
  const run = (analyze: () => Promise<MealVisionResult>) =>
    handleMealAnalyze(body, {
      userId: user,
      provider: "groq",
      analyze,
      store,
      log,
      report: () => events.push("report"),
      now: () => 0,
    });
  return { events, run };
}

Deno.test("a stored answer records usage before persisting", async () => {
  const { events, run } = harness();
  const response = await run(() => Promise.resolve({ ...usage, candidates: [dal] }));
  assertEquals(response.status, 200);
  assertEquals(events, ["reserve", "usage:200", "persist:1"]);
});

Deno.test("a rejected store still counts the call", async () => {
  const { events, run } = harness({ persistCandidates: () => Promise.resolve(false) });
  const response = await run(() => Promise.resolve({ ...usage, candidates: [dal] }));
  assertEquals(response.status, 422);
  assertEquals(events, ["reserve", "usage:200"]);
});

Deno.test("an unusable answer records its usage", async () => {
  const { events, run } = harness();
  const response = await run(() =>
    Promise.reject(new MealVisionBilledError("meal_vision_response_invalid", usage))
  );
  assertEquals(response.status, 503);
  assertEquals(events, ["reserve", "usage:200", "report"]);
});

Deno.test("a provider refusal is not billed and keeps nothing open", async () => {
  const { events, run } = harness();
  const response = await run(() =>
    Promise.reject(new Error("meal_vision_request_failed:429:rate_limit_exceeded"))
  );
  assertEquals(response.status, 429);
  assertEquals(events, ["reserve"]);
});

Deno.test("a call that may have been billed keeps its reservation", async () => {
  const { events, run } = harness();
  const response = await run(() => Promise.reject(new Error("The signal has been aborted")));
  assertEquals(response.status, 503);
  assertEquals(events, ["reserve", "keep", "report"]);
});

Deno.test("no budget means no download and no call", async () => {
  const { events, run } = harness({
    reserveBudget: () => Promise.resolve(false),
    download: () => {
      events.push("download");
      return Promise.resolve(new Uint8Array([1]));
    },
  });
  const response = await run(() => {
    events.push("call");
    return Promise.resolve({ ...usage, candidates: [] });
  });
  assertEquals(response.status, 429);
  assertEquals(events, []);
});

Deno.test("an unsafe key is never downloaded", async () => {
  const { events, run } = harness({
    loadDraft: () =>
      Promise.resolve({ objectKey: `${user}/meal/../../other/x.jpg`, contentType: "image/jpeg" }),
    download: () => {
      events.push("download");
      return Promise.resolve(new Uint8Array([1]));
    },
  });
  const response = await run(() => Promise.resolve({ ...usage, candidates: [] }));
  assertEquals(response.status, 404);
  assertEquals(events, ["reserve"]);
});

Deno.test("no food found discards the draft and still counts", async () => {
  const { events, run } = harness();
  const response = await run(() => Promise.resolve({ ...usage, candidates: [] }));
  assertEquals(response.status, 422);
  assertEquals(events, ["reserve", "usage:200", "discard"]);
});

Deno.test("no grant means no budget, no download and no call", async () => {
  const { events, run } = harness({
    consent: () => Promise.resolve({ granted: false, provider: "groq" }),
  });
  const response = await run(() => {
    events.push("call");
    return Promise.resolve({ ...usage, candidates: [] });
  });
  assertEquals(response.status, 403);
  assertEquals(await response.json(), { error: "meal_photo_ai_consent_required" });
  assertEquals(events, []);
});

Deno.test("a notice for another provider sends nothing", async () => {
  const { events, run } = harness({
    consent: () => Promise.resolve({ granted: true, provider: "gemini" }),
  });
  const response = await run(() => {
    events.push("call");
    return Promise.resolve({ ...usage, candidates: [] });
  });
  assertEquals(response.status, 503);
  assertEquals(events, []);
});

Deno.test("an unknown consent state sends nothing", async () => {
  const { events, run } = harness({ consent: () => Promise.resolve(null) });
  const response = await run(() => {
    events.push("call");
    return Promise.resolve({ ...usage, candidates: [] });
  });
  assertEquals(response.status, 503);
  assertEquals(events, []);
});
