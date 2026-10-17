// Replays the settings path (no AI gateway route) through the onboarding-plan handler with a fake
// provider and returns every request it sent. legacy_requests_golden.json holds the requests
// recorded by running this file's recordLegacyRequests against the `origin/main` tree (the code
// before the gateway change); the test replays it on the working tree and compares the bytes.
// Synthetic drafts and a synthetic key only.

import type { AiRoute } from "../_shared/ai/types.ts";
import { resolveOnboardingModel } from "../_shared/providers/onboarding_plan_provider.ts";
import type { CatalogExercise } from "../_shared/onboarding/catalog.ts";
import { handleOnboardingPlan, type OnboardingStore } from "./handler.ts";

export type RecordedRequest = Readonly<{
  url: string;
  method: string;
  headers: Record<string, string>;
  /** The request body exactly as sent. */
  body: string;
}>;

export type RecordedCase = Readonly<{
  name: string;
  requests: readonly RecordedRequest[];
}>;

export const syntheticDrafts = {
  plan: {
    path: "experienced",
    payload: {
      goal: "muscle_gain",
      sex: "female",
      birth_year: 1992,
      height_cm: 164,
      weight_kg: 68,
      target_weight_kg: 72,
      daily_activity: "some_standing",
      training_weekdays: [1, 3, 5],
      session_minutes: 60,
      equipment_items: ["dumbbells", "bench", "barbell", "pull_up_bar"],
      nutrition_context: "No dairy",
      constraints: "",
      current_plan: "Full body 3x, dumbbells",
      training_years: "1_3",
      priority_muscles: ["glutes"],
    },
  },
  questions: {
    path: "experienced",
    payload: {
      goal: "strength",
      sex: "male",
      birth_year: 1990,
      height_cm: 178,
      weight_kg: 82,
      target_weight_kg: null,
      daily_activity: "mostly_sitting",
      training_weekdays: [1, 2, 4, 5],
      session_minutes: 75,
      equipment_items: ["dumbbells", "bench", "barbell", "machines", "cables"],
      nutrition_context: "",
      constraints: "",
      current_plan: "Upper/lower 4 days",
      training_years: "over_5",
      priority_muscles: ["chest"],
    },
  },
} as const;

const keyEnv = "synthetic-test-key";

const settingsPaths: Readonly<Record<string, Record<string, string>>> = {
  "deepseek-thinking-on": {
    ONBOARDING_PLAN_PROVIDER: "deepseek",
    ONBOARDING_PLAN_MODEL: "deepseek-flash",
    ONBOARDING_PLAN_MODEL_EVALUATED: "true",
    ONBOARDING_PLAN_THINKING: "on",
    DEEPSEEK_API_KEY: keyEnv,
  },
  "deepseek-thinking-off": {
    ONBOARDING_PLAN_PROVIDER: "deepseek",
    ONBOARDING_PLAN_MODEL: "deepseek-flash",
    ONBOARDING_PLAN_MODEL_EVALUATED: "true",
    ONBOARDING_PLAN_THINKING: "off",
    DEEPSEEK_API_KEY: keyEnv,
  },
  "groq": {
    ONBOARDING_PLAN_PROVIDER: "groq",
    ONBOARDING_PLAN_MODEL: "qwen/qwen3.8-27b",
    ONBOARDING_PLAN_MODEL_EVALUATED: "true",
    ONBOARDING_PLAN_INPUT_COST_PER_MILLION_USD: "0.8",
    ONBOARDING_PLAN_OUTPUT_COST_PER_MILLION_USD: "4",
    GROQ_API_KEY: keyEnv,
  },
};

export const legacyCaseNames: readonly string[] = Object.keys(settingsPaths).flatMap((name) => [
  `plan ${name}`,
  `questions ${name}`,
]);

function fakeStore(
  draft: { path: string; payload: Record<string, unknown> },
  catalog: CatalogExercise[],
): OnboardingStore {
  const unused = () => Promise.reject(new Error("not used by the harness"));
  return {
    loadDraft: () => Promise.resolve(draft),
    claim: () => Promise.resolve({ generation_id: "gen-1", status: "running", started: true }),
    loadCatalog: () => Promise.resolve(catalog),
    timezone: () => Promise.resolve("UTC"),
    screening: () => Promise.resolve("cleared"),
    loadHealth: () => Promise.resolve({ days: [], workouts: [] }),
    loadHealthHistory: () => Promise.resolve([]),
    claimQuestions: () => Promise.resolve({ started: true }),
    saveQuestions: (_hash, stored) => Promise.resolve(stored),
    releaseQuestions: () => Promise.resolve(),
    recordQuestionUsage: () => Promise.resolve(),
    consent: () => Promise.resolve("granted"),
    budgetAvailable: () => Promise.resolve(true),
    // Only the gateway path calls these; the settings path must not.
    gatewayConsent: unused,
    reserveGatewayBudget: unused,
    releaseBudget: unused,
    recordUsage: () => Promise.resolve(),
    persist: () => Promise.resolve("stored"),
    fail: () => Promise.resolve(),
  } as OnboardingStore;
}

/** Runs one settings-path case; `routes` is what the gateway wiring returns (no usable route). */
export async function runLegacyCase(
  name: string,
  catalog: CatalogExercise[],
  routes?: Readonly<{ plan: () => AiRoute | null; questions: () => AiRoute | null }>,
): Promise<RecordedCase> {
  const [mode, settingsName] = name.split(" ") as ["plan" | "questions", string];
  const env = settingsPaths[settingsName];
  const requests: RecordedRequest[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    requests.push({
      url: String(input),
      method: String(init?.method),
      headers: { ...(init?.headers as Record<string, string>) },
      body: String(init?.body),
    });
    // An answer that breaks the plan contract: the plan gets its one repair, the questions are
    // dropped as invalid.
    return Promise.resolve(
      new Response(
        JSON.stringify({
          choices: [{ finish_reason: "stop", message: { content: "{}" } }],
          usage: { prompt_tokens: 10, completion_tokens: 2 },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
  }) as typeof fetch;
  const work: Promise<void>[] = [];
  try {
    await handleOnboardingPlan({
      mode,
      store: fakeStore(syntheticDrafts[mode], catalog),
      resolution: () => resolveOnboardingModel({ get: (key) => env[key] }),
      currentYear: 2026,
      now: () => new Date("2026-10-02T09:00:00Z"),
      background: (promise) => work.push(promise),
      observer: { info: () => {}, warn: () => {}, error: () => {} },
      sleep: () => Promise.resolve(),
      ...(routes ? { routes } : {}),
    });
    await Promise.all(work);
  } finally {
    globalThis.fetch = original;
  }
  return { name, requests };
}

export async function recordLegacyRequests(catalog: CatalogExercise[]): Promise<RecordedCase[]> {
  const cases: RecordedCase[] = [];
  for (const name of legacyCaseNames) cases.push(await runLegacyCase(name, catalog));
  return cases;
}
