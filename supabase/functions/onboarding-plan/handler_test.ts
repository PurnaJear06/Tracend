import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { catalogBySlug, exerciseCatalogV1 } from "../_shared/onboarding/catalog.ts";
import { generateOnboardingProposal } from "../_shared/onboarding/generate.ts";
import type { OnboardingProposalPayload } from "../_shared/onboarding/plan_contract.ts";
import type { AiCoachingConsent } from "../_shared/ai_consent.ts";
import type { OnboardingModelResolution } from "../_shared/providers/onboarding_plan_provider.ts";
import {
  type GenerationClaim,
  type GenerationMetadata,
  handleOnboardingPlan,
  type HandlerDeps,
  type OnboardingStore,
  questionsPollMs,
  questionsWaitMs,
  type StoredQuestions,
} from "./handler.ts";

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
    persisted: [] as {
      generationId: string;
      proposal: OnboardingProposalPayload;
      metadata: GenerationMetadata | null;
    }[],
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
    timezone: () => Promise.resolve("UTC"),
    loadHealth: () => Promise.resolve({ days: [], workouts: [] }),
    loadHealthHistory: () => Promise.resolve([]),
    claimQuestions: () => Promise.resolve({ started: true }),
    saveQuestions: (_hash, stored) => Promise.resolve(stored),
    releaseQuestions: () => Promise.resolve(),
    recordQuestionUsage: () => Promise.resolve(),
    consent: () => Promise.resolve("granted"),
    budgetAvailable: () => Promise.resolve(true),
    recordUsage: () => Promise.resolve(),
    persist: (generationId, _hash, _snapshot, proposal, metadata) => {
      calls.persisted.push({ generationId, proposal, metadata });
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

async function run(fake: OnboardingStore, extra: Partial<HandlerDeps> = {}) {
  const work: Promise<void>[] = [];
  const response = await handleOnboardingPlan({
    mode: "plan",
    store: fake,
    resolution: () => ({ kind: "rules", reason: "provider_mock" }),
    currentYear: 2026,
    now: () => new Date("2026-10-02T09:00:00Z"),
    background: (promise) => work.push(promise),
    observer: quiet,
    ...extra,
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
    persist: () => Promise.reject(new Error("database unavailable")),
  });
  const { response } = await run(fake);
  assertEquals(response.status, 202);
  assertEquals(calls.failed, ["gen-1"]);
});

Deno.test("movements to avoid never reach the plan", async () => {
  const { fake, calls } = store({
    loadDraft: () =>
      Promise.resolve({
        ...completeDraft,
        payload: {
          ...completeDraft.payload,
          constraints: "Squats and overhead pressing hurt; avoid both",
          avoid_patterns: ["squat", "vertical_push"],
        },
      }),
  });
  const { response } = await run(fake);
  assertEquals(response.status, 202);
  const slugs = (calls.persisted[0].proposal.training.weekly_structure as {
    exercises: { slug: string }[];
  }[]).flatMap((workout) => workout.exercises.map((exercise) => exercise.slug));
  const patterns = slugs.map((slug) => catalogBySlug.get(slug)!.pattern);
  assert(!patterns.includes("squat") && !patterns.includes("vertical_push"));
  assert(patterns.includes("lunge"), "squats give way to lunges");
});

Deno.test("a written limitation without movements to avoid is incomplete", async () => {
  const { fake, calls } = store({
    loadDraft: () =>
      Promise.resolve({
        ...completeDraft,
        payload: { ...completeDraft.payload, constraints: "Squats hurt" },
      }),
  });
  const { response, body } = await run(fake);
  assertEquals(response.status, 422);
  assertEquals(body.missing, ["avoid_patterns"]);
  assertEquals(calls.claimedHashes.length, 0);
});

Deno.test("answers no plan can meet are refused before any generation, every time", async () => {
  // Bodyweight only and every upper-body pattern avoided: upper days are empty.
  const { fake, calls } = store({
    loadDraft: () =>
      Promise.resolve({
        ...completeDraft,
        payload: {
          ...completeDraft.payload,
          training_weekdays: [1, 2, 4, 5],
          equipment_items: [],
          constraints: "Shoulder surgery last year",
          avoid_patterns: ["horizontal_push", "vertical_push", "horizontal_pull", "vertical_pull"],
        },
      }),
  });
  for (let retry = 0; retry < 2; retry++) {
    const { response, body, backgroundRuns } = await run(fake);
    assertEquals(response.status, 422);
    assertEquals(body.error, "onboarding_plan_infeasible");
    assertEquals(body.rule, "exercise_count_out_of_range");
    assertEquals(body.change, ["avoid_patterns", "equipment_items"]);
    assertEquals(backgroundRuns, 0);
  }
  assertEquals(calls.claimedHashes.length, 0);
});

Deno.test("the rules plan stores no model telemetry; a model plan stores its call", async () => {
  const rules = store();
  await run(rules.fake);
  assertEquals(rules.calls.persisted[0].metadata, null);

  const modelled = store();
  await run(modelled.fake, {
    resolution: () => ({
      kind: "model",
      config: {
        provider: "deepseek",
        model: "deepseek-flash",
        url: "https://api.deepseek.com/v1/chat/completions",
        apiKey: "test-key",
        extraBody: {},
        thinkingBody: {},
        thinking: true,
        price: { input: 0.3, output: 1.2 },
      },
    }),
    generate: (answers, catalog, _resolution, gate) =>
      generateOnboardingProposal(answers, catalog, { kind: "rules", reason: "stub" }, gate)
        .then((result) => ({
          ...result,
          fallbackReason: null,
          usage: {
            provider: "deepseek",
            model: "deepseek-flash",
            thinking: true,
            inputUnits: 4100,
            outputUnits: 9800,
            reasoningUnits: 7300,
            finishReason: "stop",
            estimatedCostUsd: 0.013,
            latencyMs: 41_250,
          },
          attempts: [{
            attempt: "initial",
            outcome: "valid",
            rule: null,
            path: null,
            latencyMs: 41_250,
            httpStatus: null,
          }],
        })),
  });
  assertEquals(modelled.calls.persisted[0].metadata, {
    thinking: true,
    latency_ms: 41_250,
    attempts: 1,
    input_units: 4100,
    output_units: 9800,
    reasoning_units: 7300,
    finish_reason: "stop",
  });
});

Deno.test("Apple Health is read for the athlete's own 28 days and changes the hash", async () => {
  const windows: [string, string][] = [];
  const steps = (count: number) =>
    Array.from({ length: count }, (_, index) => ({
      local_date: `2026-09-${String(10 + index).padStart(2, "0")}`,
      steps: 9000,
      active_energy_kcal: null,
      sleep_minutes: null,
      weight_kg: null,
    }));
  const withHealth = (days: ReturnType<typeof steps>) =>
    store({
      timezone: () => Promise.resolve("Asia/Kolkata"),
      loadHealth: (from, through) => {
        windows.push([from, through]);
        return Promise.resolve({ days, workouts: [] });
      },
    });
  const none = store();
  await run(none.fake, { now: () => new Date("2026-10-02T20:00:00Z") });
  const connected = withHealth(steps(10));
  await run(connected.fake, { now: () => new Date("2026-10-02T20:00:00Z") });
  // 20:00 UTC on 2 October is 3 October in India: the window ends on the 2nd.
  assertEquals(windows[0], ["2026-09-05", "2026-10-02"]);
  assert(none.calls.claimedHashes[0] !== connected.calls.claimedHashes[0]);
  const calculation = connected.calls.persisted[0].proposal.training.calculation as {
    health?: { steps_per_day?: number };
  };
  assertEquals(calculation.health?.steps_per_day, 9000);

  // The same data on the same day reuses the generation.
  const again = withHealth(steps(10));
  await run(again.fake, { now: () => new Date("2026-10-02T21:00:00Z") });
  assertEquals(again.calls.claimedHashes[0], connected.calls.claimedHashes[0]);
});

Deno.test("the usual months are read for completed months only and change the hash", async () => {
  const windows: [string, string][] = [];
  const month = (start: string) => ({
    month: start,
    workouts: 16,
    strength_workouts: 16,
    workout_minutes: 960,
    sleep_nights: 28,
    sleep_minutes_avg: 430,
    weight_days: 4,
    weight_kg_avg: 68,
    data_days: 29,
  });
  const withHistory = store({
    loadHealthHistory: (from, through) => {
      windows.push([from, through]);
      return Promise.resolve(["2026-07-01", "2026-08-01", "2026-09-01"].map(month));
    },
  });
  const none = store();
  await run(none.fake);
  await run(withHistory.fake);
  assertEquals(windows[0], ["2025-11-01", "2026-09-01"]);
  assert(none.calls.claimedHashes[0] !== withHistory.calls.claimedHashes[0]);
  const training = withHistory.calls.persisted[0].proposal.training;
  const calculation = training.calculation as {
    health_history?: { usual_strength_per_week?: number };
  };
  assertEquals(calculation.health_history?.usual_strength_per_week, 3.6);
  // Lifting about 3.6 times a week usually and nothing lately: a break.
  assertEquals(
    (training.calculation as { returning_from_break?: boolean }).returning_from_break,
    true,
  );
});

const questionsDraft = {
  path: "experienced",
  payload: {
    ...completeDraft.payload,
    current_plan: "Upper/lower 4 days",
    training_years: "over_5",
    priority_muscles: ["chest"],
  },
};

const deepseek: OnboardingModelResolution = {
  kind: "model",
  config: {
    provider: "deepseek",
    model: "deepseek-flash",
    url: "https://api.deepseek.com/v1/chat/completions",
    apiKey: "test-key",
    extraBody: {},
    thinkingBody: {},
    thinking: true,
    price: { input: 0.3, output: 1.2 },
  },
};

const oneQuestion = () =>
  Promise.resolve({
    questions: [{
      category: "stalled_lift" as const,
      question: "How often do you bench?",
      choices: ["Once a week", "Twice a week"],
    }],
    usage: null,
    skippedReason: null,
  });

/** Claims as the database does: the first request starts, later ones get its outcome. */
function questionStore(overrides: Partial<OnboardingStore> = {}) {
  const saved = new Map<string, StoredQuestions>();
  const running = new Set<string>();
  const released: string[] = [];
  const fake = store({
    loadDraft: () => Promise.resolve(questionsDraft),
    claimQuestions: (hash) => {
      const stored = saved.get(hash);
      if (stored) return Promise.resolve({ started: false, stored });
      if (running.has(hash)) return Promise.resolve({ started: false });
      running.add(hash);
      return Promise.resolve({ started: true });
    },
    saveQuestions: (hash, stored) => {
      running.delete(hash);
      saved.set(hash, stored);
      return Promise.resolve(stored);
    },
    releaseQuestions: (hash) => {
      running.delete(hash);
      released.push(hash);
      return Promise.resolve();
    },
    ...overrides,
  }).fake;
  return { fake, saved, running, released };
}

Deno.test("questions are asked once per set of answers and stored under its hash", async () => {
  const { fake } = questionStore();
  let asked = 0;
  const askQuestions = () => {
    asked++;
    return oneQuestion();
  };
  const first = await run(fake, { mode: "questions", resolution: () => deepseek, askQuestions });
  assertEquals(first.response.status, 200);
  assertEquals(first.body.questions.length, 1);
  assertEquals(first.backgroundRuns, 0);
  const again = await run(fake, { mode: "questions", resolution: () => deepseek, askQuestions });
  assertEquals(again.body, first.body);
  assertEquals(asked, 1);
});

Deno.test("an overlapping request waits for the first one's questions instead of asking", async () => {
  const { fake } = questionStore();
  let asked = 0;
  let finish = () => {};
  const askQuestions = () => {
    asked++;
    return new Promise<Awaited<ReturnType<typeof oneQuestion>>>((done) => {
      finish = () => oneQuestion().then(done);
    });
  };
  // Whichever request claims first asks; the other polls until it is done.
  let polls = 0;
  const sleep = () => {
    if (++polls >= 3) finish();
    return new Promise<void>((done) => setTimeout(done, 0));
  };
  const deps = { mode: "questions" as const, resolution: () => deepseek, askQuestions, sleep };
  const [a, b] = await Promise.all([run(fake, deps), run(fake, deps)]);
  assertEquals(asked, 1);
  assertEquals(b.body, a.body);
  assertEquals(b.body.questions.length, 1);
});

Deno.test("a claim held past the wait answers without questions and stores nothing", async () => {
  const { fake, saved } = questionStore({
    claimQuestions: () => Promise.resolve({ started: false }),
  });
  let polls = 0;
  const { body } = await run(fake, {
    mode: "questions",
    resolution: () => deepseek,
    askQuestions: () => {
      throw new Error("no call expected");
    },
    sleep: () => {
      polls++;
      return Promise.resolve();
    },
  });
  assertEquals(body.questions, []);
  assertEquals(body.skipped_reason, "questions_in_progress");
  assertEquals(polls, questionsWaitMs / questionsPollMs);
  assertEquals(saved.size, 0);
});

Deno.test("no consent, no budget or no model ask nothing and are never stored", async () => {
  const { fake, saved } = questionStore();
  let consent: AiCoachingConsent = "not_granted";
  let budget = true;
  const ask = (resolution: OnboardingModelResolution = deepseek) =>
    run(
      {
        ...fake,
        consent: () => Promise.resolve(consent),
        budgetAvailable: () => Promise.resolve(budget),
      },
      { mode: "questions", resolution: () => resolution, askQuestions: oneQuestion },
    );
  assertEquals((await ask()).body.skipped_reason, "ai_consent_not_granted");
  consent = "granted";
  budget = false;
  assertEquals((await ask()).body.skipped_reason, "ai_usage_limit");
  budget = true;
  assertEquals(
    (await ask({ kind: "rules", reason: "model_not_evaluated" })).body.skipped_reason,
    "model_not_evaluated",
  );
  assertEquals(saved.size, 0);
  // Consent granted, budget back, model ready: the same answers get questions.
  assertEquals((await ask()).body.questions.length, 1);
  assertEquals(saved.size, 1);
});

Deno.test("a failed question call releases its claim, so it may be asked again", async () => {
  const { fake, saved, running, released } = questionStore();
  const { body } = await run(fake, {
    mode: "questions",
    resolution: () => deepseek,
    askQuestions: () =>
      Promise.resolve({ questions: [], usage: null, skippedReason: "provider_timeout" }),
  });
  assertEquals(body.questions, []);
  assertEquals(body.skipped_reason, "provider_timeout");
  assertEquals(saved.size, 0);
  assertEquals(released.length, 1);
  assertEquals(running.size, 0);
  const retry = await run(fake, {
    mode: "questions",
    resolution: () => deepseek,
    askQuestions: oneQuestion,
  });
  assertEquals(retry.body.questions.length, 1);
});

Deno.test("follow-up answers reach the plan only for the answers they were asked for", async () => {
  const hashes: string[] = [];
  const ask = store({
    loadDraft: () => Promise.resolve(questionsDraft),
    saveQuestions: (hash, value) => {
      hashes.push(hash);
      return Promise.resolve(value);
    },
  });
  await run(ask.fake, {
    mode: "questions",
    resolution: () => deepseek,
    askQuestions: () => Promise.resolve({ questions: [], usage: null, skippedReason: null }),
  });
  const followUps = [{
    category: "stalled_lift",
    question: "How often do you bench?",
    answer: "Once a week",
  }];
  const snapshots: Record<string, unknown>[] = [];
  const planWith = (payload: Record<string, unknown>) =>
    store({
      loadDraft: () => Promise.resolve({ ...questionsDraft, payload }),
      persist: (_id, _hash, snapshot) => {
        snapshots.push(snapshot);
        return Promise.resolve("stored");
      },
    }).fake;
  await run(
    planWith({ ...questionsDraft.payload, follow_ups: followUps, follow_ups_hash: hashes[0] }),
  );
  // An earlier answer changed after the questions: the follow-ups are stale.
  await run(planWith({
    ...questionsDraft.payload,
    session_minutes: 60,
    follow_ups: followUps,
    follow_ups_hash: hashes[0],
  }));
  const answers = (index: number) => snapshots[index].answers as { follow_ups: unknown[] };
  assertEquals(answers(0).follow_ups.length, 1);
  assertEquals(answers(1).follow_ups, []);
});
