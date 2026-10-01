import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { exerciseCatalogV1 } from "../_shared/onboarding/catalog.ts";
import type { OnboardingProposalPayload } from "../_shared/onboarding/plan_contract.ts";
import { type GenerationClaim, handleOnboardingPlan, type OnboardingStore } from "./handler.ts";

const completeDraft = {
  path: "beginner",
  payload: {
    goal: "fat_loss",
    sex: "female",
    birth_year: 1992,
    height_cm: 164,
    weight_kg: 68,
    target_weight_kg: 62,
    daily_activity: "some_standing",
    training_weekdays: [1, 3, 5],
    session_minutes: 45,
    equipment_items: ["dumbbells", "bench"],
    nutrition_context: "No dairy",
    constraints: "",
  },
};

function store(overrides: Partial<OnboardingStore> & { claimAs?: GenerationClaim } = {}) {
  const calls = {
    claimedHashes: [] as string[],
    persisted: [] as { generationId: string; proposal: OnboardingProposalPayload }[],
    failed: [] as string[],
  };
  const fake: OnboardingStore = {
    loadDraft: () => Promise.resolve(completeDraft),
    claim: (hash) => {
      calls.claimedHashes.push(hash);
      return Promise.resolve(
        overrides.claimAs ?? { generation_id: "gen-1", status: "running", started: true },
      );
    },
    loadCatalog: () => Promise.resolve([...exerciseCatalogV1]),
    consent: () => Promise.resolve("granted"),
    budgetAvailable: () => Promise.resolve(true),
    recordUsage: () => Promise.resolve(),
    persist: (generationId, _hash, _snapshot, proposal) => {
      calls.persisted.push({ generationId, proposal });
      return Promise.resolve("stored");
    },
    fail: (generationId) => {
      calls.failed.push(generationId);
      return Promise.resolve();
    },
    ...overrides,
  };
  return { fake, calls };
}

const quiet = { info: () => {}, warn: () => {}, error: () => {} };

async function run(fake: OnboardingStore) {
  const work: Promise<void>[] = [];
  const response = await handleOnboardingPlan({
    store: fake,
    resolution: () => ({ kind: "rules", reason: "provider_mock" }),
    currentYear: 2026,
    background: (promise) => work.push(promise),
    observer: quiet,
  });
  await Promise.all(work);
  return { response, body: await response.json(), backgroundRuns: work.length };
}

Deno.test("an old draft is told what is missing", async () => {
  const { fake } = store({
    loadDraft: () =>
      Promise.resolve({ path: "beginner", payload: { goal: "fat_loss", training_days: 3 } }),
  });
  const { response, body, backgroundRuns } = await run(fake);
  assertEquals(response.status, 422);
  assertEquals(body.error, "onboarding_answers_incomplete");
  assert((body.missing as string[]).includes("training_weekdays"));
  assertEquals(backgroundRuns, 0);
});

Deno.test("a new generation answers 202 and stores its proposal in the background", async () => {
  const { fake, calls } = store();
  const { response, body, backgroundRuns } = await run(fake);
  assertEquals(response.status, 202);
  assertEquals(body, { schema_version: "1.0", generation_id: "gen-1", status: "running" });
  assertEquals(backgroundRuns, 1);
  assertEquals(calls.persisted.length, 1);
  const training = calls.persisted[0].proposal.training;
  assertEquals(training.origin, "rules");
  assertEquals(
    (training.weekly_structure as { preferred_weekday: number }[]).map((w) => w.preferred_weekday),
    [1, 3, 5],
  );
});

Deno.test("the same answers hash the same, and a running or finished generation is returned", async () => {
  const first = store();
  await run(first.fake);
  const again = store();
  await run(again.fake);
  assertEquals(first.calls.claimedHashes, again.calls.claimedHashes);

  const finished = store({
    claimAs: { generation_id: "gen-1", status: "succeeded", started: false, proposal_id: "p-1" },
  });
  const { response, body, backgroundRuns } = await run(finished.fake);
  assertEquals(response.status, 200);
  assertEquals(body.proposal_id, "p-1");
  assertEquals(backgroundRuns, 0);
});

Deno.test("a failure in the background marks the generation failed", async () => {
  const { fake, calls } = store({
    loadCatalog: () => Promise.reject(new Error("database unavailable")),
  });
  const { response } = await run(fake);
  assertEquals(response.status, 202);
  assertEquals(calls.failed, ["gen-1"]);
  assertEquals(calls.persisted.length, 0);
});
