// Live onboarding plan evaluation: synthetic athletes through the production
// path (generateOnboardingProposal: prompt -> model -> validation -> one
// repair -> rules fallback). Run it before setting
// ONBOARDING_PLAN_MODEL_EVALUATED=true for a provider or model.
//
//   DEEPSEEK_API_KEY=... ./scripts/deno.sh run --allow-env --allow-net --allow-write \
//     supabase/functions/_evals/onboarding_plan_eval.ts
//
// EVAL_PROVIDER (deepseek | groq | gemini; default deepseek) and EVAL_MODEL
// (default deepseek-flash) pick the model; the provider's own key secret is
// read (DEEPSEEK_API_KEY, GROQ_API_KEY or GEMINI_API_KEY). EVAL_BASE_URL +
// EVAL_API_KEY send the same requests to an OpenAI-compatible router instead
// (a smoke test: latency is reported, not gated). EVAL_REPORT_DIR defaults to
// .tooling/onboarding-evals/<timestamp>.
//
// Gate: at least 90% of athletes get a valid model plan (initial or repaired)
// without falling back to the rules plan, and, for a direct provider, p95
// latency under 60 s. Exits non-zero when the gate fails. Synthetic data only.

import { type OnboardingAnswers } from "../_shared/onboarding/answers.ts";
import { exerciseCatalogV1 } from "../_shared/onboarding/catalog.ts";
import {
  generateOnboardingProposal,
  onboardingPlanTiming,
} from "../_shared/onboarding/generate.ts";
import {
  type OnboardingModelConfig,
  type OnboardingPlanProviderName,
  onboardingPlanProviders,
} from "../_shared/providers/onboarding_plan_provider.ts";

const base: OnboardingAnswers = {
  path: "beginner",
  experience: "beginner",
  goal: "recomposition",
  sex: "male",
  birthYear: 1994,
  age: 32,
  heightCm: 176,
  weightKg: 78,
  targetWeightKg: null,
  dailyActivity: "mostly_sitting",
  trainingWeekdays: [1, 3, 5],
  sessionMinutes: 60,
  equipment: ["dumbbells", "barbell", "bench", "cables", "machines", "pull_up_bar"],
  equipmentNote: "",
  nutritionContext: "",
  limitations: "",
  avoidPatterns: [],
  currentPlan: "",
  revisionNote: "",
};

const gym = base.equipment;
const athletes: Readonly<Record<string, OnboardingAnswers>> = {
  "beginner-fat-loss-gym-3d": { ...base, goal: "fat_loss", targetWeightKg: 72 },
  "beginner-muscle-gain-dumbbells-4d": {
    ...base,
    goal: "muscle_gain",
    sex: "female",
    weightKg: 56,
    heightCm: 163,
    equipment: ["dumbbells", "bench"],
    trainingWeekdays: [1, 2, 4, 5],
    sessionMinutes: 45,
  },
  "beginner-recomp-bodyweight-2d": {
    ...base,
    equipment: [],
    trainingWeekdays: [2, 6],
    sessionMinutes: 30,
    limitations: "No jumping; apartment with downstairs neighbours",
  },
  "beginner-strength-home-3d": {
    ...base,
    goal: "strength",
    equipment: ["barbell", "bench", "pull_up_bar"],
    dailyActivity: "physical_labour",
  },
  "beginner-aesthetic-bands-5d": {
    ...base,
    goal: "aesthetic",
    sex: "unspecified",
    equipment: ["bands", "pull_up_bar"],
    trainingWeekdays: [1, 2, 3, 5, 6],
    sessionMinutes: 45,
  },
  "beginner-six-days-gym": {
    ...base,
    goal: "muscle_gain",
    trainingWeekdays: [1, 2, 3, 4, 5, 6],
    sessionMinutes: 60,
  },
  "beginner-heavy-fat-loss": {
    ...base,
    goal: "fat_loss",
    weightKg: 140,
    heightCm: 178,
    targetWeightKg: 110,
    equipment: ["machines", "cables", "dumbbells"],
    limitations: "Squats and overhead pressing hurt; avoid both",
    avoidPatterns: ["squat", "vertical_push"],
  },
  "beginner-light-woman-fat-loss": {
    ...base,
    goal: "fat_loss",
    sex: "female",
    weightKg: 45,
    heightCm: 152,
    age: 41,
    birthYear: 1985,
    equipment: ["dumbbells"],
    nutritionContext: "Vegetarian, no eggs",
  },
  "experienced-strength-gym-4d": {
    ...base,
    path: "experienced",
    experience: "intermediate",
    goal: "strength",
    trainingWeekdays: [1, 2, 4, 5],
    sessionMinutes: 90,
    currentPlan:
      "Upper/lower 4 days: squat 5x5, bench 5x5, deadlift 3x5, rows, pull-ups; stalled on bench for 6 weeks",
  },
  "experienced-muscle-gain-ppl-6d": {
    ...base,
    path: "experienced",
    experience: "intermediate",
    goal: "muscle_gain",
    trainingWeekdays: [1, 2, 3, 4, 5, 6],
    sessionMinutes: 75,
    currentPlan: "PPL twice a week, about 22 sets for chest, mostly machines, sleeping 6 h",
  },
  "experienced-fat-loss-kettlebell-3d": {
    ...base,
    path: "experienced",
    experience: "intermediate",
    goal: "fat_loss",
    equipment: ["kettlebells", "pull_up_bar"],
    currentPlan: "Kettlebell swings and presses three times a week, 30 minutes",
    limitations: "Right shoulder aches with overhead pressing",
    avoidPatterns: ["vertical_push"],
  },
  "experienced-recomp-gym-revision": {
    ...base,
    path: "experienced",
    experience: "intermediate",
    goal: "recomposition",
    equipment: gym,
    currentPlan: "Full body 3x, compound lifts",
    revisionNote: "Fewer exercises per session and no barbell deadlifts",
  },
};

function config(): { config: OnboardingModelConfig; router: boolean } {
  const router = Deno.env.get("EVAL_BASE_URL");
  const providerName = (Deno.env.get("EVAL_PROVIDER") ?? "deepseek") as OnboardingPlanProviderName;
  const entry = onboardingPlanProviders[providerName];
  if (!entry) throw new Error(`Unknown EVAL_PROVIDER ${providerName}`);
  const model = Deno.env.get("EVAL_MODEL") ?? "deepseek-flash";
  const price = entry.defaultPrice ?? { input: 0, output: 0 };
  if (router) {
    return {
      router: true,
      config: {
        provider: providerName,
        model,
        url: `${router.replace(/\/$/, "")}/chat/completions`,
        apiKey: Deno.env.get("EVAL_API_KEY") ?? "",
        extraBody: {},
        price,
      },
    };
  }
  const apiKey = Deno.env.get(entry.keyEnv) ?? "";
  if (!apiKey) throw new Error(`${entry.keyEnv} is required`);
  return {
    router: false,
    config: {
      provider: providerName,
      model,
      url: entry.url,
      apiKey,
      extraBody: entry.extraBody,
      price,
    },
  };
}

const percentile = (values: number[], p: number) => {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(p * sorted.length) - 1)] ?? 0;
};

async function main() {
  const { config: modelConfig, router } = config();
  const timing = router
    ? { totalDeadlineMs: 240_000, initialAttemptMs: 120_000, repairAttemptMs: 120_000 }
    : onboardingPlanTiming;
  const results = [];
  for (const [name, answers] of Object.entries(athletes)) {
    const started = performance.now();
    const result = await generateOnboardingProposal(
      answers,
      exerciseCatalogV1,
      { kind: "model", config: modelConfig },
      { consentGranted: true, budgetAvailable: true },
      fetch,
      timing,
    );
    const row = {
      athlete: name,
      origin: result.proposal.training.origin as string,
      fallback_reason: result.fallbackReason,
      attempts: result.attempts,
      latency_ms: Math.round(performance.now() - started),
      cost_usd: result.usage?.estimatedCostUsd ?? 0,
      calories: result.proposal.nutrition.calories,
      title: result.proposal.training.title,
    };
    results.push(row);
    console.log(
      `${name}: ${row.origin}${
        row.fallback_reason ? ` (${row.fallback_reason})` : ""
      } ${row.latency_ms} ms`,
    );
  }
  const valid = results.filter((row) => row.origin === "ai").length;
  const repaired =
    results.filter((row) =>
      row.origin === "ai" && row.attempts.some((attempt) => attempt.attempt === "repair")
    ).length;
  const latencies = results.map((row) => row.latency_ms);
  const summary = {
    provider: modelConfig.provider,
    model: modelConfig.model,
    router,
    athletes: results.length,
    valid_without_fallback: valid,
    valid_rate: valid / results.length,
    repaired,
    fallback: results.length - valid,
    p50_latency_ms: percentile(latencies, 0.5),
    p95_latency_ms: percentile(latencies, 0.95),
    total_cost_usd: Math.round(results.reduce((sum, row) => sum + row.cost_usd, 0) * 1e6) / 1e6,
  };
  const gates = {
    valid_rate_at_least_90pct: summary.valid_rate >= 0.9,
    p95_under_60s: router || summary.p95_latency_ms < 60_000,
  };
  const dir = Deno.env.get("EVAL_REPORT_DIR") ??
    `.tooling/onboarding-evals/${new Date().toISOString().replaceAll(":", "-")}`;
  await Deno.mkdir(dir, { recursive: true });
  await Deno.writeTextFile(
    `${dir}/report.json`,
    JSON.stringify({ summary, gates, results }, null, 2),
  );
  console.log(JSON.stringify({ summary, gates }, null, 2));
  if (!Object.values(gates).every(Boolean)) Deno.exit(1);
}

if (import.meta.main) await main();
