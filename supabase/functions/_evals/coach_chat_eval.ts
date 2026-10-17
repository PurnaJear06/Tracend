// Live Coach chat operations evaluation: about 54 varied prompts x 3 synthetic athletes through
// the production code path (classifyQuestion -> generateCoachChat -> data-summary fallback). It
// gates what the answer bank (coach_bank/) does not: how often a model answer arrives, dead ends,
// unpermitted evidence, latency, spend and the prompt cache. What a reply says is graded by the
// bank.
//
//   DEEPSEEK_API_KEY=... ./scripts/deno.sh run --allow-env --allow-net --allow-read \
//     --allow-write supabase/functions/_evals/coach_chat_eval.ts
//
// Optional: EVAL_REPEATS (default 2), EVAL_CONCURRENCY (default 4),
// EVAL_REPORT_DIR (default .tooling/coach-evals/<timestamp>),
// EVAL_MAX_CALLS (cheap sample: one prompt per category, rotating prompts and athletes), and the
// model settings in live_model.ts (a gateway route, a router, or DeepSeek).
//
// With a gateway route the run first asks one question twice and records both `ai_call` log
// lines, the proof that a repeated question reads the cached prefix. EVAL_MAX_USD (default 1)
// stops new calls once the run has spent that much at list prices.
// Exits non-zero when a merge gate fails. Synthetic data only.

import prompts from "./prompts.json" with { type: "json" };
import { evalProfiles } from "./fixtures.ts";
import { buildCoachChatDataSummary } from "../_shared/coach_chat_fallback.ts";
import {
  classifyQuestion,
  coachChatFailureUsage,
  type CoachChatGeneration,
  CoachChatUnavailableError,
} from "../_shared/providers/coach_chat_provider.ts";
import type { AiRoute } from "../_shared/ai/types.ts";
import {
  type Generate,
  hostSleep,
  liveModelFromEnv,
  routerTiming,
  runAwake,
} from "./live_model.ts";

type EvalPrompt = Readonly<{
  id: string;
  category: string;
  text: string;
  history?: ReadonlyArray<Readonly<{ role: string; content: string }>>;
}>;

type Outcome = "model" | "boundary" | "data_summary" | "dead_end";

type RunResult = {
  profile: string;
  prompt_id: string;
  category: string;
  repeat: number;
  context_kind: string;
  outcome: Outcome;
  failure_code?: string;
  initial_rule?: string;
  repair_rule?: string;
  latency_ms: number;
  safety_state?: string;
  answer?: string;
  evidence_codes?: string[];
  follow_ups?: readonly string[];
  cost_usd: number;
  cache_read_tokens: number;
  cache_write_tokens: number;
  prompt_tokens: number;
  checks: Record<string, boolean>;
};

const cacheTokens = (attempts: CoachChatGeneration["attempts"]) => ({
  cache_read_tokens: attempts.reduce((sum, a) => sum + (a.cacheReadTokens ?? 0), 0),
  cache_write_tokens: attempts.reduce((sum, a) => sum + (a.cacheWriteTokens ?? 0), 0),
  prompt_tokens: attempts.reduce((sum, a) => sum + (a.promptTokens ?? 0), 0),
});

export const evalGates = Object.freeze({
  minModelAnswerRate: 0.97,
  maxDeadEnds: 0,
  maxUnpermittedEvidence: 0,
  maxP95LatencyMs: 25_000,
});

function percentile(values: readonly number[], p: number): number {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1)];
}

// A cheap run: one prompt per category per round, rotating prompts within a category and athletes
// across categories and rounds.
export function sampleJobs<
  T extends Readonly<{ profileId: string; category: string; promptId: string }>,
>(jobs: readonly T[], maxCalls: number): T[] {
  if (!(maxCalls > 0) || maxCalls >= jobs.length) return [...jobs];
  const profiles = [...new Set(jobs.map((job) => job.profileId))];
  const picked = new Set<T>();
  const pickFirst = (...preferences: Array<(job: T) => boolean>) => {
    for (const preferred of preferences) {
      const job = jobs.find((j) => !picked.has(j) && preferred(j));
      if (job) {
        picked.add(job);
        return;
      }
    }
  };

  const categories = [...new Set(jobs.map((j) => j.category))];
  for (let round = 0; picked.size < maxCalls; round++) {
    const before = picked.size;
    for (const [index, category] of categories.entries()) {
      if (picked.size >= maxCalls) break;
      const promptIds = [
        ...new Set(jobs.filter((j) => j.category === category).map((j) => j.promptId)),
      ];
      const promptId = promptIds[round % promptIds.length];
      const profileId = profiles[(index + round) % profiles.length];
      pickFirst(
        (j) => j.promptId === promptId && j.profileId === profileId,
        (j) => j.promptId === promptId,
        (j) => j.category === category,
      );
    }
    if (picked.size === before) break;
  }
  return [...picked];
}

async function runOne(
  profile: ReturnType<typeof evalProfiles>[number],
  prompt: EvalPrompt,
  repeat: number,
  generate: Generate,
): Promise<RunResult> {
  const context = structuredClone(profile.context);
  if (prompt.history) context.recent_messages = [...prompt.history];
  const permitted = (context.permitted_evidence as string[]) ?? [];
  const contextKind = classifyQuestion(prompt.text);
  const started = performance.now();
  const base = {
    profile: profile.id,
    prompt_id: prompt.id,
    category: prompt.category,
    repeat,
    context_kind: contextKind,
  };
  try {
    const generation = await generate({
      question: prompt.text,
      context,
      contextKind,
      contributions: null,
    });
    const answer = generation.answer;
    const checks: Record<string, boolean> = {
      evidence_permitted: answer.evidence.every((e) => permitted.includes(e.code)),
    };
    return {
      ...base,
      outcome: generation.provider === "mock" ? "boundary" : "model",
      latency_ms: Math.round(performance.now() - started),
      safety_state: answer.safety_state,
      answer: answer.answer,
      evidence_codes: answer.evidence.map((e) => e.code),
      follow_ups: answer.suggested_follow_ups,
      cost_usd: generation.estimatedCostUsd,
      ...cacheTokens(generation.attempts),
      checks,
    };
  } catch (error) {
    const latency_ms = Math.round(performance.now() - started);
    if (error instanceof CoachChatUnavailableError) {
      // The fallback the athlete would get: a data summary, or a safety
      // referral when the message may be about a health risk.
      const summary = buildCoachChatDataSummary(context, prompt.text);
      return {
        ...base,
        outcome: "data_summary",
        failure_code: error.failureReason,
        initial_rule: error.metadata.initialRule,
        repair_rule: error.metadata.repairRule,
        latency_ms,
        safety_state: summary.safety_state,
        answer: summary.answer,
        cost_usd: coachChatFailureUsage(error).estimatedCostUsd,
        ...cacheTokens(error.metadata.attempts ?? []),
        checks: {},
      };
    }
    return {
      ...base,
      outcome: "dead_end",
      failure_code: error instanceof Error ? error.name : "unknown",
      latency_ms,
      cost_usd: 0,
      cache_read_tokens: 0,
      cache_write_tokens: 0,
      prompt_tokens: 0,
      checks: {},
    };
  }
}

/** The `ai_call` log lines the gateway writes while run() goes; other output passes through. */
async function aiCallLines<T>(run: () => Promise<T>): Promise<{ result: T; calls: unknown[] }> {
  const calls: unknown[] = [];
  const saved = { log: console.log, warn: console.warn };
  const capture = (write: (...args: unknown[]) => void) => (...args: unknown[]) => {
    const line = args.map(String).join(" ");
    try {
      const entry = JSON.parse(line);
      if (entry?.msg === "ai_call") {
        calls.push(entry);
        return;
      }
    } catch {
      // Not a log entry.
    }
    write(...args);
  };
  console.log = capture(saved.log);
  console.warn = capture(saved.warn);
  try {
    return { result: await run(), calls };
  } finally {
    Object.assign(console, saved);
  }
}

async function main(): Promise<void> {
  const live = liveModelFromEnv();
  if ("error" in live) {
    console.error(live.error);
    Deno.exit(2);
  }
  await runEvaluation(live);
}

async function runEvaluation(setup: {
  generate: Generate;
  endpoint: string;
  model: string;
  router: boolean;
  coachRoute?: AiRoute;
}): Promise<void> {
  const { generate, endpoint, model } = setup;
  const router = setup.router;
  const maxUsd = Number(Deno.env.get("EVAL_MAX_USD") ?? "1");
  const repeats = Number(Deno.env.get("EVAL_REPEATS") ?? "2");
  const concurrency = Number(Deno.env.get("EVAL_CONCURRENCY") ?? "4");
  const maxCalls = Number(Deno.env.get("EVAL_MAX_CALLS") ?? "0");
  const reportDir = Deno.env.get("EVAL_REPORT_DIR") ??
    `.tooling/coach-evals/${new Date().toISOString().replace(/[:.]/g, "-")}`;

  const planned = evalProfiles().flatMap((profile) =>
    (prompts as EvalPrompt[]).flatMap((prompt) =>
      Array.from({ length: repeats }, (_, index) => ({
        profile,
        prompt,
        repeat: index + 1,
        profileId: profile.id,
        category: prompt.category,
        promptId: prompt.id,
      }))
    )
  );
  const jobs: Array<() => Promise<RunResult>> = sampleJobs(planned, maxCalls).map((job) => () =>
    runAwake(() => runOne(job.profile, job.prompt, job.repeat, generate))
  );

  // Cache proof: the same question twice for the same athlete, one after the other.
  const cacheProof: unknown[] = [];
  if (setup.coachRoute) {
    const athlete = evalProfiles().find((p) => p.id === "rich")!;
    const question = "How did my training go over the last two weeks?";
    for (let ask = 0; ask < 2; ask++) {
      const { calls } = await aiCallLines(() =>
        generate({
          question,
          context: structuredClone(athlete.context),
          contextKind: classifyQuestion(question),
          contributions: null,
        }).catch((error) => error)
      );
      cacheProof.push(...calls);
    }
  }
  const proofSpent = cacheProof.reduce(
    (sum: number, entry) => sum + Number((entry as { cost_usd?: number }).cost_usd ?? 0),
    0,
  );

  const results: RunResult[] = [];
  let next = 0;
  let spent = proofSpent;
  let stoppedForBudget = false;
  const workers = Array.from({ length: Math.max(1, concurrency) }, async () => {
    while (next < jobs.length) {
      if (spent >= maxUsd) {
        stoppedForBudget = true;
        return;
      }
      const job = jobs[next++];
      const result = await job();
      spent += result.cost_usd;
      results.push(result);
      if (results.length % 20 === 0) console.log(`${results.length}/${jobs.length} runs done`);
    }
  });
  await Promise.all(workers);

  const count = (outcome: Outcome) => results.filter((r) => r.outcome === outcome).length;
  const failedCheck = (name: string) =>
    results.filter((r) => name in r.checks && !r.checks[name]).length;
  const latencies = results.filter((r) => r.outcome !== "dead_end").map((r) => r.latency_ms);
  const modelAnswerRate = (count("model") + count("boundary")) / results.length;
  const rules = new Map<string, number>();
  for (const r of results) {
    for (const rule of [r.initial_rule, r.repair_rule]) {
      if (rule) rules.set(rule, (rules.get(rule) ?? 0) + 1);
    }
    if (r.outcome === "data_summary" && !r.initial_rule && r.failure_code) {
      rules.set(r.failure_code, (rules.get(r.failure_code) ?? 0) + 1);
    }
  }
  const categories = [...new Set(results.map((r) => r.category))].map((category) => {
    const inCategory = results.filter((r) => r.category === category);
    const answered = inCategory.filter((r) => r.outcome === "model" || r.outcome === "boundary");
    return {
      category,
      runs: inCategory.length,
      model_answer_rate: answered.length / inCategory.length,
    };
  });

  const gates = {
    model_answer_rate: modelAnswerRate >= evalGates.minModelAnswerRate,
    dead_ends: count("dead_end") <= evalGates.maxDeadEnds,
    unpermitted_evidence: failedCheck("evidence_permitted") <= evalGates.maxUnpermittedEvidence,
    // A router's latency says nothing about production, so it is reported only.
    p95_latency: router || percentile(latencies, 95) <= evalGates.maxP95LatencyMs,
    // Through the gateway the repeated question must read the cached prefix.
    cache_read: !setup.coachRoute ||
      Number((cacheProof.at(-1) as { cache_read_tokens?: number } | undefined)?.cache_read_tokens) >
        0,
  };
  const passed = Object.values(gates).every(Boolean) && !stoppedForBudget;
  const promptTokens = results.reduce((sum, r) => sum + r.prompt_tokens, 0);
  const cacheRead = results.reduce((sum, r) => sum + r.cache_read_tokens, 0);
  const cacheWrite = results.reduce((sum, r) => sum + r.cache_write_tokens, 0);
  const answered = count("model");
  const proofLines = cacheProof.map((entry) => {
    const e = entry as Record<string, unknown>;
    return `- ${e.outcome}: input ${e.input_tokens}, cache read ${e.cache_read_tokens}, cache write ${e.cache_write_tokens}, output ${e.output_tokens}, USD ${e.cost_usd}, ${e.latency_ms} ms`;
  });

  const summary = [
    `# Coach chat live evaluation — ${passed ? "PASSED" : "FAILED"}`,
    "",
    `Runs: ${results.length} of ${planned.length} (${prompts.length} prompts × ${evalProfiles().length} athletes × ${repeats} repeats${
      jobs.length < planned.length ? `, sampled to ${jobs.length}` : ""
    })`,
    `Endpoint: ${endpoint}, model \`${model}\`${
      router
        ? ` (router smoke test: not production latency or upstream; attempts wait up to ${
          routerTiming.initialAttemptMs / 1000
        } s, repairs ${routerTiming.repairAttemptMs / 1000} s)`
        : ""
    }`,
    "",
    `Spend: USD ${spent.toFixed(4)} at list prices (cap ${maxUsd})${
      stoppedForBudget ? " — STOPPED at the cap before every run finished" : ""
    }; USD ${(answered ? (spent - proofSpent) / answered : 0).toFixed(5)} per model answer.`,
    `Runs repeated because the host slept mid-request: ${hostSleep.reruns}.`,
    `Prompt tokens: ${promptTokens}, of which cache reads ${cacheRead} (${
      promptTokens ? ((cacheRead / promptTokens) * 100).toFixed(1) : "0"
    }%) and cache writes ${cacheWrite}.`,
    ...(proofLines.length
      ? ["", "Cache proof (`ai_call` lines, same question asked twice):", ...proofLines]
      : []),
    "",
    "| Gate | Result | Value |",
    "|---|---|---|",
    `| Model answers ≥ ${evalGates.minModelAnswerRate * 100}% | ${
      gates.model_answer_rate ? "pass" : "FAIL"
    } | ${(modelAnswerRate * 100).toFixed(1)}% |`,
    ...(setup.coachRoute
      ? [
        `| Repeated question reads the cache | ${gates.cache_read ? "pass" : "FAIL"} | ${
          proofLines.at(-1) ?? "no call"
        } |`,
      ]
      : []),
    `| Dead-ends = 0 | ${gates.dead_ends ? "pass" : "FAIL"} | ${count("dead_end")} |`,
    `| Unpermitted evidence accepted = 0 | ${gates.unpermitted_evidence ? "pass" : "FAIL"} | ${
      failedCheck("evidence_permitted")
    } |`,
    `| p95 latency ≤ ${evalGates.maxP95LatencyMs / 1000} s | ${
      router ? "not gated (router)" : gates.p95_latency ? "pass" : "FAIL"
    } | ${(percentile(latencies, 95) / 1000).toFixed(1)} s (p50 ${
      (percentile(latencies, 50) / 1000).toFixed(1)
    } s) |`,
    "",
    `Outcomes: ${count("model")} model, ${count("boundary")} safety boundary, ${
      count("data_summary")
    } labeled data summary, ${count("dead_end")} dead-end.`,
    "",
    "Failure rules:",
    ...(rules.size
      ? [...rules.entries()].sort((a, b) => b[1] - a[1]).map(([rule, n]) => `- ${rule}: ${n}`)
      : ["- none"]),
    "",
    "| Category | Runs | Model answers |",
    "|---|---|---|",
    ...categories.map((c) =>
      `| ${c.category} | ${c.runs} | ${(c.model_answer_rate * 100).toFixed(0)}% |`
    ),
    "",
  ].join("\n");

  await Deno.mkdir(reportDir, { recursive: true });
  await Deno.writeTextFile(`${reportDir}/summary.md`, summary);
  await Deno.writeTextFile(
    `${reportDir}/report.json`,
    JSON.stringify({ gates, passed, results }, null, 2),
  );
  const stepSummary = Deno.env.get("GITHUB_STEP_SUMMARY");
  if (stepSummary) await Deno.writeTextFile(stepSummary, summary, { append: true });
  console.log(summary);
  console.log(`Full report: ${reportDir}/report.json`);
  if (!passed) Deno.exit(1);
}

if (import.meta.main) await main();
