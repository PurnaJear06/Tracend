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
// (latency is reported, not gated). EVAL_THINKING (on | off; default on)
// matches ONBOARDING_PLAN_THINKING. EVAL_REPORT_DIR defaults to
// .tooling/onboarding-evals/<timestamp>.
//
// Gate: at least 90% of athletes get a valid model plan (initial or repaired)
// without falling back to the rules plan, every valid plan for an athlete with
// focus muscles names one of them in its assessment, and, for a direct
// provider, p95 latency under 60 s (120 s with thinking). Exits non-zero when
// the gate fails. Synthetic data only.

import { type OnboardingAnswers } from "../_shared/onboarding/answers.ts";
import { exerciseCatalogV1 } from "../_shared/onboarding/catalog.ts";
import { generateOnboardingProposal } from "../_shared/onboarding/generate.ts";
import {
  type HealthDay,
  type HealthSummary,
  type HealthWorkout,
  shiftDate,
  summarizeHealth,
} from "../_shared/onboarding/health_summary.ts";
import {
  type HealthHistory,
  type HealthMonth,
  monthStart,
  summarizeHealthHistory,
} from "../_shared/onboarding/health_history.ts";
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
  trainingYears: null,
  trainingHistory: "",
  currentLifts: [],
  priorityMuscles: [],
  strongMuscles: [],
  followUps: [],
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
    trainingYears: "3_5",
    trainingHistory: "Squat and deadlift keep moving; bench has been stuck at 90 kg for 6 weeks",
    currentLifts: [
      { slug: "barbell-bench-press", loadKg: 90, reps: 5, repsLeft: 1 },
      { slug: "barbell-back-squat", loadKg: 130, reps: 5, repsLeft: 2 },
      { slug: "barbell-deadlift", loadKg: 170, reps: 3, repsLeft: 2 },
      { slug: "barbell-row", loadKg: 70, reps: 8, repsLeft: 2 },
    ],
    priorityMuscles: ["chest"],
    strongMuscles: ["quads", "hamstrings"],
    followUps: [{
      category: "stalled_lift",
      question: "How often do you bench each week now?",
      answer: "Once, always 5x5 at the same weight",
    }],
  },
  "experienced-muscle-gain-ppl-6d": {
    ...base,
    path: "experienced",
    experience: "intermediate",
    goal: "muscle_gain",
    trainingWeekdays: [1, 2, 3, 4, 5, 6],
    sessionMinutes: 75,
    currentPlan: "PPL twice a week, about 22 sets for chest, mostly machines, sleeping 6 h",
    trainingYears: "over_5",
    trainingHistory: "Chest and arms grow easily; my back and shoulders lag behind",
    priorityMuscles: ["back", "shoulders"],
    strongMuscles: ["chest", "biceps"],
  },
  // Five years of lifting four times a week, then two lazy months.
  "experienced-returning-gym-4d": {
    ...base,
    path: "experienced",
    experience: "intermediate",
    goal: "aesthetic",
    trainingWeekdays: [1, 2, 4, 5],
    sessionMinutes: 60,
    currentPlan: "Upper/lower, stopped for two months after a busy period at work",
    trainingYears: "over_5",
    currentLifts: [
      { slug: "barbell-bench-press", loadKg: 80, reps: 8, repsLeft: 2 },
      { slug: "barbell-back-squat", loadKg: 100, reps: 8, repsLeft: 2 },
    ],
    priorityMuscles: ["chest"],
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

// Synthetic Apple Health for four athletes, summarised by the production code.
const evalToday = "2026-10-03";
function syntheticHealth(
  day: (back: number) => Partial<HealthDay>,
  workouts: readonly Readonly<{ back: number; type: string; minutes: number }>[] = [],
): HealthSummary {
  const days: HealthDay[] = Array.from({ length: 28 }, (_, index) => ({
    local_date: shiftDate(evalToday, index + 1),
    steps: null,
    active_energy_kcal: null,
    sleep_minutes: null,
    weight_kg: null,
    ...day(index + 1),
  }));
  const found: HealthWorkout[] = workouts.map((workout) => ({
    local_date: shiftDate(evalToday, workout.back),
    activity_type: workout.type,
    duration_seconds: workout.minutes * 60,
  }));
  return summarizeHealth(days, found, evalToday)!;
}

const health: Readonly<Record<string, HealthSummary>> = {
  // Losing about half a kilo a week, weighed every few days.
  "beginner-fat-loss-gym-3d": syntheticHealth((back) => ({
    steps: 6400,
    active_energy_kcal: 380,
    sleep_minutes: 420,
    weight_kg: back % 3 === 0 ? 84 + back * 0.07 : null,
  })),
  // Short sleep: the plan starts lighter.
  "beginner-muscle-gain-dumbbells-4d": syntheticHealth(() => ({
    steps: 7200,
    sleep_minutes: 340,
  })),
  // Very active, already lifting four times a week.
  "experienced-muscle-gain-ppl-6d": syntheticHealth(
    () => ({ steps: 12600, active_energy_kcal: 720, sleep_minutes: 450 }),
    Array.from({ length: 16 }, (_, index) => ({
      back: 1 + Math.floor(index * 1.7),
      type: index % 4 === 3 ? "RUNNING" : "TRADITIONAL_STRENGTH_TRAINING",
      minutes: 65,
    })),
  ),
  // Steps but no workouts found: nothing is claimed about training.
  "experienced-strength-gym-4d": syntheticHealth(() => ({ steps: 8800, sleep_minutes: 410 })),
};

// Usual months for the returning athlete: four strength sessions a week, every
// night's sleep and a weekly weigh-in, through the month before last.
const history: Readonly<Record<string, HealthHistory>> = {
  "experienced-returning-gym-4d": summarizeHealthHistory(
    Array.from({ length: 11 }, (_, index): HealthMonth => ({
      month: monthStart(evalToday, index + 1),
      workouts: index < 2 ? 1 : 17,
      strength_workouts: index < 2 ? 1 : 17,
      workout_minutes: index < 2 ? 60 : 1100,
      sleep_nights: 30,
      sleep_minutes_avg: 440,
      weight_days: 4,
      weight_kg_avg: 80 + index * 0.2,
      data_days: 30,
    })),
    evalToday,
  )!,
};

function config(): { config: OnboardingModelConfig; router: boolean } {
  const router = Deno.env.get("EVAL_BASE_URL");
  const providerName = (Deno.env.get("EVAL_PROVIDER") ?? "deepseek") as OnboardingPlanProviderName;
  const entry = onboardingPlanProviders[providerName];
  if (!entry) throw new Error(`Unknown EVAL_PROVIDER ${providerName}`);
  const model = Deno.env.get("EVAL_MODEL") ?? "deepseek-flash";
  const price = entry.defaultPrice ?? { input: 0, output: 0 };
  const thinkingSetting = Deno.env.get("EVAL_THINKING") ?? "on";
  if (thinkingSetting !== "on" && thinkingSetting !== "off") {
    throw new Error(`EVAL_THINKING must be on or off, not ${thinkingSetting}`);
  }
  const thinking = thinkingSetting === "on" && entry.thinkingBody !== null;
  if (router) {
    return {
      router: true,
      config: {
        provider: providerName,
        model,
        url: `${router.replace(/\/$/, "")}/chat/completions`,
        apiKey: Deno.env.get("EVAL_API_KEY") ?? "",
        // The provider's own request settings, plus thinking off in the
        // routers' terms (as coach_chat_eval.ts does) for calls that should
        // not think.
        extraBody: {
          ...entry.extraBody,
          ...("thinking" in entry.extraBody ? { reasoning_effort: "none" } : {}),
        },
        thinkingBody: entry.thinkingBody,
        thinking,
        // The router ignores thinking-off and DeepSeek V4 still thinks (9-21
        // thousand characters of reasoning per answer on 2026-10-02), so every
        // routed answer gets room for the reasoning on top of the plan.
        maxOutputTokens: 24_000,
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
      thinkingBody: entry.thinkingBody,
      thinking,
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
  // A direct run uses production timing (chosen by thinking); the router adds
  // its own queueing and gets more room.
  const timing = router
    ? { totalDeadlineMs: 240_000, initialAttemptMs: 120_000, repairAttemptMs: 120_000 }
    : undefined;
  const results = [];
  // What the provider returned for each call (synthetic athletes only), so a
  // failed run shows why: finish reason, token counts and the answer's end.
  let calls: Record<string, unknown>[] = [];
  const recording: typeof fetch = async (input, init) => {
    const response = await fetch(input, init);
    const copy = response.clone();
    try {
      const payload = await copy.json() as Record<string, unknown>;
      const choice = (payload.choices as Record<string, unknown>[] | undefined)?.[0];
      const message = choice?.message as Record<string, unknown> | undefined;
      const content = typeof message?.content === "string" ? message.content : "";
      const reasoning = typeof message?.reasoning_content === "string"
        ? message.reasoning_content
        : "";
      calls.push({
        status: response.status,
        // A provider or router error says why (a 503 carries no plan).
        ...(response.ok ? {} : { error: JSON.stringify(payload.error ?? payload).slice(0, 300) }),
        finish_reason: choice?.finish_reason ?? null,
        usage: payload.usage ?? null,
        content_chars: content.length,
        reasoning_chars: reasoning.length,
        content_head: content.slice(0, 200),
        content_tail: content.slice(-300),
      });
    } catch {
      calls.push({ status: response.status, body: "not JSON" });
    }
    return response;
  };
  for (const [name, answers] of Object.entries(athletes)) {
    const started = performance.now();
    const result = await generateOnboardingProposal(
      answers,
      exerciseCatalogV1,
      { kind: "model", config: modelConfig },
      { consentGranted: true, budgetAvailable: true },
      recording,
      timing,
      health[name] ?? null,
      history[name] ?? null,
    );
    const assessment = String(result.proposal.training.assessment ?? "").toLowerCase();
    const row = {
      athlete: name,
      apple_health: name in health,
      origin: result.proposal.training.origin as string,
      fallback_reason: result.fallbackReason,
      attempts: result.attempts,
      latency_ms: Math.round(performance.now() - started),
      cost_usd: result.usage?.estimatedCostUsd ?? 0,
      output_units: result.usage?.outputUnits ?? 0,
      reasoning_units: result.usage?.reasoningUnits ?? 0,
      calories: result.proposal.nutrition.calories,
      title: result.proposal.training.title,
      // An assessment that names a focus muscle speaks to this athlete.
      names_focus: answers.priorityMuscles.length === 0 ||
        answers.priorityMuscles.some((muscle) => assessment.includes(muscle)),
      assessment: result.proposal.training.assessment,
      calls,
    };
    calls = [];
    results.push(row);
    const status = result.attempts.find((attempt) => attempt.httpStatus !== null)?.httpStatus;
    console.log(
      `${name}: ${row.origin}${row.fallback_reason ? ` (${row.fallback_reason})` : ""}${
        status ? ` HTTP ${status}` : ""
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
    thinking: modelConfig.thinking,
    athletes: results.length,
    valid_without_fallback: valid,
    valid_rate: valid / results.length,
    repaired,
    fallback: results.length - valid,
    p50_latency_ms: percentile(latencies, 0.5),
    p95_latency_ms: percentile(latencies, 0.95),
    p50_output_units: percentile(results.map((row) => row.output_units), 0.5),
    p50_reasoning_units: percentile(results.map((row) => row.reasoning_units), 0.5),
    total_cost_usd: Math.round(results.reduce((sum, row) => sum + row.cost_usd, 0) * 1e6) / 1e6,
  };
  const p95LimitMs = modelConfig.thinking ? 120_000 : 60_000;
  const gates = {
    valid_rate_at_least_90pct: summary.valid_rate >= 0.9,
    ai_plans_name_focus_muscles: results.every((row) => row.origin !== "ai" || row.names_focus),
    p95_within_limit: router || summary.p95_latency_ms < p95LimitMs,
  };
  const dir = Deno.env.get("EVAL_REPORT_DIR") ??
    `.tooling/onboarding-evals/${new Date().toISOString().replaceAll(":", "-")}`;
  await Deno.mkdir(dir, { recursive: true });
  await Deno.writeTextFile(
    `${dir}/report.json`,
    JSON.stringify({ summary, gates, results }, null, 2),
  );
  console.log(JSON.stringify({ summary, gates }, null, 2));
  if (router) {
    console.log(
      "Router run: the router forwards to the provider with its own model id and timeouts and ignores thinking-off, so it does not prove the exact production request.",
    );
  }
  if (!Object.values(gates).every(Boolean)) Deno.exit(1);
}

if (import.meta.main) await main();
